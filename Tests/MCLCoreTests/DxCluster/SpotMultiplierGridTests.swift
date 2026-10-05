import Foundation
import Testing
@testable import MCLCore

/// `SpotAnalyzer.multiplierGrid`, read from `ContestController.kt:615-697` (v1.1.1); values measured on the JVM
/// (`SpotAnalysisJava`).
@Suite struct SpotMultiplierGridTests {

    typealias F = SpotAnalysisFixture

    @Test func dxccGridHasWorkedSpottedAndDoubleCells() throws {
        let a = try SpotAnalyzerTests.cqww()
        let g = a.multiplierGrid(kind: "dxcc", spots: F.cqww)
        #expect(g.available && g.worked == 3 && g.possible == 6 && g.rows.count == 6)
        let us = try #require(g.rows.first { $0.key == "291" })
        #expect(us.label == "United States" && us.prefix == "K" && us.continent == "NA")
        #expect(us.cells["40m"] == .worked)          // worked wins over the dupe spot on 40 m
        #expect(us.cells["20m"] == .spottedDbl)      // W1AW on 20 m brings two new multipliers
        #expect(us.cells["160m"] == .empty)
        #expect(us.cells.count == SpotAnalyzer.multGridBands.count)
        // The phone spot of LU1ABC is ignored; its CW self spot on 80 m counts.
        let lu = try #require(g.rows.first { $0.key == "100" })
        #expect(lu.cells["20m"] == .empty && lu.cells["80m"] == .spottedDbl)
        // `spotAt` keeps the first spot of a cell, also for bands outside the grid (30 m).
        #expect(g.spotAt[MultGridView.CellKey(key: "291", band: "20m")]?.freqHz == 14_010_000)
        #expect(g.spotAt[MultGridView.CellKey(key: "230", band: "30m")]?.dxCall == "DL3AA")
    }

    @Test func gridFieldsAddSpottedRowsSortedByKey() throws {
        let env = try F.environment()
        try env.activate("ww-digi")
        try env.log("DL1AE", "20m", "FT8", ("grid", "JO31"))
        try env.log("JA1QQQ", "15m", "FT8", ("grid", "PM95"))
        let g = env.analyzer().multiplierGrid(kind: "grid", spots: F.digi)
        #expect(g.available && g.worked == 2 && g.possible == -1)
        // Worked keys from the tracker first (JO, PM), then spotted-only keys sorted (GG, JN).
        #expect(g.rows.map(\.key) == ["JO", "PM", "GG", "JN"])
        #expect(g.rows[2] == MultGridRow(key: "GG", label: "GG", prefix: "", continent: "",
                                         cells: ["160m": .empty, "80m": .empty, "40m": .empty, "20m": .empty,
                                                 "15m": .spotted, "10m": .empty]))
        #expect(g.rows[1].cells["15m"] == .worked && g.rows[1].cells["20m"] == .spotted)
    }

    @Test func kindsWithoutABindingOrUnknownAreUnavailable() throws {
        let a = try SpotAnalyzerTests.cqww()
        for kind in ["grid", "itu", "districts", "sections", "other", "bogus", "DXCC"] {
            #expect(a.multiplierGrid(kind: kind, spots: F.cqww) == .unavailable, "\(kind)")
        }
        #expect(a.multiplierGrid(kind: "cq", spots: F.cqww).possible == 40)
    }

    @Test func otherKindHasNoSpotKey() throws {
        let env = try F.environment()
        try env.activate("iaru-hf")
        try env.log("DA0HQ", "20m", "CW", ("rst", "599"), ("exch", "DARC"))
        let a = env.analyzer()
        let other = a.multiplierGrid(kind: "other", spots: F.iaru)
        #expect(other.available && other.worked == 1 && other.possible == 117 && other.spotAt.isEmpty)
        #expect(other.rows.first { $0.key == "DARC" }?.cells["20m"] == .worked)
        #expect(other.rows.first?.label == "")
        let itu = a.multiplierGrid(kind: "itu", spots: F.iaru)
        #expect(itu.rows.first { $0.key == "28" }?.cells["20m"] == .spotted)
    }
}
