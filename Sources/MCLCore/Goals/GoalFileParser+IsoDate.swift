extension GoalFileParser {

    /// Java `LocalDate.parse(text)` = `DateTimeFormatter.ISO_LOCAL_DATE` (JDK 21) → epoch day; where Java
    /// throws `DateTimeParseException`, returns `nil`. Rewritten from `NumberPrinterParser.parse` and the
    /// `ResolverStyle.STRICT` resolution:
    /// - year `appendValue(YEAR, 4, 10, EXCEEDS_PAD)`: 4–10 **ASCII** digits; `+` only with more than 4 digits,
    ///   `-` always (proleptic year, `-0000` is invalid); range ±999 999 999;
    /// - `-`, month exactly 2 digits, `-`, day exactly 2 digits (no sign), then end of text;
    /// - STRICT: a non-existent day (`2026-02-29`, `2026-04-31`) is an error (not clamped to the end of the month).
    static func isoLocalDate(_ text: String) -> Int64? {
        let units: [UInt16] = Array(text.utf16)
        var position = 0
        guard let year = isoYear(units, &position),
              let month = twoDigitField(units, &position),
              let day = twoDigitField(units, &position),
              position == units.count
        else { return nil }
        guard (-999_999_999...999_999_999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        guard day <= monthLength(year, month) else { return nil }
        return JavaLocalDate.epochDay(year: year, month: month, day: day)
    }

    /// Signed year per `SignStyle.EXCEEDS_PAD` in strict mode.
    private static func isoYear(_ units: [UInt16], _ position: inout Int) -> Int64? {
        guard !units.isEmpty else { return nil }
        var negative = false
        var positive = false
        if units[0] == 0x2B { // '+'
            positive = true
            position = 1
        } else if units[0] == 0x2D { // '-'
            negative = true
            position = 1
        }
        let start: Int = position
        guard start + 4 <= units.count else { return nil }
        let maxEnd: Int = min(start + 10, units.count)
        var total: Int64 = 0
        var end: Int = start
        while end < maxEnd, let digit = asciiDigit(units[end]) {
            total = total * 10 + digit
            end += 1
        }
        let length: Int = end - start
        guard length >= 4 else { return nil }
        if negative {
            guard total != 0 else { return nil }
            total = -total
        } else if positive {
            guard length > 4 else { return nil }
        } else {
            guard length <= 4 else { return nil }
        }
        position = end
        return total
    }

    /// `-` and the field `appendValue(field, 2)` (exactly two digits, no sign).
    private static func twoDigitField(_ units: [UInt16], _ position: inout Int) -> Int64? {
        guard position + 3 <= units.count, units[position] == 0x2D,
              let tens = asciiDigit(units[position + 1]), let ones = asciiDigit(units[position + 2])
        else { return nil }
        position += 3
        return tens * 10 + ones
    }

    private static func asciiDigit(_ unit: UInt16) -> Int64? {
        unit >= 0x30 && unit <= 0x39 ? Int64(unit - 0x30) : nil
    }

    private static func monthLength(_ year: Int64, _ month: Int64) -> Int64 {
        switch month {
        case 2: return JavaLocalDate.isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}
