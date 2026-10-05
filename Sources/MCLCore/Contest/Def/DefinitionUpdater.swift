import CryptoKit
import Foundation

/// Network layer of `DefinitionUpdater`: downloads a URL and returns the status code and body.
/// A transfer error is thrown; a status ≠ 200 is judged only by the updater.
public protocol DataFetcher: Sendable {
    func fetch(_ url: URL) async throws -> (status: Int, data: Data)
}

/// Default `DataFetcher` over `URLSession` — analogous to Java `HttpClient`
/// (connect timeout 10 s, request timeout 30 s, `Redirect.NORMAL`).
///
/// `URLSession` has no separate connect timeout: 10 s here is inactivity
/// (`timeoutIntervalForRequest`, covers establishing the connection too), 30 s the whole request
/// (`timeoutIntervalForResource`). Redirects are followed except https → http,
/// like `Redirect.NORMAL`.
public struct URLSessionDataFetcher: DataFetcher {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    public func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
        let (data, response) = try await session.data(from: url, delegate: NormalRedirects())
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    /// Java `HttpClient.Redirect.NORMAL`: never from https to http.
    private final class NormalRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            let from = task.currentRequest?.url?.scheme?.lowercased()
            let to = request.url?.scheme?.lowercased()
            return from == "https" && to == "http" ? nil : request
        }
    }
}

/// An error that fails the whole `DefinitionUpdater.update` (Java `IOException`
/// or `IllegalArgumentException` from `URI.resolve` / `Properties.load`).
/// `message` is the text the UI shows after „Aktualizace definic selhala: ".
public struct DefinitionUpdaterError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Updating contest definitions from the internet (N1MM „Check for updated contest
/// definitions", DXLog contest updates). Downloads `index.txt` and the files in it
/// from the published `contest-data` directory and stores them in the data directory.
///
/// Port of Java `contest/def/DefinitionUpdater.java` (v1.1.1). A file the
/// user edited locally (the hash does not match what was last downloaded) is
/// **not overwritten** — only reported. Downloaded contest definitions must pass
/// `DefinitionEditing.check`, otherwise they are not written. The hash manifest is in the
/// `java.util.Properties` format (`JavaProperties`), so the Java version can read it too.
public struct DefinitionUpdater: Sendable {

    /// Public source: the contest-data directory in the project repository.
    public static let defaultBase = URL(string: "https://raw.githubusercontent.com/ok1xoe/MacContestLogger/main/contest-data/")!

    static let manifestName = ".update-manifest.properties"
    static let manifestComment = "Hash naposledy stažených souborů (lokálně upravené se nepřepisují)"

    public enum Status: String, CaseIterable, Sendable, CustomStringConvertible {
        case new = "NEW"
        case updated = "UPDATED"
        case unchanged = "UNCHANGED"
        case skippedLocalChanges = "SKIPPED_LOCAL_CHANGES"
        case failed = "FAILED"

        /// Java constant name (the UI prints it into messages).
        public var description: String { rawValue }
    }

    public struct FileResult: Equatable, Sendable {
        public let path: String
        public let status: Status
        public let detail: String

        public init(path: String, status: Status, detail: String) {
            self.path = path
            self.status = status
            self.detail = detail
        }
    }

    public struct Report: Equatable, Sendable {
        public let files: [FileResult]

        public init(files: [FileResult]) {
            self.files = files
        }

        public func count(_ status: Status) -> Int {
            files.filter { $0.status == status }.count
        }

        public func summary() -> String {
            "nové \(count(.new)), aktualizované \(count(.updated)), beze změny \(count(.unchanged)), "
                + "ponechané lokální úpravy \(count(.skippedLocalChanges)), chyby \(count(.failed))"
        }
    }

    private let fetcher: any DataFetcher

    public init(fetcher: any DataFetcher = URLSessionDataFetcher()) {
        self.fetcher = fetcher
    }

    /// The downloaded `index.txt`: the root it was resolved against and its lines (Java `lines`, stripped,
    /// without blanks and `#` comments).
    public struct Index: Equatable, Sendable {
        let root: String
        public let paths: [String]
    }

    /// What the network phase downloaded: the bodies by path (first occurrence order, keys by UTF-16) and the
    /// files that already failed (unsafe path, download error), in index order.
    public struct Downloaded: Equatable, Sendable {
        let order: [String]
        let bodies: [[UInt16]: Data]
        let failed: [FileResult]
    }

    /// Java `update(URI base, Path dataDir)`, composed of the phases below in Java's order: the index
    /// (`fetchIndex`), the manifest (`loadManifest`), the downloads (`download`), then the checks and writes
    /// (`apply`). A caller that must keep file work off Swift's shared pool runs the two synchronous phases on its
    /// own thread.
    ///
    /// It fails as a whole (and writes nothing) when `index.txt` cannot be downloaded, the
    /// manifest cannot be read, or when a path in the index does not pass Java `URI.resolve`
    /// (a space, `|`, a lone `%` …). A local file error in the second phase
    /// fails `update` too — what was written until then stays, the manifest does not.
    public func update(_ base: URL, dataDir: URL) async throws(DefinitionUpdaterError) -> Report {
        let index = try await fetchIndex(base)
        let manifest = try Self.loadManifest(dataDir: dataDir)
        let downloaded = try await download(index)
        return try Self.apply(downloaded, manifest: manifest, dataDir: dataDir)
    }

    /// Phase 1 (network): downloads and splits `index.txt` of `base`.
    public func fetchIndex(_ base: URL) async throws(DefinitionUpdaterError) -> Index {
        var root = base.absoluteString
        if root.utf16.last != UInt16(UInt8(ascii: "/")) { root += "/" }
        let indexData = try await get(JavaURIReference.resolve(root: root, "index.txt"))
        return Index(root: root, paths: Self.indexLines(String(decoding: indexData, as: UTF8.self)))
    }

    /// Phase 2 (local, blocking): the hash manifest of the data directory (empty when missing).
    public static func loadManifest(dataDir: URL) throws(DefinitionUpdaterError) -> JavaProperties {
        try loadManifest(RawFileSystem.javaPath(of: dataDir))
    }

    /// Phase 3 (network only): every safe path of the index downloaded. A path Java `URI.resolve` rejects fails
    /// the whole update; a failed download is recorded as `FAILED`.
    public func download(_ index: Index) async throws(DefinitionUpdaterError) -> Downloaded {
        // Download everything first, so the definitions are checked against the new multiplier sets.
        // Java `LinkedHashMap<String, …>`: key by UTF-16, position of the first occurrence.
        var remoteOrder: [String] = []
        var remote: [[UInt16]: Data] = [:]
        var out: [FileResult] = []
        for path in index.paths {
            guard Self.isSafe(path) else {
                out.append(FileResult(path: path, status: .failed, detail: "neplatná cesta"))
                continue
            }
            let reference = try JavaURIReference.resolve(root: index.root, path)
            do throws(DefinitionUpdaterError) {
                let body = try await get(reference)
                let key = Array(path.utf16)
                if remote.updateValue(body, forKey: key) == nil {
                    remoteOrder.append(path)
                }
            } catch {
                out.append(FileResult(path: path, status: .failed, detail: error.message))
            }
        }
        return Downloaded(order: remoteOrder, bodies: remote, failed: out)
    }

    /// Phase 4 (local, blocking): the definitions checked against the known multiplier sets, the hashes compared,
    /// the new and updated files written, the manifest saved.
    public static func apply(_ downloaded: Downloaded, manifest initial: JavaProperties,
                             dataDir: URL) throws(DefinitionUpdaterError) -> Report {
        let dataPath = RawFileSystem.javaPath(of: dataDir)
        var manifest = initial
        var out: [FileResult] = downloaded.failed
        let sets = Self.knownSets(dataPath, downloaded: downloaded.order)

        for path in downloaded.order {
            let body = downloaded.bodies[Array(path.utf16)]!
            if let id = Self.stem(path, prefix: "contests/") {
                let check = DefinitionEditing.check(String(decoding: body, as: UTF8.self), fileId: id, knownSets: sets)
                if check.hasErrors {
                    out.append(FileResult(path: path, status: .failed,
                                          detail: "nevalidní definice: " + check.issues[0].message))
                    continue
                }
            }
            let target = RawFileSystem.resolve(dataPath, path)
            let remoteHash = Self.sha256(body)
            let status: Status
            if !Self.exists(target) {
                status = .new
            } else {
                let localHash = Self.sha256(try Self.readAll(target))
                if localHash == remoteHash {
                    status = .unchanged
                } else if localHash == manifest[path] {
                    status = .updated
                } else {
                    out.append(FileResult(path: path, status: .skippedLocalChanges, detail: "soubor je lokálně upravený"))
                    continue
                }
            }
            if status != .unchanged {
                try Self.write(target, body)
            }
            manifest[path] = remoteHash
            out.append(FileResult(path: path, status: status, detail: ""))
        }
        try Self.saveManifest(dataPath, manifest)
        return Report(files: out)
    }

    /// Java `get`: only HTTP 200, otherwise „HTTP <code> pro <uri>" (the URI as
    /// `URI.toString()`, with the fragment). Cancelling the task = Java interrupt.
    private func get(_ reference: JavaURIReference) async throws(DefinitionUpdaterError) -> Data {
        let response: (status: Int, data: Data)
        do {
            response = try await fetcher.fetch(reference.request)
        } catch is CancellationError {
            throw DefinitionUpdaterError(message: "Stahování přerušeno")
        } catch let error as URLError where error.code == .cancelled {
            throw DefinitionUpdaterError(message: "Stahování přerušeno")
        } catch {
            throw DefinitionUpdaterError(message: error.localizedDescription)
        }
        guard response.status == 200 else {
            throw DefinitionUpdaterError(message: "HTTP \(response.status) pro " + reference.display)
        }
        return response.data
    }

    // MARK: - helpers (Java static methods)

    /// Lines of `index.txt`: Java `lines()` (breaks `\n`, `\r`, `\r\n`) → `strip()`
    /// → without empty ones and without those starting with `#`.
    static func indexLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        var previousCR = false
        var pending = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" && previousCR {
                previousCR = false
                continue
            }
            previousCR = scalar == "\r"
            if scalar == "\n" || scalar == "\r" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
                pending = false
            } else {
                current.append(scalar)
                pending = true
            }
        }
        if pending { lines.append(String(current)) }
        return lines.map(JavaText.strip).filter { !$0.isEmpty && $0.unicodeScalars.first != "#" }
    }

    /// Java `isSafe`: does not start with `/`, contains no `..`, `\` or `:`.
    static func isSafe(_ path: String) -> Bool {
        let units = Array(path.utf16)
        if units.first == UInt16(UInt8(ascii: "/")) { return false }
        if units.contains(UInt16(UInt8(ascii: "\\"))) || units.contains(UInt16(UInt8(ascii: ":"))) { return false }
        return !zip(units, units.dropFirst()).contains { $0 == UInt16(UInt8(ascii: ".")) && $1 == UInt16(UInt8(ascii: ".")) }
    }

    /// Java `sha256`: SHA-256, lower-case hex.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `path.startsWith(prefix) && path.endsWith(".yaml")` → the middle (by UTF-16).
    private static func stem(_ path: String, prefix: String) -> String? {
        let units = Array(path.utf16)
        let head = Array(prefix.utf16)
        let tail = Array(".yaml".utf16)
        guard units.starts(with: head), units.count >= head.count + tail.count,
              units.suffix(tail.count).elementsEqual(tail) else { return nil }
        return String(decoding: units[head.count..<(units.count - tail.count)], as: UTF16.self)
    }

    /// Java `TreeSet(knownSets(dataDir/multipliers))` + stems of the downloaded
    /// `multipliers/*.yaml`: sorted by UTF-16, without duplicates (by UTF-16).
    private static func knownSets(_ dataPath: String, downloaded: [String]) -> [String] {
        let local = DefinitionEditing.knownSets(URL(fileURLWithPath: RawFileSystem.resolve(dataPath, "multipliers")))
        let all = (local + downloaded.compactMap { stem($0, prefix: "multipliers/") })
            .map { Array($0.utf16) }
            .sorted { $0.lexicographicallyPrecedes($1) }
        var out: [[UInt16]] = []
        for set in all where out.last != set {
            out.append(set)
        }
        return out.map { String(decoding: $0, as: UTF16.self) }
    }

    // MARK: - files (Java java.nio.file)

    /// Java `Files.exists` (follows symbolic links).
    private static func exists(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0
    }

    /// Java `Files.readAllBytes`.
    private static func readAll(_ path: String) throws(DefinitionUpdaterError) -> Data {
        switch RawFileSystem.readFile(RawPath(path)) {
        case .data(let data): return data
        case .openFailed: throw DefinitionUpdaterError(message: path)
        case .readFailed(let reason): throw DefinitionUpdaterError(message: reason)
        }
    }

    /// Text of the Java exception from `UnixException.translateToIOException`:
    /// `AccessDenied`/`NoSuchFile`/`FileAlreadyExists` = path only, otherwise „path: reason".
    private static func ioMessage(_ path: String, _ code: Int32) -> String {
        switch code {
        case EACCES, ENOENT, EEXIST: return path
        default: return path + ": " + String(cString: strerror(code))
        }
    }

    /// Java `Files.createDirectories`: an existing directory is fine;
    /// a file in the path → `FileAlreadyExistsException(path)` (if it is the last
    /// component), otherwise „…: Not a directory" at the following component.
    private static func createDirectories(_ directory: String) throws(DefinitionUpdaterError) {
        if let failure = RawFileSystem.createDirectories(directory) {
            throw DefinitionUpdaterError(message: ioMessage(failure.path, failure.errno))
        }
    }

    /// Java `write`: a temporary `def*.tmp` in the target directory (permissions 0600 like
    /// `createTempFile`) and a move over the target; the temp file does not remain after an error.
    private static func write(_ target: String, _ body: Data) throws(DefinitionUpdaterError) {
        let parent = parentPath(target)
        try createDirectories(parent)
        do {
            try RawFileSystem.writeAtomically([UInt8](body), to: target, temporaryIn: parent, prefix: "def")
        } catch {
            switch error {
            case .createTemporary(let code):
                throw DefinitionUpdaterError(message: ioMessage(parent, code))
            case .write(let temporary, let code), .rename(let temporary, let code):
                throw DefinitionUpdaterError(message: ioMessage(temporary, code))
            }
        }
    }

    /// Writes everything to the open descriptor and closes it.
    private static func writeAll(_ descriptor: Int32, _ body: Data, path: String) throws(DefinitionUpdaterError) {
        let bytes = [UInt8](body)
        var written = 0
        while written < bytes.count {
            let count = bytes[written...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                let code = errno
                close(descriptor)
                throw DefinitionUpdaterError(message: ioMessage(path, code))
            }
            written += count
        }
        guard close(descriptor) == 0 else {
            throw DefinitionUpdaterError(message: ioMessage(path, errno))
        }
    }

    /// Java `Path.getParent()` for a path from `RawFileSystem.resolve` (always with `/`).
    private static func parentPath(_ path: String) -> String {
        guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")) else { return "." }
        if slash == path.utf8.startIndex { return "/" }
        return String(path[..<slash])
    }

    private static func loadManifest(_ dataPath: String) throws(DefinitionUpdaterError) -> JavaProperties {
        let path = RawFileSystem.resolve(dataPath, manifestName)
        guard exists(path) else { return JavaProperties() }
        do {
            return try JavaProperties.load(try readAll(path))
        } catch let error as JavaPropertiesError {
            throw DefinitionUpdaterError(message: error.message)
        } catch let error as DefinitionUpdaterError {
            throw error
        } catch {
            throw DefinitionUpdaterError(message: "\(error)")
        }
    }

    /// Java `saveManifest`: `Files.newOutputStream` (overwrites in place, not atomically)
    /// + `Properties.store` with a Java comment.
    private static func saveManifest(_ dataPath: String, _ manifest: JavaProperties) throws(DefinitionUpdaterError) {
        try createDirectories(dataPath)
        let path = RawFileSystem.resolve(dataPath, manifestName)
        let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else {
            throw DefinitionUpdaterError(message: ioMessage(path, errno))
        }
        try writeAll(descriptor, manifest.store(comments: manifestComment), path: path)
    }
}

/// A path from the index resolved against the root like Java `root.resolve(path)`.
///
/// Checks characters by the grammar of Java `java.net.URI` (RFC 2396): the path may contain
/// `unreserved`, `;:@&=+$,/`, `%XX` escapes and non-ASCII characters that are neither
/// a space (`Character.isSpaceChar`) nor a control character; the query and fragment additionally
/// `?[]`. Otherwise `IllegalArgumentException` with Java's text and an index in UTF-16.
/// The path is normalized like `URI.normalize` (`.` and empty components dropped).
struct JavaURIReference {
    /// Java `URI.toString()` — for the message „HTTP … pro …".
    let display: String
    /// The request as `HttpClient` sends it: without the fragment, NFC, non-ASCII
    /// as UTF-8 `%XX` (`URI.toASCIIString`).
    let request: URL

    static func resolve(root: String, _ child: String) throws(DefinitionUpdaterError) -> JavaURIReference {
        let units = Array(child.utf16)
        let n = units.count
        func fail(_ reason: String, _ index: Int) -> DefinitionUpdaterError {
            DefinitionUpdaterError(message: "\(reason) at index \(index): \(child)")
        }
        func check(_ start: Int, _ end: Int, _ allowed: Set<UInt16>, _ what: String) throws(DefinitionUpdaterError) {
            var p = start
            while p < end {
                let c = units[p]
                if c != 0 && c < 128 && allowed.contains(c) {
                    p += 1
                } else if c == UInt16(UInt8(ascii: "%")) {
                    guard p + 3 <= end, isHex(units[p + 1]), isHex(units[p + 2]) else {
                        throw fail("Malformed escape pair", p)
                    }
                    p += 3
                } else if c > 128 && !isSpaceChar(c) && !isISOControl(c) {
                    p += 1
                } else {
                    throw fail("Illegal character in " + what, p)
                }
            }
        }
        let questionOrHash = units.firstIndex { $0 == UInt16(UInt8(ascii: "?")) || $0 == UInt16(UInt8(ascii: "#")) } ?? n
        try check(0, questionOrHash, pathChars, "path")
        var p = questionOrHash
        var query: String?
        if p < n && units[p] == UInt16(UInt8(ascii: "?")) {
            let end = units[(p + 1)...].firstIndex(of: UInt16(UInt8(ascii: "#"))) ?? n
            try check(p + 1, end, uricChars, "query")
            query = String(decoding: units[(p + 1)..<end], as: UTF16.self)
            p = end
        }
        var fragment: String?
        if p < n && units[p] == UInt16(UInt8(ascii: "#")) {
            try check(p + 1, n, uricChars, "fragment")
            fragment = String(decoding: units[(p + 1)...], as: UTF16.self)
        }
        let path = normalize(String(decoding: units[..<questionOrHash], as: UTF16.self))

        // Root without query and fragment, truncated after the last `/` of the path.
        var base = Array(root.utf16)
        if let cut = base.firstIndex(where: { $0 == UInt16(UInt8(ascii: "?")) || $0 == UInt16(UInt8(ascii: "#")) }) {
            base = Array(base[..<cut])
        }
        if let slash = base.lastIndex(of: UInt16(UInt8(ascii: "/"))) {
            base = Array(base[...slash])
        }
        let directory = String(decoding: base, as: UTF16.self)
        let withoutFragment = directory + path + (query.map { "?" + $0 } ?? "")
        let display = withoutFragment + (fragment.map { "#" + $0 } ?? "")
        guard let request = URL(string: asciiEncoded(withoutFragment)) else {
            throw DefinitionUpdaterError(message: "Neplatná URL: " + display)
        }
        return JavaURIReference(display: display, request: request)
    }

    /// Java `URI.normalize` for a relative path without `..` (which `isSafe` excludes):
    /// `.` and empty components (doubled `/`) dropped, a trailing `/` stays.
    private static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let kept = segments.filter { !$0.isEmpty && $0 != "." }
        let trailingSlash = segments.last == "" || segments.last == "."
        guard !kept.isEmpty else { return "" }
        return kept.joined(separator: "/") + (trailingSlash ? "/" : "")
    }

    /// Java `URI.toASCIIString`: NFC, then non-ASCII as UTF-8 `%XX` (upper-case hex).
    private static func asciiEncoded(_ text: String) -> String {
        var out = ""
        for byte in text.precomposedStringWithCanonicalMapping.utf8 {
            if byte < 0x80 {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    private static func isHex(_ c: UInt16) -> Bool {
        (UInt16(UInt8(ascii: "0"))...UInt16(UInt8(ascii: "9"))).contains(c)
            || (UInt16(UInt8(ascii: "a"))...UInt16(UInt8(ascii: "f"))).contains(c)
            || (UInt16(UInt8(ascii: "A"))...UInt16(UInt8(ascii: "F"))).contains(c)
    }

    /// Java `Character.isSpaceChar(char)`: categories Zs, Zl, Zp.
    private static func isSpaceChar(_ c: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false } // surrogate
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    /// Java `Character.isISOControl(char)`.
    private static func isISOControl(_ c: UInt16) -> Bool {
        c <= 0x1F || (0x7F...0x9F).contains(c)
    }

    private static func ascii(_ text: String) -> Set<UInt16> { Set(text.utf16) }

    private static let alphanum = ascii("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    /// `unreserved` = alphanumeric + `mark`.
    private static let unreserved = alphanum.union(ascii("-_.!~*'()"))
    /// `L_PATH` = `pchar` (`unreserved`, `:@&=+$,`) + `;/`.
    private static let pathChars = unreserved.union(ascii(":@&=+$,;/"))
    /// `L_URIC` = `reserved` (`;/?:@&=+$,[]`) + `unreserved`.
    private static let uricChars = unreserved.union(ascii(";/?:@&=+$,[]"))
}
