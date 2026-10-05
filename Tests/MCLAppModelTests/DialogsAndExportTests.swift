import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// Menu actions (`KApp:611-674`).
@MainActor @Suite struct MenuActionsTests {

    @Test func dialogsAndWindowsOpenFromTheMenu() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        #expect(MenuActions.perform("contest.new", app: model) == nil)
        #expect(model.dialogs.newContest != nil)
        #expect(model.dialogs.isOpen(.newContest))
        #expect(MenuActions.perform("contest.open", app: model) == nil)
        #expect(model.dialogs.showContestBrowser)
        #expect(MenuActions.perform("database.new", app: model) == nil)
        #expect(model.dialogs.showNewDatabase)
        #expect(MenuActions.perform("database.open", app: model) == nil)
        #expect(model.dialogs.showOpenDatabase)
        model.windows.setOpen("log", false)
        #expect(!model.windows.isOpen("log"))
        #expect(MenuActions.perform("window.log", app: model) == nil)
        #expect(model.windows.isOpen("log"))
        #expect(await app.savedConfigFlushed().openWindows == ["log"])
        // The Info window (Kotlin `showRateWindow = true`) is saved as `rate`.
        #expect(MenuActions.perform("window.rate", app: model) == nil)
        #expect(model.windows.isOpen("rate"))
    }

    @Test func exportsAskForAFile() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        #expect(MenuActions.perform("settings.export", app: model) == .saveAdif(suggestedName: "maccontestlogger.adi"))
        // Kotlin checks the contest before the save dialog.
        #expect(MenuActions.perform("settings.exportCabrillo", app: model) == nil)
        #expect(model.status.message == "Cabrillo: není aktivní závod")
        try await app.startCqWwCw()
        #expect(MenuActions.perform("settings.exportCabrillo", app: model)
            == .saveCabrillo(suggestedName: "OK1XOE-CQ-WW-CW.log"))
    }

    @Test func contestNoneAndRescore() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        _ = MenuActions.perform("contest.rescore", app: model)
        await model.contest.settleRescore()
        #expect(model.status.message.hasPrefix("Skóre přepočteno: 1 QSO"))
        _ = MenuActions.perform("contest.none", app: model)
        #expect(!model.contest.isActive)
        _ = MenuActions.perform("contest.rescore", app: model)
        #expect(model.status.message == "Přepočet skóre: není aktivní závod")
    }
}

/// Cabrillo and ADIF export (`KA:4007-4106`).
@MainActor @Suite struct ExportModelTests {

    @Test func adifIsTheCoreWritersOutput() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5", freqKHz: "7010")
        let file: URL = app.dir.child("out.adi")
        await model.exports.exportAdif(to: file)
        #expect(model.status.message == "Exportováno do " + file.path)
        let qsos: [Qso] = try await model.database.handle.run { try $0.service.findAll() }
        #expect(qsos.count == 2)
        let expected: String = AdifWriter(contestId: "CQ-WW-CW")
            .toAdif(qsos, station: model.config.config.station.toStation())
        #expect(try Data(contentsOf: file) == Data(expected.utf8))
    }

    @Test func adifWithoutContestHasNoContestId() async throws {
        let app = try await TestApp.make()
        let file: URL = app.dir.child("free.adi")
        await app.model.exports.exportAdif(to: file)
        let text: String = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix("ADIF export z MacContestLogger\n"))
        #expect(!text.contains("CONTEST_ID"))
    }

    @Test func adifWriteFailureIsReported() async throws {
        let app = try await TestApp.make()
        let file: URL = app.dir.child("missing-dir").appendingPathComponent("x.adi")
        await app.model.exports.exportAdif(to: file)
        #expect(app.model.status.message == "Nelze zapsat ADIF: " + file.path)
    }

    /// Golden comparison: the written file is the exporter's text over the whole log (no formatting in the app),
    /// with CLAIMED-SCORE recounted from zero — a QSO stored behind the live session's back counts.
    @Test func cabrilloIsTheCoreExportersOutputWithAFreshScore() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5", freqKHz: "7010")
        let live: Int64 = try #require(model.contest.score?.total)
        // A QSO only in the database (the live session never saw it).
        let first: Qso = try #require(model.logbook.rows.first)
        try await model.database.handle.run { access in
            var copy: Qso = first
            copy.id = nil
            copy.uuid = ""
            copy.call = "JA1AA"
            copy.exchangeRcvd = "599 25"
            _ = try access.service.log(&copy)
        }

        let file: URL = app.dir.child("cq.log")
        await model.exports.exportCabrillo(to: file)
        #expect(model.status.message == "Cabrillo: 3 QSO → cq.log")
        #expect(model.messages.lines.isEmpty)

        let qsos: [Qso] = try await model.database.handle.run { try $0.service.findAll() }
        let definition: ContestDefinition = try #require(model.contest.definition)
        let replay: ContestSession = try #require(model.contest.runtime.freshSession())
        let fields: ContestSession = try #require(model.contest.runtime.freshSession())
        let claimed: Int64 = try ContestReplay.replay(replay, qsos).session.score().total
        #expect(claimed > live)
        var input = CabrilloExporter.Input(definition: definition, station: model.config.config.station,
                                           qsos: qsos) { call in try fields.activeReceivedFields(call: call) }
        input.sentExchange = JavaLinkedMap([("zone", "15")])
        input.claimedScore = claimed
        input.createdBy = "MacContestLogger vývojová verze"
        let expected: CabrilloExporter.Result = try CabrilloExporter.export(input)
        let written = try Data(contentsOf: file)
        #expect(written == Data(expected.text.utf8))
        #expect(written.allSatisfy { $0 < 0x80 })
        let text: String = String(decoding: written, as: UTF8.self)
        #expect(text.contains("CLAIMED-SCORE: " + String(claimed) + "\n"))
        #expect(text.contains("CREATED-BY: MacContestLogger vyvojova verze\n"))
    }

    @Test func cabrilloCountsWarningsAndUsesTheBundleVersion() async throws {
        let app = try await TestApp.make(appVersion: "1.2.3") { config, _ in
            config.station.call = ""
        }
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let file: URL = app.dir.child("nocall.log")
        await model.exports.exportCabrillo(to: file)
        #expect(model.messages.lines.first?.text.hasPrefix("Cabrillo: Chybí volačka stanice") == true)
        #expect(model.messages.revision == 1)
        let count: Int = model.messages.lines.count
        #expect(model.status.message == "Cabrillo: 1 QSO → nocall.log · " + String(count)
            + " upozornění (viz Info okno)")
        let text: String = try String(contentsOf: file, encoding: .ascii)
        #expect(text.contains("CREATED-BY: MacContestLogger 1.2.3\n"))
        await model.language.switchTo("en")
        #expect(!model.status.message.contains("upozornění"))
    }

    @Test func cabrilloWriteFailureAndNoContest() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        await model.exports.exportCabrillo(to: app.dir.child("a.log"))
        #expect(model.status.message == "Cabrillo: není aktivní závod")
        try await app.startCqWwCw()
        let file: URL = app.dir.child("missing-dir").appendingPathComponent("b.log")
        await model.exports.exportCabrillo(to: file)
        #expect(model.status.message.hasPrefix("Cabrillo: zápis selhal ("))
    }

    @Test func cabrilloFileNameFollowsStationAndContest() async throws {
        let app = try await TestApp.make { config, _ in
            config.station.call = " ok1xoe/p "
        }
        #expect(app.model.exports.cabrilloFileName == "OK1XOE_P.log")
        try await app.startCqWwCw()
        #expect(app.model.exports.cabrilloFileName == "OK1XOE_P-CQ-WW-CW.log")
    }
}

/// The start-up, contest-browser, new-contest and database windows (`StartupDialog.kt`, `ContestBrowser.kt`,
/// `NewContestWindow.kt`, `DatabasePickerDialogs.kt`).
@MainActor @Suite struct DialogsModelTests {

    @Test func startupOffersTheLastContest() async throws {
        let app = try await TestApp.make()
        let dialogs: DialogsModel = app.model.dialogs
        #expect(!dialogs.isOpen(.startup))
        await dialogs.loadStartup()
        #expect(dialogs.startupLabel == nil)
        try await app.startCqWwCw()
        await dialogs.loadStartup()
        #expect(dialogs.startupLabel == "CQ WW DX Contest — CW")

        app.model.contest.deactivate()
        dialogs.setOpen(.startup, true)
        #expect(app.model.contest.showStartupDialog)
        dialogs.continueLastContest()
        #expect(!dialogs.isOpen(.startup))
        await dialogs.settle()
        #expect(app.model.contest.isActive)

        dialogs.setOpen(.startup, true)
        dialogs.startupNewContest()
        #expect(!dialogs.isOpen(.startup))
        #expect(dialogs.isOpen(.newContest))
        dialogs.setOpen(.newContest, false)
        dialogs.setOpen(.startup, true)
        dialogs.startupOpenContest()
        #expect(dialogs.isOpen(.contests))
    }

    @Test func browserRowsAreReadOncePerOpening() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let dialogs: DialogsModel = model.dialogs
        dialogs.setOpen(.contests, true)
        #expect(dialogs.browserRows == nil)
        await dialogs.loadBrowser()
        let rows: [ContestBrowserRow] = try #require(dialogs.browserRows)
        #expect(rows.count == 1)
        let row: ContestBrowserRow = try #require(rows.first)
        #expect(ContestBrowserText.title(row).hasSuffix("  (" + row.year + ")"))
        #expect(ContestBrowserText.detail(row) == row.dateRange + " · 1 QSO · " + row.bands + " · SINGLE-OP · LOW"
            || ContestBrowserText.detail(row) == row.dateRange + " · 1 QSO · " + row.bands + " · — · —")
        // Re-opening an open window keeps the rows; closing and opening reads them again.
        dialogs.setOpen(.contests, true)
        #expect(dialogs.browserRows != nil)
        dialogs.setOpen(.contests, false)
        dialogs.setOpen(.contests, true)
        #expect(dialogs.browserRows == nil)

        model.contest.deactivate()
        dialogs.openContest(row.contestId)
        #expect(!dialogs.showContestBrowser)
        await dialogs.settle()
        #expect(model.contest.activeId == row.contestId)
    }

    @Test func newContestSavesTheSetupAndStarts() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let dialogs: DialogsModel = model.dialogs
        dialogs.setOpen(.newContest, true)
        let form: NewContestModel = try #require(dialogs.newContest)
        #expect(form.selectedId == model.contest.runtime.available.first?.id)
        let label: String = try #require(form.labels.first { $0.id == "cq-ww-cw" }?.text)
        form.select(label: label)
        #expect(form.selectedId == "cq-ww-cw")
        #expect(form.selectedLabel == label)
        #expect(form.category("OPERATOR") == "SINGLE-OP")
        #expect(form.category("BAND") == "ALL")
        #expect(form.sentFieldIds == ["zone"])
        #expect(form.form.operators == "OK1XOE")
        form.setSent("zone", "15")
        form.setCategory("POWER", "QRP")
        form.form.soapbox = "73"

        dialogs.confirmNewContest()
        #expect(dialogs.newContest == nil)
        await dialogs.settle()
        #expect(model.contest.activeId != nil)
        #expect(model.contest.definition?.id == "cq-ww-cw")
        #expect(model.contest.activeSetup?.category["POWER"] == "QRP")
        let saved: ContestSetup = try #require(await app.savedConfigFlushed().contestSetups["cq-ww-cw"])
        #expect(saved.sentExchange["zone"] == "15")
        #expect(saved.soapbox == "73")

        // The next opening is prefilled from the saved setup, and a new window state.
        dialogs.setOpen(.newContest, true)
        let again: NewContestModel = try #require(dialogs.newContest)
        #expect(again !== form)
        again.select(label: label)
        #expect(again.category("POWER") == "QRP")
        #expect(again.sent("zone") == "15")
    }

    @Test func dateTimeFieldText() {
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC
        #expect(DateTimeText.datePart("", now: now) == "2026-09-21")
        #expect(DateTimeText.datePart("   ", now: now) == "2026-09-21")
        #expect(DateTimeText.datePart("2026-11-28 12:00", now: now) == "2026-11-28")
        #expect(DateTimeText.datePart("garbage-x", now: now) == "garbage-x")
        #expect(DateTimeText.timePart("2026-11-28 12:34") == "12:34")
        #expect(DateTimeText.timePart("2026-11-28 12:3") == "00:00")
        #expect(DateTimeText.timePart("") == "00:00")
        let picked: Date = DateTimeText.pickerDate("2026-11-28 12:00", now: now)
        #expect(picked.timeIntervalSince1970 == 1_795_824_000)
        #expect(DateTimeText.pickerDate("2026-02-30 00:00", now: now).timeIntervalSince1970 == 1_789_948_800)
        #expect(DateTimeText.pickerDate("", now: now).timeIntervalSince1970 == 1_789_948_800)
        #expect(DateTimeText.isoDate(picked) == "2026-11-28")
    }

    @Test func newContestDateFields() async throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let app = try await TestApp.make(fixedNow: now)
        app.model.dialogs.setOpen(.newContest, true)
        let form: NewContestModel = try #require(app.model.dialogs.newContest)
        let start: String = form.form.startedAt
        #expect(start == "2026-09-21 00:00")
        #expect(form.withTime(start, time: "12:00") == "2026-09-21 12:00")
        let day = Date(timeIntervalSince1970: 1_795_824_000)
        #expect(form.withDate("2026-09-21 12:00", date: day) == "2026-11-28 12:00")
        #expect(form.withDate("", date: day) == "2026-11-28 00:00")
    }

    @Test func databaseWindows() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let dialogs: DialogsModel = model.dialogs
        dialogs.setOpen(.databaseOpen, true)
        #expect(dialogs.databaseNames == nil)
        await dialogs.loadDatabases()
        #expect(dialogs.databaseNames == [model.database.currentName])

        dialogs.setOpen(.databaseNew, true)
        dialogs.newDatabaseName = "  Druhý  "
        dialogs.createDatabase()
        #expect(!dialogs.showNewDatabase)
        await dialogs.settle()
        #expect(model.database.currentName == "Druhý")
        #expect(model.status.message == "Otevřena databáze Druhý")

        // A new opening starts with an empty name.
        dialogs.setOpen(.databaseNew, true)
        #expect(dialogs.newDatabaseName.isEmpty)
        dialogs.setOpen(.databaseNew, false)

        dialogs.setOpen(.databaseOpen, false)
        dialogs.setOpen(.databaseOpen, true)
        await dialogs.loadDatabases()
        let names: [String] = try #require(dialogs.databaseNames)
        #expect(names.contains("Druhý"))
        let other: String = try #require(names.first { $0 != "Druhý" })
        dialogs.openDatabase(other)
        #expect(!dialogs.showOpenDatabase)
        await dialogs.settle()
        #expect(model.database.currentName == other)
    }

    @Test func firstRunChoosesTheDatabasesDirectory() async throws {
        let app = try await TestApp.make { config, dataDir in
            config.databasesDir = dataDir.appendingPathComponent("gone").path
        }
        let model: AppModel = app.model
        #expect(model.database.needsDatabasesDir)
        let chosen: URL = app.dir.child("dbs")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        model.dialogs.chooseDatabasesDir(chosen)
        await model.dialogs.settle()
        #expect(!model.database.needsDatabasesDir)
        #expect(model.database.databasesDir.standardizedFileURL == chosen.standardizedFileURL)
    }

    @Test func shutdownWaitsForADialogAction() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        model.dialogs.setOpen(.newContest, true)
        let form: NewContestModel = try #require(model.dialogs.newContest)
        let label: String = try #require(form.labels.first { $0.id == "cq-ww-cw" }?.text)
        form.select(label: label)
        model.dialogs.confirmNewContest()
        await model.shutdown()
        #expect(model.contest.isActive)
        #expect(!model.status.message.contains("zavřená"))
    }
}
