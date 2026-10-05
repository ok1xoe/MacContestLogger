import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The TX interlock (safety): the gate only forbids, never waits for the network and never touches the
/// release of a transmitter. Stations talk over an in-memory hub; the keying hardware is fake.
@MainActor @Suite struct TxInterlockTests {

    private static let lockout = "TX LOCKOUT: vysílá OP2 — nevysílám"

    /// OP2's status as the broker would hand it to OP1.
    private static func peer(band: String = Band.m20.adif, transmitting: Bool = true, online: Bool = true)
        -> StationStatusWire {
        StationStatusWire(stationId: "OP2", operator: "OK2", stationType: "", band: band, mode: "CW",
                          freqHz: 14_025_000, runMode: "RUN", qsoCount: 0, transmitting: transmitting,
                          online: online, timestampUtc: nil, entryCall: "")
    }

    /// OP1 active on 14.025 MHz in CW with the given interlock scope; `hub` carries OP2's statuses.
    private static func station(_ scope: Interlock.Scope, hub: InMemorySyncTransport = InMemorySyncTransport(),
                                now: TestNow = NetStation.start(), link: LinkedTransport? = nil,
                                enabled: Bool = true) async throws -> NetStation {
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now, link: link, enabled: enabled,
                                          configure: { $0.cluster.interlock = scope })
        try await a.activate()
        a.model.entry.setMode(.cw)
        a.model.entry.setFrequency("14025")
        a.model.rig.qsy(14_025_000)
        return a
    }

    private static func gate(_ a: NetStation) -> String? {
        a.model.keyer.tx.txGate()?.czech
    }

    @Test func scopesDecideWhoIsLockedOut() async throws {
        let hub = InMemorySyncTransport()
        let a = try await Self.station(.all, hub: hub)
        #expect(Self.gate(a) == nil)
        try hub.publishStatus(Self.peer())
        await eventually("peer known") { a.cluster.peers.first?.status.transmitting == true }
        #expect(Self.gate(a) == Self.lockout)

        // Another band: ALL still locks, SAME_BAND does not, the same band (any case) does.
        try hub.publishStatus(Self.peer(band: "40m"))
        await eventually("peer on 40m") { a.cluster.peers.first?.status.band == "40m" }
        #expect(Self.gate(a) == Self.lockout)
        a.model.config.config.cluster.interlock = .sameBand
        #expect(Self.gate(a) == nil)
        try hub.publishStatus(Self.peer(band: "20M"))
        await eventually("peer on 20M") { a.cluster.peers.first?.status.band == "20M" }
        #expect(Self.gate(a) == Self.lockout)

        a.model.config.config.cluster.interlock = .none
        #expect(Self.gate(a) == nil)
        a.model.config.config.cluster.interlock = .all
        try hub.publishStatus(Self.peer(transmitting: false))
        await eventually("peer quiet") { a.cluster.peers.first?.status.transmitting == false }
        #expect(Self.gate(a) == nil)
        try hub.publishStatus(Self.peer(online: false))
        await eventually("peer offline") { a.cluster.peers.first?.status.online == false }
        #expect(Self.gate(a) == nil)
    }

    @Test func aStalePeerDoesNotLockOut() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await Self.station(.all, hub: hub, now: now)
        try hub.publishStatus(Self.peer())
        await eventually("peer known") { a.cluster.peers.first?.online == true }
        #expect(Self.gate(a) == Self.lockout)
        now.advance(seconds: 100)
        #expect(Self.gate(a) == nil)
    }

    @Test func noNetworkNeverBlocks() async throws {
        let hub = InMemorySyncTransport()
        let a = try await NetStation.make(id: "OP1", hub: hub, enabled: false,
                                          configure: { $0.cluster.interlock = .all })
        try await a.app.startCqWwCw()
        #expect(Self.gate(a) == nil)
        // The session ended: from then on nothing blocks, whatever the peers said before.
        let b = try await Self.station(.all, hub: hub)
        try hub.publishStatus(Self.peer())
        await eventually("peer known") { b.cluster.peers.first?.online == true }
        #expect(Self.gate(b) == Self.lockout)
        await b.cluster.stop()
        #expect(Self.gate(b) == nil)
    }

    /// Tune, CW, the CQ repeat and the voice keyer all stop at the gate; nothing is keyed or opened.
    @Test func theLockoutStopsEveryTransmission() async throws {
        let hub = InMemorySyncTransport()
        let a = try await Self.station(.all, hub: hub)
        try hub.publishStatus(Self.peer())
        await eventually("peer known") { a.cluster.peers.first?.status.transmitting == true }

        a.model.keyer.setTune(true)
        #expect(!a.model.keyer.isTuning)
        #expect(a.status == Self.lockout)

        a.model.status.clear()
        a.model.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await a.keying.settle()
        #expect(a.status == Self.lockout)

        a.model.status.clear()
        a.model.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        #expect(!a.model.operating.cqRepeat)
        #expect(a.status == Self.lockout)

        a.model.status.clear()
        _ = a.model.keyer.voice.play([0], hisCall: "", freqHz: 14_025_000, opposite: false)
        await a.keying.settle()
        #expect(a.model.keyer.voice.playingKey == nil)
        #expect(a.status == Self.lockout)
        #expect(a.keying.keying.openedKeyers.isEmpty)

        // Released: the same actions go through.
        a.model.config.config.cluster.interlock = .none
        a.model.keyer.setTune(true)
        await a.keying.settle()
        #expect(a.model.keyer.isTuning)
        a.model.keyer.setTune(false)
        await a.keying.settle()
        #expect(!a.model.keyer.isTuning)
    }

    /// A lane stuck in the network cannot hold the announcement, the gate or the release of a carrier.
    @Test func theAnnouncementNeverDelaysTheRelease() async throws {
        let hub = InMemorySyncTransport()
        let link = LinkedTransport(hub: hub)
        let a = try await Self.station(.none, hub: hub, link: link)
        await a.settle()
        let gate = DispatchSemaphore(value: 0)
        defer { for _ in 0..<20 { gate.signal() } }
        link.statusGate = gate
        // The first status after the change blocks the lane inside the transport.
        a.model.entry.callChanged("DL1ABC")
        a.clusterClock.advance(by: 1_000)
        await eventually("lane stuck") { link.statusAttempts == 2 }

        a.model.keyer.setTune(true)
        await a.keying.settle()
        #expect(a.model.keyer.isTuning)
        a.model.keyer.tx.announceTx()
        a.clusterClock.advance(by: ClusterSyncModel.announceDelayMs)
        a.model.keyer.setTune(false)
        await a.keying.settle()
        #expect(!a.model.keyer.isTuning)
        #expect(Self.gate(a) == nil)
        #expect(link.statusPublishes.count == 1)
        for _ in 0..<20 { gate.signal() }
        await a.settle()
    }

    /// The announcement of a started transmission publishes the status ahead of the next tick, with the sending state
    /// read 50 ms after the start.
    @Test func theAnnouncementPublishesAheadOfTheLoop() async throws {
        let hub = InMemorySyncTransport()
        let a = try await Self.station(.none, hub: hub)
        await a.settle()
        let before: Int = a.transport.statusPublishes.count
        a.model.entry.callChanged("DL1ABC")
        a.cluster.announceTx()
        await a.settle()
        #expect(a.transport.statusPublishes.count == before)
        a.clusterClock.advance(by: ClusterSyncModel.announceDelayMs)
        await a.settle()
        #expect(a.transport.statusPublishes.count == before + 1)
        #expect(a.transport.statusPublishes.last?.entryCall == "DL1ABC")
    }

    /// Falsifiability of "the gate only forbids": a carrier started before the lockout is released while the
    /// lockout is active, by the tune toggle and by Esc (`stopSending`). A gate on the release turns this red.
    @Test func releaseWorksWhileTheLockoutIsActive() async throws {
        let hub = InMemorySyncTransport()
        let a = try await Self.station(.all, hub: hub)
        a.model.keyer.setTune(true)
        await a.keying.settle()
        #expect(a.model.keyer.isTuning)
        try hub.publishStatus(Self.peer())
        await eventually("peer transmits") { a.cluster.peers.first?.status.transmitting == true }
        #expect(Self.gate(a) == Self.lockout)

        a.model.keyer.setTune(false)
        await a.keying.settle()
        #expect(!a.model.keyer.isTuning)

        // The same through Esc, and a refused tune does not start again.
        a.model.config.config.cluster.interlock = .none
        a.model.keyer.setTune(true)
        await a.keying.settle()
        #expect(a.model.keyer.isTuning)
        a.model.config.config.cluster.interlock = .all
        #expect(Self.gate(a) == Self.lockout)
        #expect(a.model.keyer.stopSending())
        await a.keying.settle()
        #expect(!a.model.keyer.isTuning)
        a.model.keyer.setTune(true)
        #expect(!a.model.keyer.isTuning)
    }

    /// A CW message and a voice message started before the lockout are stopped by Esc while the lockout is active: the
    /// gate guards starting, never stopping.
    @Test func escStopsCwAndVoiceWhileTheLockoutIsActive() async throws {
        let hub = InMemorySyncTransport()
        let a = try await Self.station(.none, hub: hub)
        a.model.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await a.keying.settle()
        #expect(a.model.keyer.cwSendingKey != nil)
        a.model.config.config.cluster.interlock = .all
        try hub.publishStatus(Self.peer())
        await eventually("peer transmits") { a.cluster.peers.first?.status.transmitting == true }
        #expect(Self.gate(a) == Self.lockout)

        let aborts: Int = (a.keying.keying.lastKeyer?.events ?? []).filter { $0 == "abort" }.count
        #expect(a.model.keyer.stopSending())
        await a.keying.settle()
        #expect(a.model.keyer.cwSendingKey == nil)
        #expect((a.keying.keying.lastKeyer?.events ?? []).filter { $0 == "abort" }.count == aborts + 1)

        // Voice: started while nothing blocks, stopped under the lockout.
        a.model.config.config.cluster.interlock = .none
        _ = a.model.keyer.voice.play([0], hisCall: "", freqHz: 14_025_000, opposite: false)
        #expect(a.model.keyer.voice.isActive)
        a.model.config.config.cluster.interlock = .all
        try hub.publishStatus(Self.peer())
        #expect(Self.gate(a) == Self.lockout)
        #expect(a.model.keyer.voice.stop())
        await a.keying.settle()
        #expect(!a.model.keyer.voice.isActive)
        #expect(a.model.keyer.voice.playingKey == nil)
    }

    /// The fldigi path stops at the gate too: nothing is sent, the lamp stays off.
    @Test func theDigitalPathIsGated() async throws {
        let hub = InMemorySyncTransport()
        let a = try await Self.station(.all, hub: hub)
        a.model.config.config.digital.engine = .fldigi
        try hub.publishStatus(Self.peer())
        await eventually("peer transmits") { a.cluster.peers.first?.status.transmitting == true }
        a.model.status.clear()
        a.model.keyer.digital.send("CQ TEST")
        await a.keying.settle()
        #expect(a.status == Self.lockout)
        #expect(!a.model.keyer.digitalSending)
        #expect(a.model.keyer.sendFailures == 1)
    }
}
