import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `MultiplierGridTest` (4): building the multiplier grid (worked per band by scope).
@Suite struct MultiplierGridTests {

    static let bands: [Band] = [.m160, .m80, .m40, .m20, .m15, .m10]

    private func session() throws -> ContestSession {
        try SessionFixture.session("@cq-ww-cw.yaml")
    }

    @Test func gridMarksWorkedBandPerCountry() throws {
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("zone", "14")))
        _ = try s.log(call: "W1AW", band: "40m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("zone", "5")))

        let grid = try s.multiplierGrid(bands: Self.bands) { _, set in set is DxccMultiplierSet }
        #expect(grid.available)
        #expect(grid.possible >= 4, "enumeration of all (non-deleted) DXCC entities")
        #expect(grid.worked == 2)

        let germany = try Self.row(grid, "DL")
        #expect(germany.workedBands.contains("20m"))
        #expect(!germany.workedBands.contains("40m"), "CQ WW: a country is a per-band mult")

        let usa = try Self.row(grid, "K")
        #expect(usa.workedBands.contains("40m"))
        #expect(!usa.workedBands.contains("20m"))
    }

    @Test func gridByCqZoneSetId() throws {
        let s = try session()
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: SessionFixture.raw(("rst", "599"), ("zone", "14")))

        let grid = try s.multiplierGrid(bands: Self.bands) { _, set in set.id == "cq_zones" }
        #expect(grid.available)
        let zone14 = try #require(grid.rows.first { $0.key == "14" })
        #expect(zone14.workedBands.contains("20m"))
    }

    @Test func gridFieldsFromWorkedKeysOnly() throws {
        let s = try SessionFixture.session("@ww-digi.yaml", myCall: "OK1XOE", myGrid: "JN79")
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "DIGITAL", receivedRaw: SessionFixture.raw(("grid", "JO60")))
        _ = try s.log(call: "W1AW", band: "40m", mode: "DIGITAL", receivedRaw: SessionFixture.raw(("grid", "FN31")))

        let grid = try s.multiplierGrid(bands: Self.bands) { _, set in set.id == "grid_fields" }
        #expect(grid.available)
        #expect(grid.possible < 0, "non-enumerated set → possible = -1")
        // Rows only from worked grid fields, not an enumeration of all.
        #expect(grid.rows.count == 2)
        let jo = try #require(grid.rows.first { $0.key == "JO" })
        #expect(jo.workedBands.contains("20m"))
        #expect(!jo.workedBands.contains("40m"))
        let fn = try #require(grid.rows.first { $0.key == "FN" })
        #expect(fn.workedBands.contains("40m"))
    }

    @Test func unavailableWhenNoMatchingSet() throws {
        let s = try session()
        let grid = try s.multiplierGrid(bands: Self.bands) { _, _ in false }
        #expect(!grid.available)
    }

    private static func row(_ grid: ContestSession.MultiplierGrid, _ prefix: String) throws -> ContestSession.GridRow {
        try #require(grid.rows.first { $0.prefix == prefix }, "row with prefix \(prefix) not found")
    }
}
