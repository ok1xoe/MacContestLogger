import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// Import, merge, the EDI and other exports, printing and their menu wiring (`AS:4007-4180`, `App.kt:616-642`).
@MainActor @Suite struct ImportExportModelTests {

    // MARK: - fixtures

    /// One ADIF record (synthetic calls).
    static func adifRecord(_ call: String, band: String = "20m", freq: String = "14.025", time: String = "1200",
                           grid: String = "") -> String {
        var record: String = "<call:" + String(call.utf8.count) + ">" + call
        record += "<qso_date:8>20251129<time_on:4>" + time
        record += "<band:" + String(band.utf8.count) + ">" + band + "<mode:2>CW"
        record += "<freq:" + String(freq.utf8.count) + ">" + freq + "<rst_sent:3>599<rst_rcvd:3>599"
        if !grid.isEmpty {
            record += "<gridsquare:" + String(grid.utf8.count) + ">" + grid
        }
        return record + "<eor>\n"
    }

    static func write(_ text: String, _ url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// The stored QSOs of every contest (straight from the database).
    static func stored(_ app: TestApp) async throws -> [Qso] {
        try await app.model.database.handle.run { try $0.repository.findAll() }
    }

    /// The dupe index equals a rebuild from the rows.
    static func expectDupeIndexRebuilt(_ model: AppModel) {
        let rebuilt = LogbookMutations(existing: model.logbook.rows)
        for row in model.logbook.rows {
            #expect(model.logbook.isDupe(call: row.call, band: row.band) == rebuilt.isDupe(call: row.call, band: row.band!))
        }
        #expect(!model.logbook.isDupe(call: "ZZ9ZZZ", band: .m20))
    }

    // MARK: - import

    @Test func importAdifIntoTheContestConvertsTheExchangeAndRequestsTheRecount() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let file: URL = app.dir.child("log.adi")
        try Self.write(Self.adifRecord("DL1ABC") + Self.adifRecord("W1AW", band: "40m", freq: "7.010"), file)
        let revision: Int64 = model.logbook.revision

        await model.exports.importQsos(from: file)

        #expect(model.status.message == "Importováno 2 QSO (ADIF) z log.adi")
        #expect(model.logbook.rows.map(\.call) == ["DL1ABC", "W1AW"])
        #expect(model.logbook.qsoCount == 2)
        #expect(model.logbook.revision > revision)
        let active: String = model.logbook.activeContestId
        #expect(!active.isEmpty)
        #expect(model.logbook.rows.allSatisfy { $0.contestId == active && !$0.imported })
        #expect(model.logbook.rows.allSatisfy { $0.exchangeRcvd == "599" })
        #expect(model.logbook.rows.first?.dxccEntity != nil)
        #expect(model.contest.scheduler.isBusy)
        Self.expectDupeIndexRebuilt(model)
        #expect(model.logbook.isDupe(call: "DL1ABC", band: .m20))
        await model.logbook.settle()
        #expect(model.logbook.displayed.count == 2)
    }

    @Test func importCabrilloOutsideAContestKeepsTheExchange() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let file: URL = app.dir.child("log.log")
        try Self.write("START-OF-LOG: 3.0\nQSO: 14025 CW 2025-11-29 1200 OK1XOE 599 15 DL1ABC 599 14\n"
                       + "END-OF-LOG:\n", file)

        await model.exports.importQsos(from: file)

        #expect(model.status.message == "Importováno 1 QSO (Cabrillo) z log.log")
        // Stored without a contest; the log of „no contest" lists nothing (Kotlin `findAll(null)`).
        #expect(model.logbook.rows.isEmpty)
        #expect(model.logbook.qsoCount == 0)
        let row: Qso = try #require(try await Self.stored(app).first)
        #expect(row.exchangeRcvd == "14")
        #expect(row.rstRcvd == "599")
        #expect(row.contestId == "")
        #expect(!model.contest.scheduler.isBusy)
    }

    @Test func importCabrilloIntoTheContestUsesTheEntryForm() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let file: URL = app.dir.child("cab.txt")
        try Self.write("QSO: 14025 CW 2025-11-29 1200 OK1XOE 599 15 DL1ABC 599 14\n", file)
        await app.model.exports.importQsos(from: file)
        #expect(app.model.status.message == "Importováno 1 QSO (Cabrillo) z cab.txt")
        #expect(app.model.logbook.rows.first?.exchangeRcvd == "599 14")
    }

    /// An exception of the reader inserts nothing and shows the unreadable-file text.
    @Test func readerExceptionInsertsNothing() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let file: URL = app.dir.child("bad.adi")
        try Self.write(Self.adifRecord("DL1ABC") + "<CALL:-1>W1AW<eor>", file)
        let revision: Int64 = model.logbook.revision
        await model.exports.importQsos(from: file)
        #expect(model.status.message == "Nelze přečíst soubor: bad.adi")
        #expect(model.logbook.rows.isEmpty)
        #expect(model.logbook.revision == revision)
        #expect(try await Self.stored(app).isEmpty)
    }

    @Test func invalidUtf8AndAMissingFileAreUnreadable() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let file: URL = app.dir.child("latin1.adi")
        try Data([0x3C, 0x63, 0x61, 0x6C, 0x6C, 0x3A, 0x31, 0x3E, 0xE9, 0x3C, 0x65, 0x6F, 0x72, 0x3E]).write(to: file)
        await model.exports.importQsos(from: file)
        #expect(model.status.message == "Nelze přečíst soubor: latin1.adi")
        await model.exports.importQsos(from: app.dir.child("missing.adi"))
        #expect(model.status.message == "Nelze přečíst soubor: missing.adi")
        #expect(try await Self.stored(app).isEmpty)
    }

    /// An import queued behind a submission in flight: the QSO typed just before is stored once, not twice.
    @Test func importAfterASubmissionKeepsEveryRowOnce() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let file: URL = app.dir.child("one.adi")
        try Self.write(Self.adifRecord("JA1AA", band: "15m", freq: "21.025"), file)
        model.entry.setFrequency("14025")
        model.entry.callChanged("DL1ABC")
        model.entry.editContestField("zone", "14")
        model.entry.submit()
        await model.exports.importQsos(from: file)
        await model.entry.settle()
        await model.logbook.settle()
        #expect(model.logbook.rows.map(\.call).sorted() == ["DL1ABC", "JA1AA"])
        #expect(model.logbook.qsoCount == 2)
        Self.expectDupeIndexRebuilt(model)
    }

    /// The import or merge job waits for the submissions already made before it reads anything (falsifiable without
    /// the `settleInserts` call: `prepare` would run while the gate is still closed).
    @Test func batchWaitsForTheSubmissionsBeforePreparing() async throws {
        let app = try await TestApp.make()
        let logbook: LogbookModel = app.model.logbook
        let gateEntered = FlagBox()
        let prepareRan = FlagBox()
        var gate: CheckedContinuation<Void, Never>?
        logbook.settleInserts = {
            await withCheckedContinuation { continuation in
                gate = continuation
                gateEntered.set()
            }
        }
        let job = Task { @MainActor in
            await logbook.importBatch { _ in
                prepareRan.set()
                return LogbookModel.BatchPlan(qsos: [], value: ())
            }
        }
        while !gateEntered.isSet && !prepareRan.isSet {
            await Task.yield()
        }
        #expect(gateEntered.isSet)
        #expect(!prepareRan.isSet)
        gate?.resume()
        _ = await job.value
        #expect(prepareRan.isSet)
    }

    /// End to end: A and B are submitted while the handle is busy (B chained behind A), then a file containing B is
    /// merged — B is compared, not inserted twice.
    @Test func mergeComparesAgainstQsosSubmittedBeforeIt() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        // The stored time of a submission is the logbook's clock (now); the file's B is within LogMerger's ±2 min.
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyyMMdd HHmm"
        let stamp: [String] = format.string(from: Date()).split(separator: " ").map(String.init)
        let file: URL = app.dir.child("b.adi")
        let record: String = Self.adifRecord("W1AW", time: stamp[1])
        try Self.write(record.replacingOccurrences(of: "<qso_date:8>20251129", with: "<qso_date:8>" + stamp[0]), file)

        let gate = DispatchSemaphore(value: 0)
        let held = FlagBox()
        let handle: LogbookHandle = model.database.handle
        let blocker = Task {
            try await handle.run { _ in
                held.set()
                gate.wait()
            }
        }
        while !held.isSet { await Task.yield() }
        for (call, zone) in [("DL1ABC", "14"), ("W1AW", "5")] {
            model.entry.setFrequency("14025")
            model.entry.callChanged(call)
            model.entry.editContestField("zone", zone)
            model.entry.submit()
        }
        let merge = Task { @MainActor in await model.exports.merge(from: file) }
        // Let the merge read its file and queue behind the submissions before the handle is released.
        for _ in 0..<200 { await Task.yield() }
        gate.signal()
        try await blocker.value
        await merge.value
        await model.entry.settle()
        await model.logbook.settle()

        #expect(model.status.message == "Sloučeno z b.adi: přidáno 0 QSO, přeskočeno 1 duplicit")
        let stored: [Qso] = try await Self.stored(app)
        #expect(stored.map(\.call).sorted() == ["DL1ABC", "W1AW"])
    }

    /// The active contest changed while the job waited: nothing is inserted (Kotlin runs it synchronously).
    @Test func contestChangeBeforeTheJobRefusesTheImportAndTheMerge() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let file: URL = app.dir.child("x.adi")
        try Self.write(Self.adifRecord("DL1ABC"), file)
        let handle: LogbookHandle = model.database.handle
        let active: String = model.logbook.activeContestId
        model.logbook.settleInserts = {
            _ = try? await handle.run { access in access.service.activeContestId = "other" }
        }
        await model.exports.importQsos(from: file)
        #expect(model.status.message == "Závod se mezitím změnil — z x.adi se nic nevložilo")
        await model.exports.merge(from: file)
        #expect(model.status.message == "Závod se mezitím změnil — z x.adi se nic nevložilo")
        #expect(try await Self.stored(app).isEmpty)
        _ = try await handle.run { access in access.service.activeContestId = active }
    }

    // MARK: - merge

    /// S11-07: 3 QSOs already in the log, 5 in the file → 2 added, 3 duplicates.
    @Test func mergeAddsOnlyNewQsos() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let first: URL = app.dir.child("first.adi")
        let three: String = Self.adifRecord("DL1ABC") + Self.adifRecord("W1AW", time: "1201")
            + Self.adifRecord("JA1AA", time: "1202")
        try Self.write(three, first)
        await model.exports.importQsos(from: first)
        let other: URL = app.dir.child("other.adi")
        try Self.write(three + Self.adifRecord("OK1ABC", time: "1203") + Self.adifRecord("G4AAA", time: "1204"), other)

        await model.exports.merge(from: other)

        #expect(model.status.message == "Sloučeno z other.adi: přidáno 2 QSO, přeskočeno 3 duplicit")
        #expect(model.logbook.rows.count == 5)
        let added: [Qso] = model.logbook.rows.filter(\.imported)
        #expect(added.map(\.call).sorted() == ["G4AAA", "OK1ABC"])
        #expect(added.allSatisfy { $0.contestId == model.logbook.activeContestId && $0.exchangeRcvd == "599" })
        #expect(model.contest.scheduler.isBusy)
        Self.expectDupeIndexRebuilt(model)
    }

    /// A foreign database is filtered by the active contest and never modified.
    @Test func mergeFromAForeignDatabaseFiltersByContestAndLeavesItUntouched() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let foreign: URL = app.dir.child("Foreign.SQLITE")
        do {
            let repository = try LogbookRepository(url: foreign)
            defer { repository.close() }
            let service = LogbookService(repository: repository)
            let active: String = model.logbook.activeContestId
            for (contest, call) in [(active, "DL1ABC"), (active, "W1AW"), ("other", "JA1AA")] {
                service.activeContestId = contest
                var qso = Qso()
                qso.call = call
                qso.band = .m20
                qso.mode = .cw
                qso.timestampUtc = Date(timeIntervalSince1970: 1_764_417_600)
                _ = try service.log(&qso)
            }
        }
        let before = try Data(contentsOf: foreign)

        await model.exports.merge(from: foreign)

        #expect(model.status.message == "Sloučeno z Foreign.SQLITE: přidáno 2 QSO, přeskočeno 0 duplicit")
        #expect(model.logbook.rows.map(\.call).sorted() == ["DL1ABC", "W1AW"])
        #expect(try Data(contentsOf: foreign) == before)
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: app.dir.url.path)
        #expect(!names.contains { $0.hasPrefix("Foreign.SQLITE-") })
    }

    /// The database open now is read through its own handle: everything is a duplicate.
    @Test func mergeFromTheOpenDatabaseFindsOnlyDuplicates() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        await model.exports.merge(from: model.database.handle.url)
        let name: String = model.database.handle.url.lastPathComponent
        #expect(model.status.message == "Sloučeno z " + name + ": přidáno 0 QSO, přeskočeno 2 duplicit")
        #expect(model.logbook.rows.count == 2)
    }

    @Test func mergeFailuresNameTheFileAndTheJavaMessage() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let missing: URL = app.dir.child("missing.adi")
        await model.exports.merge(from: missing)
        #expect(model.status.message == "Sloučení: nelze přečíst missing.adi (" + missing.path + ")")
        let bad: URL = app.dir.child("bad.adi")
        try Self.write("<CALL:-1>W1AW<eor>", bad)
        await model.exports.merge(from: bad)
        #expect(model.status.message.hasPrefix("Sloučení: nelze přečíst bad.adi ("))
        let text: URL = app.dir.child("notadb.db")
        try Self.write("hello", text)
        await model.exports.merge(from: text)
        #expect(model.status.message == "Sloučení: nelze přečíst notadb.db (Nelze otevřít deník: jdbc:sqlite:"
            + text.path + ")")
        #expect(try await Self.stored(app).isEmpty)
    }

    // MARK: - station-class expression errors (Kotlin crashes on import and EDI, catches on merge)

    /// A copy of the contest data with a VHF definition whose station class expression fails.
    static func brokenContestData(_ dir: TempDir) throws -> URL {
        let root: URL = dir.child("contest-data")
        try FileManager.default.copyItem(at: Fixtures.contestData, to: root)
        let source: URL = root.appendingPathComponent("contests/iaru-r1-vhf.yaml")
        var text: String = try String(contentsOf: source, encoding: .utf8)
        text = text.replacingOccurrences(of: "id: iaru-r1-vhf", with: "id: broken-vhf")
        text = text.replacingOccurrences(of: "\nexchange:", with: "\nstationClasses:\n"
            + "  - { id: e, when: { expr: \"foo(1)\" } }\n\nexchange:")
        try Data(text.utf8).write(to: root.appendingPathComponent("contests/broken-vhf.yaml"))
        return root
    }

    @Test func expressionErrorsInsertAndWriteNothing() async throws {
        let holder = try TempDir()
        let data: URL = try Self.brokenContestData(holder)
        let app = try await TestApp.make { config, _ in
            config.contestDataDir = data.path
            config.station.gridSquare = "JO70FD"
        }
        let model: AppModel = app.model
        let started: Bool = await model.contest.createAndStart(definitionId: "broken-vhf", setup: ContestSetup())
        try #require(started, "activation failed: \(model.status.message)")
        let file: URL = app.dir.child("vhf.adi")
        try Self.write(Self.adifRecord("DL1ABC", band: "2m", freq: "144.050", grid: "JO62QM"), file)

        await model.exports.importQsos(from: file)
        let message: String = model.status.message
        // The expression error's message (Java `getMessage()`), verbatim.
        #expect(message == "Neznámá funkce: foo")
        #expect(try await Self.stored(app).isEmpty)

        await model.exports.merge(from: file)
        #expect(model.status.message == "Sloučení: nelze přečíst vhf.adi (" + message + ")")
        #expect(try await Self.stored(app).isEmpty)

        // A QSO in the log (written behind the model's back) for the EDI export.
        try await model.database.handle.run { access in
            var qso = Qso()
            qso.call = "DL1ABC"
            qso.band = .m2
            qso.mode = .cw
            qso.timestampUtc = Date(timeIntervalSince1970: 1_764_417_600)
            _ = try access.service.log(&qso)
        }
        let out: URL = app.dir.child("edi")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        await model.exports.exportEdi(to: out)
        #expect(model.status.message == message)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    // MARK: - EDI

    @Test func ediChecksInKotlinOrderAndWritesOneFilePerBand() async throws {
        let app = try await TestApp.make { config, _ in
            config.station.gridSquare = "JO70"
        }
        let model: AppModel = app.model
        // No contest → the text, no panel.
        #expect(MenuActions.perform("settings.exportEdi", app: model) == nil)
        #expect(model.status.message == "EDI: není aktivní závod")
        let out: URL = app.dir.child("edi")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        await model.exports.exportEdi(to: out)
        #expect(model.status.message == "EDI: není aktivní závod")

        let started: Bool = await model.contest.createAndStart(definitionId: "iaru-r1-vhf", setup: ContestSetup())
        try #require(started)
        #expect(MenuActions.perform("settings.exportEdi", app: model) == .chooseDirectory(.edi))
        await model.exports.exportEdi(to: out)
        #expect(model.status.message == "EDI: doplň 6místný lokátor stanice (Nastavení → Stanice)")
        model.config.config.station.gridSquare = " JO70FD "
        await model.exports.exportEdi(to: out)
        #expect(model.status.message == "EDI: deník je prázdný")

        let file: URL = app.dir.child("vhf.adi")
        try Self.write(Self.adifRecord("DL1ABC", band: "2m", freq: "144.050", grid: "JO62QM")
                       + Self.adifRecord("OK1ABC", band: "70cm", freq: "432.100", time: "1210", grid: "JN79US"), file)
        await model.exports.importQsos(from: file)
        await model.exports.exportEdi(to: out)
        #expect(model.status.message == "EDI: zapsáno OK1XOE_2m.edi, OK1XOE_70cm.edi do " + out.path)

        let qsos: [Qso] = try await model.database.handle.run { try $0.service.findAll() }
        let session: ContestSession = try #require(model.contest.runtime.freshSession())
        let expected = try ExportJobs.edi(definition: model.contest.definition,
                                          station: model.config.config.station, setup: model.contest.activeSetup,
                                          qsos: qsos) { try session.activeReceivedFields(call: $0) }
        let files: [ExportFile] = try expected.get()
        for exported in files {
            #expect(try Data(contentsOf: out.appendingPathComponent(exported.name)) == exported.bytes)
        }
    }

    // MARK: - other exports

    @Test func otherExportsWriteCsvTextAndSummaryWithAFreshScore() async throws {
        let app = try await TestApp.make { config, _ in
            config.station.call = "OK1XOE/P"
        }
        let model: AppModel = app.model
        #expect(MenuActions.perform("settings.exportOther", app: model) == .chooseDirectory(.other))
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5", freqKHz: "7010")
        let out: URL = app.dir.child("other")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        await model.exports.exportOther(to: out)

        #expect(model.status.message == "Export: OK1XOE_P.csv, OK1XOE_P.txt, OK1XOE_P-summary.txt do " + out.path)
        let qsos: [Qso] = try await model.database.handle.run { try $0.service.findAll() }
        let session: ContestSession = try #require(model.contest.runtime.freshSession())
        let score: ScoreState = try ContestReplay.replay(session, qsos).session.score()
        let expected: [ExportFile] = try ExportJobs.other(contestName: "CQ WW DX Contest — CW", call: "OK1XOE/P",
                                                          score: score, qsos: qsos)
        for exported in expected {
            #expect(try Data(contentsOf: out.appendingPathComponent(exported.name)) == exported.bytes)
        }

        // Outside a contest: „Deník" and no score; a file that cannot be written is left out silently.
        model.contest.deactivate()
        let partial: URL = app.dir.child("partial")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: partial.appendingPathComponent("OK1XOE_P.txt"),
                                                withIntermediateDirectories: true)
        await model.exports.exportOther(to: partial)
        #expect(model.status.message == "Export: OK1XOE_P.csv, OK1XOE_P-summary.txt do " + partial.path)
        let summary = try String(contentsOf: partial.appendingPathComponent("OK1XOE_P-summary.txt"), encoding: .utf8)
        let plain: String = try LogExports.summary("Deník", "OK1XOE/P", nil, model.logbook.rows)
        #expect(summary == plain)
    }

    // MARK: - printing

    @Test func printJobTitleTextAndOutcomes() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let empty: ImportExportModel.PrintJob = try #require(await model.exports.printJob())
        #expect(empty.title == "Deník — OK1XOE")
        #expect(empty.text == LogExports.text("Deník — OK1XOE", []))

        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        #expect(MenuActions.perform("settings.print", app: model) == nil)
        await model.exports.settle()
        let title: String = "CQ WW DX Contest — CW — OK1XOE"
        let expected = ImportExportModel.PrintJob(title: title, text: LogExports.text(title, model.logbook.rows))
        #expect(model.exports.pendingRequest == .print(expected))
        #expect(MenuActions.takeModelRequest(app: model) == .print(expected))
        #expect(model.exports.pendingRequest == nil)
        #expect(MenuActions.takeModelRequest(app: model) == nil)

        model.exports.printFinished(.sent)
        #expect(model.status.message == "Deník odeslán na tiskárnu")
        model.exports.printFinished(.cancelled)
        #expect(model.status.message == "Tisk zrušen")
        model.exports.printFinished(.failed("Printer offline"))
        #expect(model.status.message == "Tisk selhal: Printer offline")
        model.exports.printFinished(.failed(nil))
        #expect(model.status.message == "Tisk selhal: null")
        await model.language.switchTo("en")
        #expect(model.status.message == "Tisk selhal: null")
    }

    // MARK: - menu

    @Test func menuRoutesTheNewActions() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        for id in ["settings.import", "settings.merge", "settings.exportEdi", "settings.exportOther", "settings.print",
                   "database.refillDxcc", "contest.updateCallHistory", "contest.updateDefinitions", "contest.editor",
                   "settings.profiles"] {
            #expect(model.menu.isImplemented(id), "\(id)")
        }
        #expect(!model.menu.isImplemented("x.future"))
        #expect(MenuActions.perform("settings.import", app: model) == .openImport)
        #expect(MenuActions.perform("settings.merge", app: model) == .openMerge)
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        #expect(MenuActions.perform("database.refillDxcc", app: model) == .confirmRefillDxcc(count: 1))
        #expect(MenuActions.perform("contest.editor", app: model) == nil)
        #expect(model.windows.isOpen("defeditor"))
        var ran: [String] = []
        model.extraMenuActions["contest.updateDefinitions"] = { ran.append("definitions") }
        #expect(MenuActions.perform("contest.updateDefinitions", app: model) == nil)
        #expect(ran == ["definitions"])
    }

    /// The IMPORT command opens the import panel through the pending menu action.
    @Test func importCommandRequestsTheImportPanel() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        model.entry.callChanged("IMPORT")
        model.entry.submit()
        await model.entry.settle()
        #expect(model.menu.pendingMenuAction == "settings.import")
        #expect(MenuActions.performPending(app: model) == .openImport)
        #expect(model.logbook.rows.isEmpty)
    }
}
