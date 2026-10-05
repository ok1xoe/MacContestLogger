import Testing
@testable import MCLCore

/// `RatePanel` and `GoalStatus` against `ui/RateWindow.kt` (`:601-782`, `:959-963`) of v1.1.1: the glue is a
/// transcription of the composables over the real `ContestStats` and `GoalSet`
/// (maintainer-only probe, rows `status`, `near`, `trend`).
@Suite struct RatePanelTests {

    static func statusName(_ s: GoalStatus) -> String {
        switch s {
        case .none: return "none"
        case .met: return "met"
        case .close: return "close"
        case .missed: return "missed"
        }
    }

    @Test func goalStatusMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("status")
        #expect(rows.count == 190)
        for row in rows {
            let f = row.input.split(separator: "|").map(String.init)
            let goal: Int? = f[1] == "-" ? nil : Int(f[1])
            #expect(Self.statusName(GoalStatus.of(value: try #require(Int(f[0])), goal: goal)) == row.result,
                    "\(row.input)")
        }
    }

    /// RW:959-963: `goal * 3 / 4` wraps in `Int`; the probe's 715 827 883 and 2 000 000 000 rows pin it.
    @Test func goalStatusThresholdsByHand() {
        #expect(GoalStatus.of(value: 50, goal: 50) == .met)
        #expect(GoalStatus.of(value: 36, goal: 50) == .missed)
        #expect(GoalStatus.of(value: 37, goal: 50) == .close)
        #expect(GoalStatus.of(value: 0, goal: 0) == .none)
        #expect(GoalStatus.of(value: 0, goal: nil) == .none)
        #expect(GoalStatus.of(value: 0, goal: -4) == .none)
        // 2 000 000 000 * 3 wraps to 1 705 032 704 in `Int`, so the "close" threshold is 426 258 176.
        #expect(GoalStatus.of(value: 426_258_175, goal: 2_000_000_000) == .missed)
        #expect(GoalStatus.of(value: 426_258_176, goal: 2_000_000_000) == .close)
        // 715 827 883 * 3 wraps to a negative number: every non-negative value is "close".
        #expect(GoalStatus.of(value: 0, goal: 715_827_883) == .close)
    }

    static func nearText(_ n: NearTermRates) -> String {
        let bars: [String] = n.bars.map { $0.label + "=" + String($0.value) + ":" + statusName($0.status) }
        let line: String = n.goalLine.map { String($0) } ?? "~"
        return "title=" + n.title + ";bars=" + bars.joined(separator: ",") + ";peak=" + String(n.peak) + ";line=" + line
    }

    @Test func nearTermRatesMatchTheJvm() {
        let rows = InfoProbeTable.area("near")
        #expect(rows.count == 190)
        for row in rows {
            let f = row.input.split(separator: "|").map(String.init)
            let stats = ContestStats.of(InfoProbeTable.logs[f[0]] ?? [])
            let now = InfoProbeTable.instant(millis: Int64(f[1])!)
            let goal: Int? = f[2] == "-" ? nil : Int(f[2])
            let panel = RatePanel.nearTerm(stats: stats, now: now, goal: goal)
            #expect(Self.nearText(panel) == row.result, "\(row.input)")
        }
    }

    static func trendText(_ t: TrendView) -> String {
        let points: [String] = t.points.map { $0.clock + "=" + String($0.value) + ":" + statusName($0.status) }
        let grid: [String] = t.gridLabels.map { String($0) }
        let line: String = t.goalLine.map { String($0) } ?? "~"
        let goal: String = t.goal.map { String($0) } ?? "~"
        var text: String = "title=" + t.title + ";scale=" + String(t.scale) + ";grid=" + grid.joined(separator: ",")
        text += ";line=" + line + ";pts=" + points.joined(separator: ",") + ";goal=" + goal
        return text
    }

    @Test func trendMatchesTheJvm() throws {
        let rows = InfoProbeTable.area("trend")
        #expect(rows.count == 570)
        for row in rows {
            let f = row.input.split(separator: "|").map(String.init)
            let stats = ContestStats.of(InfoProbeTable.logs[f[0]] ?? [])
            let now = InfoProbeTable.instant(millis: Int64(f[1])!)
            let minutes = try #require(Int(f[2]))
            let cfg = f[3]
            let start: JavaInstant? = cfg == "nostart" ? nil : InfoProbeTable.contestStart
            let goals = InfoProbeTable.goalSet(cfg == "off" || cfg == "nostart" ? "a" : cfg)
            let show = cfg != "off"
            let view = try RatePanel.trend(stats: stats, now: now, minutes: minutes) { at in
                RatePanel.goal(goals: goals, contestStart: start, showGoals: show, at: at)
            }
            #expect(Self.trendText(view) == row.result, "\(row.input)")
        }
    }

    /// The trend of an empty log is five zero points at epoch-aligned intervals (RW:660-668).
    @Test func trendOfAnEmptyLogByHand() throws {
        let now = InfoProbeTable.instant(millis: InfoProbeTable.baseMillis)
        let view = try RatePanel.trend(stats: ContestStats.of([]), now: now, minutes: 20, goalAt: { _ in nil })
        #expect(view.points.map(\.clock) == ["10:40", "11:00", "11:20", "11:40", "12:00"])
        #expect(view.points.allSatisfy { $0.value == 0 && $0.status == .none })
        #expect(view.scale == 1)
        #expect(view.goalLine == nil)
        #expect(view.title == "Průběh — 20min")
    }

    /// A zero interval is the Java division by zero (before anything else is computed).
    @Test func zeroIntervalThrows() {
        #expect(throws: JavaArithmeticError.self) {
            _ = try RatePanel.trend(stats: ContestStats.of([]), now: .epoch, minutes: 0, goalAt: { _ in nil })
        }
    }

    @Test func goalHelperHonoursTheSwitch() {
        let goals = InfoProbeTable.goalSet("a")
        let at = InfoProbeTable.instant(millis: InfoProbeTable.baseMillis)
        #expect(RatePanel.goal(goals: goals, contestStart: InfoProbeTable.contestStart, showGoals: true, at: at) == 30)
        #expect(RatePanel.goal(goals: goals, contestStart: InfoProbeTable.contestStart, showGoals: false, at: at) == nil)
        // No contest start: the default goal (GoalSet.defaultGoal).
        #expect(RatePanel.goal(goals: goals, contestStart: nil, showGoals: true, at: at) == 50)
    }
}
