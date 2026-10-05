import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// (safety), the outward half: QSOs logged by the pileup simulator are stored in the local database as
/// in Kotlin, but while it runs nothing is published — no cluster sync, Club Log, score report, N1MM broadcast, BCLOG,
/// WSJT-X send or plugin — and the simulated QSOs are never published later either. Every "nothing was sent" is proved
/// by a positive control through the same lane afterwards. Only loopback sockets and scripted fakes.
@MainActor @Suite struct SimulatorOutwardSafetyTests {

    /// The three hooks every consumer of a live QSO hangs on (Club Log, plugins, broadcast, WSJT-X; the broadcast of an
    /// edit and of a delete), wrapped to record what passes.
    @MainActor private final class HookLog {
        var live: [String] = []
        var edited: [String] = []
        var deleted: [String] = []

        func attach(to logbook: LogbookModel) {
            let live = logbook.onLiveQso
            logbook.onLiveQso = { [self] qso in
                self.live.append(qso.call)
                live?(qso)
            }
            let edited = logbook.onQsoEdited
            logbook.onQsoEdited = { [self] old, new in
                self.edited.append(new.call)
                edited?(old, new)
            }
            let deleted = logbook.onQsoDeleted
            logbook.onQsoDeleted = { [self] qso in
                self.deleted.append(qso.call)
                deleted?(qso)
            }
        }
    }

    /// Starts the simulation with the start refusal switched off: these tests exercise the backstops that guard a
    /// simulation that runs while a service is live (a service switched on later, a session that was already there).
    private static func startSimulation(_ model: AppModel) async {
        model.simulator.liveOutwardService = { nil }
        model.simulator.random = CountingPileupRandom()
        model.simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        await model.simulator.settle()
    }

    private static func edit(_ app: IntegrationApp, call: String) async throws {
        let old: Qso = try #require(app.model.logbook.rows.first { $0.call == call })
        var new: Qso = old
        new.comment = "edited"
        _ = await app.model.logbook.update(LogbookMutations.Edit(old: old, new: new))
    }

    // MARK: - Club Log, plugins, broadcast, BCLOG and the score

    @Test func nothingSimulatedIsPublishedWhileItRunsOrAfterwards() async throws {
        let contacts = UdpSink()
        defer { contacts.close() }
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(configure: { config, _ in
            OnlineServicesTests.clubLog(&config)
            OnlineServicesTests.score(&config)
            BroadcastIntegrationTests.enable(&config, contacts: contacts)
        }, adjust: { audio.install(into: &$0) })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        try await app.app.startCqWwCw()
        let hooks = HookLog()
        hooks.attach(to: app.model.logbook)
        await app.app.logContestQso(call: "OK1PRE", zone: "15")
        await contacts.waitFor("<call>OK1PRE</call>")
        await eventually("pre uploaded") { app.online.uploads.count == 1 }

        // A QSO of the simulation: stored locally, checked — and published nowhere.
        await Self.startSimulation(app.model)
        await app.app.logContestQso(call: "OK1SIM", zone: "15")
        #expect(app.model.logbook.rows.map(\.call) == ["OK1PRE", "OK1SIM"])
        #expect(app.model.logbook.qsoCount == 2)
        #expect(app.model.simulator.qsos == 1)
        try await Self.edit(app, call: "OK1SIM")
        app.integrations.broadcastWholeLog()
        #expect(app.model.status.message == "Simulátor běží — vysílání do TRX je zamčené (nejdřív ho zastav)")
        app.services.reportScoreNow()
        app.integrationClock.advance(by: 60_000)
        await app.services.settle()
        app.integrations.refreshBroadcastSnapshot()
        #expect(hooks.live == ["OK1PRE"])
        #expect(hooks.edited.isEmpty)
        #expect(app.online.posts.isEmpty)
        #expect(app.online.uploads.count == 1)

        // A REAL edit and delete during the run are published as usual (the gate is per QSO).
        try await Self.edit(app, call: "OK1PRE")
        #expect(hooks.edited == ["OK1PRE"])
        await app.model.logbook.delete(app.model.logbook.rows.filter { $0.call == "OK1PRE" })
        #expect(hooks.deleted == ["OK1PRE"])
        // The delete of a simulated QSO is not published; the QSO is gone locally.
        await app.model.logbook.delete(app.model.logbook.rows.filter { $0.call == "OK1SIM" })
        #expect(hooks.deleted == ["OK1PRE"])
        await app.app.logContestQso(call: "OK1SIM", zone: "15")

        // Stop: a real QSO is published (the positive control, behind the lanes of everything above)...
        app.model.simulator.stop()
        await app.model.simulator.settle()
        await app.app.logContestQso(call: "OK1REAL", zone: "15")
        await contacts.waitFor("<call>OK1REAL</call>")
        await eventually("club log") { app.online.uploads.count == 2 }
        #expect(hooks.live == ["OK1PRE", "OK1REAL"])
        // ...and the simulated QSOs never are: not their edit, not their delete, not in what was sent.
        try await Self.edit(app, call: "OK1SIM")
        #expect(hooks.edited == ["OK1PRE"])
        #expect(hooks.deleted == ["OK1PRE"])
        try await Self.edit(app, call: "OK1REAL")
        await contacts.waitFor("<contactreplace>", count: 2)
        #expect(hooks.edited == ["OK1PRE", "OK1REAL"])
        #expect(!contacts.texts.contains { $0.contains("OK1SIM") })
        #expect(app.online.uploads.allSatisfy { !$0.adif.contains("OK1SIM") })
        app.services.reportScoreNow()
        await eventually("score posted") { app.online.posts.count == 1 }
        // BCLOG skips the tagged QSO although it is still in the log: only OK1REAL is sent (again).
        #expect(app.model.logbook.rows.map(\.call).contains("OK1SIM"))
        let before: Int = contacts.count(containing: "<call>OK1REAL</call>")
        app.integrations.broadcastWholeLog()
        #expect(app.model.status.message == "BCLOG: odesláno 1 QSO")
        await contacts.waitFor("<call>OK1REAL</call>", count: before + 1)
        #expect(!contacts.texts.contains { $0.contains("OK1SIM") })
    }

    /// The tag follows the plan: closing the window while the QSO is being written must not publish it.
    @Test func aStopDuringTheDatabaseWriteStillKeepsTheQsoSimulated() async throws {
        let contacts = UdpSink()
        defer { contacts.close() }
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(configure: { config, _ in
            BroadcastIntegrationTests.enable(&config, contacts: contacts)
        }, adjust: { audio.install(into: &$0) })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        try await app.app.startCqWwCw()
        let hooks = HookLog()
        hooks.attach(to: app.model.logbook)
        await Self.startSimulation(app.model)
        // The plan is made while the simulation runs; the session ends before the write is processed.
        var qso = Qso()
        qso.call = "OK1SIM"
        qso.band = .m20
        qso.mode = .cw
        let context = QsoLogPipeline.Context(activeContestId: app.model.contest.activeId, operatorCall: "OK1XOE",
                                             simulatorActive: true, broadcastActive: true)
        let (prepared, effects) = QsoLogPipeline.plan(qso: qso, isImported: false, context: context)
        #expect(effects.contains(.simulator))
        app.model.simulator.stop()
        try await app.model.logbook.perform(prepared, effects: effects)
        #expect(app.model.logbook.rows.map(\.call) == ["OK1SIM"])
        await app.app.logContestQso(call: "OK1REAL", zone: "15")
        await contacts.waitFor("<call>OK1REAL</call>")
        #expect(hooks.live == ["OK1REAL"])
        #expect(!contacts.texts.contains { $0.contains("OK1SIM") })
    }

    /// The tag is set before the contest-switch early return: a simulated QSO stored under a contest that is no longer
    /// the active one is still known as simulated (so its later edit or delete is not published).
    @Test func theTagIsSetBeforeTheContestSwitchReturn() async throws {
        let app = try await IntegrationApp.make()
        try await app.app.startCqWwCw()
        var qso = Qso()
        qso.call = "OK1SIM"
        qso.band = .m20
        qso.mode = .cw
        let context = QsoLogPipeline.Context(activeContestId: app.model.contest.activeId, operatorCall: "OK1XOE",
                                             simulatorActive: true, broadcastActive: false)
        let (prepared, effects) = QsoLogPipeline.plan(qso: qso, isImported: false, context: context)
        #expect(effects.contains(.simulator))
        let stored = try #require(try await app.model.logbook.perform(prepared, effects: effects,
                                                                      contestId: "another-contest"))
        #expect(app.model.simulator.isSimulated(stored))
        #expect(!app.model.logbook.rows.contains { $0.call == "OK1SIM" })
    }

    // MARK: - start refusal while an outward service is live

    private static func expectRefused(_ app: AppModel, _ service: String, _ audio: SimAudioFactory,
                                      sourceLocation: SourceLocation = #_sourceLocation) async {
        app.simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        await app.simulator.settle()
        #expect(!app.simulator.isOn, sourceLocation: sourceLocation)
        #expect(!app.simulator.isStarting, sourceLocation: sourceLocation)
        #expect(audio.sinks.isEmpty, sourceLocation: sourceLocation)
        #expect(app.status.message == "Simulátor: nejdřív vypni \(service), nebo použij zkušební závod",
                sourceLocation: sourceLocation)
        // The window shows the very text of the refusal (it never starts anything the model refuses).
        #expect(app.simulator.startNotice == app.status.message, sourceLocation: sourceLocation)
    }

    @Test func startIsRefusedWhileTheScoreReportingIsOn() async throws {
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(configure: { config, _ in OnlineServicesTests.score(&config) },
                                                adjust: { audio.install(into: &$0) })
        await Self.expectRefused(app.model, "hlášení skóre", audio)
    }

    @Test func startIsRefusedWhileTheBroadcastRuns() async throws {
        let contacts = UdpSink()
        defer { contacts.close() }
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(configure: { config, _ in
            BroadcastIntegrationTests.enable(&config, contacts: contacts)
        }, adjust: { audio.install(into: &$0) })
        await eventually("broadcast started") { app.integrations.broadcastActive }
        await Self.expectRefused(app.model, "N1MM broadcast", audio)
    }

    @Test func startIsRefusedWhileClubLogIsConfigured() async throws {
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(configure: { config, _ in OnlineServicesTests.clubLog(&config) },
                                                adjust: { audio.install(into: &$0) })
        await Self.expectRefused(app.model, "Club Log", audio)
    }

    @Test func startIsRefusedWhileTheClusterRuns() async throws {
        let hub = InMemorySyncTransport()
        let audio = SimAudioFactory()
        let a = try await NetStation.make(id: "OP1", hub: hub, adjust: { audio.install(into: &$0) })
        try await a.activate()
        await Self.expectRefused(a.model, "cluster", audio)
    }

    /// WSJT-X Reply makes WSJT-X call a station and, with its default, transmit: refused while a simulation runs.
    @Test func theWsjtxReplyIsRefusedWhileItRuns() async throws {
        let wsjtx = UdpSink()
        defer { wsjtx.close() }
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(configure: { config, _ in ReceiveIntegrationTests.enableWsjtx(&config) },
                                                adjust: { audio.install(into: &$0) })
        await eventually("listening") { app.integrations.wsjtxPort != nil }
        let port: Int = try #require(app.integrations.wsjtxPort)
        wsjtx.send(WsjtxPackets.decode("CQ OK1ABC JO70"), toPort: port)
        await eventually("row") { app.integrations.wsjtxDecodes.rows.count == 1 }
        let row: WsjtxDecodes.Row = try #require(app.integrations.wsjtxDecodes.rows.first)
        await Self.startSimulation(app.model)
        app.integrations.reply(to: row)
        #expect(app.model.status.message == "Simulátor běží — vysílání do TRX je zamčené (nejdřív ho zastav)")
        await app.integrations.settle()
        #expect(wsjtx.bytes.isEmpty)
        app.model.simulator.stop()
        app.integrations.reply(to: row)
        await eventually("reply arrived") { !wsjtx.bytes.isEmpty }
    }

    /// BCLOG after the simulation is a plain command again.
    @Test func bclogWorksAgainAfterTheStop() async throws {
        let audio = SimAudioFactory()
        let app = try await IntegrationApp.make(adjust: { audio.install(into: &$0) })
        await Self.startSimulation(app.model)
        app.integrations.broadcastWholeLog()
        #expect(app.model.status.message == "Simulátor běží — vysílání do TRX je zamčené (nejdřív ho zastav)")
        app.model.simulator.stop()
        app.integrations.broadcastWholeLog()
        #expect(app.model.status.message == "BCLOG: UDP broadcast je vypnutý (Nastavení → Broadcast Data)")
    }

    // MARK: - the cluster

    /// The network log: the simulated QSO is stored locally and reaches the peer neither as an insert, an edit nor a
    /// delete; after the stop a real QSO does reach it (positive control through the same lane), and a later edit of
    /// the simulated one still does not.
    @Test func noSimulatedQsoReachesTheCluster() async throws {
        let hub = InMemorySyncTransport()
        let audio = SimAudioFactory()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now, adjust: { audio.install(into: &$0) })
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        await a.log("OK1PRE", zone: "15")
        await eventually("B sees PRE") { b.model.logbook.rows.map(\.call) == ["OK1PRE"] }

        await Self.startSimulation(a.model)
        await a.log("OK1SIM", zone: "15")
        #expect(a.model.logbook.rows.map(\.call) == ["OK1PRE", "OK1SIM"])
        #expect(a.model.simulator.qsos == 1)
        var simulated: Qso = try #require(a.model.logbook.rows.first { $0.call == "OK1SIM" })
        let old: Qso = simulated
        simulated.comment = "edited"
        _ = await a.model.logbook.update(LogbookMutations.Edit(old: old, new: simulated))
        await a.settle()
        // A real edit and an ingested QSO during the run reach the peer (the gate is per QSO).
        var real: Qso = try #require(a.model.logbook.rows.first { $0.call == "OK1PRE" })
        let realOld: Qso = real
        real.comment = "real edit"
        _ = await a.model.logbook.update(LogbookMutations.Edit(old: realOld, new: real))
        await eventually("B sees the real edit") { b.model.logbook.rows.first?.comment == "real edit" }
        var imported = Qso()
        imported.call = "OK1IMP"
        imported.band = .m20
        imported.mode = .cw
        let context = QsoLogPipeline.Context(activeContestId: a.model.contest.activeId, operatorCall: "OK1XOE",
                                             syncStationId: a.model.logbook.syncStationId,
                                             simulatorActive: true)
        let (prepared, effects) = QsoLogPipeline.plan(qso: imported, isImported: true, context: context)
        try await a.model.logbook.perform(prepared, effects: effects)
        await eventually("B sees the import") { b.model.logbook.rows.contains { $0.call == "OK1IMP" } }

        a.model.simulator.stop()
        await a.model.simulator.settle()
        await a.log("OK1REAL", zone: "15")
        await eventually("B sees the real QSO") { b.model.logbook.rows.contains { $0.call == "OK1REAL" } }
        // A later edit of the simulated QSO is not published; the marker QSO behind it proves the lane passed.
        _ = await a.model.logbook.update(LogbookMutations.Edit(old: simulated, new: {
            var again: Qso = simulated
            again.comment = "again"
            return again
        }()))
        await a.settle()
        await a.log("OK1MARK", zone: "15")
        await eventually("B sees the marker") { b.model.logbook.rows.count == 4 }
        #expect(Set(b.model.logbook.rows.map(\.call)) == ["OK1PRE", "OK1IMP", "OK1REAL", "OK1MARK"])
    }
}
