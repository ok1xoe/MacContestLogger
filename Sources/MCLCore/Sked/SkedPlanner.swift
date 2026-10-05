/// Sked planning (N1MM Sked system), Java `sked/SkedPlanner` v1.1.1: a time entered as `HHmm`
/// is the nearest future such time (today, otherwise tomorrow), `yyyy-MM-dd HHmm` exactly. A sked is
/// "due" a while before its time and a while after it.
///
/// Instants are `JavaInstant` (nanoseconds and years outside `Date`, like the Java `Instant`). Where Java
/// does not catch `DateTimeException` from arithmetic at the edges of the `Instant`/`LocalDate` range,
/// `JavaDateTimeException` is thrown (measured by the maintainer-only probe).
public enum SkedPlanner {

    /// How long in advance to remind about a sked (`LEAD` = 1 min), in seconds.
    public static let leadSeconds: Int64 = 60
    /// How long after its time a sked is still "now" (`GRACE` = 5 min), in seconds.
    public static let graceSeconds: Int64 = 300

    /// The Java `FORMAT` pattern verbatim (`\d`, `\s` ASCII only, the whole input via `matches`).
    private static let format: JavaRegex = {
        do {
            return try JavaRegex("(?:(\\d{4})-(\\d{2})-(\\d{2})\\s+)?(\\d{1,2}):?(\\d{2})")
        } catch {
            preconditionFailure("pevný vzor skedu musí jít zkompilovat: \(error)")
        }
    }()

    /// Sked time from text (after Java `trim()`); `HHmm` = nearest future — today, unless it is
    /// older than `GRACE` before `now`, otherwise tomorrow. Invalid text or date → `nil`.
    ///
    /// Throws like Java for `now` at the range edges: `now` date outside `LocalDate`, `now − GRACE`
    /// or `+ 1 day` outside `Instant`.
    public static func parseTime(_ text: String?, now: JavaInstant) throws(JavaDateTimeException) -> JavaInstant? {
        guard let text, let match = format.wholeMatch(JavaText.trim(text)),
              let hourText = match.group(4), let minuteText = match.group(5),
              let hh = Int64(hourText), let mm = Int64(minuteText) else {
            return nil
        }
        if hh > 23 || mm > 59 {
            return nil
        }
        let secondOfDay: Int64 = hh * 3_600 + mm * 60
        if let yearText = match.group(1) {
            guard let year = Int64(yearText), let monthText = match.group(2), let month = Int64(monthText),
                  let dayText = match.group(3), let day = Int64(dayText),
                  isValidDate(year: year, month: month, day: day) else {
                return nil
            }
            let epochDay: Int64 = JavaLocalDate.epochDay(year: year, month: month, day: day)
            return JavaInstant(uncheckedSecond: epochDay * 86_400 + secondOfDay, nano: 0)
        }
        let epochDay: Int64 = try JavaDateTimeException.utcEpochDay(now)
        let today = JavaInstant(uncheckedSecond: epochDay * 86_400 + secondOfDay, nano: 0)
        guard let earliest = now.plus(seconds: -graceSeconds) else {
            throw JavaDateTimeException()
        }
        guard today < earliest else {
            return today
        }
        guard let tomorrow = today.plus(seconds: 86_400) else {
            throw JavaDateTimeException()
        }
        return tomorrow
    }

    /// Sked time (`Instant.parse(atUtc)`); invalid → `nil`.
    public static func at(_ sked: SkedEntry) -> JavaInstant? {
        JavaInstant.parseIsoInstant(sked.atUtc)
    }

    /// Skeds by time, those without a valid time at the end (Java `Instant.MAX`); stable.
    public static func sorted(_ skeds: [SkedEntry]) -> [SkedEntry] {
        let keyed: [(index: Int, at: JavaInstant, sked: SkedEntry)] = skeds.enumerated().map {
            (index: $0.offset, at: at($0.element) ?? maxInstant, sked: $0.element)
        }
        let ordered = keyed.sorted { left, right in
            left.at != right.at ? left.at < right.at : left.index < right.index
        }
        return ordered.map(\.sked)
    }

    /// Is the sked "due" — from `LEAD` before its time to `GRACE` after it (both bounds inclusive)?
    /// A sked without a valid time is not. `t − LEAD` outside `Instant` throws (Java does not catch).
    public static func isDue(_ sked: SkedEntry, now: JavaInstant) throws(JavaDateTimeException) -> Bool {
        guard let time = at(sked) else { return false }
        guard let from = time.plus(seconds: -leadSeconds) else { throw JavaDateTimeException() }
        if now < from {
            return false
        }
        guard let until = time.plus(seconds: graceSeconds) else { throw JavaDateTimeException() }
        return !(until < now)
    }

    /// Expired sked (more than `GRACE` after its time). `t + GRACE` outside `Instant` throws (Java does not catch).
    public static func isPast(_ sked: SkedEntry, now: JavaInstant) throws(JavaDateTimeException) -> Bool {
        guard let time = at(sked) else { return false }
        guard let until = time.plus(seconds: graceSeconds) else { throw JavaDateTimeException() }
        return until < now
    }

    /// Nearest sked that has not yet expired (lazily in `sorted` order like the Java stream
    /// with `findFirst` — expiry is checked only up to the first match).
    public static func next(_ skeds: [SkedEntry], now: JavaInstant) throws(JavaDateTimeException) -> SkedEntry? {
        for sked in sorted(skeds) where at(sked) != nil {
            if !(try isPast(sked, now: now)) {
                return sked
            }
        }
        return nil
    }

    /// Java `Instant.MAX` (+1000000000-12-31T23:59:59.999999999Z).
    private static let maxInstant = JavaInstant(uncheckedSecond: JavaInstant.maxSecond, nano: 999_999_999)

    /// `LocalDate.of(year, month, day)` without an exception (a 4-digit year is always in range).
    private static func isValidDate(year: Int64, month: Int64, day: Int64) -> Bool {
        guard month >= 1, month <= 12, day >= 1 else { return false }
        let lengths: [Int64] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let length: Int64 = month == 2 && JavaLocalDate.isLeap(year) ? 29 : lengths[Int(month - 1)]
        return day <= length
    }
}
