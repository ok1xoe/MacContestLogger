import Foundation
import Testing
@testable import MCLCore

/// Replays a maintainer-only probe step by step over `SpotAnalyzer` and compares
/// every output line with the JVM (`SpotAnalysisJava.tsv`, Kotlin `ContestController` v1.1.1).
@Suite struct SpotAnalyzerParityTests {

    typealias F = SpotAnalysisFixture

    /// The JVM lines of one kind (first column), in order.
    static func java(_ kind: String) -> [String] {
        SpotAnalysisJava.tsv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { $0.hasPrefix(kind + "\t") }
    }

    /// The probe's `section(c, tag, spots)`.
    static func section(_ analyzer: SpotAnalyzer, _ tag: String, _ spots: [DxSpot]) -> [String] {
        var out: [String] = []
        out.append("needs\t\(tag)\t\(analyzer.needsHamQthLookup)\t\(analyzer.needsGridLookup)")
        for (i, spot) in spots.enumerated() {
            let status = analyzer.spotStatus(spot)
            out.append("status\t\(tag)\t\(i)\t\(status.dupe)\t\(status.newMultCount)\t\(status.newMult)")
            let mode = analyzer.resolveSpotMode(call: spot.dxCall, freqHz: spot.freqHz, comment: spot.comment)
            out.append("mode\t\(tag)\t\(i)\t\(mode)\t\(analyzer.spotCategory(spot) ?? "null")")
            out.append("predict\t\(tag)\t\(i)\t" + F.esc(F.mapText(analyzer.predictExchange(spot))))
            out.append("tooltip\t\(tag)\t\(i)\t" + F.esc(analyzer.spotTooltip(spot)))
        }
        for r in analyzer.spotRows(spots) {
            let cols: [String] = [
                "row", tag, F.esc(r.call), String(r.freqHz), F.str(r.azimuth), r.mode, String(r.newMultCount),
                String(r.dupe), F.str(r.snr), String(r.points), r.spotter, String(r.isMult),
            ]
            out.append(cols.joined(separator: "\t"))
        }
        for kind in ["dxcc", "grid", "itu", "cq", "districts", "sections", "other", "bogus"] {
            out.append("grid\t\(tag)\t\(kind)\t" + F.esc(gridText(analyzer.multiplierGrid(kind: kind, spots: spots))))
        }
        return out
    }

    /// The probe's text of a `MultGridView`.
    static func gridText(_ g: MultGridView) -> String {
        var sb = "\(g.available) \(g.worked) \(g.possible) rows=\(g.rows.count)"
        for (idx, r) in g.rows.enumerated() {
            var cells = ""
            for band in SpotAnalyzer.multGridBands {
                if let cell = r.cells[band.adif], cell != .empty {
                    cells += "\(band.adif)=\(cell.rawValue),"
                }
            }
            if !cells.isEmpty || idx == 0 || idx == g.rows.count - 1 {
                sb += " | \(r.key)/\(r.label)/\(r.prefix)/\(r.continent) \(cells)"
            }
        }
        var at: [String] = g.spotAt.map { key, spot in
            "\(key.key)@\(key.band)=\(spot.dxCall)@\(spot.freqHz)"
        }
        at.sort { JavaText.compare($0, $1) < 0 }
        let spotAt: String = at.joined(separator: ", ")
        return "\(sb) spotAt=[\(spotAt)]"
    }

    static func expectLines(_ swift: [String], _ java: [String]) {
        #expect(!java.isEmpty)
        #expect(swift.count == java.count)
        for (s, j) in zip(swift, java) where s != j {
            Issue.record("Swift: \(s)\nJava:  \(j)")
        }
    }

    /// `SpotAnalysisProbe.java` parseSnr rows → `ContestController.kt:725-729`.
    @Test func parseSnrMatchesJvm() {
        let inputs: [String] = [
            "", "CW 25 dB 28 WPM CQ", "25dB", "25   dB", "-12 dB", "dB 7", "7 db", "007 dB", "99999999999 dB",
            "2147483647 dB", "2147483648 dB", "1 dB 2 dB", "\u{0661}\u{0662} dB", "12\u{00A0}dB", "12\tdB",
            "x5 dBm",
        ]
        var out: [String] = inputs.map { "parseSnr\t\(F.esc($0))\t\(F.str(SpotAnalyzer.parseSnr($0)))" }
        out.append("parseSnr\tnull\t" + F.str(SpotAnalyzer.parseSnr(nil)))
        Self.expectLines(out, Self.java("parseSnr"))
    }

    /// The probe outside a contest, then CQ WW CW, WW DIGI (with the grid log), the reactivation and IARU HF.
    @Test func sectionsMatchJvm() throws {
        let env = try F.environment()
        var out: [String] = Self.section(env.analyzer(), "none", F.basic)

        try env.activate("cq-ww-cw")
        try env.log("DL1ABC", "20m", "CW", ("rst", "599"), ("zone", "14"))
        try env.log("JA1XYZ", "15m", "CW", ("rst", "599"), ("zone", "25"))
        try env.log("W1AW", "40m", "CW", ("rst", "599"), ("zone", "5"))
        out += Self.section(env.analyzer(), "cqww", F.cqww)

        try env.activate("ww-digi")
        try env.log("DL1AE", "20m", "FT8", ("grid", "JO31"))
        try env.log("JA1QQQ", "15m", "FT8", ("grid", "PM95"))
        _ = env.lines.take()
        out += Self.section(env.analyzer(), "digi", F.digi)
        out += env.lines.take().map { "gridLog\t" + F.esc($0) }
        out += Self.section(env.analyzer(), "digi2", F.digi)
        out.append("gridLogAfter\t\(env.lines.take().count)")
        try env.activate("ww-digi")
        _ = env.analyzer().spotStatus(F.digi[0])
        out += env.lines.take().map { "gridLogReactivated\t" + F.esc($0) }

        try env.activate("iaru-hf")
        try env.log("DA0HQ", "20m", "CW", ("rst", "599"), ("exch", "DARC"))
        out += Self.section(env.analyzer(), "iaru", F.iaru)

        try env.activate("ok-om-dx-cw")
        try env.log("OK1ABC", "20m", "CW", ("rst", "599"), ("district", "APB"))
        out += Self.section(env.analyzer(), "okom", F.okom)
        try env.activate("arrl-dx-cw")
        try env.log("W1AW", "20m", "CW", ("rst", "599"), ("state", "CT"))
        out += Self.section(env.analyzer(), "arrl", F.arrl)

        let kinds: Set<String> = ["needs", "status", "mode", "predict", "tooltip", "row", "grid", "gridLog",
                                  "gridLogAfter", "gridLogReactivated"]
        let java: [String] = SpotAnalysisJava.tsv.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { line in
                guard let tab = line.firstIndex(of: "\t") else { return false }
                return kinds.contains(String(line[..<tab]))
            }
        Self.expectLines(out, java)
    }

    /// The probe's bandPlanCategory / bandPlanSegments rows (my region from OK1XOE = R1).
    @Test func bandPlanMatchesJvm() throws {
        let analyzer = try F.environment().analyzer()
        var out: [String] = []
        let freqs: [Int64] = [1_810_000, 3_550_000, 3_700_000, 7_074_000, 14_000_000, 14_100_000, 14_200_000,
                              50_100_000, 144_300_000, 5_000_000, 0]
        for f in freqs {
            out.append("bandPlanCategory\t\(f)\t" + (analyzer.bandPlanCategory(f)?.rawValue ?? "null"))
        }
        let windows: [(Int64, Int64)] = [(14_000_000, 14_350_000), (7_000_000, 7_200_000), (3_500_000, 3_800_000),
                                         (14_060_000, 14_070_000), (5_000_000, 5_100_000), (14_350_000, 14_000_000)]
        for (lo, hi) in windows {
            let segments: [String] = analyzer.bandPlanSegments(lo: lo, hi: hi).map {
                "\($0.category.rawValue):\($0.lowHz)-\($0.highHz)"
            }
            out.append("bandPlanSegments\t\(lo)-\(hi)\t" + segments.joined(separator: " "))
        }
        Self.expectLines(out, Self.java("bandPlanCategory") + Self.java("bandPlanSegments"))
    }

    /// The probe's sortRows rows (`AvailableMultipliersWindow.kt:279-286`).
    @Test func sortRowsMatchesJvm() {
        let rows: [SpotRow] = [
            SpotRow(call: "A1", freqHz: 14_010_000, azimuth: 90, mode: "CW", newMultCount: 0, dupe: false, snr: nil,
                    points: 3, spotter: "S"),
            SpotRow(call: "A2", freqHz: 14_005_000, azimuth: nil, mode: "CW", newMultCount: 1, dupe: false, snr: nil,
                    points: 1, spotter: "S"),
            SpotRow(call: "A3", freqHz: 14_010_000, azimuth: 45, mode: "CW", newMultCount: 0, dupe: true, snr: nil,
                    points: 3, spotter: "S"),
            SpotRow(call: "A4", freqHz: 7_000_000, azimuth: 90, mode: "CW", newMultCount: 2, dupe: false, snr: nil,
                    points: 0, spotter: "S"),
            SpotRow(call: "A5", freqHz: 21_000_000, azimuth: nil, mode: "CW", newMultCount: 0, dupe: false, snr: nil,
                    points: 3, spotter: "S"),
            SpotRow(call: "A6", freqHz: 14_010_000, azimuth: 300, mode: "CW", newMultCount: 0, dupe: false, snr: nil,
                    points: 1, spotter: "S"),
        ]
        var out: [String] = []
        for column in AvailableMults.SortColumn.allCases {
            for ascending in [true, false] {
                let calls = AvailableMults.sorted(rows, by: column, ascending: ascending).map(\.call)
                out.append("sortRows\t\(column.rawValue)\t\(ascending)\t" + calls.joined(separator: " "))
            }
        }
        Self.expectLines(out, Self.java("sortRows"))
    }
}
