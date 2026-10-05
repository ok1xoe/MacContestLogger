import Foundation
import Testing
@testable import MCLCore

/// `LogImporter` against the Kotlin `AppState.importQsos` (`AS:4154-4180`) and `mergeLog` (`AS:4115-4152`) of
/// v1.1.1 and the maintainer-only probe.
@Suite struct LogImporterTests {

    private typealias Field = ContestDefinition.ExchangeField

    private static let czech = DxccEntity(
        entityCode: 503, name: "Czech Republic", countryCode: "OK", continents: ["EU"],
        cq: [15], itu: [28], lat: 50.0, lon: 15.0)

    private struct Lookup: DxccLookup {
        func resolve(_ callsign: String?) -> DxccEntity? {
            (callsign ?? "").hasPrefix("OK") ? LogImporterTests.czech : nil
        }

        func entities() -> [DxccEntity] {
            [LogImporterTests.czech]
        }
    }

    private static func definition(_ id: String) throws -> ContestDefinition {
        let file = try PointsCalculatorTests.contestsDirectory().appendingPathComponent("\(id).yaml")
        return try ContestDefinitionLoader.loadFile(file)
    }

    private static func received(_ d: ContestDefinition) -> [Field] {
        (d.exchange?.received ?? []).compactMap { $0 }.filter { $0.appliesWhen == nil }
    }

    private static func qso(_ call: String, minute: Int, band: Band = .m20, mode: Mode = .cw,
                            contest: String = "") -> Qso {
        var q = Qso()
        q.call = call
        q.timestampUtc = Date(timeIntervalSince1970: 1_764_288_000 + TimeInterval(60 * minute))
        q.band = band
        q.mode = mode
        q.freqHz = 14_025_000
        q.contestId = contest
        return q
    }

    private static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("log-importer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - detection (`AS:4129`, `AS:4159-4161`, `AS:4120`)

    @Test(arguments: [
        ("log.adi", "", LogImporter.Format.adif), ("LOG.ADIF", "", .adif), ("log.txt", "x <EoR>", .adif),
        ("log.txt", "<CALL:4>W1AW", .adif), ("log.log", "QSO: 14000 CW", .cabrillo), ("log.adi.bak", "", .cabrillo),
        ("LOG.ADİF", "", .cabrillo),
    ])
    func importDetection(_ name: String, _ content: String, _ format: LogImporter.Format) {
        #expect(LogImporter.importFormat(fileName: name, content: content) == format)
    }

    /// Merge does not know `<call` (`AS:4129`) — a single record without `<eor>` merges as Cabrillo.
    @Test(arguments: [
        ("log.adi", "", LogImporter.Format.adif), ("log.ADIF", "", .adif), ("log.txt", "<eor>", .adif),
        ("log.txt", "<call:4>W1AW", .cabrillo), ("log.log", "", .cabrillo),
    ])
    func mergeDetection(_ name: String, _ content: String, _ format: LogImporter.Format) {
        #expect(LogImporter.mergeFormat(fileName: name, content: content) == format)
    }

    @Test func databaseDetection() {
        #expect(LogImporter.isDatabase(fileName: "Contest.SQLITE"))
        #expect(LogImporter.isDatabase(fileName: "log.db"))
        #expect(!LogImporter.isDatabase(fileName: "log.db3"))
        #expect(!LogImporter.isDatabase(fileName: "log.adi"))
    }

    /// Only ASCII letters fold — `<ｅor>` (fullwidth) is not `<eor>`.
    @Test func containsIgnoringCaseIsPerUnit() {
        #expect(LogImporter.containsIgnoringCase("a<EOR>b", "<eor>"))
        #expect(!LogImporter.containsIgnoringCase("<\u{FF45}or>", "<eor>"))
        #expect(!LogImporter.containsIgnoringCase("<eo", "<eor>"))
    }

    // MARK: - reading (`Files.readString`, rows `FS`, `MAL`)

    @Test func readTextLikeFilesReadString() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ok = dir.appendingPathComponent("ok.adi")
        try Data([0xEF, 0xBB, 0xBF, 0x41]).write(to: ok)
        #expect(try LogImporter.readText(ok).unicodeScalars.map(\.value) == [0xFEFF, 0x41])

        let bad = dir.appendingPathComponent("bad.adi")
        try Data([0x41, 0xE2, 0x82, 0x41]).write(to: bad)
        let malformed = #expect(throws: JavaIOError.self) { try LogImporter.readText(bad) }
        #expect(malformed?.javaClass == "java.nio.charset.MalformedInputException")
        #expect(malformed?.message == "Input length = 3")

        let missing = dir.appendingPathComponent("missing.adi")
        let absent = #expect(throws: JavaIOError.self) { try LogImporter.readText(missing) }
        #expect(absent?.javaClass == "java.nio.file.NoSuchFileException")
        #expect(absent?.message == missing.path)

        let sub = dir.appendingPathComponent("adir.adi")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let directory = #expect(throws: JavaIOError.self) { try LogImporter.readText(sub) }
        #expect(directory?.javaClass == "java.io.IOException")
        #expect(directory?.message == "Is a directory")
    }

    /// The readers' exceptions surface as `JavaThrowable` (rows `ADIF.read`, `CAB.read`); the caller
    /// inserts nothing.
    @Test func readerErrorsAreJavaThrowables() {
        let adif = #expect(throws: (any Error).self) { try LogImporter.read(.adif, content: "<CALL:-1>W1AW") }
        #expect(adif.map { JavaThrowables.describe($0).javaClass } == "java.lang.StringIndexOutOfBoundsException")
        let line = "QSO: 14000 CW 2024-01-01 0000 OK1XOE 599 1 W1AW 599 99999999999"
        let cab = #expect(throws: (any Error).self) { try LogImporter.read(.cabrillo, content: line) }
        #expect(cab.map { JavaThrowables.describe($0).message } == "For input string: \"99999999999\"")
    }

    /// Row `IMP`: the readers never set `imported`.
    @Test func readersDoNotMarkImported() throws {
        let adif = try LogImporter.read(.adif, content: "<call:4>W1AW<band:3>20m<mode:2>CW<qso_date:8>20240101"
                                        + "<time_on:4>1200<eor>")
        let cab = try LogImporter.read(.cabrillo, content: "QSO: 14000 CW 2024-01-01 0000 OK1XOE 599 1 W1AW 599 2")
        #expect(adif.count == 1 && cab.count == 1)
        #expect(!adif[0].imported && !cab[0].imported)
    }

    // MARK: - preparing (`AS:4164-4173`, `AS:4138-4145`)

    @Test func prepareImportConvertsExchangeOnlyWithDefinitionAndFillsDxcc() throws {
        let def = try Self.definition("cq-ww-cw")
        let read = try LogImporter.read(.cabrillo, content:
            "QSO: 14025 CW 2026-11-28 0001 OK1XOE 599 15 OK1ABC 599 14\nQSO: 14025 CW 2026-11-28 0002 OK1XOE 599 15 DL1ABC 599 14")
        var asked: [String] = []
        let prepared = LogImporter.prepareImport(read, definition: def, fields: { call in
            asked.append(call)
            return Self.received(def)
        }, dxcc: Lookup())
        #expect(asked == ["OK1ABC", "DL1ABC"])
        #expect(prepared.map(\.exchangeRcvd) == ["599 14", "599 14"])
        #expect(prepared[0].dxccName == "Czech Republic")
        #expect(prepared[1].dxccName == "")
        #expect(prepared.allSatisfy { !$0.imported })

        let plain = LogImporter.prepareImport(read, definition: nil, fields: { _ in
            Issue.record("no fields without a definition")
            return []
        }, dxcc: nil)
        #expect(plain.map(\.exchangeRcvd) == read.map(\.exchangeRcvd))
    }

    /// S11-07: 3 of 5 already in the log (±2 min) → 2 added with `id = nil`, the active contest, `imported`.
    @Test func prepareMergeMarksAddedQsos() {
        let existing = [Self.qso("OK1AA", minute: 0), Self.qso("OK1BB", minute: 5), Self.qso("OK1CC", minute: 10)]
        var incoming = [Self.qso("OK1AA", minute: 1), Self.qso("OK1BB", minute: 7), Self.qso("OK1CC", minute: 8),
                        Self.qso("OK1DD", minute: 20), Self.qso("W1AW", minute: 21)]
        for index in incoming.indices {
            incoming[index].id = Int64(100 + index)
            incoming[index].contestId = "other"
        }
        let merged = LogImporter.prepareMerge(existing: existing, incoming: incoming, activeContestId: "cq-ww-cw",
                                              dxcc: Lookup())
        #expect(merged.duplicates == 3)
        #expect(merged.toAdd.map(\.call) == ["OK1DD", "W1AW"])
        #expect(merged.toAdd.allSatisfy { $0.id == nil && $0.contestId == "cq-ww-cw" && $0.imported })
        #expect(merged.toAdd.map(\.dxccName) == ["Czech Republic", ""])

        let outside = LogImporter.prepareMerge(existing: [], incoming: incoming, activeContestId: nil, dxcc: nil)
        #expect(outside.toAdd.allSatisfy { $0.contestId == "" })
    }

    /// `AS:4122-4125`: the active contest's QSOs when the source has any, otherwise all.
    @Test func databaseSourceFiltersByActiveContest() {
        let all = [Self.qso("A", minute: 0, contest: "x"), Self.qso("B", minute: 1, contest: "y"),
                   Self.qso("C", minute: 2)]
        #expect(LogImporter.databaseSource(all, activeContestId: "y").map(\.call) == ["B"])
        #expect(LogImporter.databaseSource(all, activeContestId: "z").map(\.call) == ["A", "B", "C"])
        #expect(LogImporter.databaseSource(all, activeContestId: nil).map(\.call) == ["C"])
        // `é` precomposed vs decomposed: Kotlin `==` compares UTF-16 units.
        let accented = [Self.qso("D", minute: 3, contest: "caf\u{E9}")]
        #expect(LogImporter.databaseSource(accented + all, activeContestId: "cafe\u{301}").count == 4)
    }

    // MARK: - foreign database

    /// An older schema (row `DB.migrate`): Kotlin migrates the source in place; the copy leaves it untouched.
    @Test func readDatabaseNeverModifiesTheSource() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = dir.appendingPathComponent("old.sqlite")
        let db = try SQLiteDatabase.open(at: old.path)
        try db.execute("CREATE TABLE qso (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp_utc INTEGER NOT NULL,"
                       + " call TEXT NOT NULL, freq_hz INTEGER NOT NULL, band TEXT, mode TEXT)")
        db.close()
        let before = try Data(contentsOf: old)

        _ = try LogImporter.readDatabase(at: old, activeContestId: "cq-ww-cw")
        #expect(try Data(contentsOf: old) == before)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(left == ["old.sqlite"])
    }

    /// I-1 of the review: a symlinked source is resolved — the old-schema target and its hot journal stay
    /// byte-identical; a read-only target still migrates in the copy.
    @Test func readDatabaseThroughSymlinkLeavesTargetUntouched() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.sqlite")
        let db = try SQLiteDatabase.open(at: real.path)
        try db.execute("CREATE TABLE qso (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp_utc INTEGER NOT NULL,"
                       + " call TEXT NOT NULL, freq_hz INTEGER NOT NULL, band TEXT, mode TEXT)")
        db.close()
        let journal = URL(fileURLWithPath: real.path + "-journal")
        try Data(repeating: 0x5A, count: 64).write(to: journal)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: real.path)
        let before = try Data(contentsOf: real)
        let journalBefore = try Data(contentsOf: journal)
        let link = dir.appendingPathComponent("link.sqlite")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "real.sqlite")

        #expect(try LogImporter.readDatabase(at: link, activeContestId: nil).isEmpty)
        #expect(try Data(contentsOf: real) == before)
        #expect(try Data(contentsOf: journal) == journalBefore)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(left == ["link.sqlite", "real.sqlite", "real.sqlite-journal"])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: real.path)
    }

    /// Symlinked `-wal`/`-journal` files are resolved; the targets keep bytes and permissions, the copies
    /// are regular 0600 files; a broken link and a directory are skipped.
    @Test func readDatabaseResolvesSymlinkedSideFiles() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let other = dir.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("foreign.sqlite")
        let repository = try LogbookRepository(url: file)
        var a = Self.qso("OK1AA", minute: 0, contest: "cq-ww-cw")
        _ = try repository.insert(&a)
        repository.close()
        try? FileManager.default.removeItem(atPath: file.path + "-wal")
        try? FileManager.default.removeItem(atPath: file.path + "-journal")
        let walTarget = other.appendingPathComponent("target-wal")
        let journalTarget = other.appendingPathComponent("target-journal")
        let walBytes = Data(repeating: 0, count: 0)
        try walBytes.write(to: walTarget)
        try Data(repeating: 0, count: 8).write(to: journalTarget)
        for target in [walTarget, journalTarget] {
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: target.path)
        }
        try FileManager.default.createSymbolicLink(atPath: file.path + "-wal", withDestinationPath: walTarget.path)
        try FileManager.default.createSymbolicLink(atPath: file.path + "-journal",
                                                   withDestinationPath: journalTarget.path)
        let journalBefore = try Data(contentsOf: journalTarget)

        #expect(try LogImporter.readDatabase(at: file, activeContestId: nil).map(\.call) == ["OK1AA"])
        for target in [walTarget, journalTarget] {
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            #expect((attributes[.posixPermissions] as? Int) == 0o444)
        }
        #expect(try Data(contentsOf: walTarget) == walBytes)
        #expect(try Data(contentsOf: journalTarget) == journalBefore)

        // Broken link and directory: skipped, the database still reads.
        try FileManager.default.removeItem(atPath: file.path + "-wal")
        try FileManager.default.removeItem(atPath: file.path + "-journal")
        try FileManager.default.createSymbolicLink(atPath: file.path + "-wal",
                                                   withDestinationPath: other.appendingPathComponent("nope").path)
        try FileManager.default.createDirectory(atPath: file.path + "-journal", withIntermediateDirectories: true)
        #expect(try LogImporter.readDatabase(at: file, activeContestId: nil).map(\.call) == ["OK1AA"])
        for target in [walTarget, journalTarget] {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        }
    }

    @Test func readDatabaseReadsTheActiveContest() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("foreign.sqlite")
        let repository = try LogbookRepository(url: file)
        var a = Self.qso("OK1AA", minute: 0, contest: "cq-ww-cw")
        var b = Self.qso("OK1BB", minute: 1, contest: "other")
        _ = try repository.insert(&a)
        _ = try repository.insert(&b)
        repository.close()

        #expect(try LogImporter.readDatabase(at: file, activeContestId: "cq-ww-cw").map(\.call) == ["OK1AA"])
        #expect(try LogImporter.readDatabase(at: file, activeContestId: "none").map(\.call) == ["OK1AA", "OK1BB"])
    }

    /// Rows `DB.notADatabase`, `DB.directory`, `DB.missing`.
    @Test func readDatabaseErrorsLikeJava() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("text.sqlite")
        let body = Data("this is not a database, just some text long enough to fill a header....................".utf8)
        try body.write(to: text)
        let notDb = #expect(throws: LogbookError.self) { try LogImporter.readDatabase(at: text, activeContestId: nil) }
        #expect(notDb?.message == "Nelze otevřít deník: jdbc:sqlite:" + text.path)
        #expect(try Data(contentsOf: text) == body)

        let sub = dir.appendingPathComponent("adir.db")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let directory = #expect(throws: LogbookError.self) { try LogImporter.readDatabase(at: sub, activeContestId: nil) }
        #expect(directory?.message == "Nelze otevřít deník: jdbc:sqlite:" + sub.path)

        let missing = dir.appendingPathComponent("absent.sqlite")
        #expect(try LogImporter.readDatabase(at: missing, activeContestId: nil).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    // MARK: - texts

    @Test func statusTexts() {
        #expect(IoTexts.imported(count: 12, format: .adif, file: "a.adi").czech == "Importováno 12 QSO (ADIF) z a.adi")
        #expect(IoTexts.imported(count: 0, format: .cabrillo, file: "b.log").czech
            == "Importováno 0 QSO (Cabrillo) z b.log")
        #expect(IoTexts.unreadable(file: "a.adi").czech == "Nelze přečíst soubor: a.adi")
        #expect(IoTexts.merged(file: "x.sqlite", added: 2, skipped: 3).czech
            == "Sloučeno z x.sqlite: přidáno 2 QSO, přeskočeno 3 duplicit")
        #expect(IoTexts.mergeUnreadable(file: "x.adi", message: "Input length = 1").czech
            == "Sloučení: nelze přečíst x.adi (Input length = 1)")
        #expect(IoTexts.mergeUnreadable(file: "x.adi", message: nil).czech == "Sloučení: nelze přečíst x.adi (null)")
    }
}
