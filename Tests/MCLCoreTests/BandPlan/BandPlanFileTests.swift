import Foundation
import Testing
@testable import MCLCore

/// Mirrors the Java `BandPlanFileTest` (3 `@Test`).
@Suite struct BandPlanFileTests {

    @Test func overlapDetectionWithinRegion() {
        let segs = [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040),
            BandPlanFile.Segment(region: "R1", mode: "DIGI", fromKhz: 7040, toKhz: 7050),
        ]
        // The new segment 7030-7045 overlaps both CW and DIGI.
        #expect(BandPlanFile.overlaps(segs, "R1", 7030, 7045, -1))
        // 7050-7100 does not overlap (touching at a boundary is not an overlap).
        #expect(!BandPlanFile.overlaps(segs, "R1", 7050, 7100, -1))
        // The same range in ANOTHER region does not matter.
        #expect(!BandPlanFile.overlaps(segs, "R2", 7000, 7040, -1))
        // Editing row 0 (self) is not compared with itself.
        #expect(!BandPlanFile.overlaps(segs, "R1", 7000, 7040, 0))
    }

    @Test func roundTripReadWrite() throws {
        let dir = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(dir) }
        let segs = [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040),
            BandPlanFile.Segment(region: "R1", mode: "PHONE", fromKhz: 7050, toKhz: 7200),
            BandPlanFile.Segment(region: "R2", mode: "CW", fromKhz: 7000, toKhz: 7040),
        ]
        try BandPlanFile.write(dir, segs)
        let back = BandPlanFile.read(dir)
        #expect(back.count == 3)
        // What was written, then loaded, gives the same values (order within the region preserved).
        #expect(back.contains {
            $0.region == "R1" && $0.mode == "CW" && $0.fromKhz == 7000 && $0.toKhz == 7040
        })
        #expect(back.contains { $0.region == "R2" && $0.mode == "CW" })

        // And BandPlan really loads it too (integration of the format).
        #expect(BandPlan.fromDir(dir).modeAt(7_005_000, .r1) == .cw)
    }

    @Test func missingFileReadsEmpty() {
        #expect(BandPlanFile.read(URL(fileURLWithPath: "/nonexistent-bp")).isEmpty)
    }
}
