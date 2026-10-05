import Foundation

/// The pure part of importing QSOs (File → Import) and of merging another log (N1MM Merge logs): format
/// detection, reading, the exchange in entry-window form, and preparing the QSOs for the logbook. Port of
/// `AppState.importQsos` (`AS:4154-4180`) and `AppState.mergeLog` (`AS:4115-4152`) of the Kotlin UI v1.1.1; the app
/// model runs the steps off the main thread and inserts the result in one logbook mutation.
///
/// Kotlin behaviour kept:
/// - **two different detection rules**: import treats a file as ADIF by its extension or when the content contains
///   `<eor>` **or `<call`**; merge knows only the extension and `<eor>` (`AS:4129` against `AS:4160-4161`), so a
///   single ADIF record without `<eor>` merges as Cabrillo (= nothing);
/// - the file name is lower-cased with Kotlin `lowercase()` (`Locale.ROOT`, `İ` → `i̇`), the content is read
///   like `Files.readString` (strict UTF-8, the BOM stays);
/// - the readers never set `isImported` (probe row `IMP`): import leaves it `false`, merge sets it on the QSOs it
///   adds;
/// - the exchange is converted only with an active definition, with the fields of the counterpart's call.
///
/// Divergences: an exception of a reader is the caller's "Nelze přečíst soubor: %s" with nothing
/// inserted (Kotlin crashes); a foreign `.sqlite` is read from a **temporary copy** (`readDatabase`) — Kotlin opens
/// it in place, which migrates an older schema of the source file (probe row `DB.migrate`) and creates a missing
/// one (`DB.missing`).
public enum LogImporter {

    public enum Format: Equatable, Sendable {
        case adif
        case cabrillo

        /// The word in the import status text (`AS:4178`).
        public var label: String {
            switch self {
            case .adif: return "ADIF"
            case .cabrillo: return "Cabrillo"
            }
        }
    }

    // MARK: - detection

    /// Import (`AS:4159-4161`): `.adi`/`.adif`, or the content contains `<eor>` or `<call` ignoring case.
    public static func importFormat(fileName: String, content: String) -> Format {
        let name: String = JavaText.toLowerCase(fileName)
        if hasSuffix(name, ".adi") || hasSuffix(name, ".adif") {
            return .adif
        }
        if containsIgnoringCase(content, "<eor>") || containsIgnoringCase(content, "<call") {
            return .adif
        }
        return .cabrillo
    }

    /// Merge (`AS:4129`): `.adi`/`.adif`, or the content contains `<eor>` ignoring case — **not** `<call`.
    public static func mergeFormat(fileName: String, content: String) -> Format {
        let name: String = JavaText.toLowerCase(fileName)
        if hasSuffix(name, ".adi") || hasSuffix(name, ".adif") || containsIgnoringCase(content, "<eor>") {
            return .adif
        }
        return .cabrillo
    }

    /// Merge from a MacContestLogger database (`AS:4120`): `.sqlite` or `.db` after `lowercase()`.
    public static func isDatabase(fileName: String) -> Bool {
        let name: String = JavaText.toLowerCase(fileName)
        return hasSuffix(name, ".sqlite") || hasSuffix(name, ".db")
    }

    // MARK: - reading

    /// Java `Files.readString(path)`: strict UTF-8 keeping the BOM. Errors as Java (probe rows `FS`, `MAL`): a
    /// missing file `NoSuchFileException: <path>`, no permission `AccessDeniedException: <path>`, a directory
    /// `IOException: Is a directory`, invalid UTF-8 `MalformedInputException: Input length = <n>`.
    ///
    /// Blocking POSIX I/O — call off the main thread and off the shared pool.
    public static func readText(_ url: URL) throws(JavaIOError) -> String {
        let path: String = RawFileSystem.javaPath(of: url)
        let descriptor: Int32 = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw openError(path, errno)
        }
        defer { close(descriptor) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count: Int = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 {
                let code: Int32 = errno
                if code == EINTR { continue }
                throw JavaIOError(String(cString: strerror(code)))
            }
            bytes.append(contentsOf: buffer[0..<count])
        }
        if let length = Utf8Text.readStringMalformedLength(bytes) {
            throw JavaIOError("Input length = " + String(length), javaClass: "java.nio.charset.MalformedInputException")
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// `AdifReader().read(content)` or `CabrilloReader().read(content)`. The errors are `JavaThrowable`
    /// (`JavaIndexOutOfBoundsError`, `CabrilloReaderError`).
    public static func read(_ format: Format, content: String) throws -> [Qso] {
        switch format {
        case .adif: return try AdifReader().read(content)
        case .cabrillo: return try CabrilloReader().read(content)
        }
    }

    /// The exchange in entry-window form (`AS:4129-4133`, `AS:4164-4168`): with an active definition every QSO's
    /// `exchangeRcvd` becomes `ImportedExchange.toFlat(def, fields(call), q)` (`nil` → empty); without one nothing
    /// changes. An error of `fields` (the station class expression) propagates. Kotlin catches it on the **merge**
    /// path (inside `runCatching`, `AS:4118-4135` → `IoTexts.mergeUnreadable` with its message) but not on the
    /// import path (`AS:4164-4168`, a crash).
    public static func applyExchange(_ qsos: [Qso], definition: ContestDefinition?,
                                     fields: (String) throws -> [ContestDefinition.ExchangeField]) rethrows -> [Qso] {
        guard let definition else {
            return qsos
        }
        var out: [Qso] = []
        out.reserveCapacity(qsos.count)
        for var q in qsos {
            let active = try fields(q.call)
            q.exchangeRcvd = ImportedExchange.toFlat(definition, active, q) ?? ""
            out.append(q)
        }
        return out
    }

    /// Import (`AS:4164-4173`): the exchange (`applyExchange`), then `fillDxcc` (only what is missing) on every QSO.
    /// The QSOs keep `isImported == false` and get their contest from `LogbookService.log`.
    public static func prepareImport(_ qsos: [Qso], definition: ContestDefinition?,
                                     fields: (String) throws -> [ContestDefinition.ExchangeField],
                                     dxcc: (any DxccLookup)?) rethrows -> [Qso] {
        var out: [Qso] = try applyExchange(qsos, definition: definition, fields: fields)
        for index in out.indices {
            DxccFiller.fill(&out[index], dxcc)
        }
        return out
    }

    /// Merge (`AS:4138-4145`): `LogMerger.merge(existing, incoming)`; every QSO to add gets `id = nil`,
    /// `contestId` = the active contest (`nil` → empty, Java `null`), `isImported = true` and `fillDxcc`.
    /// `incoming` from a file has its exchange converted already (`applyExchange`), from a database not.
    public static func prepareMerge(existing: [Qso], incoming: [Qso], activeContestId: String?,
                                    dxcc: (any DxccLookup)?) -> (toAdd: [Qso], duplicates: Int) {
        let result = LogMerger.merge(existing: existing, incoming: incoming)
        var toAdd: [Qso] = []
        toAdd.reserveCapacity(result.toAdd.count)
        for var q in result.toAdd {
            q.id = nil
            q.contestId = activeContestId ?? ""
            q.imported = true
            DxccFiller.fill(&q, dxcc)
            toAdd.append(q)
        }
        return (toAdd, result.duplicates)
    }

    /// The QSOs a database contributes (`AS:4122-4125`): those of the active contest when it has any, otherwise all.
    /// Contest ids compare by UTF-16 units (Kotlin `==`); no active contest = Java `null` = empty here.
    public static func databaseSource(_ all: [Qso], activeContestId: String?) -> [Qso] {
        let active: String = activeContestId ?? ""
        let same: [Qso] = all.filter { $0.contestId.utf16.elementsEqual(active.utf16) }
        return same.isEmpty ? all : same
    }

    /// Reads a foreign MacContestLogger database for a merge **without touching it**: symbolic links are
    /// resolved first (a copied link would open the source in place), the real file and its side files (`-journal`,
    /// so a hot journal is rolled back in the copy as Kotlin would in place, and `-wal`) are copied to a temporary
    /// directory and made writable (a read-only older-schema source still migrates in the copy), the copy is opened with `LogbookRepository` (which migrates
    /// an older schema of the copy, as Kotlin does to the source), `findAll()` is filtered with `databaseSource`, and
    /// the copy is removed.
    ///
    /// - A missing file gives no QSOs (Kotlin creates an empty database there and merges nothing; the source is
    ///   not created here).
    /// - A directory, an unreadable file or one that is not a database: `LogbookError` with the Java message
    ///   `Nelze otevřít deník: jdbc:sqlite:<path>` (probe rows `DB.notADatabase`, `DB.directory`) naming the
    ///   **source** path.
    ///
    /// Blocking file and SQLite I/O — call off the main thread and off the shared pool.
    public static func readDatabase(at url: URL, activeContestId: String?) throws -> [Qso] {
        let openFailed = LogbookError("Nelze otevřít deník: jdbc:sqlite:" + url.path)
        let source: String = url.resolvingSymlinksInPath().path
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source, isDirectory: &isDirectory) else {
            return []
        }
        if isDirectory.boolValue {
            throw openFailed
        }
        let workDir: URL = manager.temporaryDirectory
            .appendingPathComponent("mcl-merge-" + UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: workDir) }
        let copy: URL = workDir.appendingPathComponent("source.sqlite")
        do {
            try manager.createDirectory(at: workDir, withIntermediateDirectories: true)
            try copyWritable(source, to: copy.path)
            for side in ["-journal", "-wal"] {
                // A side file may itself be a link: it is resolved, and anything but a regular file is skipped.
                let resolved: String = URL(fileURLWithPath: source + side).resolvingSymlinksInPath().path
                guard resolved != source, isRegularFile(resolved) else { continue }
                try copyWritable(resolved, to: copy.path + side)
            }
        } catch {
            throw openFailed
        }
        let repository: LogbookRepository
        do {
            repository = try LogbookRepository(url: copy)
        } catch {
            throw openFailed
        }
        defer { repository.close() }
        return databaseSource(try repository.findAll(), activeContestId: activeContestId)
    }

    // MARK: - helpers

    private static func isRegularFile(_ path: String) -> Bool {
        let attributes: [FileAttributeKey: Any]? = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.type] as? FileAttributeType) == .typeRegular
    }

    /// Copies a regular file (never a link: `source` is resolved) and gives the copy owner read/write.
    private static func copyWritable(_ source: String, to target: String) throws {
        let manager = FileManager.default
        try manager.copyItem(atPath: source, toPath: target)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target)
    }

    /// Kotlin `String.endsWith` (UTF-16 units).
    private static func hasSuffix(_ text: String, _ suffix: String) -> Bool {
        let units = Array(text.utf16)
        let tail = Array(suffix.utf16)
        return units.count >= tail.count && Array(units[(units.count - tail.count)...]) == tail
    }

    /// Kotlin `contains(needle, ignoreCase = true)` for an ASCII needle: per UTF-16 unit, `Char.equals(…,
    /// ignoreCase)` (upper-cased, then lower-cased) matches the letters of `<eor>`/`<call` only by their ASCII
    /// counterparts — no other character upper- or lower-cases to `E O R C A L` (the Kelvin sign, long s and dotless
    /// i map to letters outside the needles).
    static func containsIgnoringCase(_ text: String, _ needle: String) -> Bool {
        let hay: [UInt16] = text.utf16.map(asciiLower)
        let pattern: [UInt16] = needle.utf16.map(asciiLower)
        guard !pattern.isEmpty else { return true }
        guard hay.count >= pattern.count else { return false }
        for start in 0...(hay.count - pattern.count) where hay[start] == pattern[0] {
            if Array(hay[start..<(start + pattern.count)]) == pattern {
                return true
            }
        }
        return false
    }

    private static func asciiLower(_ unit: UInt16) -> UInt16 {
        (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit
    }

    /// `UnixException.translateToIOException(file, null)` (JDK 21), as `GoalFileIO`.
    private static func openError(_ file: String, _ code: Int32) -> JavaIOError {
        switch code {
        case EACCES: return JavaIOError(file, javaClass: "java.nio.file.AccessDeniedException")
        case ENOENT: return JavaIOError(file, javaClass: "java.nio.file.NoSuchFileException")
        default:
            let reason = String(cString: strerror(code))
            return JavaIOError(file + ": " + reason, javaClass: "java.nio.file.FileSystemException")
        }
    }
}
