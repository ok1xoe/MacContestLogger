import Foundation

/// Text form of `Double` exactly as Java's `Double.toString` produces it.
///
/// Why custom: Swift's `String(Double)` gives **different text** for the same value —
/// `3.333333333E-4` (Java) vs `0.0003333333333` (Swift). `BandPlanFile.write`
/// writes frequencies to the user's file and contest definitions contain decimal
/// numbers (`contests/ww-digi.yaml`), so a difference would change the content of their data.
///
/// Java rules (JDK 19 and up, measured on JDK 21):
/// - `NaN`, `Infinity`, `-Infinity`, `0.0`, `-0.0` literally;
/// - otherwise the shortest decimal form that reads back without loss, but
///   **at least two significant digits** (hence `Double.MIN_VALUE` is `4.9E-324`,
///   not `5E-324`);
/// - a value from `1e-3` (inclusive) to `1e7` (exclusive) is written without exponent and always
///   with at least one digit after the point (`1843.0`, `0.001`), otherwise exponentially
///   (`1.0E7`, `3.333333333E-4`).
enum JavaDouble {

    /// `Double.toString`.
    static func toString(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        if value == 0 { return value.sign == .minus ? "-0.0" : "0.0" }

        let negative = value < 0
        let (digits, exponent) = significand(abs(value))

        let sign = negative ? "-" : ""
        // Without exponent while the value is in <1e-3, 1e7). `exponent` is the power
        // of ten at the first digit, so the bounds are -3 and 6.
        if exponent >= -3 && exponent <= 6 {
            if exponent >= 0 {
                let wholeCount = exponent + 1
                var whole = digits
                var fraction = ""
                if digits.count > wholeCount {
                    whole = String(digits.prefix(wholeCount))
                    fraction = String(digits.dropFirst(wholeCount))
                } else if digits.count < wholeCount {
                    whole += String(repeating: "0", count: wholeCount - digits.count)
                }
                return sign + whole + "." + (fraction.isEmpty ? "0" : fraction)
            }
            return sign + "0." + String(repeating: "0", count: -exponent - 1) + digits
        }
        let first = String(digits.prefix(1))
        let rest = String(digits.dropFirst())
        return sign + first + "." + (rest.isEmpty ? "0" : rest) + "E" + String(exponent)
    }

    /// The decimal number Java assigns to a `double` (`DoubleToDecimal`):
    /// significant digits without trailing zeros and the power of ten at the first of them, i.e.
    /// the value `d1.d2… × 10^exponent`. Java builds both
    /// `Double.toString` and `Formatter` (`%.Nf` via `FormattedFPDecimal`) from the same decomposition.
    /// `magnitude` must be finite and positive.
    static func significand(_ magnitude: Double) -> (digits: String, exponent: Int) {
        var (digits, exponent) = shortestDigits(magnitude)

        // Java takes at least two significant digits: when the shortest form comes out as
        // one, it takes the two-digit form nearest to the real value. `%.1e`
        // rounds exactly and to the nearest even, i.e. the same as Java.
        if digits.count == 1 {
            (digits, exponent) = twoDigits(magnitude)
        }
        // Trailing zeros do not affect the result (there is always at least one
        // digit after the point), so don't let more of them slip through than Java writes.
        while digits.count > 1 && digits.last == "0" { digits.removeLast() }
        return (digits, exponent)
    }

    /// Same as `significand`, only with digits as values 0–9 and without
    /// intermediate steps via `String` — `JavaFormat` calls this for every `%f` (a pass over
    /// frequencies in tests does millions of them). `JavaFormatTests` guards that the two agree.
    static func decimalDigits(_ magnitude: Double) -> (digits: [UInt8], exponent: Int) {
        var decimal = parseDigits(String(magnitude).utf8)
        if decimal.digits.count == 1 {
            let two = twoDigits(magnitude)
            decimal = (two.0.utf8.map { $0 - 0x30 }, two.1)
        }
        while decimal.digits.count > 1 && decimal.digits.last == 0 { decimal.digits.removeLast() }
        return decimal
    }

    /// `decompose` over the bytes of the text (`1843.0`, `0.001`, `1e-05`, `4.9e-324`).
    private static func parseDigits(_ text: String.UTF8View) -> (digits: [UInt8], exponent: Int) {
        var digits: [UInt8] = []
        digits.reserveCapacity(24)
        var wholeCount = 0
        var seenPoint = false
        var exponent = 0
        var bytes = text.makeIterator()
        scan: while let byte = bytes.next() {
            switch byte {
            case 0x30...0x39:
                digits.append(byte - 0x30)
                if !seenPoint { wholeCount += 1 }
            case 0x2E:
                seenPoint = true
            case 0x65, 0x45:
                var negative = false
                var value = 0
                while let next = bytes.next() {
                    if next == 0x2D {
                        negative = true
                    } else if next >= 0x30 && next <= 0x39 {
                        value = value * 10 + Int(next - 0x30)
                    }
                }
                exponent = negative ? -value : value
                break scan
            default:
                break
            }
        }
        var position = wholeCount - 1 + exponent
        var start = 0
        while start < digits.count - 1 && digits[start] == 0 {
            start += 1
            position -= 1
        }
        var end = digits.count
        while end - start > 1 && digits[end - 1] == 0 { end -= 1 }
        return (Array(digits[start..<end]), position)
    }

    /// Shortest valid digits and the power of ten at the first of them: the value is
    /// `0.d1d2… × 10^(exponent+1)`, i.e. `d1.d2… × 10^exponent`.
    ///
    /// Digits are taken from Swift's `String(Double)`, which is also "the shortest form
    /// that round-trips, and of those the nearest" — only the **shape**
    /// of the text differs, not the digits. Verified by bulk comparison with Java.
    private static func shortestDigits(_ magnitude: Double) -> (String, Int) {
        decompose(String(magnitude))
    }

    /// Two-digit form nearest to the value, via exact rounding in `%.1e`.
    private static func twoDigits(_ magnitude: Double) -> (String, Int) {
        decompose(String(format: "%.1e", magnitude))
    }

    /// Parses the text of a decimal number (`1843.0`, `0.001`, `1e-05`, `4.9e-324`)
    /// into significant digits without leading zeros and the power of ten at the first of them.
    private static func decompose(_ text: String) -> (String, Int) {
        var mantissa = text
        var exponent = 0
        if let marker = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = String(text[text.startIndex..<marker])
            exponent = Int(text[text.index(after: marker)...]) ?? 0
        }
        var whole = mantissa
        var fraction = ""
        if let dot = mantissa.firstIndex(of: ".") {
            whole = String(mantissa[mantissa.startIndex..<dot])
            fraction = String(mantissa[mantissa.index(after: dot)...])
        }
        var digits = whole + fraction
        // Power of ten at the first digit, before leading zeros are removed.
        var position = whole.count - 1 + exponent
        while digits.count > 1 && digits.first == "0" {
            digits.removeFirst()
            position -= 1
        }
        while digits.count > 1 && digits.last == "0" { digits.removeLast() }
        return (digits, position)
    }
}

// MARK: - Double.parseDouble

/// Java `NumberFormatException` from `Double.parseDouble`: carries the literal text
/// of the message (`getMessage()`), because `Expression` shows it in the UI.
public struct JavaNumberFormatError: Error, Equatable, Sendable {
    public let message: String
}

extension JavaDouble {

    /// Equivalent of Java's `Double.parseDouble(String)` — `nil` where Java
    /// throws `NumberFormatException`. The exception text is given by `parse(_:)`.
    static func parseDouble(_ text: String) -> Double? {
        try? parse(text)
    }

    /// Java `Double.parseDouble(String)` ported from
    /// `FloatingDecimal.readJavaFormatString` (JDK 21), including exception messages.
    ///
    /// Swift's `Double(String)` differs in both directions (measured): it accepts `nan`,
    /// `inf`, `infinity`, `nan(0x1)` and a hexadecimal number without exponent
    /// (`0x10` = 16), does not trim spaces and does not accept a type suffix (`1d`, `1f`).
    /// Java, on the other hand:
    /// - first trims the input with Java's `trim()` (everything `<= U+0020`, not NBSP
    ///   nor `U+0085`) and the error message already contains the trimmed text;
    /// - empty input → `empty String`;
    /// - an optional sign, then exactly `NaN` or `Infinity` (without suffix),
    ///   or `0x…` → hexadecimal notation `HEX* [. HEX*] p [+-] DEC+`
    ///   with at least one hexadecimal digit, or decimal notation
    ///   `DEC* [. DEC*] [eE [+-] DEC+]` with at least one digit;
    /// - a second point in the digits (before the exponent) → `multiple points`;
    /// - a single `f`/`F`/`d`/`D` character is allowed at the end;
    /// - digits only ASCII (`١` is an error), no `_`;
    /// - anything else → `For input string: "<trimmed input>"`.
    ///
    /// The value itself is computed by Swift's `Double(_:)` over the already validated ASCII
    /// text without sign and suffix — both round correctly to the nearest
    /// `double`, overflow gives infinity, underflow zero (verified by a table).
    static func parse(_ text: String) throws(JavaNumberFormatError) -> Double {
        let input = JavaText.trim(text)
        let units = Array(input.utf16)
        let length = units.count
        if length == 0 {
            throw JavaNumberFormatError(message: "empty String")
        }
        let invalid = JavaNumberFormatError(message: "For input string: \"" + input + "\"")
        var i = 0
        var negative = false
        if units[0] == 0x2D { // '-'
            negative = true
            i = 1
        } else if units[0] == 0x2B { // '+'
            i = 1
        }
        guard i < length else { throw invalid }
        let rest = Array(units[i...])
        if units[i] == 0x4E { // 'N'
            guard rest == Array("NaN".utf16) else { throw invalid }
            return .nan
        }
        if units[i] == 0x49 { // 'I'
            guard rest == Array("Infinity".utf16) else { throw invalid }
            return negative ? -.infinity : .infinity
        }
        let end: Int
        if units[i] == 0x30, i + 1 < length, units[i + 1] == 0x78 || units[i + 1] == 0x58 { // "0x"
            guard let hexEnd = hexLiteralEnd(units, from: i + 2) else { throw invalid }
            end = hexEnd
        } else {
            end = try decimalLiteralEnd(units, from: i, invalid: invalid)
        }
        guard let magnitude = Double(String(decoding: units[i..<end], as: UTF16.self)) else {
            throw invalid
        }
        return negative ? -magnitude : magnitude
    }

    private static func isDecimalDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private static func isHexDigit(_ unit: UInt16) -> Bool {
        isDecimalDigit(unit) || (unit >= 0x41 && unit <= 0x46) || (unit >= 0x61 && unit <= 0x66)
    }

    private static func isTypeSuffix(_ unit: UInt16) -> Bool {
        unit == 0x66 || unit == 0x46 || unit == 0x64 || unit == 0x44 // f F d D
    }

    /// End of the numeric part (without type suffix), if only the end of
    /// input or a single `fFdD` suffix follows; otherwise `nil`.
    private static func endBeforeSuffix(_ units: [UInt16], _ index: Int) -> Int? {
        if index == units.count { return index }
        if index == units.count - 1, isTypeSuffix(units[index]) { return index }
        return nil
    }

    /// Java pattern `0[xX](HEX+ .? | HEX* . HEX+)[pP][+-]?DEC+[fFdD]?` from the position
    /// after `0x`. The two branches together mean "at least one hexadecimal
    /// digit before the point or after it".
    private static func hexLiteralEnd(_ units: [UInt16], from start: Int) -> Int? {
        var i = start
        var digits = 0
        while i < units.count, isHexDigit(units[i]) {
            i += 1
            digits += 1
        }
        if i < units.count, units[i] == 0x2E { // '.'
            i += 1
            while i < units.count, isHexDigit(units[i]) {
                i += 1
                digits += 1
            }
        }
        guard digits > 0, i < units.count, units[i] == 0x70 || units[i] == 0x50 else { // 'p'
            return nil
        }
        i += 1
        if i < units.count, units[i] == 0x2B || units[i] == 0x2D {
            i += 1
        }
        let exponentStart = i
        while i < units.count, isDecimalDigit(units[i]) {
            i += 1
        }
        guard i > exponentStart else { return nil }
        return endBeforeSuffix(units, i)
    }

    /// Decimal branch of `readJavaFormatString`: digits and at most one point
    /// (the second throws `multiple points` as soon as the loop meets it), at least
    /// one digit, an optional exponent with at least one digit.
    private static func decimalLiteralEnd(
        _ units: [UInt16], from start: Int, invalid: JavaNumberFormatError
    ) throws(JavaNumberFormatError) -> Int {
        var i = start
        var digits = 0
        var pointSeen = false
        while i < units.count {
            let unit = units[i]
            if isDecimalDigit(unit) {
                digits += 1
            } else if unit == 0x2E { // '.'
                if pointSeen {
                    throw JavaNumberFormatError(message: "multiple points")
                }
                pointSeen = true
            } else {
                break
            }
            i += 1
        }
        guard digits > 0 else { throw invalid }
        if i < units.count, units[i] == 0x65 || units[i] == 0x45 { // 'e'
            i += 1
            guard i < units.count else { throw invalid }
            if units[i] == 0x2B || units[i] == 0x2D {
                i += 1
            }
            let exponentStart = i
            while i < units.count, isDecimalDigit(units[i]) {
                i += 1
            }
            guard i > exponentStart else { throw invalid }
        }
        guard let end = endBeforeSuffix(units, i) else { throw invalid }
        return end
    }
}
