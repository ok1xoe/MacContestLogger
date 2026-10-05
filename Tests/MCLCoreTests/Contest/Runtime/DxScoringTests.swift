import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `DxScoringTest` (3). DX (free logging): the exchange is just the report, no
/// multipliers, 1 point per QSO. Guards the formula `total: "qsoPoints"` and `dupeWorthZero: false`
/// with scope `PER_BAND_MODE` (a dupe is reported but the QSO is counted).
@Suite struct DxScoringTests {

    private func session() throws -> ContestSession {
        try SessionFixture.session("@dx.yaml")
    }

    @Test func everyQsoIsWorthOnePointAndScoreIsQsoCount() throws {
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599")))
        _ = try s.log(call: "W1AW", band: "40m", mode: "SSB", receivedRaw: SessionFixture.raw(("rst", "59")))
        _ = try s.log(call: "OK2XYZ", band: "17m", mode: "RTTY", receivedRaw: SessionFixture.raw(("rst", "599")))

        let sc = try s.score()
        #expect(sc.qsoCount == 3)
        #expect(sc.qsoPoints == 3)
        #expect(sc.multTotal == 0, "the contest has no multipliers")
        #expect(sc.total == 3, "total = qsoPoints, ne qsoPoints * multTotal")
    }

    @Test func dupeIsReportedButStillCounts() throws {
        let s = try session()
        #expect(try !s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"))).dupe)
        #expect(try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"))).dupe)

        let sc = try s.score()
        #expect(sc.qsoCount == 2)
        #expect(sc.qsoPoints == 2, "dupeWorthZero: false → even a dupe has its point")
        #expect(sc.total == 2)
    }

    @Test func sameCallOnOtherModeOfSameBandIsNotDupe() throws {
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599")))
        #expect(try !s.log(call: "DL1ABC", band: "20m", mode: "SSB", receivedRaw: SessionFixture.raw(("rst", "59"))).dupe,
                "scope PER_BAND_MODE")
        #expect(try s.log(call: "DL1ABC", band: "20m", mode: "SSB", receivedRaw: SessionFixture.raw(("rst", "59"))).dupe)
    }
}
