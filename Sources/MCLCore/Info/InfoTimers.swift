import Foundation

/// State of a timer cell: the background the Info window gives it. `none` = no background.
public enum TimerState: Equatable, Sendable {
    case none
    case ok
    case warn
    case over
}

/// One timer of the Info window (Kotlin `Timer(label, value, background)`): the caption, the text value
/// (`nil` = shown as `—`) and the background state.
public struct TimerCell: Equatable, Sendable {
    public let label: String
    public let value: String?
    public let state: TimerState

    public init(label: String, value: String?, state: TimerState) {
        self.label = label
        self.value = value
        self.state = state
    }
}

/// The timers on the right of the Info window of v1.1.1 (`ui/RateWindow.kt`: `Timers` `:784-838`, `OffTimeTimer`
/// `:841-898`, `suffix`, `hm`, `hms`, `elapsed` `:900-948`): the off-time timer in one of five modes, the time on
/// the band and the band change counter. All pure over a `ContestStats` snapshot and an injected `now`.
///
/// Time is `Instant.getEpochSecond()` (whole seconds, `Long` arithmetic wraps). The three formatters are the Kotlin
/// private functions of the same names, measured on the JVM (maintainer-only probe, rows `hm`, `hms`,
/// `elapsed`, `suffix`); the logic that lives inside the `@Composable` functions is a transcription,
/// measured through the real `ContestStats` (rows `offtime`, `onband`, `bandchg`).
public enum InfoTimers {

    /// The rules valid for the chosen category (`OperatingRules.resolve(definition?.operating(), activeCategory)`),
    /// `RW:790-791`.
    public static func rules(definition: ContestDefinition?, category: [String: String]?)
        -> ContestDefinition.Operating? {
        OperatingRules.resolve(definition?.operating, category)
    }

    // MARK: - Off-time timer (RW:841-898)

    /// The off-time timer in the mode chosen in the context menu (`sinceLastQso`, `offTime`, `countUp`, `countDown`,
    /// `cumulativeOff`; any other text behaves as `sinceLastQso`, like the Kotlin `else`).
    ///
    /// - Parameters:
    ///   - rules: the resolved operating rules (`rules(definition:category:)`); only `offTime` is used.
    ///   - contestStart: the contest start (`AppState.contestStartedAt`); `nil` = no cumulative off time.
    public static func offTime(mode: String, stats: ContestStats, now: JavaInstant,
                               rules: ContestDefinition.Operating?, contestStart: JavaInstant?,
                               translate: Translator = .source) -> TimerCell {
        let offRules: ContestDefinition.OffTime? = rules?.offTime
        let start: JavaInstant? = stats.offTimeStart()
        let minMinutes: Int? = offRules?.minimumMinutes
        let required: Int? = offRules?.requiredMinutes
        var offSec: Int64?
        if let start {
            offSec = max(0, now.epochSecond &- start.epochSecond)
        }
        // An ongoing pause reached the minimum — for the modes that show it.
        var breakReached = false
        if let minMinutes, let offSec {
            breakReached = offSec >= Int64(minMinutes) &* 60
        }

        let label: String
        var value: String?
        switch mode {
        case "offTime":
            label = "Off time ↑" + suffix(minMinutes)
            value = offSec.map { hm($0) }
        case "countUp":
            label = "Interval ↑" + suffix(minMinutes)
            value = offSec.map { hm($0) }
        case "countDown":
            // Without a limit there is nothing to count down from (RW:857-860).
            if let minMinutes, let offSec {
                value = hm(max(0, Int64(minMinutes) &* 60 &- offSec))
            }
            label = "Interval ↓" + suffix(minMinutes)
        case "cumulativeOff":
            if let contestStart, let minMinutes {
                let cumulative: Int = stats.cumulativeOffMinutes(contestStart, now, minMinutes)
                value = hm(Int64(cumulative) &* 60)
            }
            label = "Off time celkem" + suffix(required)
        default:
            label = translate.translate("Od posledního QSO")
            if let last = stats.lastQsoAt() {
                value = elapsed(since: last, now: now)
            }
        }

        // For the cumulative mode green means "the required total of pauses is met", not "the ongoing
        // pause reached the minimum" (RW:880-893).
        var cumulativeReached = false
        if mode == "cumulativeOff", let required, let contestStart, let minMinutes {
            cumulativeReached = stats.cumulativeOffMinutes(contestStart, now, minMinutes) >= required
        }
        let ok: Bool
        switch mode {
        case "sinceLastQso": ok = false
        case "cumulativeOff": ok = cumulativeReached
        default: ok = breakReached
        }
        return TimerCell(label: label, value: value, state: ok ? .ok : .none)
    }

    // MARK: - Time on the band (RW:795-818)

    /// The time on the current band, or `nil` when no start of the stay is known. The start is the later of two
    /// instants: when the tuned band last changed in this session (`tunedSince`) and the first QSO after the last
    /// band change in the log.
    ///
    /// - Parameters:
    ///   - band: the tuned band (`AppState.currentBand`); `nil` falls back to the band of the last QSO.
    ///   - tunedSince: when the tuned band last changed in this session (`nil` = not yet).
    ///   - rules: the resolved operating rules; only `bandChange.minimumMinutes` is used.
    public static func onBand(band: Band?, stats: ContestStats, tunedSince: JavaInstant?, now: JavaInstant,
                              rules: ContestDefinition.Operating?, translate: Translator = .source) -> TimerCell? {
        let bandRules: ContestDefinition.BandChange? = rules?.bandChange
        let resolved: Band? = band ?? stats.lastQsoBand()
        let fromLog: JavaInstant? = stats.currentBandRunStart(resolved)
        let candidates: [JavaInstant] = [tunedSince, fromLog].compactMap { $0 }
        guard let bandSince = candidates.max() else { return nil }

        let minMinutes: Int = bandRules?.minimumMinutes ?? 0
        let minSec: Int64 = Int64(minMinutes) &* 60
        let elapsedSec: Int64 = now.epochSecond &- bandSince.epochSecond
        let reached: Bool = minSec > 0 && elapsedSec >= minSec
        let text: String
        if minSec > 0 && !reached {
            // The countdown to the rule being met — until it runs out the band should not be left.
            text = hms(minSec &- elapsedSec)
        } else if minSec == 0 {
            // Without a rule it is only information and the stay can be long: days instead of 3-digit hours.
            text = elapsed(since: bandSince, now: now)
        } else {
            text = hms(elapsedSec)
        }
        let caption: String = translate.translate("Na pásmu %s", [.string(resolved?.adif ?? "")])
        var label: String = KotlinText.trim(caption)
        if minSec > 0 {
            label += " (" + String(minMinutes) + ")"
        }
        return TimerCell(label: label, value: text, state: reached ? .ok : .none)
    }

    // MARK: - Band change counter (RW:820-835)

    /// The counter of band changes in the current UTC hour, or `nil` when the rules have no hourly limit.
    /// `.over` at the limit, `.warn` one below it, `.ok` otherwise.
    public static func bandChanges(stats: ContestStats, now: JavaInstant, rules: ContestDefinition.Operating?,
                                   translate: Translator = .source) -> TimerCell? {
        guard let perHour = rules?.bandChange?.perHour, perHour > 0 else { return nil }
        let used: Int = stats.bandChangesInClockHour(now)
        let state: TimerState
        if used >= perHour {
            state = .over
        } else if used >= perHour - 1 {
            state = .warn
        } else {
            state = .ok
        }
        return TimerCell(label: translate.translate("Změny pásma"), value: String(used) + "/" + String(perHour),
                         state: state)
    }

    // MARK: - Formatters (RW:900-948)

    /// The limit in minutes in brackets, as N1MM writes it into a frame caption (`RW:900`).
    static func suffix(_ minutes: Int?) -> String {
        guard let minutes else { return "" }
        return " (" + String(minutes) + ")"
    }

    /// Hours and minutes — the format of the off-time timers (`RW:928`: `"%d:%02d"`).
    public static func hm(_ seconds: Int64) -> String {
        JavaFormat.format("%d:%02d", .int(Int(seconds / 3600)), .int(Int((seconds % 3600) / 60)))
    }

    /// Hours, minutes and seconds for the short timers (`RW:931-938`); negative values are zero.
    public static func hms(_ seconds: Int64) -> String {
        let s: Int64 = max(0, seconds)
        if s >= 3600 {
            return JavaFormat.format("%d:%02d:%02d", .int(Int(s / 3600)), .int(Int((s % 3600) / 60)),
                                     .int(Int(s % 60)))
        }
        return JavaFormat.format("%d:%02d", .int(Int(s / 60)), .int(Int(s % 60)))
    }

    /// Elapsed time: up to an hour `m:ss`, up to a day `h:mm:ss`, over a day `2 d 5:07` (`RW:944-948`).
    public static func elapsed(since: JavaInstant, now: JavaInstant) -> String {
        let s: Int64 = max(0, now.epochSecond &- since.epochSecond)
        let d: Int64 = s / 86_400
        if d > 0 {
            return JavaFormat.format("%d d %d:%02d", .int(Int(d)), .int(Int((s % 86_400) / 3600)),
                                     .int(Int((s % 3600) / 60)))
        }
        return hms(s)
    }
}
