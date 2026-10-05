import Foundation

/// Character predicates and conversions that Java performs **one UTF-16 unit at a time**
/// (`char`), not per Unicode scalar or per grapheme.
///
/// `PrefixExtractor` and `CallsignScanner` index and slice strings via
/// `charAt`/`substring`, i.e. by UTF-16 units. Swift `String` slices by
/// graphemes, which gives a **different result** for combining characters: Java's
/// `"AA\u{0308}B".substring(0, 2)` is `"AA"` (and the WPX prefix then `"AA0"`),
/// whereas Swift's `prefix(2)` is `"AÄ"`. Hence this works with `[UInt16]`.
enum JavaChar {

    /// Equivalent of Java's `Character.isDigit(char)`.
    ///
    /// Java returns `true` for category `Nd` (`DECIMAL_DIGIT_NUMBER`) — not only
    /// for ASCII. Measured on JDK 21: there are 370 such code points in the BMP and the set
    /// matches `Character.getType(cp) == DECIMAL_DIGIT_NUMBER` exactly.
    /// A surrogate unit is not a digit, because Java's `char`
    /// never evaluates half of a pair as a digit.
    static func isDigit(_ unit: UInt16) -> Bool {
        if unit < 0x80 {
            return unit >= 0x30 && unit <= 0x39
        }
        guard let scalar = Unicode.Scalar(unit) else {
            return false // half of a surrogate pair
        }
        return scalar.properties.generalCategory == .decimalNumber
    }

    /// Equivalent of Java's `Character.digit(char, 10)`: the value of a decimal
    /// digit of category `Nd` (so also `٣` or full-width `１`), otherwise `nil`.
    /// Half of a surrogate pair is not a digit — same as for `isDigit`.
    static func digit(_ unit: UInt16) -> Int? {
        if unit < 0x80 {
            return (unit >= 0x30 && unit <= 0x39) ? Int(unit - 0x30) : nil
        }
        guard let scalar = Unicode.Scalar(unit),
              scalar.properties.generalCategory == .decimalNumber,
              let value = scalar.properties.numericValue else {
            return nil
        }
        return Int(value)
    }

    /// Equivalent of Java's `Character.isLetter(char)`: categories `Lu`, `Ll`,
    /// `Lt`, `Lm`, `Lo`. Not `Nl` (Roman numeral I, `〇`), not combining marks, not
    /// half of a surrogate pair — a non-BMP character is therefore not a letter, because
    /// Java walks it unit by unit. Measured on JDK 21: 48965 points in the BMP
    /// (Swift's stdlib with newer Unicode additionally knows the same new points as
    /// u `isLetterOrDigit`).
    static func isLetter(_ unit: UInt16) -> Bool {
        if unit < 0x80 {
            return (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
        }
        guard let scalar = Unicode.Scalar(unit) else {
            return false // half of a surrogate pair
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
             .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    /// Equivalent of Java's `Character.isLetterOrDigit(char)`: a letter (category
    /// `Lu`, `Ll`, `Lt`, `Lm`, `Lo`) or a decimal digit (`Nd`).
    /// Measured on JDK 21: 49335 points in the BMP.
    static func isLetterOrDigit(_ unit: UInt16) -> Bool {
        if unit < 0x80 {
            return (unit >= 0x30 && unit <= 0x39)
                || (unit >= 0x41 && unit <= 0x5A)
                || (unit >= 0x61 && unit <= 0x7A)
        }
        guard let scalar = Unicode.Scalar(unit) else {
            return false
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
             .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// Points where Java's **simple** (1:1) `Character.toUpperCase(char)` mapping
    /// differs from the **full** `String.toUpperCase()` mapping that Swift offers.
    /// Measured over the whole BMP: 27 points, all Greek with iota subscript.
    static let simpleUpperOverrides: [UInt16: UInt16] = [
        0x1F80: 0x1F88, 0x1F81: 0x1F89, 0x1F82: 0x1F8A, 0x1F83: 0x1F8B,
        0x1F84: 0x1F8C, 0x1F85: 0x1F8D, 0x1F86: 0x1F8E, 0x1F87: 0x1F8F,
        0x1F90: 0x1F98, 0x1F91: 0x1F99, 0x1F92: 0x1F9A, 0x1F93: 0x1F9B,
        0x1F94: 0x1F9C, 0x1F95: 0x1F9D, 0x1F96: 0x1F9E, 0x1F97: 0x1F9F,
        0x1FA0: 0x1FA8, 0x1FA1: 0x1FA9, 0x1FA2: 0x1FAA, 0x1FA3: 0x1FAB,
        0x1FA4: 0x1FAC, 0x1FA5: 0x1FAD, 0x1FA6: 0x1FAE, 0x1FA7: 0x1FAF,
        0x1FB3: 0x1FBC, 0x1FC3: 0x1FCC, 0x1FF3: 0x1FFC,
    ]

    /// The only BMP point where the simple `Character.toLowerCase(char)` differs from
    /// the full mapping: `U+0130` (İ) → `i` simply, but `i` + `U+0307` fully.
    private static let simpleLowerOverrides: [UInt16: UInt16] = [0x0130: 0x0069]

    /// Equivalent of Java's `Character.toUpperCase(char)` — simple mapping,
    /// which always returns **one** unit (if one is not enough, Java leaves the character).
    static func toUpperCase(_ unit: UInt16) -> UInt16 {
        if unit < 0x80 {
            return (unit >= 0x61 && unit <= 0x7A) ? unit - 0x20 : unit
        }
        if let override = simpleUpperOverrides[unit] {
            return override
        }
        return singleUnit(of: Unicode.Scalar(unit)?.properties.uppercaseMapping, fallback: unit)
    }

    /// Equivalent of Java's `Character.toLowerCase(char)`.
    static func toLowerCase(_ unit: UInt16) -> UInt16 {
        if unit < 0x80 {
            return (unit >= 0x41 && unit <= 0x5A) ? unit + 0x20 : unit
        }
        if let override = simpleLowerOverrides[unit] {
            return override
        }
        return singleUnit(of: Unicode.Scalar(unit)?.properties.lowercaseMapping, fallback: unit)
    }

    /// Use the full mapping only if it fits into one UTF-16 unit —
    /// otherwise Java has no simple mapping and leaves the character alone.
    private static func singleUnit(of mapping: String?, fallback: UInt16) -> UInt16 {
        guard let mapping else { return fallback }
        var units = mapping.utf16.makeIterator()
        guard let first = units.next(), units.next() == nil else { return fallback }
        return first
    }

    /// Equivalent of Java's `String.equalsIgnoreCase(String)`: same length
    /// in UTF-16 units and per unit equal directly, or after `toUpperCase`,
    /// or after `toLowerCase(toUpperCase(…))`. A `nil` argument gives `false`
    /// (Java does not throw on `null`, it returns `false`).
    static func equalsIgnoreCase(_ left: String, _ right: String?) -> Bool {
        guard let right else { return false }
        let a = Array(left.utf16)
        let b = Array(right.utf16)
        guard a.count == b.count else { return false }
        for index in a.indices where a[index] != b[index] {
            let u1 = toUpperCase(a[index])
            let u2 = toUpperCase(b[index])
            if u1 == u2 { continue }
            if toLowerCase(u1) == toLowerCase(u2) { continue }
            return false
        }
        return true
    }

    /// Equivalent of Java's `Character.isWhitespace(char)` over one UTF-16 unit
    /// (`TextTokens.words`). Same set as `JavaText.isWhitespace(Unicode.Scalar)`
    /// (U+0009…U+000D, U+001C…U+001F, `Zs`/`Zl`/`Zp` except U+00A0, U+2007, U+202F — so not U+0085
    /// nor U+200B); half of a surrogate pair is not whitespace. Measured over all 65,536 units on JDK 21:
    /// 25 jednotek (`JavaCharTests.isWhitespaceUnitMatchesJava`).
    static func isWhitespace(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else {
            return false // half of a surrogate pair
        }
        return JavaText.isWhitespace(scalar)
    }

    /// Java's `\s` in a regex without `UNICODE_CHARACTER_CLASS`: `[ \t\n\u{0B}\f\r]`.
    static func isRegexSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || (unit >= 0x09 && unit <= 0x0D)
    }

    /// String from UTF-16 units.
    ///
    /// **Known divergence:** a lone half of a surrogate pair cannot be carried by
    /// Swift's `String`, so it becomes `U+FFFD`. Java keeps it in the string
    /// (`wpx("A\u{D835}\u{DFCE}X")` returns `"A\u{D835}0"`). This happens only when
    /// slicing in the middle of a pair — unrealistic for callsigns, unrepresentable in Swift.
    static func string(_ units: [UInt16]) -> String {
        String(decoding: units, as: UTF16.self)
    }
}
