import Foundation
import Testing
@testable import MCLCore

/// N1MM Move Multipliers over the spots: the cell texts, the count range, the filters and the QSO counts.
@Suite struct SpotMoveMultsTests {

    private static func row(_ cells: [String: SpotMoveMults.Cell]) -> SpotMoveMults.Row {
        SpotMoveMults.Row(call: "DL1ABC", mode: "CW", cells: cells)
    }

    private static let spot = DxSpot(spotter: "W3LPL", freqHz: 14_025_000, dxCall: "DL1ABC", comment: "")

    @Test func cellTextsByDisplay() {
        let row = Self.row([
            "20m": .init(newMults: 1, points: 3, count: 0, spot: Self.spot),
            "40m": .init(newMults: 2, points: 3, count: 2, spot: nil),
            "80m": .init(newMults: 0, points: 0, count: 1, spot: nil),
        ])
        #expect(SpotMoveMults.text(row, band: .m20, display: .multipliers) == "M1")
        #expect(SpotMoveMults.text(row, band: .m40, display: .multipliers) == "M2")
        #expect(SpotMoveMults.text(row, band: .m80, display: .multipliers) == "")
        #expect(SpotMoveMults.text(row, band: .m80, display: .points) == "3", "the row's points in every column")
        #expect(SpotMoveMults.text(row, band: .m20, display: .counts) == "-")
        #expect(SpotMoveMults.text(row, band: .m40, display: .counts) == "2")
        #expect(row.count == 3)
        #expect(row.spottedBands([.m80, .m40, .m20]) == [.m20])
    }

    @Test func theCountRange() {
        #expect(SpotMoveMults.range("3-5") == 3...5)
        #expect(SpotMoveMults.range(" 5 ") == 5...5)
        #expect(SpotMoveMults.range("5-3") == SpotMoveMults.defaultRange)
        #expect(SpotMoveMults.range("0-101") == SpotMoveMults.defaultRange)
        #expect(SpotMoveMults.range("x") == 0...6)
    }

    @Test func theDisplayFiltersRows() {
        let mult = Self.row(["20m": .init(newMults: 1, points: 1, count: 0, spot: nil)])
        let none = SpotMoveMults.Row(call: "K1ZZ", mode: "CW",
                                     cells: ["20m": .init(newMults: 0, points: 8, count: 7, spot: nil)])
        #expect(SpotMoveMults.filter([mult, none], display: .multipliers, range: 0...6).map(\.call) == ["DL1ABC"])
        #expect(SpotMoveMults.filter([mult, none], display: .points, range: 0...6).map(\.call) == ["DL1ABC"])
        #expect(SpotMoveMults.filter([mult, none], display: .counts, range: 7...7).map(\.call) == ["K1ZZ"])
    }

    @Test func modesAndCounts() {
        #expect(SpotMoveMults.passes("CW", .contest, contestCategories: ["CW"]))
        #expect(!SpotMoveMults.passes("PHONE", .contest, contestCategories: ["CW"]))
        #expect(SpotMoveMults.passes("PHONE", .all, contestCategories: ["CW"]))
        #expect(SpotMoveMults.passes("DIGI", .digi, contestCategories: []))
        var a = Qso()
        a.call = "dl1abc"
        a.band = .m20
        a.mode = .cw
        var b = a
        b.xqso = true
        var c = a
        c.band = .m40
        #expect(SpotMoveMults.counts([a, b, c]) == ["DL1ABC/CW": ["20m": 1, "40m": 1]])
    }
}
