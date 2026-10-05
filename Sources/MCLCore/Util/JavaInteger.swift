import Foundation

/// Java conversions of text to an integer.
enum JavaInteger {

    /// Equivalent of Java's `Integer.parseInt(String)` (radix 10) — returns `nil`
    /// where Java throws `NumberFormatException`.
    ///
    /// Swift's `Int32(_:)` differs in both directions (measured on JDK 21.0.2):
    /// - Java accepts **any Unicode decimal digits** (`Character.digit`,
    ///   category `Nd`), so `"٣"` is 3 and `"１２"` is 12;
    /// - Java walks the text by **UTF-16 units**, so a digit outside the BMP
    ///   (a surrogate pair) is not a digit;
    /// - both `+` and `-` signs are allowed, a bare sign is not; spaces and `_`
    ///   are not tolerated; out of `int` range → error.
    ///
    /// The only implementation in the project: called by the YAML decoder (`JacksonCoercion`)
    /// and by the `cty.dat` reader (`CtyDxccResolver`).
    static func parseInt(_ text: String) -> Int32? {
        let units = Array(text.utf16)
        guard let firstUnit = units.first else { return nil }
        var index = 0
        var negative = false
        // Copy of Java's algorithm: accumulation in negative numbers so that
        // the `Integer.MIN_VALUE` fits as well.
        var limit = -Int64(Int32.max)
        if firstUnit < 0x30 { // '0'
            if firstUnit == 0x2D { // '-'
                negative = true
                limit = Int64(Int32.min)
            } else if firstUnit != 0x2B { // '+'
                return nil
            }
            if units.count == 1 { return nil }
            index = 1
        }
        let multmin = limit / 10
        var result: Int64 = 0
        while index < units.count {
            guard let digit = JavaChar.digit(units[index]), result >= multmin else { return nil }
            result *= 10
            guard result >= limit + Int64(digit) else { return nil }
            result -= Int64(digit)
            index += 1
        }
        return Int32(negative ? result : -result)
    }

    /// Equivalent of Java's `Long.parseLong(String)` (radix 10) — `RigctldClient.parseLongSafe`
    /// (measured on Java v1.1.1). Same algorithm as `parseInt`, only in 64 bits: `+`/`-`, any
    /// Unicode decimal digits by UTF-16 units (`+14074000`, `١٤٠٧٤٠٠٠`), without spaces, `_`, `0x`
    /// and exponent. Error = Java `NumberFormatException` with the literal message
    /// `For input string: "<input>"` (also for empty input and overflow). Measured on JDK 21.0.2.
    static func parseLong(_ text: String) throws(JavaNumberFormatError) -> Int64 {
        let invalid = JavaNumberFormatError(message: "For input string: \"" + text + "\"")
        let units = Array(text.utf16)
        guard let firstUnit = units.first else { throw invalid }
        var index = 0
        var negative = false
        // Copy of Java's algorithm: accumulation in negative numbers so that `Long.MIN_VALUE` works too.
        var limit: Int64 = -Int64.max
        if firstUnit < 0x30 { // '0'
            if firstUnit == 0x2D { // '-'
                negative = true
                limit = Int64.min
            } else if firstUnit != 0x2B { // '+'
                throw invalid
            }
            if units.count == 1 { throw invalid }
            index = 1
        }
        let multmin: Int64 = limit / 10
        var result: Int64 = 0
        while index < units.count {
            guard let digit = JavaChar.digit(units[index]), result >= multmin else { throw invalid }
            result *= 10
            guard result >= limit + Int64(digit) else { throw invalid }
            result -= Int64(digit)
            index += 1
        }
        return negative ? result : -result
    }
}
