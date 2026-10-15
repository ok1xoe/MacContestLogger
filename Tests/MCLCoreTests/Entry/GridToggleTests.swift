@testable import MCLCore
import Testing

/// N1MM's grid square keys (VHF and up): Alt+- toggles the grid field through the call history's grids and the
/// typed one; a right-click on a band button in a network finds the station working that band.
@Suite struct GridToggleTests {

    private func record(_ pairs: [(String, String)]) -> JavaLinkedMap<String> {
        var map = JavaLinkedMap<String>()
        for (key, value) in pairs {
            map.put(key, value)
        }
        return map
    }

    @Test func historyGridsAreValidUpperCaseAndAtMostTwo() {
        let grids = GridToggle.historyGrids(record([("name", "Pavel"), ("loc1", " jn79fx "), ("loc2", "JN79"),
                                                    ("grid", "JO70")]))
        #expect(grids == ["JN79FX", "JN79"])
        #expect(GridToggle.historyGrids(record([("loc1", "15"), ("loc2", "JN79FX"), ("grid", "jn79fx")])) == ["JN79FX"])
        #expect(GridToggle.historyGrids(nil).isEmpty)
        #expect(GridToggle.historyGrids(record([("loc1", "XX99")])).isEmpty)
    }

    @Test func candidatesPutTheTypedGridFirst() {
        #expect(GridToggle.candidates(entered: "jo70", history: ["JN79FX", "JN79"]) == ["JO70", "JN79FX", "JN79"])
        #expect(GridToggle.candidates(entered: "JN79", history: ["JN79FX", "JN79"]) == ["JN79FX", "JN79"])
        #expect(GridToggle.candidates(entered: nil, history: ["JN79FX"]) == ["JN79FX"])
        #expect(GridToggle.candidates(entered: "  ", history: ["JN79FX"]) == ["JN79FX"])
    }

    @Test func nextCyclesAndStartsAtTheCallHistory() {
        let history = ["JN79FX", "JN79"]
        let all = GridToggle.candidates(entered: "JO70", history: history)
        #expect(GridToggle.next(current: "", candidates: all, history: history) == "JN79FX")
        #expect(GridToggle.next(current: "JO70", candidates: all, history: history) == "JN79FX")
        #expect(GridToggle.next(current: "jn79fx", candidates: all, history: history) == "JN79")
        #expect(GridToggle.next(current: "JN79", candidates: all, history: history) == "JO70")
        #expect(GridToggle.next(current: "KN08", candidates: all, history: history) == "JN79FX")
        #expect(GridToggle.next(current: "JO70", candidates: ["JO70"], history: []) == nil)
    }

    @Test func thePeerOnABandIsFoundByPassFrequencyThenByItsOwn() {
        let peers = NetworkSendTests.peers(op2: true, op3: true, op4: true, op5: true)
        #expect(NetMessages.peerOnBand(.m20, peers: peers) == "OP2")
        #expect(NetMessages.peerOnBand(.m15, peers: peers) == "OP3")
        // OP4 is offline, OP5 stale: not online.
        #expect(NetMessages.peerOnBand(.m80, peers: peers) == nil)
        #expect(NetMessages.peerOnBand(.m40, peers: peers) == nil)
        // OP3 announced a pass frequency on 20 m: it is the 20 m station for a pass.
        #expect(NetMessages.peerOnBand(.m20, peers: peers, passFrequencies: ["OP3": 14_040_000]) == "OP3")
        #expect(NetMessages.peerOnBand(.m2, peers: peers) == nil)
    }
}
