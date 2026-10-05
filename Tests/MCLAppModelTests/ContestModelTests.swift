import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// `ContestModel`: activation by the plan (performed and deferred effects), the replay guard, the recount and the
/// database switch. Kotlin source: `AppState.createAndStartContest/openContest/activateContest/requestRescore`.
@MainActor @Suite struct ContestModelTests {

    private static func metaLastContest(_ app: TestApp) async throws -> String? {
        try await app.model.database.handle.run { access in
            try access.repository.metaGet("last_contest_id")
        }
    }

    @Test func newContestIsActivatedWithTheKotlinEffects() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let contest: ContestModel = app.model.contest
        #expect(contest.isActive)
        #expect(contest.activeName == "CQ WW DX Contest — CW")
        #expect(app.model.status.message == "Spuštěn závod CQ WW DX Contest — CW")
        let id: String = try #require(contest.activeId)
        #expect(app.model.logbook.activeContestId == id)
        #expect(try await Self.metaLastContest(app) == id)
        #expect(contest.activeSetup?.sentExchange["zone"] == "15")
        #expect(contest.score?.qsoCount == 0)
        // The spot filters are applied: the definition's mode category; the plugin event and the cluster start
        // stay deferred.
        #expect(app.model.availMult.modes == ["CW"])
        #expect(contest.deferredEffects.count == 2)
        #expect(contest.deferredEffects.last == .startClusterIfIdle)
        // Single-mode contest: the entry takes CW and the contest report.
        #expect(app.model.entry.form.mode == .cw)
        #expect(app.model.entry.form.contestExchange["rst"] == "599")
        // The log table follows the contest's columns.
        #expect(app.model.logbook.visibleColumns.contains(.points))
        #expect(!app.model.logbook.visibleColumns.contains(.serialSent))
    }

    @Test func activationFailureIsReported() async throws {
        let app = try await TestApp.make(withDxcc: false)
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        let started: Bool = await app.model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup)
        #expect(!started)
        #expect(!app.model.contest.isActive)
        #expect(app.model.status.message == "Nelze aktivovat závod: Contest engine není dostupný.")
    }

    @Test func unknownDefinitionIsReported() async throws {
        let app = try await TestApp.make()
        let started: Bool = await app.model.contest.createAndStart(definitionId: "no-such", setup: ContestSetup())
        #expect(!started)
        #expect(app.model.status.message == "Nelze načíst definici závodu 'no-such' pro snapshot.")
    }

    @Test func openingReplaysTheLog() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let id: String = try #require(app.model.contest.activeId)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        let total: Int64? = app.model.contest.score?.total
        app.model.contest.deactivate()
        #expect(!app.model.contest.isActive)
        let opened: Bool = await app.model.contest.open(contestId: id)
        #expect(opened)
        #expect(app.model.status.message == "Otevřen závod CQ WW DX Contest — CW")
        #expect(app.model.contest.score?.qsoCount == 2)
        #expect(app.model.contest.score?.total == total)
        #expect(app.model.logbook.rows.count == 2)
    }

    @Test func openingAMissingContestIsReported() async throws {
        let app = try await TestApp.make()
        let opened: Bool = await app.model.contest.open(contestId: "missing")
        #expect(!opened)
        #expect(app.model.status.message == "Závod nenalezen v databázi")
    }

    @Test func staleActivationReplayIsReplayedAgain() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let id: String = try #require(app.model.contest.activeId)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        app.model.contest.deactivate()
        var injected = false
        app.model.contest.afterActivationReplay = {
            guard !injected else { return }
            injected = true
            // A QSO stored while the replay ran (the entry is closed meanwhile, so it arrives through the logbook
            // directly, as an import or a network QSO would): the first replay is stale.
            var qso = Qso()
            qso.call = "W1AW"
            qso.freqHz = 14_025_000
            qso.mode = .cw
            qso.exchangeRcvd = "599 5"
            _ = try? await app.model.logbook.perform(qso, effects: [.persist, .bumpRevision, .addDupe, .appendRow,
                                                                   .refreshCount])
        }
        let opened: Bool = await app.model.contest.open(contestId: id)
        #expect(opened)
        #expect(injected)
        #expect(app.model.contest.score?.qsoCount == 2)
    }

    @Test func manualRescoreOutsideAContest() async throws {
        let app = try await TestApp.make()
        app.model.contest.requestRescore(manual: true)
        #expect(app.model.status.message == "Přepočet skóre: není aktivní závod")
    }

    @Test func manualRescoreReportsTheSummary() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        let total: Int64 = try #require(app.model.contest.score?.total)
        app.model.contest.requestRescore(manual: true)
        await app.model.contest.settleRescore()
        #expect(app.model.status.message == "Skóre přepočteno: 2 QSO, celkem \(total) (beze změny)")
        #expect(!app.model.contest.scheduler.isBusy)
    }

    @Test func automaticRescoreWaitsForTheDebounce() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        app.model.status.clear()
        app.model.contest.requestRescore()
        app.model.contest.requestRescore()
        #expect(app.rescoreClock.pendingCount == 1)
        app.rescoreClock.advance(by: 299)
        #expect(app.model.contest.rescoreTask == nil)
        app.rescoreClock.advance(by: 1)
        await app.model.contest.settleRescore()
        #expect(app.model.contest.score?.qsoCount == 1)
        #expect(app.model.status.message == "")
    }

    @Test func rescoreAfterALogChangeRunsAgain() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        app.model.contest.requestRescore(manual: true)
        // The log changes while the replay runs: the result is dropped and the recount repeats.
        app.model.logbook.bumpRevision()
        await app.model.contest.settleRescore()
        #expect(app.model.status.message.hasPrefix("Skóre přepočteno: 1 QSO"))
    }

    @Test func noneDeactivatesOnlyTheSession() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let id: String? = app.model.contest.activeId
        app.model.contest.deactivate()
        #expect(!app.model.contest.isActive)
        #expect(app.model.contest.score == nil)
        // Kotlin `contest.deactivate()` leaves the logbook's active contest.
        #expect(app.model.logbook.activeContestId == id)
        #expect(!app.model.logbook.visibleColumns.contains(.points))
    }

    @Test func browserRowsAreReadOffTheMainThread() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let rows: [ContestBrowserRow] = await app.model.contest.browserRows()
        #expect(rows.count == 1)
        #expect(rows.first?.name == "CQ WW DX Contest — CW")
    }
}

/// `DatabaseModel`: create, open, the first-run directory.
@MainActor @Suite struct DatabaseModelTests {

    @Test func createOpensTheNewDatabase() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.model.database.create("  Polní den ")
        #expect(app.model.database.currentName == "Polní den")
        #expect(app.model.status.message == "Otevřena databáze Polní den")
        #expect(app.model.config.config.lastDatabase == "Polní den")
        #expect(!app.model.contest.isActive)
        #expect(app.model.logbook.activeContestId == "")
        #expect(app.model.logbook.rows.isEmpty)
        #expect(try await app.model.database.list() == ["Deník", "Polní den"])
        await app.model.config.flush()
        #expect(app.savedConfig().lastDatabase == "Polní den")
    }

    @Test func existingNameIsRefused() async throws {
        let app = try await TestApp.make()
        await app.model.database.create("Deník")
        #expect(app.model.status.message == "Databáze Deník už existuje — použij Otevřít databázi.")
        await app.model.database.create(" \u{00A0}")
        #expect(app.model.database.currentName == "Deník")
    }

    @Test func openingAnotherDatabaseOffersItsContests() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.model.database.create("Druhá")
        #expect(!app.model.contest.showStartupDialog)
        await app.model.database.open("Deník")
        #expect(app.model.contest.showStartupDialog)
        #expect(app.model.status.message == "Otevřena databáze Deník")
    }

    @Test func firstRunDirectoryIsSavedAndUsed() async throws {
        let app = try await TestApp.make()
        let chosen: URL = app.dataDir.appendingPathComponent("chosen")
        await app.model.database.setDatabasesDir(chosen)
        #expect(!app.model.database.needsDatabasesDir)
        #expect(app.model.database.databasesDir == chosen)
        #expect(FileManager.default.fileExists(atPath: chosen.appendingPathComponent("Deník.sqlite").path))
        await app.model.config.flush()
        #expect(app.savedConfig().databasesDir == chosen.path)
    }
}

/// Extras changed during an activation replay are applied to the adopted session.
@MainActor @Suite struct ActivationExtrasTests {

    @Test func qtcCountChangedDuringTheReplayIsReapplied() async throws {
        let app = try await TestApp.make()
        let contest: ContestModel = app.model.contest
        contest.afterActivationReplay = {
            // The replayed session was created with 0 QTCs; the live count changes meanwhile.
            contest.runtime.setQtcCount(5)
        }
        let started: Bool = await contest.createAndStart(definitionId: "wae-cw", setup: ContestSetup())
        #expect(started)
        #expect(contest.score?.qtcPoints == 5)
    }
}
