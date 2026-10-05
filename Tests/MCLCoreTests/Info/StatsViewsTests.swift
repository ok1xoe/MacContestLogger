import Testing
@testable import MCLCore

/// `StatsViews` and `ContestRuntime.breakdown` against `ui/StatisticsWindow.kt`, `ui/ScoreWindow.kt` and
/// `ui/DupesheetWindow.kt` of v1.1.1. `ScoreWindowKt.cells`, `StatisticsWindowKt.TIME`, `ContestController.breakdown`
/// and the Java classes underneath are real; the glue is a transcription of the composables
/// (maintainer-only probe).
@Suite struct StatsViewsTests {

    @Test func dimensionLabelsMatchTheJvm() {
        let rows = InfoProbeTable.area("dimension")
        #expect(rows.count == 9)
        for row in rows {
            #expect(LogStatistics.Dimension(rawValue: row.input)?.label == row.result, "\(row.input)")
            #expect(StatsViews.dimension(forLabel: row.result)?.rawValue == row.input)
        }
        #expect(StatsViews.rowDimensions.count == 8)
        #expect(!StatsViews.rowDimensions.contains(.NONE))
        #expect(StatsViews.columnDimensions.count == 9)
        #expect(StatsViews.dimension(forLabel: "nic") == nil)
    }

    static func tableText(_ t: StatisticsTable) -> String {
        var text = "H:" + t.rowHeader
        for c in t.columns { text += "," + c }
        text += "," + t.totalLabel
        for r in t.rows {
            text += " R:" + r.label
            for c in r.cells { text += "," + c }
            text += "," + r.total
        }
        text += " T:" + t.totalLabel
        for c in t.columnTotals { text += "," + c }
        text += "," + t.grandTotal
        return text
    }

    @Test func pivotTablesMatchTheJvm() throws {
        let rows = InfoProbeTable.area("pivot")
        #expect(rows.count == 288)
        for row in rows {
            let f = row.input.split(separator: "|").map(String.init)
            let table = StatsViews.statisticsTable(qsos: InfoProbeTable.logs[f[0]] ?? [],
                                                   rowDim: try #require(LogStatistics.Dimension(rawValue: f[1])),
                                                   colDim: try #require(LogStatistics.Dimension(rawValue: f[2])))
            #expect(Self.tableText(table) == row.result, "\(row.input)")
        }
    }

    @Test func hourlyChartMatchesTheJvm() {
        let rows = InfoProbeTable.area("hourly")
        #expect(rows.count == 4)
        for row in rows {
            let chart = StatsViews.hourlyChart(qsos: InfoProbeTable.logs[row.input] ?? [])
            let text = "title=" + chart.title + ";values=" + InfoProbeTable.listText(chart.values.map { String($0) })
                + ";keys=" + InfoProbeTable.listText(chart.hours)
            #expect(text == row.result, "\(row.input)")
            #expect(chart.scale >= 1)
        }
    }

    @Test func reportsMatchTheJvm() {
        let rows = InfoProbeTable.area("reports")
        #expect(rows.count == 4)
        for row in rows {
            let sections = StatsViews.reports(qsos: InfoProbeTable.logs[row.input] ?? [])
            #expect(sections.count == 3)
            var parts: [String] = []
            for (i, section) in sections.enumerated() {
                parts.append("T" + String(i + 1) + "=" + section.title)
                parts.append(contentsOf: section.lines)
            }
            #expect(parts.joined(separator: "|") == row.result, "\(row.input)")
        }
    }

    // MARK: - Score and dupesheet over the real contest data

    static func scoreText(_ t: ScoreTable) -> String {
        var text = "H:" + t.headers.joined(separator: ",")
        for r in t.rows { text += " R:" + r.joined(separator: ",") }
        text += " T:" + t.total.joined(separator: ",")
        if let title = t.modesTitle {
            text += " M:" + title
            for r in t.modeRows { text += " R:" + r.joined(separator: ",") }
        }
        text += " F:" + t.footer
        if let skipped = t.skippedNote { text += " S:" + skipped }
        return text
    }

    @Test func breakdownAndScoreTablesMatchTheJvm() throws {
        let env = try SpotAnalysisFixture.environment()
        let runtime = env.runtime
        // Outside a contest: no breakdown, no scope, no bands.
        let none = try #require(InfoProbeTable.area("breakdown").first)
        #expect(none.input == "none")
        #expect(try runtime.breakdown(InfoProbeTable.logs["cqww"] ?? []) == nil)
        #expect(runtime.dupeScope == nil)
        #expect(runtime.bandOrder.isEmpty)
        #expect(none.result == "~ scope=~ order=[]")

        let rows = InfoProbeTable.area("score")
        #expect(rows.count == 4)
        for row in rows {
            let f = row.input.split(separator: "|").map(String.init)
            try env.activate(f[0])
            let breakdown = try #require(try runtime.breakdown(InfoProbeTable.logs[f[1]] ?? []))
            let table = StatsViews.scoreTable(breakdown: breakdown, bandOrder: runtime.bandOrder, byMode: f[2] == "true")
            #expect(Self.scoreText(table) == row.result, "\(row.input)")
        }
        for row in InfoProbeTable.area("scoreEmpty") {
            try env.activate(row.input)
            let breakdown = try #require(try runtime.breakdown([]))
            let table = StatsViews.scoreTable(breakdown: breakdown, bandOrder: runtime.bandOrder, byMode: true)
            #expect(Self.scoreText(table) == row.result, "\(row.input)")
        }
    }

    @Test func rulesResolveOverRealDefinitions() throws {
        let env = try SpotAnalysisFixture.environment()
        let rows = InfoProbeTable.area("resolve")
        #expect(rows.count == 14)
        for row in rows {
            let f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            try env.activate(f[0])
            var category: [String: String]?
            if f[1] != "~" {
                // Java `Map.toString`: `{A=B, C=D}`.
                let inner = f[1].dropFirst().dropLast()
                category = [:]
                for item in inner.split(separator: ",") {
                    let pair = item.trimmingCharacters(in: .init(charactersIn: ",")).split(separator: "=", maxSplits: 1,
                                                                                         omittingEmptySubsequences: false)
                    let key = pair[0].hasPrefix(" ") ? String(pair[0].dropFirst()) : String(pair[0])
                    category?[key] = String(pair[1])
                }
            }
            let op = InfoTimers.rules(definition: env.runtime.definition, category: category)
            var text = "none"
            if let op {
                func pairText(_ a: Int?, _ b: Int?) -> String {
                    (a.map { String($0) } ?? "~") + "/" + (b.map { String($0) } ?? "~")
                }
                let off: String = op.offTime.map { "off=" + pairText($0.minimumMinutes, $0.requiredMinutes) } ?? "off=~"
                let band: String = op.bandChange.map { "band=" + pairText($0.minimumMinutes, $0.perHour) } ?? "band=~"
                text = off + " " + band
            }
            #expect(text == row.result, "\(row.input)")
        }
    }

    static func dupesheetText(_ v: DupesheetView) -> String {
        var text = "T:" + v.title
        for column in v.columns {
            text += " C:" + column.header
            for call in column.calls { text += (call.hit ? " *" : " ") + call.text }
        }
        return text
    }

    @Test func dupesheetMatchesTheJvm() throws {
        let env = try SpotAnalysisFixture.environment()
        let rows = InfoProbeTable.area("dupesheet")
        #expect(rows.count == 420)
        for row in rows {
            var f = row.input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            // `tag|log|band|mode|partial`, the tag being `none`, a contest id, or `<contest id>|<score log>`.
            let tail = Array(f.suffix(3))
            f.removeLast(3)
            let log = f.removeLast()
            var scope: ContestDefinition.Scope?
            if f.first != "none" {
                try env.activate(f[0])
                scope = env.runtime.dupeScope
            }
            let qsos = InfoProbeTable.logs[log] ?? []
            let band: String? = tail[0] == "~" ? nil : tail[0]
            let mode: String? = tail[1] == "~" ? nil : tail[1]
            let view = StatsViews.dupesheet(qsos: qsos, scope: scope, band: band, mode: mode, typedCall: tail[2])
            #expect(Self.dupesheetText(view) == row.result, "\(row.input)")
        }
    }
}
