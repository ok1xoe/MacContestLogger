import Foundation

/// Calendar date and time as `java.time` handles them (proleptic Gregorian
/// calendar, UTC) — without `DateFormatter`/`Calendar`, whose behavior depends on the system version
/// and locale.
///
/// Covers what the `io/` package needs: `DateTimeFormatter.ofPattern("yyyyMMdd")`
/// (and `"yyyy-MM-dd"`) when reading **strictly with the SMART resolver** (the default state of
/// `ofPattern`) and when writing, `LocalTime.of`, conversion to an instant in UTC and back.
enum JavaLocalDate {

    /// `LocalDate.toEpochDay` (JDK 21, `LocalDate.java`).
    static func epochDay(year: Int64, month: Int64, day: Int64) -> Int64 {
        var total: Int64 = 365 * year
        if year >= 0 {
            total += (year + 3) / 4 - (year + 99) / 100 + (year + 399) / 400
        } else {
            total -= year / -4 - year / -100 + year / -400
        }
        total += (367 * month - 362) / 12
        total += day - 1
        if month > 2 {
            total -= 1
            if !isLeap(year) { total -= 1 }
        }
        return total - daysFrom0000To1970
    }

    /// `LocalDate.ofEpochDay` → (year, month, day).
    static func civil(epochDay: Int64) -> (year: Int64, month: Int64, day: Int64) {
        var zeroDay = epochDay + daysFrom0000To1970 - 60
        var adjust: Int64 = 0
        if zeroDay < 0 {
            let adjustCycles = (zeroDay + 1) / daysPerCycle - 1
            adjust = adjustCycles * 400
            zeroDay += -adjustCycles * daysPerCycle
        }
        var yearEst = (400 * zeroDay + 591) / daysPerCycle
        var doyEst = zeroDay - (365 * yearEst + yearEst / 4 - yearEst / 100 + yearEst / 400)
        if doyEst < 0 {
            yearEst -= 1
            doyEst = zeroDay - (365 * yearEst + yearEst / 4 - yearEst / 100 + yearEst / 400)
        }
        yearEst += adjust
        let marchMonth0 = (doyEst * 5 + 2) / 153
        let month = (marchMonth0 + 2) % 12 + 1
        let day = doyEst - (marchMonth0 * 306 + 5) / 10 + 1
        yearEst += marchMonth0 / 10
        return (yearEst, month, day)
    }

    static func isLeap(_ year: Int64) -> Bool {
        (year & 3) == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    /// Instant `date + time` in UTC as a `Date` (`LocalDateTime.toInstant(ZoneOffset.UTC)`).
    static func instant(epochDay: Int64, secondOfDay: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epochDay * 86_400 + secondOfDay))
    }

    /// `LocalTime.of(hour, minute, second).toSecondOfDay()`; out of range (Java throws
    /// `DateTimeException`) → `nil`.
    static func secondOfDay(hour: Int32, minute: Int32, second: Int32) -> Int64? {
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            return nil
        }
        return Int64(hour) * 3600 + Int64(minute) * 60 + Int64(second)
    }

    /// Decomposition of an instant like `DateTimeFormatter.withZone(UTC).format(instant)`: epoch day
    /// and second of day, **truncated down** (Instant carries `floor` seconds). Outside the `Int64`
    /// range (Java cannot represent such an `Instant`) → `nil`.
    static func split(_ date: Date) -> (epochDay: Int64, secondOfDay: Int64)? {
        guard let seconds = Int64(exactly: date.timeIntervalSince1970.rounded(.down)) else { return nil }
        let day = JavaMath.floorDiv(seconds, 86_400)
        return (day, seconds - day * 86_400)
    }

    /// `yyyy` when writing (`YEAR_OF_ERA`, `SignStyle.EXCEEDS_PAD`, width 4–19): year of era
    /// (`1 − year` before the Common Era), zero-padded to 4, above 4 digits with a `+` sign.
    static func formatYearOfEra(_ year: Int64) -> String {
        let yearOfEra = year >= 1 ? year : 1 - year
        let digits = String(yearOfEra)
        if digits.count > 4 { return "+" + digits }
        return String(repeating: "0", count: 4 - digits.count) + digits
    }

    /// `yy` when writing (`ReducedPrinterParser`, base 2000, width 2): the last two digits
    /// of the year of era.
    static func formatReducedYear(_ year: Int64) -> String {
        let yearOfEra = year >= 1 ? year : 1 - year
        return twoDigits(yearOfEra % 100)
    }

    /// Two digits (`MM`, `dd`, `HH`, `mm`, `ss`).
    static func twoDigits(_ value: Int64) -> String {
        value < 10 ? "0" + String(value) : String(value)
    }

    /// `LocalDate.parse(text, DateTimeFormatter.ofPattern("yyyy" + sep + "MM" + sep + "dd"))`
    /// — default strict parsing and `ResolverStyle.SMART`; where Java throws
    /// `DateTimeParseException`, returns `nil`. Returns the epoch day.
    ///
    /// Ported from `NumberPrinterParser.parse` and `IsoChronology.resolveYMD` (JDK 21):
    /// - digits ASCII only (`DecimalStyle.STANDARD`), no trimming;
    /// - `yyyy`: without a sign **exactly 4** digits; `+` only when there are more than 4 digits;
    ///   `-` gives a negative year of era, hence an error; without a separator `MM` and `dd`
    ///   reserve 4 digits at the end (adjacent value parsing);
    /// - `MM`, `dd`: exactly 2 digits, no sign; nothing after `dd`;
    /// - year of era 1…999 999 999, month 1…12, day 1…31; SMART clamps a day past the end of the month
    ///   to the last day (`20260230` → 28 Feb, `20260431` → 30 Apr).
    static func parseDate(_ text: String, separator: UInt16?) -> Int64? {
        let units = Array(text.utf16)
        let length = units.count
        guard length > 0 else { return nil }
        var position = 0
        var positive = false
        if units[0] == 0x2B { // '+'
            positive = true
            position = 1
        } else if units[0] == 0x2D { // '-': year of era < 1 → error on resolve
            return nil
        }
        let subsequentWidth = separator == nil ? 4 : 0
        let maxEnd = min(position + 19 + subsequentWidth, length)
        var digits = 0
        while position + digits < maxEnd, isAsciiDigit(units[position + digits]) {
            digits += 1
        }
        guard digits >= 4 else { return nil }
        let yearLength = subsequentWidth > 0 ? max(4, digits - subsequentWidth) : digits
        if positive ? yearLength <= 4 : yearLength > 4 { return nil }
        var yearOfEra: Int64 = 0
        for unit in units[position..<(position + yearLength)] {
            // Above 999 999 999 the year is invalid; nothing changes that anymore (only leading zeros could).
            if yearOfEra <= 999_999_999 { yearOfEra = yearOfEra * 10 + Int64(unit - 0x30) }
        }
        position += yearLength
        guard let month = twoDigitField(units, &position, separator: separator),
            let day = twoDigitField(units, &position, separator: separator),
            position == length
        else { return nil }
        guard (1...999_999_999).contains(yearOfEra), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        var dayOfMonth = day
        if month == 4 || month == 6 || month == 9 || month == 11 {
            dayOfMonth = min(dayOfMonth, 30)
        } else if month == 2 {
            dayOfMonth = min(dayOfMonth, isLeap(yearOfEra) ? 29 : 28)
        }
        return epochDay(year: yearOfEra, month: month, day: dayOfMonth)
    }

    // MARK: - Helpers

    private static let daysPerCycle: Int64 = 146_097
    private static let daysFrom0000To1970: Int64 = daysPerCycle * 5 - (30 * 365 + 7)

    private static func isAsciiDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    /// Optional separator and a fixed-width field of 2 (`MM`, `dd`).
    private static func twoDigitField(_ units: [UInt16], _ position: inout Int, separator: UInt16?) -> Int64? {
        if let separator {
            guard position < units.count, units[position] == separator else { return nil }
            position += 1
        }
        guard position + 2 <= units.count,
            isAsciiDigit(units[position]), isAsciiDigit(units[position + 1])
        else { return nil }
        let value = Int64(units[position] - 0x30) * 10 + Int64(units[position + 1] - 0x30)
        position += 2
        return value
    }
}
