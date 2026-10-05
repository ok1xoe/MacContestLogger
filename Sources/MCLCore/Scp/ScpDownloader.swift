import Foundation

/// Download of the current `MASTER.SCP` (N1MM Tools → Download latest Check Partial file, DXLog Update Super Check
/// Partial database) — Java `scp/ScpDownloader`. The target file is overwritten only after checking that it really is
/// a list of callsigns — a broken download (an HTML error page, a truncated transfer) thus does not destroy the old file.
///
/// Over `JavaHttpClient` (connect timeout 10 s, `Redirect.NORMAL`, request timeout 60 s). **Blocks** —
/// call only from your own thread, never from the main one (guarded by `JavaHttpClient`) or Swift's shared pool.
///
/// Deliberate divergences from Java v1.1.1: Java writes the body straight into a temporary
/// `master<n>.scp.part` created **before** the request, here the body is held in memory and the temporary file is created only
/// after the check (`RawFileSystem.writeAtomically`, permissions 0600, `rename` over the target) — an error creating the temporary
/// file is thus reported only after the download; the result (target 0600, no `*.scp.part` after an error) is the same.
/// Java's thread interruption ("Stahování přerušeno") does not exist in Swift.
public final class ScpDownloader: Sendable {

    /// Official source (supercheckpartial.com).
    public static let defaultURI = "https://www.supercheckpartial.com/MASTER.SCP"

    /// Fewer callsigns is no longer a master.scp (a real one has tens of thousands).
    static let minCalls = 1000

    /// Java `Pattern.compile("[A-Z0-9/]{3,15}")` (ASCII).
    private static let callPattern: JavaRegex = {
        do {
            return try JavaRegex("[A-Z0-9/]{3,15}")
        } catch {
            preconditionFailure("pevný vzor volačky musí jít zkompilovat: \(error)")
        }
    }()

    /// Result: where it was saved (Java `Path.toString()` of the target) and how many callsigns the file has.
    public struct Result: Equatable, Sendable {
        public let file: String
        public let calls: Int

        public init(file: String, calls: Int) {
            self.file = file
            self.calls = calls
        }
    }

    private let http: JavaHttpClient

    public convenience init() {
        self.init(http: JavaHttpClient(connectTimeout: 10, redirect: .normal))
    }

    init(http: JavaHttpClient) {
        self.http = http
    }

    /// Java `download(uri, target)`: errors as Java exceptions — network (`JavaHttpClient`), status ≠ 200
    /// ("Server vrátil HTTP 404"), content (`validate`), files (`UnixException` texts).
    public func download(_ uri: String, to target: String) throws(JavaHttpError) -> Result {
        let file = RawFileSystem.javaPath(target)
        let directory = Self.parent(of: Self.absolute(file))
        do {
            try Self.createDirectories(directory)
        } catch {
            throw .io(error)
        }
        let response = try http.send(method: "GET", url: uri, requestTimeout: 60)
        if response.status != 200 {
            throw .io(JavaIOError("Server vrátil HTTP " + String(response.status)))
        }
        let bytes = [UInt8](response.body)
        let calls: Int
        do {
            calls = try Self.validate(bytes)
        } catch {
            throw .io(error)
        }
        do {
            try RawFileSystem.writeAtomically(bytes, to: file, temporaryIn: directory, prefix: "master",
                                              suffix: ".scp.part")
        } catch {
            throw .io(Self.ioError(error, target: file, directory: directory))
        }
        return Result(file: file, calls: calls)
    }

    /// Number of callsigns; an exception when the content does not look like master.scp (fewer than 1 000 callsigns, or more
    /// other lines than an integer tenth of the callsigns). Latin-1 lines like `Files.readAllLines`.
    static func validate(_ bytes: [UInt8]) throws(JavaIOError) -> Int {
        var calls = 0
        var bad = 0
        for line in JavaLines.split(ScpDatabase.latin1(Data(bytes))) {
            let text = JavaText.toUpperCase(JavaText.trim(line))
            if text.isEmpty || text.utf16.first == 0x23 { continue }
            if callPattern.matches(text) {
                calls += 1
            } else {
                bad += 1
            }
        }
        if calls < minCalls || bad > calls / 10 {
            throw JavaIOError("Stažený soubor nevypadá jako master.scp (\(calls) volaček, "
                + "\(bad) jiných řádků) — ponechávám původní")
        }
        return calls
    }

    // MARK: - Files as java.nio.file

    /// Java `toAbsolutePath()`.
    private static func absolute(_ path: String) -> String {
        if path.utf8.first == UInt8(ascii: "/") { return path }
        return RawFileSystem.resolve(FileManager.default.currentDirectoryPath, path)
    }

    /// Java `getParent()` of an absolute path (the root for `/x`).
    private static func parent(of path: String) -> String {
        guard let slash = path.utf8.lastIndex(of: UInt8(ascii: "/")) else { return "." }
        if slash == path.utf8.startIndex { return "/" }
        return String(path[..<slash])
    }

    /// Java `Files.createDirectories`: an existing directory is fine; a file in place of a directory →
    /// `FileAlreadyExistsException(path)`, a file higher up the path → "…: Not a directory".
    private static func createDirectories(_ directory: String) throws(JavaIOError) {
        if let failure = RawFileSystem.createDirectories(directory) {
            throw unixError(failure.path, nil, failure.errno)
        }
    }

    private static func ioError(_ failure: RawFileSystem.AtomicWriteFailure, target: String,
                                directory: String) -> JavaIOError {
        switch failure {
        case .createTemporary(let code):
            return unixError(directory, nil, code)
        case .write(let temporary, let code):
            return unixError(temporary, nil, code)
        case .rename(let temporary, let code):
            return unixError(temporary, target, code)
        }
    }

    /// Java `UnixException.translateToIOException(file, other)`: `EACCES`/`ENOENT`/`EEXIST` = paths only,
    /// otherwise `FileSystemException` with a reason (`strerror`); `other` as "file -> other".
    private static func unixError(_ file: String, _ other: String?, _ code: Int32) -> JavaIOError {
        let paths: String = other.map { file + " -> " + $0 } ?? file
        switch code {
        case EACCES: return JavaIOError(paths, javaClass: "java.nio.file.AccessDeniedException")
        case ENOENT: return JavaIOError(paths, javaClass: "java.nio.file.NoSuchFileException")
        case EEXIST: return JavaIOError(paths, javaClass: "java.nio.file.FileAlreadyExistsException")
        default:
            let reason = String(cString: strerror(code))
            return JavaIOError(paths + ": " + reason, javaClass: "java.nio.file.FileSystemException")
        }
    }
}
