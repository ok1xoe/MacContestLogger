import Foundation

extension ContestRuntime {

    /// The score breakdown by band and mode for the Score window (`ContestController.breakdown`): the log is
    /// replayed into a fresh session of the active definition (with the stored tour and bonus stations), so the
    /// result matches the score recomputation. `nil` outside a contest.
    ///
    /// The Kotlin window wraps the call in `runCatching { … }.getOrNull()`, so a score computation error is shown
    /// as "still computing" — callers do `try?`. Like `replayed`, this does not touch the live session and may run
    /// off the owning actor.
    ///
    /// - Throws: a score computation error (`ScoreBreakdown.compute`), like Java.
    public func breakdown(_ qsos: [Qso], now: () -> Date = Date.init) throws(ExpressionError) -> ScoreBreakdown? {
        guard let fresh = freshSession() else { return nil }
        return try ScoreBreakdown.compute(fresh, qsos, now: now)
    }
}
