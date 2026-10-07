import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Tools → Assign call to country, File → Export → ADIF by date, call history export and clearing.
@MainActor @Suite struct N1mmMiscToolsTests {

    private static let t0 = Date(timeIntervalSince1970: 1_795_867_200)   // 2026-11-28T12:00:00Z

    /// A QSO stored into the log at a given time (the entry stamps its QSOs with the real clock).
    private static func inject(_ app: TestApp, _ call: String, zone: String = "14", at time: Date) async throws {
        var qso = Qso()
        qso.timestampUtc = time
        qso.call = call
        qso.freqHz = 14_025_000
        qso.mode = .cw
        qso.exchangeRcvd = "599 " + zone
        try await app.model.logbook.perform(qso, effects: [.persist, .bumpRevision, .addDupe, .appendRow,
                                                           .refreshCount])
    }

    // MARK: assign call to country

    @Test func theWindowListsEntitiesAndStartsWithTheTypedCall() async throws {
        let app = try await TestApp.make()
        app.model.entry.form.call = "ok1xyz"
        #expect(MenuActions.perform("tools.addCallToCountry", app: app.model) == nil)
        let model: DxccOverridesModel = try #require(app.model.dialogs.dxccOverrides)
        #expect(model.call == "OK1XYZ")
        #expect(model.choices.map(\.number).contains(503))
        #expect(model.choices.map(\.name) == model.choices.map(\.name).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
        model.filter = "germ"
        #expect(model.shown.map(\.number) == [230])
        model.filter = "503"
        #expect(model.shown.map(\.name) == ["Czech Republic"])
        #expect(!model.canAdd)
    }

    @Test func anAssignmentAppliesAtOnceAndSurvivesARestart() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        #expect(model.contest.runtime.dxccLookup?.resolve("OK1XYZ")?.entityCode == 503)
        model.dialogs.setOpen(.dxccOverrides, true)
        let window: DxccOverridesModel = try #require(model.dialogs.dxccOverrides)
        window.call = "ok1xyz"
        window.selected = 230
        #expect(window.canAdd)
        await window.add()

        #expect(model.status.message == "Volačka OK1XYZ přiřazena k zemi Germany")
        #expect(model.contest.runtime.dxccLookup?.resolve("OK1XYZ")?.entityCode == 230)
        #expect(window.entries == [DxccOverrideStore.Entry(call: "OK1XYZ", dxcc: 230, name: "Germany")])
        #expect(window.call.isEmpty)
        let file: URL = DxccOverrideStore.file(in: model.dataDir)
        #expect(FileManager.default.fileExists(atPath: file.path))

        await model.shutdown()
        let again = AppModel.Environment(dataDir: app.dataDir, dxccDir: try Fixtures.dxccDir(in: app.dir),
                                         rescoreClock: ManualClock(), geometryClock: ManualClock(),
                                         backupClock: ManualClock())
        let second: AppModel = try await AppModel.bootstrap(again)
        #expect(second.contest.runtime.dxccLookup?.resolve("OK1XYZ")?.entityCode == 230)
        second.dialogs.setOpen(.dxccOverrides, true)
        let reopened: DxccOverridesModel = try #require(second.dialogs.dxccOverrides)
        #expect(reopened.entries.map(\.call) == ["OK1XYZ"])
        await reopened.remove("OK1XYZ")
        #expect(second.contest.runtime.dxccLookup?.resolve("OK1XYZ")?.entityCode == 503)
        #expect(second.status.message == "Přiřazení volačky OK1XYZ odebráno")
        await second.shutdown()
    }

    @Test func theRecalculationOfTheLogUsesTheAssignments() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "OK1ABC", zone: "15")
        #expect(model.logbook.rows.first?.dxccEntity == 503)
        model.dialogs.setOpen(.dxccOverrides, true)
        let window: DxccOverridesModel = try #require(model.dialogs.dxccOverrides)
        window.call = "OK1ABC"
        window.selected = 230
        await window.add()
        // Stored QSOs keep their country until the recalculation …
        #expect(model.logbook.rows.first?.dxccEntity == 503)
        // … which the window offers through the same confirmation as the menu.
        #expect(MenuActions.perform("database.refillDxcc", app: model) == .confirmRefillDxcc(count: 1))
        let fixed: Int = await model.dataTools.refillDxcc()
        #expect(fixed == 1)
        #expect(model.logbook.rows.first?.dxccEntity == 230)
    }

    // MARK: ADIF by date

    private static func adifCalls(_ file: URL) throws -> [String] {
        let text: String = try String(contentsOf: file, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: "<CALL:\\d+>([^ <]+)")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    @Test func theWindowCountsTheQsosOfThePeriodAndExportsThem() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        try await Self.inject(app, "DL1AAA", at: Self.t0.addingTimeInterval(-26 * 3600))   // 27th 10:00
        try await Self.inject(app, "DL1BBB", at: Self.t0)                                    // 28th 12:00
        try await Self.inject(app, "DL1CCC", at: Self.t0.addingTimeInterval(11 * 3600 + 59 * 60 + 59))  // 28th 23:59:59
        try await Self.inject(app, "DL1DDD", at: Self.t0.addingTimeInterval(12 * 3600))      // 29th 00:00:00

        #expect(MenuActions.perform("settings.exportAdifRange", app: model) == nil)
        let window: AdifRangeModel = try #require(model.dialogs.adifRange)
        // Starts on the first and last day of the log.
        #expect(window.qsoCount == 4)
        window.first = Self.t0
        window.last = Self.t0
        #expect(window.qsoCount == 2)
        #expect(window.canExport)
        #expect(window.suggestedName == "maccontestlogger-2026-11-28.adi")

        let file: URL = app.dir.child("range.adi")
        await model.exports.exportAdif(to: file, range: window.range)
        #expect(try Self.adifCalls(file).sorted() == ["DL1BBB", "DL1CCC"])
        #expect(model.status.message == "Exportováno do " + file.path + " (2 QSO)")

        // The whole export is unchanged.
        let all: URL = app.dir.child("all.adi")
        await model.exports.exportAdif(to: all)
        #expect(try Self.adifCalls(all).count == 4)
    }

    @Test func aPeriodWithoutQsosWritesNoFile() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        try await Self.inject(app, "DL1AAA", at: Self.t0)
        let range = try #require(AdifDateRange(firstDay: Self.t0.addingTimeInterval(86_400 * 5),
                                               lastDay: Self.t0.addingTimeInterval(86_400 * 6)))
        let file: URL = app.dir.child("none.adi")
        await app.model.exports.exportAdif(to: file, range: range)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(app.model.status.message == "Export ADIF: v zadaném období nejsou žádná QSO")
    }

    @Test func aReversedPeriodCannotBeExported() async throws {
        let app = try await TestApp.make()
        app.model.dialogs.setOpen(.adifRange, true)
        let window: AdifRangeModel = try #require(app.model.dialogs.adifRange)
        window.first = Self.t0.addingTimeInterval(86_400 * 3)
        window.last = Self.t0
        #expect(window.range == nil)
        #expect(!window.canExport)
    }

    // MARK: call history

    private static func appWithHistory(_ lines: [String]) async throws -> (app: TestApp, file: URL) {
        var path: URL?
        let app = try await TestApp.make { config, dataDir in
            let file: URL = dataDir.appendingPathComponent("history.txt")
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
            config.callHistoryFile = file.path
            path = file
        }
        await app.model.callData.settle()
        return (app, try #require(path))
    }

    @Test func exportWritesTheN1mmFileAndCsv() async throws {
        let (app, source) = try await Self.appWithHistory(["!!Order!!,Call,Name,State", "W1AW,Hiram,CT", "K1ZZ,,MA"])
        let model: AppModel = app.model
        #expect(model.dataTools.hasCallHistory)
        let before: Data = try Data(contentsOf: source)

        #expect(MenuActions.perform("callhistory.exportN1mm", app: model)
            == .saveCallHistory(format: .n1mm, suggestedName: "call-history.txt"))
        #expect(MenuActions.perform("callhistory.exportCsv", app: model)
            == .saveCallHistory(format: .csv, suggestedName: "call-history.csv"))
        let n1mm: URL = app.dir.child("out.txt")
        await model.dataTools.exportCallHistory(to: n1mm, format: .n1mm)
        #expect(CallHistory.load(n1mm.path).size == 2)
        let csv: URL = app.dir.child("out.csv")
        await model.dataTools.exportCallHistory(to: csv, format: .csv)
        #expect(try String(contentsOf: csv, encoding: .utf8) == "Call,Name,State\r\nK1ZZ,,MA\r\nW1AW,Hiram,CT\r\n")
        #expect(model.status.message == "Call history exportována do " + csv.path + " (2 volaček)")
        // The loaded file is untouched.
        #expect(try Data(contentsOf: source) == before)
    }

    @Test func exportWithoutAHistorySaysSo() async throws {
        let app = try await TestApp.make()
        #expect(!app.model.dataTools.hasCallHistory)
        #expect(MenuActions.perform("callhistory.exportCsv", app: app.model) == nil)
        #expect(app.model.status.message == "Call history je prázdná")
        #expect(MenuActions.perform("callhistory.clear", app: app.model) == nil)
        #expect(app.model.dialogs.confirmation == nil)
    }

    @Test func clearAsksFirstThenKeepsABackupAndEmptiesTheFile() async throws {
        let (app, source) = try await Self.appWithHistory(["!!Order!!,Call,Name,State", "W1AW,Hiram,CT", "K1ZZ,,MA"])
        let model: AppModel = app.model
        let original: Data = try Data(contentsOf: source)

        #expect(MenuActions.perform("callhistory.clear", app: model) == nil)
        #expect(model.dialogs.confirmation == .clearCallHistory)
        #expect(model.dialogs.confirmationButton == .verbatim("Vymazat"))
        // Nothing happened yet.
        #expect(try Data(contentsOf: source) == original)
        #expect(model.dataTools.hasCallHistory)

        // Cancelling changes nothing.
        model.dialogs.cancelConfirmation()
        #expect(try Data(contentsOf: source) == original)

        model.dialogs.ask(.clearCallHistory)
        model.dialogs.confirm()
        await model.dataTools.settle()

        #expect(!model.dataTools.hasCallHistory)
        let lines: [String] = try String(contentsOf: source, encoding: .utf8).components(separatedBy: "\n")
        #expect(lines.contains("!!Order!!,Call,Name,State"))
        #expect(!lines.contains { $0.hasPrefix("W1AW") })
        let backups: [URL] = try FileManager.default.contentsOfDirectory(at: source.deletingLastPathComponent(),
                                                                         includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("history.txt.bak-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
        #expect(model.status.message.hasPrefix("Call history vymazána (2 volaček), záloha: "))
        // The call history tab / prefill sees an empty list; clearing again says so.
        #expect(MenuActions.perform("callhistory.clear", app: model) == nil)
        #expect(model.dialogs.confirmation == nil)
    }
}
