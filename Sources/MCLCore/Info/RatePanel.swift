import Foundation

/// How a rate relates to the goal (Kotlin `barColor`, `RW:959-963`): a met goal green, a value within a quarter
/// below the goal orange, a clearly lower one red; without a goal (`nil` or not positive) the base colour.
public enum GoalStatus: Equatable, Sendable {
    /// No goal — the base (primary) colour.
    case none
    /// `value >= goal`.
    case met
    /// `value >= goal * 3 / 4` ("still catchable").
    case close
    /// Below that ("the hour is lost").
    case missed

    /// `goal * 3 / 4` is `Int` arithmetic in Kotlin: it wraps for goals above 715 827 882.
    public static func of(value: Int, goal: Int?) -> GoalStatus {
        guard let goal, goal > 0 else { return .none }
        if value >= goal {
            return .met
        }
        let g = Int32(truncatingIfNeeded: goal)
        let threeQuarters = Int(g &* 3 / 4)
        if value >= threeQuarters {
            return .close
        }
        return .missed
    }
}

/// One column of the left graph.
public struct RateBar: Equatable, Sendable {
    public let label: String
    public let value: Int
    public let status: GoalStatus
}

/// The left graph of the Info window: four rates side by side (`NearTermRates` + `GoalOverlay`, `RW:601-649`).
public struct NearTermRates: Equatable, Sendable {
    /// `QSO/hod` or `QSO/hod — cíl N` (translated); a zero goal is not written.
    public let title: String
    /// Last 10 QSOs, last 100 QSOs, `60m`, and the current clock hour (`<minute>m`).
    public let bars: [RateBar]
    /// The scale: the highest value, raised to the goal, at least 1.
    public let peak: Int
    /// The goal line when it is drawn (`0 < goal <= peak`), else `nil`.
    public let goalLine: Int?
}

/// One point of the trend graph.
public struct TrendPoint: Equatable, Sendable {
    /// The start of the interval (aligned to the epoch).
    public let start: JavaInstant
    /// `HH:mm` (UTC) label under the point.
    public let clock: String
    public let value: Int
    public let status: GoalStatus
}

/// The middle graph of the Info window: the rate in fixed intervals aligned to the hours (`TrendChart`,
/// `RW:660-782`). The last point is the ongoing interval (drawn as an outline, the last segment faded).
public struct TrendView: Equatable, Sendable {
    /// `Průběh — <minutes>min` (translated).
    public let title: String
    public let points: [TrendPoint]
    /// The scale: the highest value, raised to the goal, at least 1.
    public let scale: Int
    /// The labels of the Y axis grid, bottom to top: `scale * step / 4` for `step` in 0...4 (`Int` arithmetic).
    public let gridLabels: [Int]
    /// The goal of the current interval, or `nil` (no goals shown).
    public let goal: Int?
    /// The dashed goal line when it is drawn (`0 < goal <= scale`), else `nil`.
    public let goalLine: Int?
}

/// The rate panel of the Info window of v1.1.1 (`ui/RateWindow.kt`: `NearTermRates`, `GoalOverlay`, `TrendChart`,
/// `barColor`). The numbers come from `ContestStats`; this layer adds the scale, the goal comparison and the
/// texts. Measured through the real `ContestStats` over seeded logs (maintainer-only probe, rows `near`,
/// `trend`, `status`) — the glue itself is a transcription of the composables.
public enum RatePanel {

    /// Rates over the last N QSOs (`RATE_QSOS_SHORT`, `RATE_QSOS_LONG`).
    static let shortQsos = 10
    static let longQsos = 100
    /// The trend has five intervals, the last one ongoing (`TREND_BUCKETS`).
    static let trendBuckets = 5
    /// The Y axis is divided into four parts (`TREND_GRID_STEPS`).
    static let gridSteps = 4

    /// The goal of the hour that contains `at`; `nil` without shown goals (`RW:205-208`). `goalFor` can only throw
    /// at the edges of the `Instant` range (unreachable from a log); it is then treated as "no goal".
    public static func goal(goals: GoalSet, contestStart: JavaInstant?, showGoals: Bool, at: JavaInstant) -> Int? {
        guard showGoals else { return nil }
        guard let value = try? goals.goalFor(contestStart, at) else { return nil }
        return Int(value)
    }

    /// The left graph (`RW:601-626`). `ratePerHour` cannot throw for the fixed one-hour window.
    public static func nearTerm(stats: ContestStats, now: JavaInstant, goal: Int?,
                                translate: Translator = .source) -> NearTermRates {
        let hourStart: Int64 = JavaMath.floorDiv(now.epochSecond, 3600) &* 3600
        let elapsedMinute: Int64 = (now.epochSecond &- hourStart) / 60
        let perHour: Int = (try? stats.ratePerHour(now, .seconds(3600))) ?? 0
        let values: [(String, Int)] = [
            (String(shortQsos), stats.rateForLastQsos(shortQsos)),
            (String(longQsos), stats.rateForLastQsos(longQsos)),
            ("60m", perHour),
            (String(elapsedMinute) + "m", stats.rateThisClockHour(now)),
        ]
        let highest: Int = values.map { $0.1 }.max() ?? 0
        // The goal enters the scale, otherwise its line would run off the graph.
        let peak: Int = max(max(highest, goal ?? 0), 1)
        let bars: [RateBar] = values.map { RateBar(label: $0.0, value: $0.1, status: GoalStatus.of(value: $0.1, goal: goal)) }
        var title: String = translate.translate("QSO/hod")
        if let goal, goal > 0 {
            title = translate.translate("QSO/hod — cíl %s", [.int(goal)])
        }
        var line: Int?
        if let goal, goal > 0, goal <= peak {
            line = goal
        }
        return NearTermRates(title: title, bars: bars, peak: peak, goalLine: line)
    }

    /// The middle graph (`RW:660-782`).
    ///
    /// - Parameters:
    ///   - minutes: the interval length (the options 20, 30, 60 of the settings).
    ///   - goalAt: the goal of the hour containing an instant (`goal(goals:contestStart:showGoals:at:)`).
    /// - Throws: what `ContestStats.trendRates` throws (a zero interval), or `JavaDateTimeException` when an
    ///   interval start leaves the `Instant` range.
    public static func trend(stats: ContestStats, now: JavaInstant, minutes: Int,
                             goalAt: (JavaInstant) -> Int?, translate: Translator = .source) throws -> TrendView {
        let intervalSeconds: Int64 = Int64(minutes) &* 60
        let values: [Int] = try stats.trendRates(now, .seconds(intervalSeconds), trendBuckets)
        let peak: Int = values.max() ?? 0
        // Kotlin `Long / Long` truncates toward zero.
        let currentStart: Int64 = now.epochSecond / intervalSeconds &* intervalSeconds
        let goal: Int? = goalAt(now)
        let scale: Int = max(max(peak, goal ?? 0), 1)

        var points: [TrendPoint] = []
        for (i, value) in values.enumerated() {
            let offset: Int64 = Int64(trendBuckets - 1 - i) &* intervalSeconds
            guard let start = JavaInstant.ofEpochSecond(currentStart &- offset) else {
                throw JavaDateTimeException()
            }
            points.append(TrendPoint(start: start, clock: clockLabel(start), value: value,
                                     status: GoalStatus.of(value: value, goal: goalAt(start))))
        }
        // `scale * step / 4` is `Int` arithmetic in Kotlin.
        let s = Int32(truncatingIfNeeded: scale)
        var grid: [Int] = []
        for step in 0...gridSteps {
            grid.append(Int(s &* Int32(step) / Int32(gridSteps)))
        }
        var line: Int?
        if let goal, goal > 0, goal <= scale {
            line = goal
        }
        return TrendView(title: translate.translate("Průběh — %smin", [.int(minutes)]), points: points, scale: scale,
                         gridLabels: grid, goal: goal, goalLine: line)
    }

    /// `HH:mm` of an instant in UTC (`CLOCK_FORMAT`).
    static func clockLabel(_ instant: JavaInstant) -> String {
        let second: Int64 = instant.epochSecond &- JavaMath.floorDiv(instant.epochSecond, 86_400) &* 86_400
        return JavaLocalDate.twoDigits(second / 3600) + ":" + JavaLocalDate.twoDigits(second / 60 % 60)
    }
}
