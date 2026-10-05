/// A contest goal set — the planned number of QSOs for individual hours (Java `goals/GoalSet`). The Info window draws
/// a line in the graphs from it, so the operator immediately sees whether the plan is being met.
///
/// The key is `dhh`, as N1MM introduced it: `d` is the contest day (from 1), `hh` the start of the hour in UTC. For example `222`
/// is the second day of the contest, the hour from 22:00Z. The day is counted by **calendar days** in UTC, not by
/// elapsed hours.
///
/// Rules taken from N1MM:
/// - an empty set or a missing start date → the default goal `defaultGoal`;
/// - an hour without an entry in a non-empty set → 0;
/// - before the start the goal of the first hour of the contest is used;
/// - from `horizonHours` hours after the start the goals are zero.
///
/// Numbers are Java `int` (`Int32`) including wraparound in `key`. The Java `GoalSet` has no `equals` (identity is
/// compared); the Swift one is a value type (`Equatable` by `entries`). The order of `entries` is random in Java
/// (`Map.copyOf`) — it shows nowhere, the writer sorts.
public struct GoalSet: Equatable, Sendable {

    /// The goal used when there are no goals or they cannot be determined.
    public static let defaultGoal: Int32 = 50

    /// After this many hours from the contest start goals no longer make sense.
    public static let horizonHours: Int32 = 96

    /// Goals by key `dhh` — the base for export.
    public let entries: [Int32: Int32]

    private init(_ entries: [Int32: Int32]) {
        self.entries = entries
    }

    /// Java `GoalSet.of(map)`. A `null` value (Java: NPE from `Map.copyOf`) is not allowed by the Swift dictionary.
    public static func of(_ byKey: [Int32: Int32]) -> GoalSet {
        GoalSet(byKey)
    }

    public static func empty() -> GoalSet {
        GoalSet([:])
    }

    /// Key `dhh` for a contest day and a UTC hour — `contestDay * 100 + hourUtc` in Java `int` (wraps).
    public static func key(_ contestDay: Int32, _ hourUtc: Int32) -> Int32 {
        let days: Int32 = contestDay &* 100
        return days &+ hourUtc
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Keys of the hours during which the contest runs — the base for the goal editor. It starts with the full hour in which the
    /// contest began. At the edges of the `Instant` range (a date outside `LocalDate`, a shift outside `Instant`) Java throws
    /// `DateTimeException`, Swift `JavaDateTimeException`.
    public static func hoursOf(_ contestStart: JavaInstant?, _ durationHours: Int32) throws(JavaDateTimeException)
        -> [Int32] {
        guard let contestStart, durationHours > 0 else { return [] }
        let from: Int64 = JavaInstant.floorDiv(contestStart.epochSecond, 3600) * 3600
        let firstDay: Int64 = try day(of: from)
        var keys: [Int32] = []
        keys.reserveCapacity(Int(durationHours))
        for i in 0..<Int64(durationHours) {
            guard let at = JavaInstant.ofEpochSecond(from + i * 3600) else {
                throw JavaDateTimeException()
            }
            let atDay: Int64 = try day(of: at.epochSecond)
            keys.append(key(contestDay(firstDay, atDay), hour(of: at.epochSecond)))
        }
        return keys
    }

    /// Goal for the instant `when` in a contest starting at `contestStart` (rules in the type description).
    public func goalFor(_ contestStart: JavaInstant?, _ when: JavaInstant?) throws(JavaDateTimeException) -> Int32 {
        guard let contestStart, let when else { return Self.defaultGoal }
        // The horizon takes precedence over the default goal: for a contest that ended a week ago the plan has nothing to say.
        guard let horizon = contestStart.plus(seconds: Int64(Self.horizonHours) * 3600) else {
            throw JavaDateTimeException()
        }
        if !(when < horizon) {
            return 0
        }
        if entries.isEmpty {
            return Self.defaultGoal
        }
        let at: JavaInstant = when < contestStart ? contestStart : when
        let startDay: Int64 = try Self.day(of: contestStart.epochSecond)
        let atDay: Int64 = try Self.day(of: at.epochSecond)
        let key: Int32 = Self.key(Self.contestDay(startDay, atDay), Self.hour(of: at.epochSecond))
        return entries[key] ?? 0
    }

    // MARK: - Calendar in UTC (shared with `GoalsFromLog`)

    /// `instant.atZone(UTC).toLocalDate().toEpochDay()`; a date outside `LocalDate` → `JavaDateTimeException`.
    static func day(of epochSecond: Int64) throws(JavaDateTimeException) -> Int64 {
        let instant = JavaInstant(uncheckedSecond: epochSecond, nano: 0)
        return try JavaDateTimeException.utcEpochDay(instant)
    }

    /// `instant.atZone(UTC).getHour()`.
    static func hour(of epochSecond: Int64) -> Int32 {
        let secondOfDay: Int64 = epochSecond - JavaInstant.floorDiv(epochSecond, 86_400) * 86_400
        return Int32(secondOfDay / 3600)
    }

    /// `(int) ChronoUnit.DAYS.between(first, at) + 1` — a `long` truncated to `int`, then `+ 1` with wraparound.
    static func contestDay(_ firstDay: Int64, _ atDay: Int64) -> Int32 {
        let between = Int32(truncatingIfNeeded: atDay - firstDay)
        return between &+ 1
    }
}
