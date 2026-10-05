import Foundation

/// Operating reports (N1MM Rate reports, DXLog Statistics): best rate in a window, breaks
/// (off-times) and Run streaks on one frequency. Port of `stats/RateReports.java` (Java v1.1.1).
///
/// Times are whole QSO instants (`JavaInstant(date:)`, log milliseconds without loss), not epoch
/// seconds as in `ContestStats`. Integer arithmetic as in Java (`int` = `Int32`, wraps).
public enum RateReports {

    /// Best window: start, end (last QSO) and QSO count.
    public struct BestRate: Equatable, Sendable {
        public let start: JavaInstant
        public let end: JavaInstant
        public let qsos: Int
        public let windowMinutes: Int

        public init(start: JavaInstant, end: JavaInstant, qsos: Int, windowMinutes: Int) {
            self.start = start
            self.end = end
            self.qsos = qsos
            self.windowMinutes = windowMinutes
        }

        /// Rate scaled to an hour (`int` arithmetic). A window of 0 minutes is a Java
        /// `ArithmeticException: / by zero` (measured: `bestRate(qsos, 0)` returns a window with 0 QSOs).
        public func perHour() throws(JavaArithmeticError) -> Int {
            let window: Int32 = JavaMath.l2i(Int64(windowMinutes))
            if window == 0 {
                throw JavaArithmeticError(message: "/ by zero")
            }
            let scaled: Int32 = JavaMath.l2i(Int64(qsos)) &* 60
            return Int(scaled.dividedReportingOverflow(by: window).partialValue)
        }
    }

    /// Break between two QSOs.
    public struct OffTime: Equatable, Sendable {
        public let from: JavaInstant
        public let to: JavaInstant

        public init(from: JavaInstant, to: JavaInstant) {
            self.from = from
            self.to = to
        }

        /// `Duration.between(from, to).toMinutes()`.
        public func minutes() -> Int64 {
            RateReports.minutesBetween(from, to)
        }
    }

    /// Run streak on one band and frequency.
    public struct Run: Equatable, Sendable {
        public let start: JavaInstant
        public let end: JavaInstant
        public let band: String
        public let freqHz: Int
        public let qsos: Int

        public init(start: JavaInstant, end: JavaInstant, band: String, freqHz: Int, qsos: Int) {
            self.start = start
            self.end = end
            self.band = band
            self.freqHz = freqHz
            self.qsos = qsos
        }

        /// Length in minutes, at least 1.
        public func minutes() -> Int64 {
            Swift.max(1, RateReports.minutesBetween(start, end))
        }

        /// `(int) (qsos * 60 / minutes())` — product in `int`, quotient in `long`.
        public func perHour() -> Int {
            let scaled = Int64(JavaMath.l2i(Int64(qsos)) &* 60)
            return Int(JavaMath.l2i(scaled / minutes()))
        }
    }

    /// The frequency of a streak may drift from the **first** QSO of the streak by at most this much (fine tuning).
    static let runFreqToleranceHz: Int = 2_000
    /// A longer pause (strictly more than 10 min) ends the streak.
    static let runMaxGapSeconds: Int64 = 600

    private struct Timed {
        let at: JavaInstant
        let qso: Qso
    }

    /// Non-deleted QSOs with a time, stably by time.
    private static func timed(_ qsos: [Qso]) -> [Timed] {
        var out: [Timed] = []
        for q in qsos where !q.deleted {
            guard let date = q.timestampUtc else { continue }
            out.append(Timed(at: JavaInstant(date: date), qso: q))
        }
        var order: [Int] = Array(out.indices)
        order.sort { (a: Int, b: Int) -> Bool in
            let ta: JavaInstant = out[a].at
            let tb: JavaInstant = out[b].at
            if ta != tb {
                return ta < tb
            }
            return a < b
        }
        return order.map { (i: Int) -> Timed in out[i] }
    }

    /// The most QSOs in any window of length `windowMinutes` (two pointers; on a tie the
    /// first window wins). Empty log → `nil`.
    public static func bestRate(_ qsos: [Qso], _ windowMinutes: Int) -> BestRate? {
        let t: [Timed] = timed(qsos)
        if t.isEmpty {
            return nil
        }
        let window: Int64 = Int64(JavaMath.l2i(Int64(windowMinutes))) &* 60
        var best = 0
        var bestStart = 0
        var bestEnd = 0
        var j = 0
        for i in t.indices {
            let start: JavaInstant = t[i].at
            // `t[j].isBefore(start.plus(w))` ⇔ whole seconds from `start` (toward −∞) < `w`.
            while j < t.count && floorSeconds(start, t[j].at) < window {
                j += 1
            }
            if j - i > best {
                best = j - i
                bestStart = i
                bestEnd = j - 1
            }
        }
        return BestRate(start: t[bestStart].at, end: t[bestEnd].at, qsos: best, windowMinutes: windowMinutes)
    }

    /// Breaks of at least `minMinutes` between consecutive QSOs.
    public static func offTimes(_ qsos: [Qso], _ minMinutes: Int) -> [OffTime] {
        let t: [Timed] = timed(qsos)
        var out: [OffTime] = []
        for i in t.indices.dropFirst() {
            let a: JavaInstant = t[i - 1].at
            let b: JavaInstant = t[i].at
            if minutesBetween(a, b) >= Int64(minMinutes) {
                out.append(OffTime(from: a, to: b))
            }
        }
        return out
    }

    /// Contiguous Run streaks of QSOs on the same band and frequency (at least `minQsos` QSOs).
    public static func runs(_ qsos: [Qso], _ minQsos: Int) -> [Run] {
        var out: [Run] = []
        var first: Timed?
        var last: Timed?
        var count = 0
        for item in timed(qsos) {
            let q: Qso = item.qso
            let run: Bool = q.runMode == .run && q.band != nil
            var continues = false
            if run, let head = first, let tail = last, q.band == tail.qso.band {
                continues = javaAbs(q.freqHz &- head.qso.freqHz) <= runFreqToleranceHz
                    && withinMaxGap(tail.at, item.at)
            }
            if continues {
                last = item
                count += 1
                continue
            }
            if let head = first, let tail = last, count >= minQsos {
                out.append(makeRun(head, tail, count))
            }
            first = run ? item : nil
            last = run ? item : nil
            count = run ? 1 : 0
        }
        if let head = first, let tail = last, count >= minQsos {
            out.append(makeRun(head, tail, count))
        }
        return out
    }

    private static func makeRun(_ first: Timed, _ last: Timed, _ count: Int) -> Run {
        Run(start: first.at, end: last.at, band: first.qso.band?.adif ?? "",
            freqHz: first.qso.freqHz, qsos: count)
    }

    /// `Math.abs(long)`: `Long.MIN_VALUE` stays negative.
    private static func javaAbs(_ value: Int) -> Int {
        value == Int.min ? value : Swift.abs(value)
    }

    /// `Duration.between(a, b).compareTo(RUN_MAX_GAP) <= 0` — exactly, including a fraction of a second.
    private static func withinMaxGap(_ a: JavaInstant, _ b: JavaInstant) -> Bool {
        let seconds: Int64 = floorSeconds(a, b)
        let nanos: Int32 = b.nano >= a.nano ? b.nano - a.nano : b.nano + 1_000_000_000 - a.nano
        return seconds < runMaxGapSeconds || (seconds == runMaxGapSeconds && nanos == 0)
    }

    /// `Duration.between(a, b).getSeconds()` — whole seconds toward −∞.
    static func floorSeconds(_ a: JavaInstant, _ b: JavaInstant) -> Int64 {
        let seconds: Int64 = b.epochSecond &- a.epochSecond
        return b.nano < a.nano ? seconds &- 1 : seconds
    }

    /// `Duration.between(a, b).toMinutes()` — seconds toward −∞, then division toward zero.
    static func minutesBetween(_ a: JavaInstant, _ b: JavaInstant) -> Int64 {
        floorSeconds(a, b) / 60
    }
}
