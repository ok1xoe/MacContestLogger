import Foundation
import Testing
@testable import MCLCore

/// Editing the band plan from the band map (`BandPlanEdit`), the US licence class lines and the band map's bulk spot
/// removal (`SpotBuffer.removeAll(where:)`).
@Suite struct BandPlanEditTests {

    private static func seg(_ region: String, _ mode: String, _ from: Double, _ to: Double) -> BandPlanFile.Segment {
        BandPlanFile.Segment(region: region, mode: mode, fromKhz: from, toKhz: to)
    }

    private static let twenty: [BandPlanFile.Segment] = [
        seg("R1", "CW", 14_000, 14_070), seg("R1", "DIGI", 14_070, 14_099), seg("R1", "PHONE", 14_101, 14_350),
        seg("R2", "CW", 14_000, 14_150),
    ]

    @Test func anEmptyFileStartsFromTheBuiltInPlan() {
        let rows: [BandPlanFile.Segment] = BandPlanEdit.seeded([], region: "R1")
        #expect(rows.count == BandPlan.defaultRows.count * 3)
        #expect(rows.allSatisfy { $0.region == "R1" })
        #expect(rows.contains(Self.seg("R1", "DIGI", 7_040, 7_050)))
        // Another region gets a copy of R1, which `BandPlan.fromDir` showed for it before.
        let r3: [BandPlanFile.Segment] = BandPlanEdit.seeded([], region: "R3")
        #expect(r3.filter { $0.region == "R3" }.count == BandPlan.defaultRows.count * 3)
        // A region with rows of its own is left as it is.
        #expect(BandPlanEdit.seeded(Self.twenty, region: "R2") == Self.twenty)
    }

    @Test func aNewEdgeShortensTheNeighbourAndTouchesIt() {
        let outcome = BandPlanEdit.apply(.setLow(mode: "DIGI"), atKhz: 14_060, band: .m20, region: "R1",
                                         segments: Self.twenty)
        #expect(outcome == .edited([
            Self.seg("R1", "CW", 14_000, 14_060), Self.seg("R1", "DIGI", 14_060, 14_099),
            Self.seg("R1", "PHONE", 14_101, 14_350), Self.seg("R2", "CW", 14_000, 14_150),
        ]))
        let up = BandPlanEdit.apply(.setHigh(mode: "DIGI"), atKhz: 14_120, band: .m20, region: "R1",
                                    segments: Self.twenty)
        #expect(up == .edited([
            Self.seg("R1", "CW", 14_000, 14_070), Self.seg("R1", "DIGI", 14_070, 14_120),
            Self.seg("R1", "PHONE", 14_120, 14_350), Self.seg("R2", "CW", 14_000, 14_150),
        ]))
        // The edited plan never overlaps (the Settings rule).
        if case .edited(let rows) = up {
            let r1: [BandPlanFile.Segment] = rows.filter { $0.region == "R1" }
            #expect(r1.indices.allSatisfy { !BandPlanFile.overlaps(r1, "R1", r1[$0].fromKhz, r1[$0].toKhz, $0) })
        }
    }

    @Test func aCoveredNeighbourIsDropped() {
        let outcome = BandPlanEdit.apply(.setHigh(mode: "CW"), atKhz: 14_100, band: .m20, region: "R1",
                                         segments: Self.twenty)
        #expect(outcome == .edited([
            Self.seg("R1", "CW", 14_000, 14_100), Self.seg("R1", "PHONE", 14_101, 14_350),
            Self.seg("R2", "CW", 14_000, 14_150),
        ]))
    }

    @Test func removeAndRefusals() {
        #expect(BandPlanEdit.apply(.remove, atKhz: 14_080, band: .m20, region: "R1", segments: Self.twenty)
            == .edited([Self.seg("R1", "CW", 14_000, 14_070), Self.seg("R1", "PHONE", 14_101, 14_350),
                        Self.seg("R2", "CW", 14_000, 14_150)]))
        #expect(BandPlanEdit.apply(.remove, atKhz: 14_100, band: .m20, region: "R1", segments: Self.twenty)
            == .refused(.noSegment))
        #expect(BandPlanEdit.apply(.setLow(mode: "CW"), atKhz: 7_010, band: .m40, region: "R1",
                                   segments: Self.twenty) == .refused(.noSegment))
        #expect(BandPlanEdit.apply(.setLow(mode: "CW"), atKhz: 14_080, band: .m20, region: "R1",
                                   segments: Self.twenty) == .refused(.empty))
        #expect(BandPlanEdit.apply(.setLow(mode: "CW"), atKhz: 13_000, band: nil, region: "R1",
                                   segments: Self.twenty) == .refused(.outsideBand))
        #expect(BandPlanEdit.apply(.setLow(mode: "CW"), atKhz: 7_010, band: .m20, region: "R1",
                                   segments: Self.twenty) == .refused(.outsideBand))
    }

    @Test func usLicenseLinesInTheWindow() {
        #expect(UsLicenseLines.edges(lo: 14_000_000, hi: 14_350_000) == [14_025_000, 14_150_000, 14_175_000,
                                                                        14_225_000])
        #expect(UsLicenseLines.edges(lo: 14_150_000, hi: 14_175_000) == [14_150_000, 14_175_000])
        #expect(UsLicenseLines.edges(lo: 28_000_000, hi: 29_700_000).isEmpty)
        #expect(UsLicenseLines.edgesKhz.count == 15)
    }

    @Test func bulkRemovalKeepsWhatThePredicateLeaves() {
        let buffer = SpotBuffer(maxAgeMinutes: 15, clock: DxTestClock("2026-07-09T10:00:00Z").source)
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: ""))
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 7_005_000, dxCall: "W1AW", comment: ""))
        buffer.add(DxSpot(spotter: "OK1XOE", freqHz: 14_030_000, dxCall: "DL1ABC", comment: "", selfSpotted: true))
        let removed: Int = buffer.removeAll { $0.band == .m20 && !$0.selfSpotted }
        #expect(removed == 1)
        #expect(buffer.snapshot().map(\.dxCall) == ["W1AW", "DL1ABC"])
        #expect(buffer.removeAll { _ in false } == 0)
    }
}
