import Foundation

/// Guarding the operating rules when writing a QSO (DXLog „Station type"): the N-minutes rule
/// on a band, the limit of band changes per hour and, for a MULT station, only new multipliers.
/// Mirrors Java `contest.engine.OperatingGuard` (a `final class` with a private
/// constructor — a stateless utility, hence a caseless enum, the same pattern as
/// `AppPaths`/`WindowPlacement`).
///
/// `StationType` and `Enforcement` are shared with `ClusterConfig`; `check` runs over
/// `ContestStats`. Evaluating rules by category is `OperatingRules.resolve`.
public enum OperatingGuard {

    /// Station type in multi-op: `RUN` (normal operation) or `MULT` (only new multipliers).
    /// Mirrors `OperatingGuard.StationType` — no `@JsonValue` annotation in Java,
    /// so Jackson serializes by constant name.
    public enum StationType: String, Codable, Equatable, Sendable {
        case none = "NONE"
        case run = "RUN"
        case mult = "MULT"
    }

    /// What to do on a violation: nothing, just warn, or block the write (Ctrl+Alt+Enter
    /// gets through). Mirrors `OperatingGuard.Enforcement` — likewise without `@JsonValue`.
    public enum Enforcement: String, Codable, Equatable, Sendable {
        case off = "OFF"
        case warn = "WARN"
        case block = "BLOCK"
    }

    /// Checks the QSO being written. Mirrors Java `OperatingGuard.check`.
    ///
    /// - Parameters:
    ///   - stats: QSOs of this station
    ///   - rules: band-change rules for the category (may be `nil`)
    ///   - newBand: band of the QSO being written
    ///   - newMultiplier: whether the QSO brings a new multiplier
    /// - Returns: a description of the violation, or `nil`
    ///
    /// The N-minutes rule is measured from `currentBandRunStart(last)`, otherwise from the first QSO, otherwise from `now`;
    /// `Duration.toMinutes` truncates toward zero, so `now` before the start of the stay gives a negative „only so far".
    /// The texts are Java `String.format` (only `%d`/`%s`, locale-independent for ASCII digits).
    public static func check(_ stats: ContestStats, _ rules: ContestDefinition.BandChange?, _ newBand: Band?,
                             _ now: JavaInstant, _ type: StationType, _ newMultiplier: Bool) -> String? {
        violation(stats, rules, newBand, now, type, newMultiplier)?.czech
    }

    /// `check` as a translatable message (the Czech key and its values; `czech` is the Java text).
    public static func violation(_ stats: ContestStats, _ rules: ContestDefinition.BandChange?, _ newBand: Band?,
                                 _ now: JavaInstant, _ type: StationType, _ newMultiplier: Bool) -> ContestMessage? {
        if type == .mult && !newMultiplier {
            return ContestMessage("stanice MULT smí zapsat jen nový násobič")
        }
        guard let rules, let newBand else {
            return nil
        }
        guard let last = stats.lastQsoBand(), last != newBand else {
            return nil
        }
        if let min = rules.minimumMinutes, min > 0 {
            let start: JavaInstant = stats.currentBandRunStart(last) ?? stats.firstQsoAt() ?? now
            let elapsed: Int64 = RateReports.minutesBetween(start, now)
            let limit = Int64(min)
            if elapsed < limit {
                let remaining: Int64 = limit &- elapsed
                return ContestMessage("pravidlo %s minut: na %s teprve %s min (zbývá %s)", .int(min), .string(last.adif),
                                      .int(Int(elapsed)), .int(Int(remaining)))
            }
        }
        if let perHour = rules.perHour, perHour > 0 {
            let used: Int = stats.bandChangesInClockHour(now)
            if used + 1 > perHour {
                return ContestMessage("limit změn pásma: v této hodině už %s/%s", .int(used), .int(perHour))
            }
        }
        return nil
    }
}
