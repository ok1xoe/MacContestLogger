/// Subset of Java's `java.math.BigDecimal` needed by `BeaconFile` and `CallFieldCommands`:
/// `new BigDecimal(String)`, `movePointRight(int)`, `setScale(0, HALF_UP)` and `longValueExact()` —
/// **exactly**, without `Double`.
///
/// Value = (−1)^`negative` × `digits` × 10^−`scale`; `digits` are decimal digits of magnitude
/// without leading zeros (empty = zero). A negative `scale` is not materialized (in `movePointRight`
/// Java calls `setScale(0)` for a negative scale, i.e. multiplies by 10^n; that changes nothing about the value or about whether `longValueExact`
/// succeeds).
///
/// Port from JDK 21 (`BigDecimal(char[], int, int, MathContext)`, `parseExp`, `checkScale`,
/// `longValueExact`): grammar `[+-] digit* [. digit*] [(e|E) [+-] digit+]` with at least one
/// digit in the mantissa; digits are **any `Nd` by UTF-16 units** (`Character.isDigit`,
/// `Character.digit(c, 10)`), also in the exponent; in the exponent leading zeros are skipped only while more than
/// 10 characters remain and then it may have at most 10 digits; the resulting scale (number of decimal places − exponent)
/// must fit into `int`. Spaces, `_`, `NaN`, `Infinity`, `0x…` are errors. Exception texts are
/// not copied — the caller (`BeaconFile.parse`) catches them and just skips the line.
struct JavaBigDecimal: Equatable, Sendable {
    let negative: Bool
    let digits: [UInt8]
    let scale: Int64

    private init(negative: Bool, digits: [UInt8], scale: Int64) {
        self.negative = negative
        self.digits = digits
        self.scale = scale
    }

    /// Java `new BigDecimal(text)`; `nil` where Java throws `NumberFormatException`.
    init?(_ text: String) {
        let units: [UInt16] = Array(text.utf16)
        var index = 0
        var negative = false
        guard let first = units.first else { return nil }
        if first == 0x2D {
            negative = true
            index = 1
        } else if first == 0x2B {
            index = 1
        }
        var magnitude: [UInt8] = []
        var sawDigit = false
        var dot = false
        var fraction: Int64 = 0
        var exponent: Int64 = 0
        while index < units.count {
            let unit = units[index]
            if let digit = JavaChar.digit(unit) {
                sawDigit = true
                if digit != 0 || !magnitude.isEmpty {
                    magnitude.append(UInt8(digit))
                }
                if dot { fraction += 1 }
            } else if unit == 0x2E {
                if dot { return nil }
                dot = true
            } else if unit == 0x65 || unit == 0x45 {
                guard let parsed = Self.parseExponent(units, from: index + 1) else { return nil }
                exponent = parsed
                break
            } else {
                return nil
            }
            index += 1
        }
        guard sawDigit else { return nil }
        let scale: Int64 = fraction - exponent
        guard scale >= Int64(Int32.min), scale <= Int64(Int32.max) else { return nil }
        self.init(negative: negative, digits: magnitude, scale: scale)
    }

    /// Java `parseExp`: `start` is the first character after `e`.
    private static func parseExponent(_ units: [UInt16], from start: Int) -> Int64? {
        var index = start
        guard index < units.count else { return nil }
        let negative = units[index] == 0x2D
        if negative || units[index] == 0x2B {
            index += 1
        }
        var length = units.count - index
        guard length > 0 else { return nil }
        while length > 10, JavaChar.digit(units[index]) == 0 {
            index += 1
            length -= 1
        }
        guard length <= 10 else { return nil }
        var value: Int64 = 0
        while index < units.count {
            guard let digit = JavaChar.digit(units[index]) else { return nil }
            value = value * 10 + Int64(digit)
            index += 1
        }
        return negative ? -value : value
    }

    /// Java `movePointRight(n)`; `nil` = `ArithmeticException` (scale outside `int` for a nonzero value,
    /// zero is merely clamped to the `int` limit).
    func movePointRight(_ n: Int32) -> JavaBigDecimal? {
        if n == 0 && scale >= 0 { return self }
        var newScale: Int64 = scale - Int64(n)
        if newScale < Int64(Int32.min) || newScale > Int64(Int32.max) {
            guard digits.isEmpty else { return nil }
            newScale = newScale > 0 ? Int64(Int32.max) : Int64(Int32.min)
        }
        return JavaBigDecimal(negative: negative, digits: digits, scale: newScale)
    }

    /// Java `longValueExact()`; `nil` = `ArithmeticException` (nonzero fractional part or outside `long`).
    func longValueExact() -> Int64? {
        if digits.isEmpty { return 0 }
        let integerLength: Int64 = Int64(digits.count) - scale
        guard integerLength > 0, integerLength <= 19 else { return nil }
        var integerDigits: [UInt8]
        if scale > 0 {
            let cut = Int(integerLength)
            guard digits[cut...].allSatisfy({ $0 == 0 }) else { return nil }
            integerDigits = Array(digits[..<cut])
        } else {
            integerDigits = digits
            integerDigits.append(contentsOf: [UInt8](repeating: 0, count: Int(-scale)))
        }
        var value: UInt64 = 0
        for digit in integerDigits {
            value = value * 10 + UInt64(digit)
        }
        let limit: UInt64 = negative ? UInt64(Int64.max) + 1 : UInt64(Int64.max)
        guard value <= limit else { return nil }
        if negative {
            return value == UInt64(Int64.max) + 1 ? Int64.min : -Int64(value)
        }
        return Int64(value)
    }

    /// Java `setScale(0, RoundingMode.HALF_UP)`: rounding to an integer according to the **decimal**
    /// notation — the first discarded digit ≥ 5 raises the absolute value by one (away from zero, also for negatives:
    /// `-0.5` → `-1`), the rest of the discarded digits are not read (`0.4999` → `0`). A scale ≤ 0 is already an integer
    /// and the value does not change (`longValueExact` pads zeros). A zero result is positive zero.
    func setScaleZeroHalfUp() -> JavaBigDecimal {
        guard scale > 0 else { return self }
        let integerLength: Int64 = Int64(digits.count) - scale
        var integerDigits: [UInt8] = integerLength > 0 ? Array(digits[..<Int(integerLength)]) : []
        let roundingIndex: Int64 = max(integerLength, -1)
        let roundingDigit: UInt8 = roundingIndex >= 0 && roundingIndex < Int64(digits.count)
            ? digits[Int(roundingIndex)] : 0
        if roundingDigit >= 5 {
            integerDigits = Self.incremented(integerDigits)
        }
        if integerDigits.isEmpty {
            return JavaBigDecimal(negative: false, digits: [], scale: 0)
        }
        return JavaBigDecimal(negative: negative, digits: integerDigits, scale: 0)
    }

    /// Decimal digits of magnitude + 1 (empty = zero → `[1]`).
    private static func incremented(_ digits: [UInt8]) -> [UInt8] {
        var result: [UInt8] = digits
        var index: Int = result.count - 1
        while index >= 0 {
            if result[index] < 9 {
                result[index] += 1
                return result
            }
            result[index] = 0
            index -= 1
        }
        result.insert(1, at: 0)
        return result
    }
}
