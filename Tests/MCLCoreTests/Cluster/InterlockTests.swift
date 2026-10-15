import Testing
@testable import MCLCore

/// Port `InterlockTest.java` (3 testy).
@Suite struct InterlockTests {

    private static func peer(_ id: String, _ band: String, _ tx: Bool, _ online: Bool) -> StationNetwork.Peer {
        let s = StationStatusWire(stationId: id, operator: "", stationType: "", band: band, mode: "CW", freqHz: 0,
                                  runMode: "RUN", qsoCount: 0, transmitting: tx, online: true, timestampUtc: nil,
                                  entryCall: "")
        return StationNetwork.Peer(status: s, receivedAt: JavaInstant.now(), online: online, age: .zero)
    }

    @Test func allScopeBlocksOnAnyTransmittingStation() {
        let peers = [Self.peer("STN2", "40m", true, true), Self.peer("STN3", "20m", false, true)]
        #expect(Interlock.lockedBy(peers, .all, "20m") == "STN2")
    }

    @Test func sameBandScopeBlocksOnlyOnMyBand() {
        let peers = [Self.peer("STN2", "40m", true, true)]
        #expect(Interlock.lockedBy(peers, .sameBand, "20m") == nil)
        #expect(Interlock.lockedBy(peers, .sameBand, "40M") == "STN2")
    }

    @Test func offlineOrDisabledNeverBlocks() {
        let peers = [Self.peer("STN2", "40m", true, false)]
        #expect(Interlock.lockedBy(peers, .all, "40m") == nil)
        #expect(Interlock.lockedBy([Self.peer("STN2", "40m", true, true)], Interlock.Scope.none, "40m") == nil)
    }

    /// Last one wins: only a station that started since the previous overview counts.
    @Test func newlyTransmittingSeesOnlyStarts() {
        let quiet = [Self.peer("STN2", "40m", false, true), Self.peer("STN3", "20m", true, true)]
        let started = [Self.peer("STN2", "40m", true, true), Self.peer("STN3", "20m", true, true)]
        #expect(Interlock.newlyTransmitting(old: quiet, new: started, .all, "20m") == "STN2")
        #expect(Interlock.newlyTransmitting(old: quiet, new: started, .sameBand, "20m") == nil)
        #expect(Interlock.newlyTransmitting(old: started, new: started, .all, "20m") == nil)
        #expect(Interlock.newlyTransmitting(old: [], new: started, .none, "20m") == nil)
    }
}
