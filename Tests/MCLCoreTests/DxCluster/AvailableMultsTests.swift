import Testing
@testable import MCLCore

/// `AvailableMults`, read from `ui/AvailableMultipliersWindow.kt:129-138, 219-248, 279-288` (v1.1.1); the sort is
/// also measured on the JVM (`SpotAnalyzerParityTests.sortRowsMatchesJvm`).
@Suite struct AvailableMultsTests {

    static func row(_ call: String, _ freqHz: Int, azimuth: Int? = nil, mode: String = "CW", mults: Int = 0,
                    dupe: Bool = false, points: Int = 1) -> SpotRow {
        SpotRow(call: call, freqHz: freqHz, azimuth: azimuth, mode: mode, newMultCount: mults, dupe: dupe, snr: nil,
                points: points, spotter: "S")
    }

    static let rows: [SpotRow] = [
        row("A", 14_010_000, azimuth: 90, mults: 1),
        row("B", 7_010_000, mode: "FT8", dupe: true),
        row("C", 21_020_000, azimuth: 10, mode: "SSB", mults: 2),
        row("D", 14_020_000, mode: "RTTY"),
        row("E", 10_110_000, azimuth: 200, mults: 1),
    ]

    @Test func emptySetsMeanEverything() {
        #expect(AvailableMults.filter(rows: Self.rows, bands: [], modes: []).map(\.call) == ["A", "B", "C", "D", "E"])
    }

    @Test func multsOnlyBandsAndModeCategories() {
        #expect(AvailableMults.filter(rows: Self.rows, multsOnly: true, bands: [], modes: []).map(\.call)
                == ["A", "C", "E"])
        #expect(AvailableMults.filter(rows: Self.rows, bands: [.m20, .m40], modes: []).map(\.call) == ["A", "B", "D"])
        // Spot modes go through `modeCategory`: FT8 and RTTY are DIGI, SSB is PHONE.
        #expect(AvailableMults.filter(rows: Self.rows, bands: [], modes: ["DIGI"]).map(\.call) == ["B", "D"])
        #expect(AvailableMults.filter(rows: Self.rows, multsOnly: true, bands: [.m15, .m20], modes: ["PHONE"])
                    .map(\.call) == ["C"])
    }

    @Test func rowWithoutBandPassesOnlyAnEmptyBandSet() {
        let odd = [Self.row("X", 1_000)]
        #expect(AvailableMults.filter(rows: odd, bands: [], modes: []).count == 1)
        #expect(AvailableMults.filter(rows: odd, bands: [.m20], modes: []).isEmpty)
    }

    @Test func matrixCountsMultsQsAndTotalPerBand() {
        let m = AvailableMults.matrix(rows: Self.rows)
        #expect(m[.m20] == AvailableMults.Counts(mults: 1, qs: 2, total: 2))
        #expect(m[.m40] == AvailableMults.Counts(mults: 0, qs: 0, total: 1))
        #expect(m[.m30] == AvailableMults.Counts(mults: 1, qs: 1, total: 1))   // not a matrix column
        #expect(m[.m10] == nil)
        #expect(AvailableMults.Counts.of(Self.rows) == AvailableMults.Counts(mults: 3, qs: 4, total: 5))
        #expect(AvailableMults.matrixBands.map(\.adif) == ["160m", "80m", "40m", "20m", "15m", "10m"])
    }

    @Test func emptyDirectionIsAlwaysLast() {
        let asc = AvailableMults.sorted(Self.rows, by: .dir, ascending: true).map(\.call)
        let desc = AvailableMults.sorted(Self.rows, by: .dir, ascending: false).map(\.call)
        #expect(asc == ["C", "A", "E", "B", "D"])
        #expect(desc == ["E", "A", "C", "B", "D"])
    }

    @Test func descendingReversesTies() {
        let tied = [Self.row("P", 14_000_000, points: 3), Self.row("Q", 14_000_000, points: 3)]
        #expect(AvailableMults.sorted(tied, by: .freq, ascending: true).map(\.call) == ["P", "Q"])
        #expect(AvailableMults.sorted(tied, by: .freq, ascending: false).map(\.call) == ["Q", "P"])
        #expect(AvailableMults.sorted(tied, by: .pts, ascending: false).map(\.call) == ["Q", "P"])
    }
}
