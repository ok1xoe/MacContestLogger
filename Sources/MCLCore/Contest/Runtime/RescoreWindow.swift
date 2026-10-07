import Foundation

/// „Přepočítat posledních N hodin": which QSOs a partial rescore covers.
///
/// A score depends on the QSOs before it (the first QSO with a station is the one that counts, the first with a
/// multiplier gets it), so a partial rescore still replays the whole log into a fresh session — the QSOs before the
/// window only set the context. What the window limits is what is rescored and written: the QSOs inside it are the ones
/// counted in the report and the ones whose missing country is filled in. The earlier QSOs are never written.
public enum RescoreWindow {

    /// A year: more is not a window.
    public static let maxHours = 24 * 365

    /// The hours typed into the prompt: a whole number from 1 to `maxHours`, surrounding blanks ignored.
    public static func parseHours(_ text: String) -> Int? {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), let hours = Int(trimmed),
              (1...maxHours).contains(hours) else {
            return nil
        }
        return hours
    }

    /// The start of the window: `hours` before `now`.
    public static func cutoff(hours: Int, now: Date) -> Date {
        now.addingTimeInterval(-TimeInterval(hours) * 3600)
    }

    /// A QSO is in the window from `since` on; one without a time is replayed at the time of the replay, so it is in.
    public static func contains(_ qso: Qso, since: Date) -> Bool {
        qso.timestampUtc.map { $0 >= since } ?? true
    }

    /// The counted (not deleted, not X-QSO) QSOs in the window.
    public static func count(_ qsos: [Qso], since: Date) -> Int {
        qsos.filter { !$0.deleted && !$0.xqso && contains($0, since: since) }.count
    }
}

extension ContestReplay {

    /// One replayed QSO of the window with what the session made of it.
    public struct WindowResult: Sendable {
        public let qso: Qso
        public let result: ContestSession.LogResult
    }

    /// A replay of the whole log with the results of the QSOs in the window kept.
    public struct WindowOutcome: Sendable {
        /// The complete replay (its session is what the application adopts, as after a full rescore).
        public let outcome: Outcome
        /// The window's QSOs in replay order.
        public let window: [WindowResult]
        /// QSOs in the window that could not be replayed.
        public let skippedInWindow: Int
    }

    /// Replays all `qsos` (the QSOs before `since` set the context: dupes, first multipliers) and keeps the result of
    /// every QSO from `since` on. Those results equal the ones of a full replay by construction.
    public static func replayWindow(_ fresh: ContestSession, _ qsos: [Qso], since: Date,
                                    now: () -> Date = Date.init) -> WindowOutcome {
        var window: [WindowResult] = []
        let outcome = replay(fresh, qsos, now: now) { qso, result in
            if RescoreWindow.contains(qso, since: since) {
                window.append(WindowResult(qso: qso, result: result))
            }
        }
        let skipped: Int = outcome.skips.filter { RescoreWindow.contains($0.qso, since: since) }.count
        return WindowOutcome(outcome: outcome, window: window, skippedInWindow: skipped)
    }
}
