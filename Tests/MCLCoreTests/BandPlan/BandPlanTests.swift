import Foundation
import Testing
@testable import MCLCore

/// Helper: a temporary directory with `bandplan.yaml` of the given content. Mirrors the Java
/// `@TempDir` + `Files.writeString`.
enum BandPlanTestDir {

    /// A directory with the file `bandplan.yaml` and the given content. If the write fails, the directory is deleted at once
    /// (the caller's `defer` has not run yet).
    static func with(_ yaml: String) throws -> URL {
        let dir = try empty()
        do {
            try yaml.write(to: dir.appendingPathComponent("bandplan.yaml"),
                           atomically: false, encoding: .utf8)
        } catch {
            remove(dir)
            throw error
        }
        return dir
    }

    /// An empty temporary directory. The caller cleans it up with `defer { BandPlanTestDir.remove(dir) }`
    /// (Java `@TempDir` is deleted by JUnit itself; before, thousands of `bandplan-<UUID>` stayed here).
    static func empty() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bandplan-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Deletes a temporary directory with its content; an error (already deleted) is ignored.
    static func remove(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// kHz to Hz the same way `BandPlan` does it (Java `Math.round(k * 1000)`).
    static func khz(_ k: Double) -> Int64 {
        BandPlan.khz(k)
    }
}

/// Mirrors the Java `BandPlanTest` (10 `@Test`), case by case.
@Suite struct BandPlanTests {

    private let plan = BandPlan.defaultPlan()

    @Test func cwSegmentOn40m() {
        #expect(plan.modeAt(7_005_000, .r1) == .cw)
    }

    @Test func digiSegmentOn40m() {
        #expect(plan.modeAt(7_045_000, .r1) == .digi)
    }

    @Test func phoneSegmentOn40m() {
        #expect(plan.modeAt(7_120_000, .r1) == .phone)
    }

    @Test func cwSegmentOn20m() {
        #expect(plan.modeAt(14_010_000, .r1) == .cw)
    }

    @Test func phoneSegmentOn20m() {
        #expect(plan.modeAt(14_200_000, .r1) == .phone)
    }

    @Test func outsideAnySegmentIsEmpty() {
        // 14100 kHz = the gap around the beacon (14099–14101) — outside a segment
        #expect(plan.modeAt(14_100_000, .r1) == nil)
        // completely outside the bands
        #expect(plan.modeAt(9_000_000, .r1) == nil)
    }

    @Test func regionFromContinent() {
        #expect(BandPlan.IaruRegion.forContinent("EU") == .r1)
        #expect(BandPlan.IaruRegion.forContinent("AF") == .r1)
        #expect(BandPlan.IaruRegion.forContinent("NA") == .r2)
        #expect(BandPlan.IaruRegion.forContinent("SA") == .r2)
        #expect(BandPlan.IaruRegion.forContinent("AS") == .r3)
        #expect(BandPlan.IaruRegion.forContinent("OC") == .r3)
        #expect(BandPlan.IaruRegion.forContinent(nil) == .r1)
        #expect(BandPlan.IaruRegion.forContinent("xx") == .r1)
    }

    @Test func allRegionsResolveDefault() {
        // The default plan covers all regions (until YAML supplies different ones).
        #expect(plan.modeAt(7_005_000, .r2) == .cw)
        #expect(plan.modeAt(7_005_000, .r3) == .cw)
    }

    @Test func missingDirFallsBackToDefault() {
        let p = BandPlan.fromDir(URL(fileURLWithPath: "/nonexistent-bandplan-dir"))
        #expect(p.modeAt(7_005_000, .r1) == .cw)
    }

    @Test func loadsExternalYaml() throws {
        let dir = try BandPlanTestDir.with("""
            regions:
              R2:
                - { band: "40m", cw: "7000-7040", digi: "7040-7080", phone: "7080-7300" }
            """)
        defer { BandPlanTestDir.remove(dir) }
        let p = BandPlan.fromDir(dir)
        // R2 phone from YAML reaches to 7300 kHz; the built-in default (R1) would have no
        // segment at 7250.
        #expect(p.modeAt(7_250_000, .r2) == .phone)
    }
}
