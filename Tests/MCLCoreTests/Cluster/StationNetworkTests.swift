import Testing
@testable import MCLCore

/// Port of `StationNetworkTest.java` (2 tests) with an advanceable clock (`MutableClock` → `FakeInstantClock`).
@Suite struct StationNetworkTests {

    private static func status(_ band: String, _ qsos: Int32) -> StationStatusWire {
        StationStatusWire(stationId: "x", operator: "OK1XOE", stationType: "RUN", band: band, mode: "CW",
                          freqHz: 14_025_000, runMode: "RUN", qsoCount: qsos, transmitting: false, online: true,
                          timestampUtc: nil, entryCall: "")
    }

    private static func start() -> JavaInstant {
        JavaInstant.parseIsoInstant("2026-11-28T12:00:00Z")!
    }

    @Test func stationsSeeEachOtherAndHeartbeatDedups() throws {
        let t = InMemorySyncTransport()
        let clock = FakeInstantClock(Self.start())
        let a = StationNetwork(transport: t, stationId: "STN1", clock: { clock.now })
        let b = StationNetwork(transport: t, stationId: "STN2", clock: { clock.now })
        let changes = Counter()
        try a.start { changes.increment() }
        try b.start(nil)

        #expect(try b.publish(Self.status("20m", 5)))
        #expect(try !b.publish(Self.status("20m", 5)), "nothing is published without a change and before the heartbeat")
        #expect(try b.publish(Self.status("20m", 6)), "a change is published immediately")

        #expect(a.peers().count == 1)
        let p: StationNetwork.Peer = a.peers()[0]
        #expect(p.status.stationId == "STN2")
        #expect(p.status.qsoCount == 6)
        #expect(p.online)
        #expect(changes.value == 2)
        #expect(b.peers().isEmpty, "the own state does not count among the peers")

        clock.advance(seconds: 31)
        #expect(try b.publish(Self.status("20m", 6)), "heartbeat")
        clock.advance(seconds: 120)
        #expect(!a.peers()[0].online, "without a heartbeat the station is inactive")
    }

    @Test func offlineStatusMarksPeerOffline() throws {
        let t = InMemorySyncTransport()
        let clock = FakeInstantClock(Self.start())
        let a = StationNetwork(transport: t, stationId: "STN1", clock: { clock.now })
        let b = StationNetwork(transport: t, stationId: "STN2", clock: { clock.now })
        try a.start(nil)
        try b.start(nil)
        try b.publish(Self.status("40m", 1))
        try b.goOffline()
        #expect(!a.peers()[0].online)
    }
}
