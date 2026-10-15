import Foundation
import Testing
@testable import MCLCore

/// N1MM „Set bands and modes to be displayed": the modes a Multipliers window shows. In a contest whose multipliers
/// count per band and mode, a cell is worked when the multiplier was worked in one of the modes shown, and only spots
/// of those modes are drawn; without a choice the grid shows the contest's first mode (Kotlin).
@Suite struct MultGridModesTests {

    typealias F = SpotAnalysisFixture

    @Test func theModesShownDecideWhatIsWorkedAndSpotted() throws {
        let env = try F.environment()
        try env.activate("rdxc")
        try env.log("DL1ABC", "20m", "SSB", ("rst", "59"), ("nr", "1"))
        let spots: [DxSpot] = [
            DxSpot(spotter: "W3LPL", freqHz: 14_010_000, dxCall: "W1AW", comment: "CW"),
            DxSpot(spotter: "W3LPL", freqHz: 14_250_000, dxCall: "F5AB", comment: "SSB"),
        ]
        let a = env.analyzer()

        func cell(_ grid: MultGridView, _ prefix: String) -> MultCell? {
            grid.rows.first { $0.prefix == prefix }?.cells["20m"]
        }

        let first = a.multiplierGrid(kind: "dxcc", spots: spots)
        #expect(cell(first, "DL") == .empty)     // CW only (the first mode): the SSB QSO does not count
        let cw = a.multiplierGrid(kind: "dxcc", spots: spots, modes: ["CW"])
        #expect(cw == first)
        let ssb = a.multiplierGrid(kind: "dxcc", spots: spots, modes: ["SSB"])
        #expect(cell(ssb, "DL") == .worked)
        #expect(cell(ssb, "K") == .empty)        // the CW spot is not drawn
        #expect(cell(ssb, "F") != .empty)
        let both = a.multiplierGrid(kind: "dxcc", spots: spots, modes: ["CW", "SSB"])
        #expect(cell(both, "DL") == .worked)
        #expect(cell(both, "K") != .empty)
        #expect(cell(both, "F") != .empty)
        #expect(cell(first, "K") != .empty && cell(first, "F") != .empty) // no choice: every spot as before
    }

    @Test func savedModesKeepTheContestsOrderAndDropTheDefault() {
        #expect(MultGridExtras.modesKey("dxcc") == "dxcc/modes")
        #expect(MultGridExtras.modes(nil, of: ["CW", "SSB"]) == nil)
        #expect(MultGridExtras.modes("ssb, cw,FT8", of: ["CW", "SSB"]) == ["CW", "SSB"])
        #expect(MultGridExtras.modes("FT8", of: ["CW", "SSB"]) == nil)
        #expect(MultGridExtras.savedModes(["SSB", "CW"], of: ["CW", "SSB"]) == "CW,SSB")
        #expect(MultGridExtras.savedModes(["CW"], of: ["CW", "SSB"]) == nil)
        #expect(MultGridExtras.savedModes([], of: ["CW", "SSB"]) == nil)
    }
}
