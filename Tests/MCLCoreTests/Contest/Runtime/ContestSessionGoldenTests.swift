import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `ContestSessionGoldenTest` (2): the engine computes consistently by the rules
/// in YAML (the numbers are hand-computed from the rules, not official results). DXCC fixture =
/// CZ/US/CA/DE; it has the station OK1XOE (CZ, EU).
@Suite struct ContestSessionGoldenTests {

    @Test func cqWwScoring() throws {
        let s = try SessionFixture.session("@cq-ww-cw.yaml")
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("zone", "14")))  // EU same-continent = 1
        _ = try s.log(call: "W1AW", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("zone", "5")))     // NA other-continent = 3
        _ = try s.log(call: "DL2XYZ", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("zone", "14"))) // EU = 1, zone 14 already worked

        let sc = try s.score()
        #expect(sc.qsoCount == 3)
        #expect(sc.qsoPoints == 5)    // 1 + 3 + 1
        #expect(sc.multTotal == 4)    // zones {14,5}=2 + countries {DE,US}=2
        #expect(sc.total == 20)       // 5 * 4
    }

    @Test func wpxScoring() throws {
        let s = try SessionFixture.session("@cq-wpx-cw.yaml")
        _ = try s.log(call: "W1AW", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("nr", "1")))   // other-continent, 20m = 3
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("nr", "2"))) // same-continent = 1
        _ = try s.log(call: "W1AW", band: "40m", mode: "CW", receivedRaw: SessionFixture.raw(("nr", "3")))   // other-continent, 40m = 6; prefix W1 already worked

        let sc = try s.score()
        #expect(sc.qsoCount == 3)
        #expect(sc.qsoPoints == 10)   // 3 + 1 + 6
        #expect(sc.multTotal == 2)    // prefixy {W1, DL1} (scope ONCE)
        #expect(sc.total == 20)       // 10 * 2
    }
}
