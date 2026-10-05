import Testing
@testable import MCLCore

/// Port of `dxcluster/ParallelClusterPlanTest` (2).
@Suite struct ParallelClusterPlanTests {

    private static func fav(_ name: String, _ host: String, _ port: Int, _ parallel: Bool) -> DxClusterFavorite {
        var f = DxClusterFavorite(name: name, host: host, port: port, login: "OK1XOE", password: "")
        f.parallel = parallel
        return f
    }

    @Test func connectsWantedAndDropsRemoved() {
        let rbn = Self.fav("RBN", "telnet.reversebeacon.net", 7000, true)
        let node = Self.fav("Node", "dx.ok0dx.cz", 7300, true)
        let plain = Self.fav("Plain", "other", 7300, false)

        let p = ParallelClusterPlan.plan([rbn, node, plain], open: ["dx.ok0dx.cz:7300", "old.node:7300"], primary: nil)

        #expect(p.toConnect == [rbn])
        #expect(p.toDisconnect == ["old.node:7300"])
    }

    @Test func primaryIsNotDuplicated() {
        let rbn = Self.fav("RBN", "telnet.reversebeacon.net", 7000, true)
        let p = ParallelClusterPlan.plan([rbn], open: ["telnet.reversebeacon.net:7000"],
                                         primary: "telnet.reversebeacon.net:7000")
        #expect(p.toConnect.isEmpty)
        #expect(p.toDisconnect == ["telnet.reversebeacon.net:7000"])
    }
}
