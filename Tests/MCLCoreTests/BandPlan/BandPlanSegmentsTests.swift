import Foundation
import Testing
@testable import MCLCore

/// Listing of segments for drawing the band plan in the bandmap. Unlike `modeAt`,
/// which answers for a single frequency, this returns whole ranges — and it must give
/// the same answer: what `modeAt` assigns to CW must not be in a DIGI segment.
///
/// Mirrors the Java `BandPlanSegmentsTest` (6 `@Test`).
@Suite struct BandPlanSegmentsTests {

    private static func khz(_ k: Double) -> Int64 { BandPlanTestDir.khz(k) }

    @Test func listsSegmentsOfTwentyMeters() throws {
        let segs = BandPlan.defaultPlan().segmentsIn(Self.khz(14_000), Self.khz(14_350), .r1)

        // `require`, not `expect`: on a regression that empties the list, the test must
        // end here, not crash on an index and bring down the whole test process.
        try #require(segs.count == 3, "\(segs)")
        #expect(segs[0].category == .cw)
        #expect(segs[0].lowHz == Self.khz(14_000))
        #expect(segs[0].highHz == Self.khz(14_070))
        #expect(segs[1].category == .digi)
        #expect(segs[2].category == .phone)
        #expect(segs[2].highHz == Self.khz(14_350))
    }

    @Test func clipsToVisibleWindow() throws {
        // After a zoom the bandmap shows only a window — segments are to be clipped,
        // not fall out.
        let segs = BandPlan.defaultPlan().segmentsIn(Self.khz(14_050), Self.khz(14_080), .r1)

        try #require(segs.count == 2, "\(segs)")
        #expect(segs[0].category == .cw)
        #expect(segs[0].lowHz == Self.khz(14_050))
        #expect(segs[0].highHz == Self.khz(14_070))
        #expect(segs[1].category == .digi)
        #expect(segs[1].highHz == Self.khz(14_080))
    }

    @Test func segmentsDoNotOverlapAndAgreeWithModeAt() {
        let segs = BandPlan.defaultPlan().segmentsIn(Self.khz(1_810), Self.khz(2_000), .r1)

        #expect(!segs.isEmpty)
        for i in 1..<segs.count {
            #expect(segs[i].lowHz > segs[i - 1].highHz, "segments must not overlap: \(segs)")
        }
        for s in segs {
            #expect(BandPlan.defaultPlan().modeAt(s.lowHz, .r1) == s.category,
                    "segment start \(s)")
            #expect(BandPlan.defaultPlan().modeAt(s.highHz, .r1) == s.category,
                    "konec segmentu \(s)")
        }
    }

    @Test func overlappingRangesInFileKeepTheFirstOne() throws {
        // A real case from contest-data: R2 has cw 3500-3600 on 80 m and digi
        // 3570-3600, so digi entirely inside cw. modeAt returns CW there, so DIGI
        // must not be drawn.
        let dir = try BandPlanTestDir.with("""
            ---
            regions:
              R2:
              - band: ""
                cw: "3500-3600"
              - band: ""
                digi: "3570-3600"
              - band: ""
                phone: "3600-4000"
            """)
        defer { BandPlanTestDir.remove(dir) }
        let plan = BandPlan.fromDir(dir)

        let segs = plan.segmentsIn(Self.khz(3_500), Self.khz(4_000), .r2)

        try #require(segs.count == 2, "\(segs)")
        #expect(segs[0].category == .cw)
        #expect(segs[0].highHz == Self.khz(3_600))
        #expect(segs[1].category == .phone)
    }

    @Test func windowOutsideAnySegmentIsEmpty() {
        // Between 10m digi (…28190) and phone (28300…) there is a gap that the band plan
        // does not describe.
        #expect(BandPlan.defaultPlan().segmentsIn(Self.khz(28_200), Self.khz(28_290), .r1).isEmpty)
    }

    @Test func badArgumentsAreSafe() {
        let plan = BandPlan.defaultPlan()
        #expect(plan.segmentsIn(Self.khz(14_100), Self.khz(14_000), .r1).isEmpty, "reversed range")
        #expect(plan.segmentsIn(Self.khz(14_000), Self.khz(14_100), nil).isEmpty, "region nil")
    }
}
