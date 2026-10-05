import Testing
@testable import MCLCore

/// Port of `SharedSpotsTest.java` (2 tests): telnet sharing via `SyncCoordinator.shareSpots`/`publishSpot`.
@Suite struct SharedSpotsTests {

    @Test func spotGoesToOtherStationsOnly() throws {
        let repo = try LogbookRepository.inMemory()
        defer { repo.close() }
        let logbook = LogbookService(repository: repo)
        let broker = InMemorySyncTransport()
        let run = SyncCoordinator(logbook: logbook, transport: broker, stationId: "RUN1", onChange: nil)
        let mult = SyncCoordinator(logbook: logbook, transport: broker, stationId: "MULT1", onChange: nil)
        try run.start()
        let atRun = Collected<SpotWire>()
        let atMult = Collected<SpotWire>()
        run.shareSpots { atRun.add($0) }
        mult.shareSpots { atMult.add($0) }

        try run.publishSpot(spotter: "DK9IP-#", freqHz: 14_025_000, dxCall: "OK1XOE", comment: "19 dB 28 WPM CQ")

        #expect(atMult.values == [SpotWire(stationId: "RUN1", spotter: "DK9IP-#", freqHz: 14_025_000, dxCall: "OK1XOE",
                                           comment: "19 dB 28 WPM CQ")])
        #expect(atRun.values.isEmpty, "own spot does not come back")
    }

    @Test func wireRoundTrip() throws {
        let s = SpotWire(stationId: "RUN1", spotter: "W3LPL", freqHz: 7_010_000, dxCall: "DL1ABC", comment: "loud")
        #expect(try WireJson.fromBytes(WireJson.toBytes(s), as: SpotWire.self) == s)
    }
}
