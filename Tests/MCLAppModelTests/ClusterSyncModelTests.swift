import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// A flag a task sets when it ends (the quit tests wait for it without blocking).
@MainActor
final class Done {
    var value = false
}

/// The cluster sync model over in-memory transports: the start and its silent conditions, the local-first
/// replication of two stations over a shared hub, the tombstones, the database switch, the state loop, the quit.
/// Never a socket: the factory of the sync transport hands out a `LinkedTransport`.
@MainActor @Suite struct ClusterSyncModelTests {

    // MARK: - start

    @Test func startsAfterTheActivationAndSaysSoBefore() async throws {
        let hub = InMemorySyncTransport()
        let a = try await NetStation.make(id: "OP1", hub: hub)
        a.cluster.start()
        #expect(a.status == "Cluster se připojí po aktivaci závodu.")
        #expect(a.made.count == 0)
        #expect(!a.cluster.isRunning)

        try await a.activate()
        #expect(a.made.count == 1)
        #expect(a.made.all.first?.brokerHost == "broker.invalid")
        #expect(a.cluster.stationId == "OP1")
        // Kotlin shows „Spuštěn závod" after the activation; the connect message is the one of a start now.
        a.cluster.stopNow()
        a.cluster.start()
        await eventually("connect message") { a.status == "Připojeno ke clusteru broker.invalid:1883 jako OP1" }
        #expect(a.made.count == 2)

        // The activation starts the cluster only when no session runs (`.startClusterIfIdle`).
        try await a.app.startCqWwCw()
        await a.settle()
        #expect(a.made.count == 2)
    }

    @Test func staysSilentWithoutTheSettingTheBrokerOrTheStationId() async throws {
        let hub = InMemorySyncTransport()
        let disabled = try await NetStation.make(id: "OP1", hub: hub, enabled: false)
        let noBroker = try await NetStation.make(id: "OP2", hub: hub, configure: { $0.cluster.brokerHost = "  " })
        let noId = try await NetStation.make(id: " ", hub: hub)
        for station in [disabled, noBroker, noId] {
            try await station.app.startCqWwCw()
            let before: String = station.status
            station.cluster.start()
            await station.settle()
            #expect(station.made.count == 0)
            #expect(!station.cluster.isRunning)
            #expect(station.status == before)
        }
    }

    @Test func aFailedConnectContinuesLocally() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        link.connectError = SyncTransportError("Nelze se připojit k MQTT brokeru tcp://broker.invalid:1883")
        let a = try await NetStation.make(id: "OP1", hub: hub, link: link, enabled: false)
        try await a.app.startCqWwCw()
        a.cluster.networkOn()
        await eventually("failure shown") { a.status.hasPrefix("Cluster: připojení selhalo") }
        #expect(a.status == "Cluster: připojení selhalo (Nelze se připojit k MQTT brokeru tcp://broker.invalid:1883) "
                + "— pokračuji lokálně")
        #expect(!a.cluster.isRunning)
        #expect(!a.cluster.connected)
        // The station logs and counts as ever; its QSOs carry no origin and nothing is published.
        await a.log("DL1ABC")
        let row: Qso = try #require(a.model.logbook.rows.first)
        #expect(row.stationId == "")
        #expect(a.model.logbook.qsoCount == 1)
    }

    /// The default environment never reaches the network: the inert start returns before the session directory and
    /// shows no status text (the line goes to the log only).
    @Test func theInertPortsNeverConnect() async throws {
        let app = try await TestApp.make(configure: { config, _ in
            config.cluster.brokerHost = "broker.invalid"
            config.cluster.stationId = "OP1"
        })
        try await app.startCqWwCw()
        let before: String = app.model.status.message
        app.model.cluster.networkOn()
        await app.model.cluster.settle()
        #expect(app.model.status.message == before)
        #expect(!app.model.status.message.hasPrefix("Cluster: připojení selhalo"))
        #expect(!app.model.cluster.isRunning)
        let mqtt: URL = app.dataDir.appendingPathComponent("mqtt", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: mqtt.path))
    }

    /// `connected` is the one snapshot of the transport after the start.
    @Test func connectedIsASnapshotOfTheStart() async throws {
        let hub = InMemorySyncTransport()
        let a = try await NetStation.make(id: "OP1", hub: hub)
        #expect(!a.cluster.connected)
        try await a.activate()
        #expect(a.cluster.connected)
        a.transport.dropConnection()
        a.clusterClock.advance(by: 1_000)
        await a.settle()
        #expect(a.cluster.connected)
    }

    // MARK: - replication

    @Test func twoStationsReplicateEditsAndDeletesAsTombstones() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()

        await a.log("DL1ABC")
        await eventually("B sees the QSO") { b.model.logbook.rows.map(\.call) == ["DL1ABC"] }
        let seen: Qso = try #require(b.model.logbook.rows.first)
        #expect(seen.stationId == "OP1")
        #expect(b.model.logbook.isDupe(call: "DL1ABC", band: .m20))
        #expect(a.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(a.model.logbook.rows.first?.stationId == "OP1")

        // An edit on A reaches B.
        var edited: Qso = try #require(a.model.logbook.rows.first)
        let old: Qso = edited
        edited.comment = "tnx"
        _ = await a.model.logbook.update(LogbookMutations.Edit(old: old, new: edited))
        await eventually("B sees the edit") { b.model.logbook.rows.first?.comment == "tnx" }

        // A delete on A is a tombstone, and it removes the QSO — and its dupe — on B.
        await a.model.logbook.delete(a.model.logbook.rows)
        await eventually("B lost the QSO") { b.model.logbook.rows.isEmpty }
        #expect(!b.model.logbook.isDupe(call: "DL1ABC", band: .m20))
        #expect(!a.model.logbook.isDupe(call: "DL1ABC", band: .m20))
        let stored: [Qso] = try await a.model.database.handle.run { try $0.service.findAllIncludingDeleted() }
        #expect(stored.count == 1)
        #expect(stored.first?.deleted == true)
        #expect(a.model.logbook.qsoCount == 0)
    }

    /// Free logging never reaches the cluster (the wire has no contest; B would file it under its own), and a
    /// state arriving meanwhile is filed under the last contest, never in the free-logging log.
    @Test func freeLoggingStaysOffTheCluster() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        let contestId: String = try #require(a.model.contest.activeId)

        a.model.contest.deactivate()
        await a.model.contest.settleActivations()
        let entry: EntryModel = a.model.entry
        entry.setFrequency("7010")
        entry.callChanged("W1AW")
        entry.submit()
        await entry.settle()
        var edited: Qso = try #require(a.model.logbook.rows.first)
        let old: Qso = edited
        edited.comment = "tnx"
        _ = await a.model.logbook.update(LogbookMutations.Edit(old: old, new: edited))
        await a.settle()
        #expect(a.model.logbook.rows.map(\.call) == ["W1AW"])

        // B's contest QSO reaches A (a barrier: anything A had published is on the hub before it).
        await b.log("DL1ABC")
        await a.settle()
        await b.settle()
        #expect(b.model.logbook.rows.map(\.call) == ["DL1ABC"])
        let stored: [Qso] = try await a.model.database.handle.run { try $0.service.findAllIncludingDeleted() }
        #expect(stored.first { $0.call == "DL1ABC" }?.contestId == contestId)
        await a.settle()
        #expect(a.model.logbook.rows.map(\.call) == ["W1AW"])

        await a.model.logbook.delete(a.model.logbook.rows)
        await a.settle()
        await b.settle()
        #expect(b.model.logbook.rows.map(\.call) == ["DL1ABC"])
    }

    @Test func aDeleteWithoutTheClusterIsHard() async throws {
        let hub = InMemorySyncTransport()
        let a = try await NetStation.make(id: "OP1", hub: hub, enabled: false)
        try await a.app.startCqWwCw()
        await a.log("DL1ABC")
        await a.model.logbook.delete(a.model.logbook.rows)
        let stored: [Qso] = try await a.model.database.handle.run { try $0.service.findAllIncludingDeleted() }
        #expect(stored.isEmpty)
    }

    /// The retained states a station finds on connecting are its bootstrap: one re-read after the burst, not one per
    /// state, and the log shows them all.
    @Test func aLateStationBootstrapsFromTheRetainedStates() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        try await a.activate()
        for call in ["DL1ABC", "OK2XYZ", "SP5AAA"] {
            await a.log(call, zone: "15")
        }
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await b.activate()
        await eventually("B bootstrapped") { b.model.logbook.rows.count == 3 }
        #expect(Set(b.model.logbook.rows.map(\.call)) == ["DL1ABC", "OK2XYZ", "SP5AAA"])
        #expect(b.model.logbook.qsoCount == 3)
    }

    // MARK: - the database switch

    @Test func switchingTheDatabaseStopsTheClusterAndTheNextActivationStartsIt() async throws {
        let hub = InMemorySyncTransport()
        let a = try await NetStation.make(id: "OP1", hub: hub)
        try await a.activate()
        await a.model.database.create("second")
        #expect(!a.cluster.isRunning)
        #expect(a.transport.isClosed)
        #expect(a.made.count == 1)

        try await a.app.startCqWwCw()
        await eventually("restarted") { a.cluster.isRunning && a.cluster.connected }
        #expect(a.made.count == 2)
    }

    /// The switch waits (bounded) for a re-read of the old database in flight; nothing of the old log is
    /// taken after the swap.
    @Test func theSwitchWaitsForARereadOfTheOldDatabase() async throws {
        let hub = InMemorySyncTransport()
        let a = try await NetStation.make(id: "OP1", hub: hub)
        try await a.activate()
        let gate = OneShot()
        a.cluster.reload = { await gate.wait() }
        a.cluster.remoteChanged(a.cluster.generation)
        #expect(a.cluster.refreshTask != nil)
        let done = Done()
        let switching = Task { @MainActor in
            await a.model.database.create("second")
            done.value = true
        }
        await eventually("cluster stopped") { a.transport.isClosed }
        for _ in 0..<50 {
            await runMainQueue()
        }
        #expect(!done.value, "the switch must wait for the re-read in flight")
        gate.fire()
        await switching.value
        #expect(done.value)
        #expect(a.cluster.refreshTask == nil)
    }

    /// A re-read that never ends cannot hold the switch beyond the close bound (injected clock).
    @Test func aStuckRereadDoesNotHoldTheSwitchBeyondTheBound() async throws {
        let hub = InMemorySyncTransport()
        let a = try await NetStation.make(id: "OP1", hub: hub)
        try await a.activate()
        let gate = OneShot()
        a.cluster.reload = { await gate.wait() }
        a.cluster.remoteChanged(a.cluster.generation)
        let done = Done()
        let switching = Task { @MainActor in
            await a.model.database.create("second")
            done.value = true
        }
        await eventually("cluster stopped") { a.transport.isClosed }
        for _ in 0..<50 {
            await runMainQueue()
        }
        #expect(!done.value)
        a.clusterClock.advance(by: ClusterSyncModel.closeBoundMs)
        await switching.value
        #expect(done.value)
        gate.fire()
        await a.cluster.settle()
    }

    // MARK: - the state loop

    @Test func theStatusIsPublishedOnChangeAndAsAHeartbeat() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        await a.settle()
        #expect(a.transport.statusPublishes.count == 1)
        #expect(a.transport.statusPublishes.first?.stationId == "OP1")
        #expect(a.transport.statusPublishes.first?.online == true)
        await eventually("B sees A") { b.cluster.peers.map { $0.status.stationId } == ["OP1"] }

        // Nothing changed: the loop ticks, the core publishes nothing (until the 30 s heartbeat).
        for _ in 0..<5 {
            a.clusterClock.advance(by: 1_000)
            await a.settle()
        }
        #expect(a.transport.statusPublishes.count == 1)
        #expect(a.cluster.revision > 5)

        // A change goes out on the next tick.
        a.model.entry.callChanged("dl1")
        a.clusterClock.advance(by: 1_000)
        await a.settle()
        #expect(a.transport.statusPublishes.count == 2)
        #expect(a.transport.statusPublishes.last?.entryCall == "DL1")
        #expect(a.transport.statusPublishes.last?.runMode == "S&P")

        // The heartbeat.
        now.advance(seconds: 31)
        a.clusterClock.advance(by: 1_000)
        await a.settle()
        #expect(a.transport.statusPublishes.count == 3)
    }

    @Test func statusBurstsAreCoalescedBehindABusyLane() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        let a = try await NetStation.make(id: "OP1", hub: hub, link: link)
        try await a.activate()
        await a.settle()
        let gate = DispatchSemaphore(value: 0)
        defer { for _ in 0..<20 { gate.signal() } }
        link.statusGate = gate
        // The first change blocks the lane inside `publishStatus`; the next ones only replace the waiting status.
        a.model.entry.callChanged("A1")
        a.clusterClock.advance(by: 1_000)
        await eventually("lane busy") { link.statusAttempts == 2 }
        for call in ["B2", "C3", "D4"] {
            a.model.entry.callChanged(call)
            a.clusterClock.advance(by: 1_000)
        }
        for _ in 0..<20 { gate.signal() }
        await a.settle()
        let published: [String?] = link.statusPublishes.map(\.entryCall)
        #expect(published.contains("A1"))
        #expect(published.last == "D4")
        #expect(published.count <= 3)
    }

    // MARK: - the quit

    @Test func quitClosesTheClusterBeforeTheIntegrationsAndTheDatabase() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        await eventually("B sees A online") { b.cluster.peers.first?.online == true }

        let model: AppModel = a.model
        let link: LinkedTransport = a.transport
        var order: [String] = []
        let cluster = model.shutdownServices.cluster
        model.shutdownServices.cluster = {
            order.append("cluster")
            await cluster()
            order.append("cluster done, transport closed: \(link.isClosed)")
        }
        let integrations = model.shutdownServices.integrations
        model.shutdownServices.integrations = {
            order.append("integrations, database closed: \(model.database.handle.isClosed)")
            await integrations()
        }
        await model.shutdown()
        #expect(order == ["cluster", "cluster done, transport closed: true",
                          "integrations, database closed: false"])
        #expect(model.database.handle.isClosed)
        // The station said goodbye: the others see it offline.
        await eventually("B sees A offline") { b.cluster.peers.first?.status.online == false }
        // Nothing starts afterwards.
        a.cluster.start()
        #expect(!a.cluster.isRunning)
    }

    /// A broker that does not answer the DISCONNECT: the quit waits `closeBoundMs` on the injected clock and goes on.
    @Test func quitWithAHangingBrokerEndsWithinTheBound() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        link.closeGate = gate
        let a = try await NetStation.make(id: "OP1", hub: hub, link: link)
        try await a.activate()

        let done = Done()
        let cluster: ClusterSyncModel = a.cluster
        let quit = Task { @MainActor in
            await cluster.shutdown()
            done.value = true
        }
        await eventually("close started") { link.closings == 1 }
        #expect(!a.cluster.isRunning)
        a.clusterClock.advance(by: ClusterSyncModel.closeBoundMs - 1)
        await runMainQueue()
        #expect(!done.value)
        a.clusterClock.advance(by: 1)
        await quit.value
        #expect(done.value)
        // The lane is still stuck in the close; releasing it lets the model finish cleanly.
        gate.signal()
        await a.cluster.settle()
        #expect(link.isClosed)
    }

    /// A message that arrives after the stop (the transport thread was already inside the callback) is dropped.
    @Test func aMessageAfterTheStopIsDropped() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        link.closeGate = gate
        let a = try await NetStation.make(id: "OP1", hub: hub, link: link)
        try await a.activate()
        func chat(_ text: String) -> NetMessageWire {
            NetMessageWire(type: NetMessageWire.chat, id: text, fromStation: "OP2", fromOperator: nil,
                           toStation: "", text: text, call: "", freqHz: 0, mode: "", timestampUtc: nil)
        }
        try link.deliver(chat("early"))
        await eventually("early taken") { a.network.chat.lines.count == 1 }

        a.cluster.stopNow()
        await eventually("lane in the close") { link.closings == 1 }
        try link.deliver(chat("late"))
        await runMainQueue()
        await runMainQueue()
        #expect(a.network.chat.lines.map(\.text) == ["early"])
        gate.signal()
        await a.cluster.settle()
    }

    /// The stop releases the transport's listeners, which are the cycle coordinator ↔ transport.
    @Test func stopReleasesTheSession() async throws {
        let plain = InMemorySyncTransport()
        let clock = ManualClock()
        let app = try await TestApp.make(configure: { config, _ in
            config.cluster.enabled = true
            config.cluster.brokerHost = "broker.invalid"
            config.cluster.stationId = "OP1"
        }, adjust: { environment in
            var ports: NetworkPorts = NetworkPorts.inert
            ports.makeSyncTransport = { _, _ in plain }
            ports.isInert = false
            environment.network = ports
            environment.clusterClock = clock
        })
        try await app.startCqWwCw()
        await eventually("connected") { app.model.cluster.isRunning && app.model.cluster.connected }
        let network = WeakRef(app.model.cluster.stationNetwork)
        #expect(network.value != nil)
        await app.model.cluster.stop()
        // The clock still holds the cancelled loop timer (and the session it captured) until it passes its time.
        clock.advance(by: 5_000)
        await app.model.cluster.settle()
        #expect(network.value == nil)
    }
}

/// A weak reference held in a `let` (a `weak var` that is never mutated draws a warning).
private final class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}
