import Foundation

/// Immutable snapshot of the rate computed from the log: the rate in four ways like the N1MM Info window, the sliding
/// rate trend and the base for timers (last QSO, band change). Port of
/// `stats/ContestStats.java` (Java v1.1.1).
///
/// The snapshot is a pure computation over values (`Sendable`), so it can be computed off the main thread.
/// Deleted QSOs and records without a time or band do not enter the statistics.
///
/// Java arithmetic is kept literally (measured by the maintainer-only probe):
/// - times are `Instant.getEpochSecond()` (rounding toward −∞, even before 1970), window lengths
///   `Duration.getSeconds()` (also toward −∞, `0.5 s` → 0);
/// - `long` wraps (`&+`, `&-`, `&*`), `(int)` takes the low 32 bits, `/` truncates toward zero;
/// - windows are `(from, to]` (`countBetween`), trend columns `[from, to)`;
/// - a zero window or interval length (even `0.5 s`) is a Java `ArithmeticException: / by zero`
///   → `JavaArithmeticError`; a negative column count in `trendRates` is
///   `IllegalArgumentException: Illegal Capacity: <n>` (from `new ArrayList<>(count)`)
///   → `JavaIllegalArgumentError` — but only after the division, so a zero interval wins.
public struct ContestStats: Equatable, Sendable {

    /// QSO times in epoch seconds, ascending.
    private let times: [Int64]
    /// QSO bands in the same order as `times`.
    private let bands: [Band]
    /// The full instant of the last QSO in sort order (the sort compares sub-second parts too); `nil` = empty.
    private let lastAt: JavaInstant?

    private init(times: [Int64], bands: [Band], lastAt: JavaInstant?) {
        self.times = times
        self.bands = bands
        self.lastAt = lastAt
    }

    /// Computes the snapshot from the log. The sort by time is stable (Java `List.sort`): QSOs with an
    /// equal time stay in input order, so the "last band" is the one written later.
    public static func of(_ qsos: [Qso]) -> ContestStats {
        var usable: [(at: JavaInstant, band: Band)] = []
        for q in qsos where !q.deleted {
            guard let date = q.timestampUtc, let band = q.band else { continue }
            usable.append((at: JavaInstant(date: date), band: band))
        }
        var order: [Int] = Array(usable.indices)
        order.sort { (a: Int, b: Int) -> Bool in
            let ta: JavaInstant = usable[a].at
            let tb: JavaInstant = usable[b].at
            if ta != tb {
                return ta < tb
            }
            return a < b
        }
        let times: [Int64] = order.map { (i: Int) -> Int64 in usable[i].at.epochSecond }
        let bands: [Band] = order.map { (i: Int) -> Band in usable[i].band }
        let lastAt: JavaInstant? = order.last.map { (i: Int) -> JavaInstant in usable[i].at }
        return ContestStats(times: times, bands: bands, lastAt: lastAt)
    }

    /// The snapshot with one more QSO, without sorting the log again: `ContestStats.of(xs + [qso]) ==
    /// ContestStats.of(xs).appending(qso)` whenever the result is not `nil`.
    ///
    /// A QSO the statistics ignore (deleted, without a time or band) returns the snapshot unchanged. A QSO at or after
    /// the last one is appended (an equal time stays after the earlier QSO, as the stable sort keeps it). A QSO
    /// earlier than the last one returns `nil` — it would sort into the middle, so the caller recomputes with `of`.
    ///
    /// For appends only: it cannot see an edit or a delete (an edited QSO is accepted as a new one), so after those
    /// the caller recomputes with `of`.
    public func appending(_ qso: Qso) -> ContestStats? {
        guard !qso.deleted, let date = qso.timestampUtc, let band = qso.band else {
            return self
        }
        let at = JavaInstant(date: date)
        if let lastAt, at < lastAt {
            return nil
        }
        var newTimes: [Int64] = times
        newTimes.append(at.epochSecond)
        var newBands: [Band] = bands
        newBands.append(band)
        return ContestStats(times: newTimes, bands: newBands, lastAt: at)
    }

    /// Rate from the last `n` QSOs (N1MM "last 10 / last 100 QSO rate"): `m` QSOs span
    /// `m-1` gaps. Under two QSOs or with equal times 0.
    public func rateForLastQsos(_ n: Int) -> Int {
        let m: Int = Swift.min(n, times.count)
        if m < 2 {
            return 0
        }
        let span: Int64 = times[times.count - 1] &- times[times.count - m]
        if span <= 0 {
            return 0
        }
        let gaps = Int64(m - 1) &* 3600
        return Self.int(gaps / span)
    }

    /// Rate in QSOs per hour: the number of QSOs in the window `(now − window, now]` scaled to an hour.
    /// A window shorter than a second (even zero) is a Java division by zero.
    public func ratePerHour(_ now: JavaInstant, _ window: Duration) throws(JavaArithmeticError) -> Int {
        let to: Int64 = now.epochSecond
        let seconds: Int64 = Self.javaSeconds(window)
        let count = Int64(countBetween(to &- seconds, to))
        return Self.int(try Self.divide(count &* 3600, seconds))
    }

    /// Rate since the start of the current UTC hour; on the full hour (zero elapsed time) 0.
    public func rateThisClockHour(_ now: JavaInstant) -> Int {
        let hourStart: Int64 = JavaMath.floorDiv(now.epochSecond, 3600) &* 3600
        let elapsed: Int64 = now.epochSecond &- hourStart
        if elapsed <= 0 {
            return 0
        }
        // countBetween is open on the left, hence a second earlier — a QSO on the full hour belongs to it.
        let count = Int64(countBetween(hourStart &- 1, now.epochSecond))
        return Self.int(count &* 3600 / elapsed)
    }

    /// Rate trend (the right graph of the N1MM Info window): `count` intervals of length `interval` aligned
    /// to the epoch, from the oldest; the last (ongoing) one is extrapolated from the elapsed part. The interval
    /// is `[start, end)`.
    ///
    /// Throws `JavaArithmeticError("/ by zero")` for an interval shorter than a second and
    /// `JavaIllegalArgumentError("Illegal Capacity: <count>")` for a negative `count`.
    public func trendRates(_ now: JavaInstant, _ interval: Duration, _ count: Int) throws -> [Int] {
        let len: Int64 = Self.javaSeconds(interval)
        let nowSec: Int64 = now.epochSecond
        if len == 0 {
            throw JavaArithmeticError(message: "/ by zero")
        }
        let currentStart: Int64 = JavaMath.floorDiv(nowSec, len) &* len
        if count < 0 {
            throw JavaIllegalArgumentError(message: "Illegal Capacity: " + String(count))
        }
        var out: [Int] = []
        out.reserveCapacity(count)
        for i in stride(from: count - 1, through: 0, by: -1) {
            let start: Int64 = currentStart &- Int64(i) &* len
            let end: Int64 = i == 0 ? nowSec : start &+ len
            let elapsed: Int64 = end &- start
            if elapsed <= 0 {
                out.append(0)
                continue
            }
            let qsos = Int64(countInHalfOpen(start, end))
            out.append(Self.int(qsos &* 3600 / elapsed))
        }
        return out
    }

    /// Time of the last QSO.
    public func lastQsoAt() -> JavaInstant? {
        times.last.map { JavaInstant(uncheckedSecond: $0, nano: 0) }
    }

    /// Time of the first QSO.
    public func firstQsoAt() -> JavaInstant? {
        times.first.map { JavaInstant(uncheckedSecond: $0, nano: 0) }
    }

    /// Band of the last QSO.
    public func lastQsoBand() -> Band? {
        bands.last
    }

    /// Time of the last QSO on a band **other** than `band` (Java `null` = every band is different).
    public func lastQsoOnOtherBandAt(_ band: Band?) -> JavaInstant? {
        for i in stride(from: times.count - 1, through: 0, by: -1) where bands[i] != band {
            return JavaInstant(uncheckedSecond: times[i], nano: 0)
        }
        return nil
    }

    /// Start of the off-time pause — the start of the minute following the last QSO. `nil` outside the
    /// `Instant` range (Java `DateTimeException`; unreachable from the log — the QSO time carries a `Date` with ms).
    public func offTimeStart() -> JavaInstant? {
        guard let last = times.last else { return nil }
        let minute: Int64 = JavaMath.floorDiv(last, 60) &* 60
        return JavaInstant.ofEpochSecond(minute &+ 60)
    }

    /// Cumulative off time in minutes: pauses from `contestStart` to `now` at least
    /// `minimumMinutes` long, including an ongoing one.
    public func cumulativeOffMinutes(_ contestStart: JavaInstant, _ now: JavaInstant, _ minimumMinutes: Int) -> Int {
        let min: Int64 = Int64(JavaMath.l2i(Int64(minimumMinutes))) &* 60
        let from: Int64 = contestStart.epochSecond
        let to: Int64 = now.epochSecond
        var sum: Int64 = 0
        var previous: Int64 = from
        for t in times {
            if t <= from {
                previous = Swift.max(previous, t)
                continue
            }
            if t > to {
                break
            }
            let gap: Int64 = t &- previous
            if gap >= min {
                sum = sum &+ gap
            }
            previous = t
        }
        let running: Int64 = to &- previous
        if running >= min {
            sum = sum &+ running
        }
        return Self.int(sum / 60)
    }

    /// First QSO of the current stay on band `band` (right after the last band change). Empty
    /// if `band` was not worked last or if no band change has happened yet.
    public func currentBandRunStart(_ band: Band?) -> JavaInstant? {
        var i: Int = times.count - 1
        if i < 0 || bands[i] != band {
            return nil
        }
        while i >= 0 && bands[i] == band {
            i -= 1
        }
        if i < 0 {
            return nil
        }
        return JavaInstant(uncheckedSecond: times[i + 1], nano: 0)
    }

    /// Number of band changes in the current UTC hour (decided by the time of the later QSO of the pair).
    public func bandChangesInClockHour(_ now: JavaInstant) -> Int {
        let hourStart: Int64 = JavaMath.floorDiv(now.epochSecond, 3600) &* 3600
        let to: Int64 = now.epochSecond
        var changes = 0
        for i in times.indices.dropFirst() where times[i] >= hourStart && times[i] <= to && bands[i] != bands[i - 1] {
            changes += 1
        }
        return changes
    }

    // MARK: - Helpers

    /// Number of QSOs in `[from, to)` — the boundary belongs to the newer interval.
    private func countInHalfOpen(_ from: Int64, _ to: Int64) -> Int {
        countBetween(from &- 1, to &- 1)
    }

    /// Number of QSOs in `(from, to]`.
    private func countBetween(_ from: Int64, _ to: Int64) -> Int {
        upperBound(to) - upperBound(from)
    }

    /// Index of the first time greater than `value` (= the number of times `<= value`).
    private func upperBound(_ value: Int64) -> Int {
        var low = 0
        var high: Int = times.count
        while low < high {
            let mid: Int = (low + high) / 2
            if times[mid] <= value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// `Duration.getSeconds()`: whole seconds rounded toward −∞ (`-0.5 s` → −1).
    static func javaSeconds(_ duration: Duration) -> Int64 {
        let parts: (seconds: Int64, attoseconds: Int64) = duration.components
        return parts.attoseconds < 0 ? parts.seconds &- 1 : parts.seconds
    }

    /// Java `long / long`: zero → `ArithmeticException: / by zero`, `MIN / -1` wraps.
    static func divide(_ a: Int64, _ b: Int64) throws(JavaArithmeticError) -> Int64 {
        if b == 0 {
            throw JavaArithmeticError(message: "/ by zero")
        }
        return a.dividedReportingOverflow(by: b).partialValue
    }

    /// `(int) long`.
    static func int(_ value: Int64) -> Int {
        Int(JavaMath.l2i(value))
    }
}
