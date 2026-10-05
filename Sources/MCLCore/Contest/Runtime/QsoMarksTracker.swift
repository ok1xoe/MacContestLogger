import Foundation

/// The marks of the log table (`QsoMarks`) kept up to date while QSOs are logged, without replaying the whole
/// logbook on every QSO.
///
/// Kotlin recomputes the marks with `QsoMarks.compute(freshSession, logbook)` whenever the logbook changes. The
/// replay is chronological, so a QSO logged after all the others is the last step of that replay: replaying just
/// that QSO into the session that already holds the previous replay gives the same mark the full recompute would.
/// The tracker owns such a session (built from a fresh one) and does exactly that — the same `ContestReplay` step
/// and the same label lookup as `QsoMarks.compute`, so the two cannot drift.
///
/// `append` returns `false` (and changes nothing) whenever a full recompute is needed instead: a QSO earlier than the
/// last replayed one, a QSO without a time (the replay puts it last and times it at "now"), anything appended after
/// such a QSO, an id already seen (an edit) and a tombstone (a delete). The caller then recomputes off the main
/// thread with `recomputed(fresh:qsos:now:)` (or `QsoMarks.compute`).
///
/// A class, because the replay session it owns is a reference: the tracker has one owner (the log model on the main
/// actor) that appends to it, and a full recompute replaces it as a whole. It is `@unchecked Sendable` only so that
/// `recomputed(...)` can be built off the main thread and handed over; it is not synchronised and must not be used
/// from two threads at once.
public final class QsoMarksTracker: @unchecked Sendable {

    /// QSO id → mark, equal to `QsoMarks.compute(fresh, logbook)` for the QSOs appended so far.
    public private(set) var marks: [Int64: QsoMarks.Mark] = [:]

    private let session: ContestSession
    private var labels: QsoMarks.Labels
    /// Time of the latest QSO in the replay order; `nil` = nothing timed yet.
    private var lastAt: Date?
    /// A QSO without a time is in the replay: it sorts last, so nothing can be appended after it.
    private var closed = false
    /// Ids of all QSOs seen (also X-QSOs and QSOs that were skipped).
    private var seenIds: Set<Int64> = []

    /// An empty tracker over a fresh session of the contest (the marks of an empty logbook).
    public init(fresh: ContestSession) {
        session = fresh
        labels = QsoMarks.Labels(session: fresh)
    }

    /// The full recompute: replays the logbook into the fresh session and keeps it for further appends. The marks are
    /// those of `QsoMarks.compute(fresh, qsos, now:)`. Blocking — run off the main thread.
    public static func recomputed(fresh: ContestSession, qsos: [Qso], now: () -> Date = Date.init) -> QsoMarksTracker {
        let tracker = QsoMarksTracker(fresh: fresh)
        var labels = tracker.labels
        var marks: [Int64: QsoMarks.Mark] = [:]
        _ = ContestReplay.replay(fresh, qsos, now: now) { q, r in
            guard let id = q.id else { return }
            marks[id] = QsoMarks.mark(of: r, labels: &labels)
        }
        tracker.labels = labels
        tracker.marks = marks
        for q in ContestReplay.ordered(qsos) {
            tracker.noteOrder(q)
        }
        for q in qsos {
            if let id = q.id {
                tracker.seenIds.insert(id)
            }
        }
        return tracker
    }

    /// Takes a newly logged QSO into the marks: replays it into the tracker's session and records its mark.
    ///
    /// - Returns: `true` when the marks equal a full recompute over the logbook with this QSO; `false` when the QSO
    ///   does not extend the replay at its end (earlier time, no time, an edit or a delete) — nothing changed and
    ///   the caller recomputes.
    @discardableResult
    public func append(_ qso: Qso, now: () -> Date = Date.init) -> Bool {
        if qso.deleted || closed {
            return false
        }
        if let id = qso.id, seenIds.contains(id) {
            return false
        }
        if !qso.xqso {
            guard let at = qso.timestampUtc else { return false }
            if let lastAt, at < lastAt {
                return false
            }
        }
        if let id = qso.id {
            seenIds.insert(id)
        }
        if qso.xqso {
            return true // not replayed and not marked
        }
        noteOrder(qso)
        var labels = self.labels
        var mark: QsoMarks.Mark?
        _ = ContestReplay.replay(session, [qso], now: now) { _, r in
            mark = QsoMarks.mark(of: r, labels: &labels)
        }
        self.labels = labels
        if let id = qso.id, let mark {
            marks[id] = mark
        }
        return true
    }

    /// Advances the replay-order watermark by a QSO that the replay includes (not deleted, not an X-QSO).
    private func noteOrder(_ qso: Qso) {
        guard let at = qso.timestampUtc else {
            closed = true
            return
        }
        if lastAt.map({ at > $0 }) ?? true {
            lastAt = at
        }
    }
}
