import Foundation

/// Java `java.time.Instant`: seconds since the epoch and nanoseconds within the second (0…999 999 999), range
/// `Instant.MIN` (`-1000000000-01-01T00:00Z`) to `Instant.MAX` (`+1000000000-12-31T23:59:59.999999999Z`).
///
/// The cluster sync wire JSON (`WireJson`) writes instants as `Instant.toString()` (`ISO_INSTANT`: fraction in
/// groups of 0/3/6/9 digits, year above 9999 with a `+` sign, negative year padded to 4 digits), which Swift's
/// `Date` (seconds in a `Double`) cannot carry byte-exactly — nanoseconds are lost in it. Hence a custom type; it is converted
/// from/to `Date` (model `Qso`) at the boundary (`init(date:)`, `date`).
public struct JavaInstant: Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {

    public let epochSecond: Int64
    /// 0…999 999 999.
    public let nano: Int32

    public static let minSecond: Int64 = -31_557_014_167_219_200
    public static let maxSecond: Int64 = 31_556_889_864_403_199
    public static let epoch = JavaInstant(uncheckedSecond: 0, nano: 0)

    init(uncheckedSecond: Int64, nano: Int32) {
        self.epochSecond = uncheckedSecond
        self.nano = nano
    }

    /// `Instant.ofEpochSecond(seconds, nanoAdjustment)`: nanoseconds overflow into seconds (`floorDiv`/`floorMod`);
    /// outside the `Instant` range (Java `DateTimeException`) or `long` overflow (`ArithmeticException`) → `nil`.
    public static func ofEpochSecond(_ seconds: Int64, _ nanoAdjustment: Int64 = 0) -> JavaInstant? {
        let carry: Int64 = floorDiv(nanoAdjustment, 1_000_000_000)
        let (secs, overflow) = seconds.addingReportingOverflow(carry)
        guard !overflow, secs >= minSecond, secs <= maxSecond else { return nil }
        let nos: Int64 = nanoAdjustment - carry * 1_000_000_000
        return JavaInstant(uncheckedSecond: secs, nano: Int32(nos))
    }

    /// Instant from a `Date`, rounded to **microseconds** (Java's `Clock.systemUTC()` on macOS has microseconds;
    /// a `Date` made from logbook milliseconds thus returns exactly to the millisecond, not to `…122999999`). Whole seconds and the fraction
    /// are separated without loss (`t − floor(t)` is exact in `Double`), so microseconds match as long as the error
    /// of the `Date` itself is under 0.5 µs — i.e. roughly until the year 2242 (2³³ s). Outside the `Instant` range it saturates.
    public init(date: Date) {
        let t: Double = date.timeIntervalSince1970
        let limit: Double = 9.0e15
        guard t.isFinite, abs(t) < limit else {
            let edge: Int64 = t > 0 ? Self.maxSecond : Self.minSecond
            self.init(uncheckedSecond: edge, nano: 0)
            return
        }
        let whole: Double = t.rounded(.down)
        var secs = Int64(whole)
        var micro = Int64(((t - whole) * 1_000_000).rounded())
        if micro >= 1_000_000 {
            secs += 1
            micro -= 1_000_000
        }
        let bounded: Int64 = Swift.min(Swift.max(secs, Self.minSecond), Self.maxSecond)
        self.init(uncheckedSecond: bounded, nano: Int32(micro * 1_000))
    }

    /// Current instant (`Clock.systemUTC().instant()`, microseconds).
    public static func now() -> JavaInstant {
        JavaInstant(date: Date())
    }

    /// `Date` with `Double` precision (nanoseconds far from 1970 vanish).
    public var date: Date {
        Date(timeIntervalSince1970: Double(epochSecond) + Double(nano) / 1_000_000_000)
    }

    public static func < (lhs: JavaInstant, rhs: JavaInstant) -> Bool {
        lhs.epochSecond != rhs.epochSecond ? lhs.epochSecond < rhs.epochSecond : lhs.nano < rhs.nano
    }

    /// `Duration.between(self, other)` as Swift's `Duration` (seconds + nanoseconds).
    public func duration(to other: JavaInstant) -> Duration {
        let seconds: Int64 = other.epochSecond - epochSecond
        let nanos = Int64(other.nano) - Int64(nano)
        return Duration.seconds(seconds) + Duration.nanoseconds(nanos)
    }

    /// `Instant.plus(Duration)`; outside the range → `nil`.
    public func plus(seconds: Int64, nanos: Int64 = 0) -> JavaInstant? {
        let (secs, overflow) = epochSecond.addingReportingOverflow(seconds)
        guard !overflow else { return nil }
        return Self.ofEpochSecond(secs, Int64(nano) + nanos)
    }

    public var description: String { toString() }

    // MARK: - ISO_INSTANT

    private static let secondsPer10000Years: Int64 = 146_097 * 25 * 86_400
    private static let seconds0000To1970: Int64 = ((146_097 * 5) - (30 * 365 + 7)) * 86_400

    /// `Instant.toString()` = `DateTimeFormatter.ISO_INSTANT.format` (JDK 21 `InstantPrinterParser.format`,
    /// fraction `fractionalDigits = -2`).
    public func toString() -> String {
        var buf = ""
        let inSec: Int64 = epochSecond
        if inSec >= -Self.seconds0000To1970 {
            let zeroSecs: Int64 = inSec - Self.secondsPer10000Years + Self.seconds0000To1970
            let hi: Int64 = Self.floorDiv(zeroSecs, Self.secondsPer10000Years) + 1
            let lo: Int64 = zeroSecs - (hi - 1) * Self.secondsPer10000Years
            let ldt = Self.localDateTime(lo - Self.seconds0000To1970)
            if hi > 0 {
                buf += "+" + String(hi)
            }
            buf += ldt.text
        } else {
            let zeroSecs: Int64 = inSec + Self.seconds0000To1970
            let hi: Int64 = zeroSecs / Self.secondsPer10000Years
            let lo: Int64 = zeroSecs % Self.secondsPer10000Years
            let ldt = Self.localDateTime(lo - Self.seconds0000To1970)
            var text: String = ldt.text
            if hi < 0 {
                if ldt.year == -10_000 {
                    text = String(hi - 1) + String(text.dropFirst(2))
                } else if lo == 0 {
                    text = String(hi) + text
                } else {
                    text = String(text.prefix(1)) + String(abs(hi)) + String(text.dropFirst(1))
                }
            }
            buf += text
        }
        if nano > 0 {
            buf += "."
            var value = Int(nano)
            var div = 100_000_000
            var i = 0
            while value > 0 || i % 3 != 0 {
                let digit: Int = value / div
                buf.append(Character(Unicode.Scalar(UInt8(48 + digit))))
                value -= digit * div
                div /= 10
                i += 1
            }
        }
        buf += "Z"
        return buf
    }

    /// `LocalDateTime.ofEpochSecond(s, 0, UTC).toString()` + `":00"` when the seconds are zero.
    private static func localDateTime(_ epochSecond: Int64) -> (year: Int64, text: String) {
        let epochDay: Int64 = floorDiv(epochSecond, 86_400)
        let secondOfDay: Int64 = epochSecond - epochDay * 86_400
        let civil = JavaLocalDate.civil(epochDay: epochDay)
        var text: String = yearText(civil.year)
        text += "-" + JavaLocalDate.twoDigits(civil.month)
        text += "-" + JavaLocalDate.twoDigits(civil.day)
        text += "T" + JavaLocalDate.twoDigits(secondOfDay / 3_600)
        text += ":" + JavaLocalDate.twoDigits(secondOfDay / 60 % 60)
        text += ":" + JavaLocalDate.twoDigits(secondOfDay % 60)
        return (civil.year, text)
    }

    /// Year as `LocalDate.toString()`.
    private static func yearText(_ year: Int64) -> String {
        let absYear: Int64 = abs(year)
        if absYear < 1_000 {
            if year < 0 {
                var digits = String(year - 10_000)
                digits.remove(at: digits.index(after: digits.startIndex))
                return digits
            }
            return String(String(year + 10_000).dropFirst())
        }
        return year > 9_999 ? "+" + String(year) : String(year)
    }

    /// `DateTimeFormatter.ISO_INSTANT.parse(text)` + `Instant.from` (JDK 21, `InstantPrinterParser.parse`, strict,
    /// case-insensitive for `T`/`Z`): `year-MM-ddTHH:mm:ss[.fraction 0–9 digits](Z|±HH:MM[:ss])`, year 4–10 digits
    /// (sign `+` only above 4 digits), `24:00:00` = midnight of the next day, `23:59:60` = `23:59:59`, the whole text must
    /// be consumed. Error (`DateTimeParseException`/`DateTimeException`) → `nil`.
    public static func parseIsoInstant(_ text: String) -> JavaInstant? {
        var p = IsoParser(units: Array(text.utf16))
        return p.parse()
    }

    static func floorDiv(_ x: Int64, _ y: Int64) -> Int64 {
        let q: Int64 = x / y
        return (x % y != 0 && ((x < 0) != (y < 0))) ? q - 1 : q
    }
}

/// Port of `InstantPrinterParser.parse` and the partial parsers (`NumberPrinterParser`, `FractionPrinterParser`,
/// `OffsetIdPrinterParser` with the pattern `+HH:MM:ss` and text `Z`) for strict, case-insensitive mode.
private struct IsoParser {
    let units: [UInt16]
    var pos = 0

    init(units: [UInt16]) {
        self.units = units
    }

    mutating func parse() -> JavaInstant? {
        guard let year = yearValue(), literal(0x2D),
              let month = fixed2(), literal(0x2D),
              let day = fixed2(), literal(0x54, caseInsensitive: true),
              let hour = fixed2(), literal(0x3A),
              let minute = fixed2(), literal(0x3A),
              let second = fixed2() else { return nil }
        let nano: Int64 = fraction()
        guard let offset = offsetSeconds(), pos == units.count else { return nil }
        var h: Int64 = hour
        var s: Int64 = second
        var days: Int64 = 0
        if hour == 24 && minute == 0 && second == 0 && nano == 0 {
            h = 0
            days = 1
        } else if hour == 23 && minute == 59 && second == 60 {
            s = 59
        }
        let truncated = Int32(truncatingIfNeeded: year)
        let y = Int64(truncated % 10_000)
        guard (1...12).contains(month), day >= 1, day <= Self.monthLength(y, month),
              (0...23).contains(h), (0...59).contains(minute), (0...59).contains(s),
              abs(offset) <= 18 * 3_600 else { return nil }
        let epochDay: Int64 = JavaLocalDate.epochDay(year: y, month: month, day: day) + days
        let local: Int64 = epochDay * 86_400 + h * 3_600 + minute * 60 + s
        let cycles: Int64 = year / 10_000
        let (shift, overflow) = cycles.multipliedReportingOverflow(by: 146_097 * 25 * 86_400)
        guard !overflow else { return nil }
        let (total, overflow2) = (local - offset).addingReportingOverflow(shift)
        guard !overflow2 else { return nil }
        return JavaInstant.ofEpochSecond(total, nano)
    }

    static func monthLength(_ year: Int64, _ month: Int64) -> Int64 {
        switch month {
        case 2: return JavaLocalDate.isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    func digit(at index: Int) -> Int64? {
        guard index < units.count else { return nil }
        let u: UInt16 = units[index]
        return u >= 0x30 && u <= 0x39 ? Int64(u - 0x30) : nil
    }

    mutating func literal(_ unit: UInt16, caseInsensitive: Bool = false) -> Bool {
        guard pos < units.count else { return false }
        let u: UInt16 = units[pos]
        let match: Bool = caseInsensitive ? (u == unit || u == unit + 0x20) : u == unit
        guard match else { return false }
        pos += 1
        return true
    }

    /// `appendValue(YEAR, 4, 10, EXCEEDS_PAD)`, strict.
    mutating func yearValue() -> Int64? {
        guard pos < units.count else { return nil }
        var negative = false
        var positive = false
        if units[pos] == 0x2B {
            positive = true
            pos += 1
        } else if units[pos] == 0x2D {
            negative = true
            pos += 1
        }
        let start: Int = pos
        var total: Int64 = 0
        while pos < units.count && pos - start < 10, let d = digit(at: pos) {
            total = total * 10 + d
            pos += 1
        }
        let length: Int = pos - start
        guard length >= 4 else { return nil }
        if negative {
            return total == 0 ? nil : -total
        }
        if positive ? length <= 4 : length > 4 {
            return nil
        }
        return total
    }

    /// `appendValue(field, 2)`: exactly two ASCII digits, no sign.
    mutating func fixed2() -> Int64? {
        guard let d1 = digit(at: pos), let d2 = digit(at: pos + 1) else { return nil }
        pos += 2
        return d1 * 10 + d2
    }

    /// `appendFraction(NANO_OF_SECOND, 0, 9, true)`: optional point and 0–9 digits.
    mutating func fraction() -> Int64 {
        guard pos < units.count, units[pos] == 0x2E else { return 0 }
        pos += 1
        var total: Int64 = 0
        var count = 0
        while count < 9, let d = digit(at: pos) {
            total = total * 10 + d
            pos += 1
            count += 1
        }
        while count < 9 {
            total *= 10
            count += 1
        }
        return total
    }

    /// `appendOffsetId()` = `+HH:MM:ss` with text `Z` (strict): hours two digits, minutes mandatory with a colon,
    /// seconds optional with a colon; a component above 59 does not match the pattern, hours above 23 are `DateTimeException`.
    mutating func offsetSeconds() -> Int64? {
        guard pos < units.count else { return nil }
        let u: UInt16 = units[pos]
        if u == 0x5A || u == 0x7A {
            pos += 1
            return 0
        }
        guard u == 0x2B || u == 0x2D else { return nil }
        let sign: Int64 = u == 0x2D ? -1 : 1
        var cursor: Int = pos + 1
        guard let hours = pair(&cursor, colon: false), let minutes = pair(&cursor, colon: true) else { return nil }
        var seconds: Int64 = 0
        if let s = pair(&cursor, colon: true) {
            seconds = s
        }
        guard hours <= 23 else { return nil }
        pos = cursor
        return sign * (hours * 3_600 + minutes * 60 + seconds)
    }

    /// `OffsetIdPrinterParser.parseDigits`: (colon) + two digits with a value 0…59.
    func pair(_ cursor: inout Int, colon: Bool) -> Int64? {
        var p: Int = cursor
        if colon {
            guard p < units.count, units[p] == 0x3A else { return nil }
            p += 1
        }
        guard let d1 = digit(at: p), let d2 = digit(at: p + 1) else { return nil }
        let value: Int64 = d1 * 10 + d2
        guard value <= 59 else { return nil }
        cursor = p + 2
        return value
    }
}
