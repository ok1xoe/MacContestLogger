import CryptoKit
import Dispatch
import Foundation

/// Core of the executable target `mcl-scorecheck`: walks a file or a directory of logs via
/// `ScoreCheck.check` and produces a TSV **byte-identical** to the reference from the Java generator
/// a maintainer-only probe (format in the README there).
///
/// It lives in the library (not in `main.swift`) so it can be called from tests without launching the binary.
///
/// Which header lines are **compared** with the Java reference: `format`, `columns`,
/// `dxcc-source`, `cty.dat-sha256` / `dxcc.json-sha256`, `contest-data-sha256`, `logs`
/// and all data lines. The lines `set`, `java.*`, `java-*` describe the Java side;
/// Swift writes `implementation` instead of them.
public enum ScoreCheckReport {

    /// Reference format version (same as the generator).
    public static let format = "scorecheck-reference 1"
    /// Key length: the first 16 hex characters of the SHA-256 of the file content.
    static let keyHex = 16
    /// Longer text (after escaping) is replaced by a hash — free text from the log must not go into the reference.
    static let maxText = 80
    public static let columns = "key file status contest qsoCount qsoPoints multTotal multByGroup computed claimed"
        + " unresolvedCount skipReason errorClass error"

    public enum DxccMode: String, Sendable { case cty, json }

    public struct Options: Sendable {
        public var input: URL
        public var contestData: URL
        public var dxccMode: DxccMode
        public var dxccFile: URL
        public var jobs: Int
        public var setName: String
        public init(input: URL, contestData: URL, dxccMode: DxccMode, dxccFile: URL, jobs: Int = 1,
                    setName: String? = nil) {
            self.input = input
            self.contestData = contestData
            self.dxccMode = dxccMode
            self.dxccFile = dxccFile
            self.jobs = jobs
            self.setName = setName ?? input.lastPathComponent
        }
    }

    public struct Output: Sendable {
        /// Header lines (`# key: value`, without the line ending).
        public let header: [String]
        /// Data lines in the order of the file path.
        public let rows: [String]
        /// Counts by status (`OK`, `ERR`, `EXC`, `UNREADABLE`).
        public let counts: [String: Int]

        /// The whole file: header + lines, each terminated by `\n`.
        public var text: String {
            var out = ""
            for line in header { out += line + "\n" }
            for line in rows { out += line + "\n" }
            return out
        }
    }

    public struct UsageError: Error, CustomStringConvertible, Sendable {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    // MARK: - run

    public static func run(_ options: Options) throws(UsageError) -> Output {
        let definitions: [ContestDefinition]
        let registry: MultiplierSetRegistry
        let dxcc: any DxccLookup
        let dxccHash: String
        let dxccKey: String
        do {
            dxccKey = options.dxccMode == .cty ? "cty.dat-sha256" : "dxcc.json-sha256"
            let dxccData = try Data(contentsOf: options.dxccFile)
            dxccHash = sha256Hex(dxccData)
            switch options.dxccMode {
            case .cty:
                dxcc = DxccSpecialCases(CtyDxccResolver.fromData(dxccData))
            case .json:
                dxcc = DxccSpecialCases(try DxccResolver.fromData(dxccData))
            }
            definitions = try ContestCatalog.fromDir(options.contestData.appendingPathComponent("contests"))
            registry = try MultiplierSetRegistry(dxcc: dxcc)
                .loadDir(options.contestData.appendingPathComponent("multipliers"))
        } catch {
            throw UsageError("Nelze načíst data: \(error)")
        }
        let treeHash = try Self.treeHash(options.contestData)
        let files = try collectFiles(options.input)

        var rows = [String](repeating: "", count: files.count)
        let jobs = max(1, options.jobs)
        if jobs == 1 || files.count < 2 {
            for (i, file) in files.enumerated() {
                rows[i] = rowFor(file: file, definitions: definitions, dxcc: dxcc, registry: registry)
            }
        } else {
            // the real limit: `jobs` worker threads take indices from one counter
            rows.withUnsafeMutableBufferPointer { buffer in
                let out = SlotWriter(buffer.baseAddress!)
                let next = Counter()
                let group = DispatchGroup()
                for _ in 0..<min(jobs, files.count) {
                    DispatchQueue.global().async(group: group) {
                        while true {
                            let i = next.take()
                            if i >= files.count { break }
                            out.set(i, rowFor(file: files[i], definitions: definitions, dxcc: dxcc,
                                              registry: registry))
                        }
                    }
                }
                group.wait()
            }
        }

        var counts: [String: Int] = [:]
        for row in rows {
            let status = row.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)[2]
            counts[String(status), default: 0] += 1
        }
        let header = [
            "# format: " + format,
            "# set: " + options.setName,
            "# implementation: mcl-scorecheck (swift)",
            "# contest-data-sha256: " + treeHash,
            "# dxcc-source: " + options.dxccMode.rawValue,
            "# " + dxccKey + ": " + dxccHash,
            "# logs: " + String(rows.count),
            "# columns: " + columns,
        ]
        return Output(header: header, rows: rows, counts: counts)
    }

    /// Writing to a preallocated array from several threads; each index is written by exactly one thread
    /// (the thread takes the index from the shared counter `Counter`), so there is no shared write.
    private struct SlotWriter: @unchecked Sendable {
        let base: UnsafeMutablePointer<String>
        init(_ base: UnsafeMutablePointer<String>) { self.base = base }
        func set(_ index: Int, _ value: String) { base[index] = value }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func take() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value - 1
        }
    }

    /// One line: `key \t file \t <columns>`.
    static func rowFor(file: URL, definitions: [ContestDefinition], dxcc: any DxccLookup,
                       registry: MultiplierSetRegistry) -> String {
        let name = file.lastPathComponent
        guard let data = try? Data(contentsOf: file) else {
            // read error (permissions, race…): a real UNREADABLE as `readFileQuietly` in the CLI,
            // key `\N` (we do not know the bytes); the Java generator would crash here on `readAllBytes`
            let outcome = ScoreCheck.LogOutcome(
                status: .unreadable, result: ScoreCheck.errorResult(name, nil, nil, "nelze načíst"),
                skipReason: nil, exceptionClass: nil)
            return "\\N\t" + escape(name) + "\t" + columns(outcome)
        }
        let outcome = ScoreCheck.check(fileName: name, data: data, definitions: definitions, dxcc: dxcc,
                                       registry: registry)
        return String(sha256Hex(data).prefix(keyHex)) + "\t" + escape(name) + "\t" + columns(outcome)
    }

    /// Columns `status` … `error` like `ScoreCheckRefGen.cols`.
    public static func columns(_ outcome: ScoreCheck.LogOutcome) -> String {
        let r = outcome.result
        var groups = ""
        for entry in r.multByGroup.entries {
            if !groups.isEmpty { groups += "," }
            groups += escape(entry.key) + "=" + (entry.value.map { String($0) } ?? "\\N")
        }
        let cols: [String] = [
            outcome.status.rawValue, text(r.contest), String(r.qsoCount), String(r.qsoPoints),
            String(r.multTotal), groups, String(r.computed), r.claimed.map { String($0) } ?? "\\N",
            String(r.unresolvedCalls.count), escape(outcome.skipReason), escape(outcome.exceptionClass),
            text(r.error),
        ]
        return cols.joined(separator: "\t")
    }

    // MARK: - text

    /// `\` → `\\`, outside `0x20..0x7E` → `\uXXXX` by UTF-16 units, `nil` → `\N`.
    public static func escape(_ text: String?) -> String {
        guard let text else { return "\\N" }
        var out = ""
        for unit in text.utf16 {
            if unit == 0x5C {
                out += "\\\\"
            } else if unit >= 0x20 && unit < 0x7F {
                out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            } else {
                let hex = String(unit, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            }
        }
        return out
    }

    /// Text from the log: escaped; if longer than 80 characters, `#sha256:` + 16 hex of the hash of the escaped form.
    public static func text(_ value: String?) -> String {
        let escaped = escape(value)
        if value == nil || escaped.utf8.count <= maxText { return escaped }
        return "#sha256:" + String(sha256Hex(Data(escaped.utf8)).prefix(16))
    }

    // MARK: - files and hashes

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Input: a file (a single log, no extension filter) or a directory (recursively `.log`/`.cbr`/`.cabrillo`
    /// regardless of case, sorted by the bytes of the relative path — like `Path.sorted()` in Java).
    static func collectFiles(_ input: URL) throws(UsageError) -> [URL] {
        var isDir = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDir) else {
            throw UsageError("Vstup neexistuje: \(input.path)")
        }
        if !isDir.boolValue { return [input] }
        let all = regularFiles(under: input)
        let wanted = all.filter { rel in
            let lower = Array(rel.lowercased().utf16)
            return [".log", ".cbr", ".cabrillo"].contains { suffix in
                let tail = Array(suffix.utf16)
                return lower.count >= tail.count && Array(lower.suffix(tail.count)) == tail
            }
        }
        return wanted.map { input.appendingPathComponent($0) }
    }

    /// Regular files under the directory (a symlink to a file is taken as a file — `Files.isRegularFile`),
    /// relative paths sorted by UTF-8 bytes.
    static func regularFiles(under dir: URL) -> [String] {
        var found: [String] = []
        let base = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
        guard let walker = FileManager.default.enumerator(atPath: dir.path) else { return [] }
        for case let rel as String in walker {
            var st = stat()
            if stat(base + rel, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG {
                found.append(rel)
            }
        }
        found.sort { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        return found
    }

    /// Tree hash = SHA-256 of lines `<sha256>  ./<rel>\n` sorted by path (same as the generator).
    static func treeHash(_ dir: URL) throws(UsageError) -> String {
        var listing = ""
        for rel in regularFiles(under: dir) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(rel)) else {
                throw UsageError("Nelze číst \(rel) v \(dir.path)")
            }
            listing += sha256Hex(data) + "  ./" + rel + "\n"
        }
        return sha256Hex(Data(listing.utf8))
    }
}
