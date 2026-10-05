/// Deriving goals from an earlier log — a plan for next year based on what went well last time (Java
/// `goals/GoalsFromLog`, in N1MM "Import Goals from Log").
///
/// The goal of an hour is the number of QSOs made in it. QSOs before the contest start, deleted (tombstones) and without
/// a time are not counted; a QSO without a band is counted in the total, not in the band filter.
public enum GoalsFromLog {

    /// - Parameters:
    ///   - contestStart: start of the contest the log comes from (`nil` → an empty set)
    ///   - band: only this band, or `nil` for all
    /// - Throws: `JavaDateTimeException` only at the edges of the `Instant` range (a start or QSO time with a date
    ///   outside `LocalDate`) like Java; unreachable from a log with millisecond times.
    public static func derive(_ qsos: [Qso], _ contestStart: JavaInstant?, _ band: Band?)
        throws(JavaDateTimeException) -> GoalSet {
        guard let contestStart, !qsos.isEmpty else { return GoalSet.empty() }
        var byKey: [Int32: Int32] = [:]
        for q in qsos {
            guard !q.deleted, let timestamp = q.timestampUtc else { continue }
            if let band, q.band != band {
                continue
            }
            let at = JavaInstant(date: timestamp)
            if at < contestStart {
                continue
            }
            let startDay: Int64 = try GoalSet.day(of: contestStart.epochSecond)
            let atDay: Int64 = try GoalSet.day(of: at.epochSecond)
            let key: Int32 = GoalSet.key(GoalSet.contestDay(startDay, atDay), GoalSet.hour(of: at.epochSecond))
            byKey[key, default: 0] &+= 1
        }
        return GoalSet.of(byKey)
    }
}
