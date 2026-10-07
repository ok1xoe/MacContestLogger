import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// File → Copy contest to another database, Tools → Rescore last N hours.
@MainActor @Suite struct CopyContestAndRescoreHoursTests {

    private static let t0 = Date(timeIntervalSince1970: 1_795_867_200)

    // MARK: copy

    private static func stored(_ app: TestApp, database name: String) throws -> [Qso] {
        let url: URL = app.model.database.databasesDir.appendingPathComponent(name + ".sqlite")
        let repository = try LogbookRepository(url: url)
        defer { repository.close() }
        return try repository.findAll()
    }

    @Test func theMenuItemOpensTheWindowAndCopiesTheActiveContest() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let id: String = try #require(model.contest.activeId)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        let open: String = model.database.currentName

        #expect(MenuActions.perform("file.copyContest", app: model) == nil)
        let window: CopyContestModel = try #require(model.dialogs.copyContest)
        #expect(model.dialogs.isOpen(.copyContest))
        await window.load()
        #expect(window.selectedContest == id)
        #expect(window.contests?.map(\.contestId) == [id])
        // The open database is not offered as a target.
        #expect(window.databases?.contains(open) == false)
        #expect(!window.canCopy || window.targetName != open)

        window.newName = "archive"
        #expect(window.canCopy)
        await window.copy()

        #expect(model.status.message == "Zkopírováno do databáze archive: 1 závodů, 2 QSO (0 už tam bylo)")
        #expect(!model.dialogs.isOpen(.copyContest))
        #expect(try Self.stored(app, database: "archive").map(\.call).sorted() == ["DL1ABC", "W1AW"])
        // The open database and its contest are unchanged and still active.
        #expect(model.contest.activeId == id)
        #expect(model.logbook.rows.count == 2)
        #expect(model.database.currentName == open)
    }

    @Test func copyingToAnExistingDatabaseTwiceAddsNothing() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await model.database.create("archive")
        await model.database.open("Deník")
        try await app.startCqWwCw()

        for round in 1...2 {
            model.dialogs.setOpen(.copyContest, true)
            let window: CopyContestModel = try #require(model.dialogs.copyContest)
            await window.load()
            window.selectedContest = nil
            window.targetExisting = "archive"
            await window.copy()
            if round == 2 {
                #expect(model.status.message.hasSuffix("(1 už tam bylo)"))
            }
        }
        #expect(try Self.stored(app, database: "archive").count == 1)
    }

    @Test func refusals() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        model.dialogs.setOpen(.copyContest, true)
        let window: CopyContestModel = try #require(model.dialogs.copyContest)
        await window.load()
        await window.copy()
        #expect(model.status.message == "Vyber cílovou databázi nebo zadej název nové")
        window.newName = model.database.currentName
        await window.copy()
        #expect(model.status.message == "Cílová databáze je ta otevřená")
        window.newName = "a/b"
        await window.copy()
        #expect(model.status.message == "Název databáze nesmí obsahovat „/“")
        #expect(window.canCopy)
    }

    // MARK: rescore last N hours

    /// A QSO stored straight into the log at a given time (the entry stamps the QSOs it logs with the real clock) and
    /// without a country, as an import would leave it.
    private static func inject(_ app: TestApp, _ call: String, zone: String, at time: Date) async throws {
        var qso = Qso()
        qso.timestampUtc = time
        qso.call = call
        qso.freqHz = 14_025_000
        qso.mode = .cw
        qso.exchangeRcvd = "599 " + zone
        try await app.model.logbook.perform(qso, effects: [.persist, .bumpRevision, .addDupe, .appendRow,
                                                           .refreshCount])
        // The automatic recount (no country fill, unlike the manual one).
        app.model.contest.requestRescore()
        app.rescoreClock.advance(by: 300)
        await app.model.contest.settleRescore()
    }

    @Test func promptAsksForTheHoursAndRejectsNonsense() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        #expect(MenuActions.perform("contest.rescoreHours", app: app.model) == nil)
        let prompt = try #require(app.model.dialogs.textPrompt)
        #expect(prompt.initial == "24")
        app.model.dialogs.submitPrompt("abc")
        #expect(app.model.status.message == "Neplatný počet hodin (1–8760)")
    }

    @Test func aPartialRescoreFillsCountriesOnlyInsideTheWindow() async throws {
        let now = TestNow(Self.t0)
        let app = try await TestApp.make(now: now)
        let model: AppModel = app.model
        try await app.startCqWwCw()
        // Stored 30 hours before "now", and 1 hour before.
        try await Self.inject(app, "DL1ABC", zone: "14", at: Self.t0.addingTimeInterval(-30 * 3600))
        try await Self.inject(app, "W1AW", zone: "5", at: Self.t0.addingTimeInterval(-3600))
        let total: Int64 = try #require(model.contest.score?.total)
        let before: [Qso] = try await model.database.handle.run { try $0.service.findAll() }
        #expect(before.allSatisfy { $0.dxccEntity == nil })

        model.contest.requestRescore(manual: true, lastHours: 2)
        await model.contest.settleRescore()

        #expect(model.status.message == "Skóre přepočteno za posledních 2 h: 1 QSO, celkem \(total) (beze změny) · doplněna země u 1 QSO", "\(model.status.message)")
        let rows: [Qso] = try await model.database.handle.run { try $0.service.findAll() }
        let old: Qso = try #require(rows.first { $0.call == "DL1ABC" })
        let recent: Qso = try #require(rows.first { $0.call == "W1AW" })
        #expect(old.dxccEntity == nil)
        #expect(recent.dxccEntity != nil)
        // The score is the whole log's, as after a full rescore.
        #expect(model.contest.score?.qsoCount == 2)
        #expect(model.contest.score?.total == total)

        model.contest.requestRescore(manual: true)
        await model.contest.settleRescore()
        let all: [Qso] = try await model.database.handle.run { try $0.service.findAll() }
        #expect(all.first { $0.call == "DL1ABC" }?.dxccEntity != nil)
    }

    @Test func aWindowWithoutQsosSaysSoAndChangesNothing() async throws {
        let now = TestNow(Self.t0)
        let app = try await TestApp.make(now: now)
        try await app.startCqWwCw()
        try await Self.inject(app, "DL1ABC", zone: "14", at: Self.t0)
        now.advance(seconds: 10 * 3600)
        app.model.contest.requestRescore(manual: true, lastHours: 2)
        #expect(app.model.status.message == "Přepočet skóre: v posledních 2 h nejsou žádná QSO")
        #expect(!app.model.contest.scheduler.isBusy)
    }

    @Test func theMenuItemNeedsAnActiveContest() async throws {
        let app = try await TestApp.make()
        #expect(!app.model.menu.runtimeEnabled("contest.rescoreHours") || app.model.contest.isActive)
        #expect(app.model.menu.runtimeEnabled("file.copyContest"))
        try await app.startCqWwCw()
        #expect(app.model.menu.runtimeEnabled("contest.rescoreHours"))
    }
}
