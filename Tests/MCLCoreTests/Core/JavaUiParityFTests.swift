import Foundation
import Testing
@testable import MCLCore

/// Java parity: the spot and band map logic against the real Kotlin code of v1.1.1, over a synthetic spot corpus
/// (`Fixtures/ui-gate/spots-f.txt`): `spotStatus`, `isColorRelevant`, `spotCategory`, `resolveSpotMode` and
/// `bandPlanCategory` in seven contexts (`spot.STATUS`); `spotRows`, the row filter, the band matrix, `sortRows` and
/// `modeCategory` (`spot.ROWS`); `multiplierGrid` for every kind (`mult.GRID`); `spotTooltip` and `predictExchange`
/// with callbook records and without (`spot.TIP`); `niceStepHz`, `layoutSpots`, `hitSpot` and `azimuthOf`
/// (`bandmap.LAYOUT`); mark, remove, spot to the cluster, SPOTME, store and the self-spot / auto-prefill effects of
/// the entry window on a headless `AppState` (`spot.ACT`). The reference `Fixtures/ui-f-java.json.gz` comes from
/// a maintainer-only probe (fixture `f`, instructions kept with the probe). The generator opens no socket and calls no
/// callbook.
///
/// Input rows are taken from the reference (the rows that carry a corpus spot, the `defs` and the `corpus` row are
/// rebuilt by Swift from its own files), outputs are computed by Swift (`UiParityFSections`). A change of inputs =
/// "REGENERATE REFERENCE", a different output = "MISMATCH". The gate prints nothing; each item runs on its own
/// thread, not in the shared pool.
@Suite struct JavaUiParityFTests {

    static let regenerate = " — the reference is generated from Java v1.1.1 by a maintainer-only generator (not in this repository)."

    /// Rows per item in the Java reference — against a broken generator (an empty corpus, a missing context),
    /// where inputs taken from the reference would still match.
    static let pinned: [String: Int] = [
        "spot.STATUS": 4_380, "spot.ROWS": 2_944, "mult.GRID": 732, "spot.TIP": 4_873, "bandmap.LAYOUT": 4_312,
        "spot.ACT": 1_404,
    ]

    @Test func spotsAndBandmapMatchKotlin() async throws {
        try await JavaV111Gate.run {
            let reference = try JavaIoParityFixture.reference("ui-f-java")
            #expect(reference.map(\.relative) == UiParityFSections.names, "set of reference items")
            for entry in reference {
                #expect(entry.lines.count == Self.pinned[entry.relative],
                        "\(entry.relative): number of reference rows (pinned)")
            }
            let mine: [UiParityFSections.Entry] = try await UiParityFSections.replayAll(reference)
            let report = JavaNetParityFixture.differences(reference: reference, mine: mine, regenerate: Self.regenerate,
                                                          label: "spots and band map")
            #expect(report == nil, Comment(rawValue: report ?? ""))
        }
    }

    /// The corpus and the scripts reach what the sections are meant to compare: every contest context with an
    /// available grid, the spot kinds, a self-spot and an auto-prefill of the entry window, a refused cluster
    /// command and a sent one.
    @Test func referenceCoversTheCases() throws {
        let reference = try JavaIoParityFixture.reference("ui-f-java")
        func lines(_ name: String) throws -> [[String]] {
            let entry = try #require(reference.first { $0.relative == name })
            return entry.lines.map(JavaEngineParityTests.fields)
        }
        let grid: [[String]] = try lines("mult.GRID").filter { $0[1] == "out" && $0.count == 6 }
        let available: Set<String> = Set(grid.filter { $0[2] == "1" }.map { String($0[0].split(separator: "/")[3]) })
        #expect(available == ["dxcc", "grid", "itu", "cq", "districts", "sections", "other"], "kinds with a grid")
        let status: [[String]] = try lines("spot.STATUS").filter { $0[1] == "out" && $0[0].contains("/s/") }
        #expect(status.contains { $0[2] == "1" }, "a dupe spot")
        #expect(status.contains { $0[3] != "0" && $0[4] == "1" }, "a new multiplier")
        #expect(status.contains { $0[8] == "~" }, "a spot without a band plan category")
        let act: [[String]] = try lines("spot.ACT").filter { $0[1] == "out" && $0[0].hasPrefix("a/") }
        #expect(act.contains { $0[2].hasPrefix("Spot odesl") }, "a spot sent to the cluster")
        #expect(act.contains { $0[2].hasPrefix("Spot: DX cluster nen") }, "a refused cluster command")
        #expect(act.contains { $0[2].contains("odstran") }, "a removed spot")
    }
}
