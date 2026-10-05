import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// DXCC refill, call history from the log, definition updates and the contest-data reload
/// (`AS:206-235`, `AS:1162-1186`, `WL:59-80`, `AS:3682-3714`).
@MainActor @Suite struct DataToolsModelTests {

    // MARK: - fixtures

    /// An app whose contest data is a writable copy of the fixtures (the definition update writes into it).
    static func makeWithDataCopy(definitionSource: DataToolsModel.DefinitionSource? = nil,
                                 configure: @escaping (inout AppConfig, URL) throws -> Void = { _, _ in })
        async throws -> TestApp {
        try await TestApp.make(definitionSource: definitionSource) { config, dataDir in
            let copy: URL = dataDir.deletingLastPathComponent().appendingPathComponent("contest-data-copy")
            try FileManager.default.copyItem(at: Fixtures.contestData, to: copy)
            config.contestDataDir = copy.path
            try configure(&config, dataDir)
        }
    }

    /// The stored QSOs of the active contest (straight from the database).
    static func stored(_ app: TestApp) async throws -> [Qso] {
        try await app.model.database.handle.run { try $0.service.findAll() }
    }

    /// Overwrites the country of every stored QSO whose call matches.
    static func corruptCountry(_ app: TestApp, call: String) async throws {
        try await app.model.database.handle.run { access in
            for var qso in try access.service.findAll() where qso.call == call {
                qso.dxccEntity = 999
                qso.dxccName = "Nowhere"
                qso.continent = "AN"
                try access.service.update(qso)
            }
        }
        try await app.model.logbook.refresh()
    }

    // MARK: - DXCC refill

    @Test func refillWithoutDxccDataReportsIt() async throws {
        let app = try await TestApp.make(withDxcc: false)
        let fixed: Int = await app.model.dataTools.refillDxcc()
        #expect(fixed == 0)
        #expect(app.model.status.message == "Přepočet DXCC: chybí data o zemích (~/dxcc-json)")
    }

    @Test func refillCorrectsOnlyTheWrongCountriesLocally() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        let good: Qso = try #require(model.logbook.rows.first { $0.call == "DL1ABC" })
        try await Self.corruptCountry(app, call: "DL1ABC")
        #expect(model.logbook.rows.first { $0.call == "DL1ABC" }?.dxccEntity == 999)
        let revision: Int64 = model.logbook.revision
        let deferred: Int = model.logbook.deferredEffects.count

        let fixed: Int = await model.dataTools.refillDxcc()

        #expect(fixed == 1)
        #expect(model.status.message == "Přepočet DXCC: opraveno 1 z 2 QSO")
        #expect(model.logbook.revision > revision)
        let row: Qso = try #require(model.logbook.rows.first { $0.call == "DL1ABC" })
        #expect(row.dxccEntity == good.dxccEntity)
        #expect(row.dxccName == good.dxccName)
        #expect(row.continent == good.continent)
        let stored: Qso = try #require(try await Self.stored(app).first { $0.call == "DL1ABC" })
        #expect(stored.dxccEntity == good.dxccEntity)
        // Locally only: no sync effect, no recount.
        #expect(model.logbook.deferredEffects.count == deferred)
        #expect(model.logbook.rows.count == 2)
    }

    @Test func refillWithNothingToCorrectKeepsTheRevision() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        let revision: Int64 = model.logbook.revision

        let fixed: Int = await model.dataTools.refillDxcc()

        #expect(fixed == 0)
        #expect(model.status.message == "Přepočet DXCC: vše sedí (2 QSO)")
        #expect(model.logbook.revision == revision)
    }

    @Test func refillWaitsForASubmissionInFlight() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        model.entry.setFrequency("14025")
        model.entry.callChanged("W1AW")
        model.entry.editContestField("zone", "5")
        model.entry.submit()

        _ = await model.dataTools.refillDxcc()

        // The submitted QSO was stored before the refill read the log: counted once, no row lost or doubled.
        #expect(model.status.message == "Přepočet DXCC: vše sedí (2 QSO)")
        await model.entry.settle()
        #expect(model.logbook.rows.map(\.call).sorted() == ["DL1ABC", "W1AW"])
        #expect(try await Self.stored(app).count == 2)
    }

    @Test func confirmationCountsTheRowsWhenOpenedAndJoinsTheKotlinPieces() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")

        let request: MenuActions.Request? = MenuActions.perform("database.refillDxcc", app: model)
        #expect(request == .confirmRefillDxcc(count: 2))
        let texts = model.dataTools.refillConfirmation(count: 2)
        #expect(texts.title == "Přepočítat DXCC u 2 QSO?")
        #expect(texts.text == "Země (číslo DXCC, název, kontinent) se u všech spojení odvodí znovu z volačky "
            + "podle dnešního country file a přepíše to, co je uložené teď.\n\n"
            + "Hodí se, když jsou uložená čísla špatně. Pozor: přepíše i údaje z importovaného "
            + "deníku, které mohly být určené přesněji než odhadem z prefixu. Spojení, jejichž "
            + "volačku country file nezná, zůstanou beze změny.")
        #expect(texts.confirm == "Přepočítat")
        #expect(texts.cancel == "Zrušit")
    }

    // MARK: - call history from the log

    @Test func callHistoryOutsideAContestAsksForOne() async throws {
        let app = try await TestApp.make()
        _ = MenuActions.perform("contest.updateCallHistory", app: app.model)
        #expect(app.model.status.message == "Call history se aktualizuje z deníku závodu — otevři závod")
    }

    @Test func callHistoryOfAnEmptyLogSavesNothing() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        app.model.dataTools.updateCallHistoryFromLog()
        await app.model.dataTools.settle()
        #expect(app.model.status.message == "Deník nemá žádnou výměnu k uložení do call history")
        #expect(!FileManager.default.fileExists(atPath: app.dataDir.appendingPathComponent("CALLHISTORY.txt").path))
    }

    @Test func callHistoryWithoutAConfiguredFileGoesToTheDataDirectory() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        await app.logContestQso(call: "W1AW", zone: "5")
        await model.callData.settle()
        let revision: Int = model.callData.callHistoryRevision
        let target: String = app.dataDir.appendingPathComponent("CALLHISTORY.txt").path
        // The core over the same rows and a fresh session (the values do not depend on the logged state).
        let session: ContestSession = try #require(model.contest.runtime.freshSession())
        let expected = try CallHistoryUpdater.updates(session, model.logbook.rows, CallHistory.empty)

        model.dataTools.updateCallHistoryFromLog()
        await model.dataTools.settle()

        #expect(model.status.message == "Call history: 2 volaček z deníku, celkem 2 → " + target)
        let saved: String = try String(contentsOfFile: target, encoding: .utf8)
        #expect(saved == CallHistory.empty.withUpdates(expected).toLines().map { $0 + "\n" }.joined())
        #expect(saved.contains("DL1ABC"))
        // Taken over without reading the file again; the path goes into the configuration without a reload.
        #expect(model.callData.callHistory.size == 2)
        #expect(model.callData.callHistoryRevision == revision + 1)
        #expect(model.config.config.callHistoryFile == target)
        #expect(await app.savedConfigFlushed().callHistoryFile == target)
        await Self.mainHop()
        await model.callData.settle()
        #expect(model.callData.callHistoryRevision == revision + 1)
    }

    @Test func callHistoryMergesIntoTheConfiguredFile() async throws {
        let app = try await TestApp.make { config, dataDir in
            let file: URL = dataDir.appendingPathComponent("my history.txt")
            try Data("!!Order!!,Call,Name\nOK1AA,Jan\n".utf8).write(to: file)
            config.callHistoryFile = "  " + file.path + " "
        }
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await model.callData.settle()
        #expect(model.callData.callHistory.size == 1)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let target: String = app.dataDir.appendingPathComponent("my history.txt").path

        model.dataTools.updateCallHistoryFromLog()
        await model.dataTools.settle()

        #expect(model.status.message == "Call history: 1 volaček z deníku, celkem 2 → " + target)
        #expect(model.callData.callHistory.size == 2)
        let saved: String = try String(contentsOfFile: target, encoding: .utf8)
        #expect(saved.contains("\n!!Order!!,Call,Name"))
        #expect(saved.contains("OK1AA,Jan"))
        // A configured path is not rewritten.
        #expect(model.config.config.callHistoryFile == "  " + target + " ")
    }

    @Test func callHistorySaveFailureIsReported() async throws {
        let app = try await TestApp.make { config, dataDir in
            let blocker: URL = dataDir.appendingPathComponent("blocker")
            try Data("x".utf8).write(to: blocker)
            config.callHistoryFile = blocker.appendingPathComponent("history.txt").path
        }
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let before: Int = model.callData.callHistory.size

        model.dataTools.updateCallHistoryFromLog()
        await model.dataTools.settle()

        #expect(model.status.message.hasPrefix("Uložení call history selhalo: "))
        #expect(model.status.message.contains("blocker"))
        #expect(model.callData.callHistory.size == before)
    }

    // MARK: - definition updates

    static func definitionYaml(_ id: String) throws -> String {
        let source: URL = Fixtures.contestData.appendingPathComponent("contests/cq-ww-cw.yaml")
        return DefinitionEditing.withId(try String(contentsOf: source, encoding: .utf8), id)
    }

    @Test func definitionUpdateWritesReloadsAndReportsTheChangedFiles() async throws {
        let yaml: String = try Self.definitionYaml("test-x")
        let server = try LocalHttpServer(routes: [
            "/data/index.txt": .init(body: "contests/test-x.yaml\ncontests/missing.yaml\n"),
            "/data/contests/test-x.yaml": .init(body: yaml),
        ])
        defer { server.stop() }
        let source = DataToolsModel.DefinitionSource(fetcher: URLSessionDataFetcher(),
                                                     base: try #require(URL(string: server.url("/data/"))))
        let app = try await Self.makeWithDataCopy(definitionSource: source)
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let activeId: String? = model.contest.activeId
        model.definitionEditor.refresh()
        await model.definitionEditor.settle()
        #expect(!model.definitionEditor.ids.contains("test-x"))

        _ = MenuActions.perform("contest.updateDefinitions", app: model)
        #expect(model.status.message == "Stahuji definice závodů…")
        await model.dataTools.settle()

        #expect(model.status.message == "Definice závodů: nové 1, aktualizované 0, beze změny 0, "
            + "ponechané lokální úpravy 0, chyby 1")
        let lines: [String] = model.messages.lines.map(\.text)
        #expect(lines.count == 2)
        #expect(lines.contains("Definice contests/missing.yaml: FAILED — HTTP 404 pro "
            + server.url("/data/contests/missing.yaml")))
        #expect(lines.contains("Definice contests/test-x.yaml: NEW"))
        let root: URL = URL(fileURLWithPath: try #require(model.config.config.contestDataDir))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("contests/test-x.yaml").path))
        // Reloaded, the contest stays open, the open editor sees the new file.
        #expect(model.contest.environment.catalog.contains { $0.id == "test-x" })
        #expect(model.contest.activeId == activeId)
        #expect(!model.contest.isActivating)
        await model.definitionEditor.settle()
        #expect(model.definitionEditor.ids.contains("test-x"))
    }

    @Test func definitionUpdateFailureIsReportedVerbatim() async throws {
        let server = try LocalHttpServer(routes: [:])
        defer { server.stop() }
        let source = DataToolsModel.DefinitionSource(fetcher: URLSessionDataFetcher(),
                                                     base: try #require(URL(string: server.url("/data"))))
        let app = try await Self.makeWithDataCopy(definitionSource: source)

        app.model.dataTools.updateDefinitions()
        await app.model.dataTools.settle()

        #expect(app.model.status.message == "Aktualizace definic selhala: HTTP 404 pro " + server.url("/data/index.txt"))
        #expect(app.model.messages.lines.isEmpty)
    }

    /// Shutdown waits for a definition update in flight (a fetcher held back) before it finishes.
    @Test func shutdownWaitsForADefinitionUpdateInFlight() async throws {
        let fetcher = GatedFetcher()
        let source = DataToolsModel.DefinitionSource(fetcher: fetcher, base: try #require(URL(string: "http://x.invalid/")))
        let app = try await Self.makeWithDataCopy(definitionSource: source)
        let finished = ShutdownFlag()
        app.model.dataTools.updateDefinitions()
        await fetcher.waitUntilEntered()
        let shutdown = Task { @MainActor in
            await app.model.shutdown()
            finished.done = true
        }
        for _ in 0..<50 {
            await Task.yield()
        }
        #expect(!finished.done)

        await fetcher.release()
        await shutdown.value

        #expect(finished.done)
        #expect(app.model.status.message.hasPrefix("Aktualizace definic selhala"))
    }

    @MainActor final class ShutdownFlag {
        var done = false
    }

    /// Holds `fetch` back until `release()`, then answers 404.
    actor GatedFetcher: DataFetcher {
        private var entered = false
        private var released = false
        private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
            entered = true
            for waiter in enteredWaiters {
                waiter.resume()
            }
            enteredWaiters = []
            if !released {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
            return (404, Data())
        }

        func waitUntilEntered() async {
            if !entered {
                await withCheckedContinuation { enteredWaiters.append($0) }
            }
        }

        func release() {
            released = true
            for waiter in releaseWaiters {
                waiter.resume()
            }
            releaseWaiters = []
        }
    }

    @Test func aSecondDefinitionUpdateRunsAfterTheFirst() async throws {
        let yaml: String = try Self.definitionYaml("test-x")
        let server = try LocalHttpServer(routes: [
            "/index.txt": .init(body: "contests/test-x.yaml\n"),
            "/contests/test-x.yaml": .init(body: yaml),
        ])
        defer { server.stop() }
        let source = DataToolsModel.DefinitionSource(fetcher: URLSessionDataFetcher(),
                                                     base: try #require(URL(string: server.url("/"))))
        let app = try await Self.makeWithDataCopy(definitionSource: source)

        app.model.dataTools.updateDefinitions()
        app.model.dataTools.updateDefinitions()
        await app.model.dataTools.settle()

        #expect(server.requestedPaths == ["/index.txt", "/contests/test-x.yaml", "/index.txt", "/contests/test-x.yaml"])
        // The second run found the file of the first one.
        #expect(app.model.status.message == "Definice závodů: nové 0, aktualizované 0, beze změny 1, "
            + "ponechané lokální úpravy 0, chyby 0")
        #expect(app.model.messages.lines.map(\.text) == ["Definice contests/test-x.yaml: NEW"])
    }

    // MARK: - contest-data reload

    @Test func reloadDuringAContestKeepsScoringAndDupeChecking() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let activeId: String? = model.contest.activeId
        model.status.showVerbatim("caller")

        let reopened: Bool = await model.contest.reloadContestData()

        #expect(reopened)
        #expect(model.contest.activeId == activeId)
        #expect(model.status.message == "caller")
        #expect(!model.contest.isActivating)
        let before: Int64 = try #require(model.contest.score?.total)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        #expect(model.contest.score?.total == before)
        await app.logContestQso(call: "W1AW", zone: "5")
        #expect(try #require(model.contest.score?.total) > before)
    }

    /// The reopen after a reload does not queue the spot-filter reset or the plugin event again.
    @Test func reloadDoesNotRepeatOpeningEffects() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        func count(_ matches: (ActivationEffect) -> Bool) -> Int {
            model.contest.deferredEffects.filter(matches).count
        }
        let plugin: Int = count { if case .firePlugin = $0 { return true } else { return false } }
        let cluster: Int = count { $0 == .startClusterIfIdle }
        #expect(plugin == 1)
        // The operator narrowed the available multipliers' filter; a reload does not reset it.
        model.availMult.modes = ["PHONE"]

        #expect(await model.contest.reloadContestData())

        #expect(model.availMult.modes == ["PHONE"])
        #expect(count { if case .firePlugin = $0 { return true } else { return false } } == plugin)
        #expect(count { $0 == .startClusterIfIdle } == cluster + 1)
    }

    /// The RELOAD command opens the contest as Kotlin `reloadAll` does: the opening effects run again.
    @Test func reloadCommandRepeatsOpeningEffects() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        func isPlugin(_ effect: ActivationEffect) -> Bool {
            if case .firePlugin = effect { return true }
            return false
        }
        let before: [ActivationEffect] = model.contest.deferredEffects
        // A narrowed filter goes back to the definition's (the spot filter reset runs again).
        model.availMult.modes = ["PHONE"]

        await model.contest.reloadAll()

        let after: [ActivationEffect] = model.contest.deferredEffects
        func isCluster(_ effect: ActivationEffect) -> Bool { effect == .startClusterIfIdle }
        let pluginBefore: Int = before.filter(isPlugin).count
        let clusterBefore: Int = before.filter(isCluster).count
        #expect(model.availMult.modes == ["CW"])
        #expect(after.filter(isPlugin).count == pluginBefore + 1)
        #expect(after.filter(isCluster).count == clusterBefore + 1)
    }

    /// A second reload started while the first one has dropped the runtime and not yet reopened the contest (a
    /// profile load during a definition update's reload) queues behind it and still finds the contest.
    @Test func overlappingReloadsKeepTheContestOpen() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let activeId: String? = model.contest.activeId
        let second = SecondReload()
        model.contest.beforeReopen = { [weak model] in
            guard let model, second.task == nil else { return }
            second.task = Task { await model.contest.reloadContestData() }
            // Let the second reload run as far as it can before the first one reopens.
            for _ in 0..<20 {
                await Task.yield()
            }
        }

        let first: Bool = await model.contest.reloadContestData()
        let secondReopened: Bool? = await second.task?.value

        #expect(first)
        #expect(secondReopened == true)
        #expect(model.contest.activeId == activeId)
        #expect(!model.contest.isActivating)
        let before: Int64 = try #require(model.contest.score?.total)
        await app.logContestQso(call: "DL1ABC", zone: "14")
        #expect(model.contest.score?.total == before)
        await app.logContestQso(call: "W1AW", zone: "5")
        #expect(try #require(model.contest.score?.total) > before)
    }

    @MainActor final class SecondReload {
        var task: Task<Bool, Never>?
    }

    @Test func reloadOutsideAContestOpensNothing() async throws {
        let app = try await TestApp.make()
        let reopened: Bool = await app.model.contest.reloadContestData()
        #expect(!reopened)
        #expect(!app.model.contest.isActive)
    }

    // MARK: - menu

    @Test func profilesMenuOpensTheWindowWithoutSavingIt() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let saved: [String] = model.config.config.openWindows

        _ = MenuActions.perform("settings.profiles", app: model)

        #expect(model.windows.isOpen("profiles"))
        #expect(model.config.config.openWindows == saved)
        model.windows.setOpen("log", true)
        #expect(model.config.config.openWindows.contains("log"))
        #expect(!model.config.config.openWindows.contains("profiles"))
        #expect(model.windows.isOpen("profiles"))
    }

    /// Lets the main-queue hops posted so far run (observation callbacks).
    static func mainHop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MainHop.post {
                continuation.resume()
            }
        }
    }
}
