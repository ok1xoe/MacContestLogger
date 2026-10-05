import Foundation

/// Exact equivalents of Java text operations that cannot be replaced by
/// Swift's `trimmingCharacters(in: .whitespacesAndNewlines)`.
///
/// Java has **three different** sets of "whitespace" and they are easy to mix up:
/// - `String.trim()` drops characters with code ≤ U+0020 (including control characters,
///   but **not** the non-breaking space U+00A0),
/// - `String.isBlank()` goes by `Character.isWhitespace`, which on the contrary does not treat U+00A0
///   (and U+2007, U+202F) as whitespace,
/// - the regex `\s` is only `[ \t\n\u{0B}\f\r]`.
///
/// Swift's `.whitespacesAndNewlines` does neither: it drops U+00A0
/// and keeps control characters (U+0001…U+0008, U+001C…U+001F). Where the input comes
/// from an **external data file** (`~/dxcc-json/`), this difference matters —
/// the prefix "OK\u{00A0}" is the key "OK\u{00A0}" in Java, for us it would be "OK",
/// and the lookup would then return a DXCC number where Java returns nothing.
enum JavaText {

    /// Java `a.equals(b)`: equality by UTF-16 units (`b == nil` → false). Swift's `==`
    /// compares canonically (`A` + U+030A = U+00C5), Java's does not.
    static func equals(_ left: String, _ right: String?) -> Bool {
        guard let right else { return false }
        return left.utf16.elementsEqual(right.utf16)
    }

    /// Equivalent of Java's `String.trim()`: drops characters ≤ U+0020 from both ends.
    static func trim(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, scalars[start].value <= 0x20 { start += 1 }
        while end > start, scalars[end - 1].value <= 0x20 { end -= 1 }
        if start == 0 && end == scalars.count { return text }
        scalars = Array(scalars[start..<end])
        return String(String.UnicodeScalarView(scalars))
    }

    /// Equivalent of Java's `String.strip()`: drops from both ends the characters for
    /// which `Character.isWhitespace` returns `true`. It is **not** `trim()` —
    /// control U+0001 `strip` keeps, U+3000 it drops (measured on JDK 21).
    static func strip(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isWhitespace($0) }) else {
            return ""
        }
        let last = scalars.lastIndex(where: { !isWhitespace($0) })!
        if first == scalars.startIndex && scalars.index(after: last) == scalars.endIndex {
            return text
        }
        return String(scalars[first...last])
    }

    /// Equivalent of Java's `String.split(regex, limit)` (= `Pattern.split`).
    ///
    /// A positive `limit` limits the number of parts and keeps trailing empty parts, zero
    /// removes trailing empty parts, negative keeps them. Empty input gives
    /// `[""]`; a leading empty part from a zero-width match at the start is not produced.
    static func split(_ text: String, regex: JavaRegex, limit: Int) -> [String] {
        regex.split(text, limit: limit)
    }

    /// Equivalent of Java's `String.isBlank()`: an empty string, or only characters
    /// for which `Character.isWhitespace` returns `true`.
    static func isBlank(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where !isWhitespace(scalar) {
            return false
        }
        return true
    }

    /// Equivalent of Java's `Character.isWhitespace(int)`.
    ///
    /// Whitespace are U+0009…U+000D, U+001C…U+001F and separators (categories `Zs`, `Zl`,
    /// `Zp`) **except** the non-breaking U+00A0, U+2007 and U+202F.
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x1C...0x1F:
            return true
        case 0xA0, 0x2007, 0x202F:
            return false
        default:
            switch scalar.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - toLowerCase and indices by UTF-16 units

/// Java `StringIndexOutOfBoundsException` from `substring`; message literally
/// (`Range [9, 8) out of bounds for length 13`, JDK 21).
/// Public because it is thrown by the public `AdifReader.read`/`readRecords`.
public struct JavaIndexOutOfBoundsError: Error, Equatable, Sendable {
    public let message: String
    /// The Java class: `StringIndexOutOfBoundsException` from `substring` (maintainer-only probe, row
    /// `ADIF.read`); `IndexOutOfBoundsException` where Java reads `List.get` (`WsjtxImportMapper`).
    public var javaClass: String = "java.lang.StringIndexOutOfBoundsException"
}

extension JavaText {

    /// Java `String.toLowerCase()` under the default locale `en_US`/`cs_CZ` (= `Locale.ROOT`).
    ///
    /// By code points the simple `Character.toLowerCase(int)`, except two
    /// conditional mappings from `ConditionalSpecialCasing`:
    /// - `U+0130` (İ) → `i` + `U+0307` — **two** UTF-16 units instead of one, so
    ///   indices found in the lowercased copy shift by one after every `İ` relative to
    ///   the original (the `AdifReader` exception rests on this);
    /// - `U+03A3` (Σ) → `ς` at the end of a word, otherwise `σ` (length does not change).
    ///
    /// Java takes word boundaries for the final sigma from `BreakIterator.getWordInstance`
    /// (older JDK rules, not UAX #29). Here is a simplification of them that
    /// fits all measured cases (`JavaTextLowerCaseTests`): a word consists of
    /// letters (`L*`, `Mc`) and digits (`N*`), `Mn`/`Me` attached to them,
    /// connectors `Pd`, `Pc`, `U+2027`, `"`, `'`, `.` between two letters
    /// and `"`, `'`, `,`, `U+066B`, `.` between two digits; `Cf` is transparent.
    /// "Cased" is taken from Swift's `isCased` property (complete, newer Unicode);
    /// Java's `ConditionalSpecialCasing.isCased` has a hardcoded older list of
    /// Other_Lowercase/Other_Uppercase (e.g. without `U+A69C`, `U+AB5C`) — a divergence
    /// only for such characters next to `Σ`.
    /// Turkish/Azerbaijani/Lithuanian behavior of Java (other default locales)
    /// is not emulated —.
    static func toLowerCase(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        for index in scalars.indices {
            let scalar = scalars[index]
            if scalar.value < 0x80 {
                let value = scalar.value
                out.append((value >= 0x41 && value <= 0x5A) ? Unicode.Scalar(value + 0x20)! : scalar)
            } else if scalar.value == 0x0130 {
                out.append("i")
                out.append("\u{0307}")
            } else if scalar.value == 0x03A3 {
                out.append(isFinalSigma(scalars, at: index) ? "\u{03C2}" : "\u{03C3}")
            } else {
                out.append(lowerCodePoint(scalar))
            }
        }
        return String(out)
    }

    /// Java `Character.toLowerCase(int)` — simple mapping to a single code point.
    /// The full mapping (`lowercaseMapping`) differs from the simple one only for `U+0130`.
    ///
    /// JDK 21 knows Unicode 15.0; Swift's standard library (depending on the system version)
    /// a newer one, where lowercase counterparts of new characters were added (`U+1C89`, `U+A7CB`,
    /// `U+10D50`…). Characters added after 15.0 are therefore left unchanged by Java — measured
    /// over all code points (`JavaTextLowerCaseTests.codePointTableMatchesJava`).
    static func lowerCodePoint(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.value == 0x0130 { return "i" }
        if let age = scalar.properties.age, age.major > 15 || (age.major == 15 && age.minor > 0) {
            return scalar
        }
        let mapping = scalar.properties.lowercaseMapping.unicodeScalars
        guard mapping.count == 1, let first = mapping.first else { return scalar }
        return first
    }

    /// Java `haystack.indexOf(needle, from)` by UTF-16 units: negative
    /// `from` = 0; an empty needle returns `min(from, length)`; otherwise `-1` when not found.
    static func indexOf(_ haystack: [UInt16], _ needle: [UInt16], from: Int = 0) -> Int {
        let start = max(from, 0)
        if needle.isEmpty { return min(start, haystack.count) }
        guard haystack.count >= needle.count else { return -1 }
        let last = haystack.count - needle.count
        guard start <= last else { return -1 }
        let first = needle[0]
        var index = start
        while index <= last {
            if haystack[index] == first {
                var matched = 1
                while matched < needle.count && haystack[index + matched] == needle[matched] {
                    matched += 1
                }
                if matched == needle.count { return index }
            }
            index += 1
        }
        return -1
    }

    /// Java `substring(begin, end)` by UTF-16 units: outside
    /// `0 ≤ begin ≤ end ≤ length` it throws `StringIndexOutOfBoundsException`.
    /// A cut in the middle of a surrogate pair gives `U+FFFD` (see `JavaChar.string`).
    static func substring(
        _ units: [UInt16], _ begin: Int, _ end: Int
    ) throws(JavaIndexOutOfBoundsError) -> String {
        guard begin >= 0, begin <= end, end <= units.count else {
            let range = "Range [" + String(begin) + ", " + String(end) + ")"
            throw JavaIndexOutOfBoundsError(
                message: range + " out of bounds for length " + String(units.count))
        }
        return JavaChar.string(Array(units[begin..<end]))
    }

    /// Java `substring(begin)` = `substring(begin, length())`.
    static func substring(_ units: [UInt16], _ begin: Int) throws(JavaIndexOutOfBoundsError) -> String {
        try substring(units, begin, units.count)
    }

    // MARK: Final sigma

    private enum WordClass {
        case letter, digit, attached, ignorable, other
    }

    private static func wordClass(_ scalar: Unicode.Scalar) -> WordClass {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .spacingMark:
            return isJavaCjkWordChar(scalar) ? .other : .letter
        case .decimalNumber, .letterNumber, .otherNumber:
            return .digit
        case .nonspacingMark, .enclosingMark:
            return .attached
        case .format:
            return .ignorable
        default:
            return .other
        }
    }

    /// Kanji, katakana, hiragana and their diacritics have their own words in older
    /// JDK rules — they do not belong to a letter word.
    private static func isJavaCjkWordChar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3005, 0x4E00...0x9FA5, 0xF900...0xFA2D, 0x30A1...0x30FA, 0x30FD, 0x30FE,
             0x3041...0x3094, 0x309D, 0x309E, 0x3099...0x309C, 0x30FB, 0x30FC:
            return true
        default:
            return false
        }
    }

    private static func isMidWord(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x22, 0x27, 0x2E, 0x00AD, 0x2027:
            return true
        default:
            let category = scalar.properties.generalCategory
            return category == .dashPunctuation || category == .connectorPunctuation
        }
    }

    private static func isMidNum(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x22, 0x27, 0x2C, 0x2E, 0x066B: return true
        default: return false
        }
    }

    /// Nearest "base" character (not `Cf`, not an attached mark) from `index` in direction `step`.
    private static func baseIndex(_ scalars: [Unicode.Scalar], from index: Int, step: Int) -> Int? {
        var i = index
        while i >= 0 && i < scalars.count {
            switch wordClass(scalars[i]) {
            case .ignorable, .attached:
                i += step
            default:
                return i
            }
        }
        return nil
    }

    /// Does `scalars[index]` (a connector character) belong to a word between neighboring bases?
    private static func joins(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        guard let before = baseIndex(scalars, from: index - 1, step: -1),
              let after = baseIndex(scalars, from: index + 1, step: 1) else { return false }
        let left = wordClass(scalars[before])
        let right = wordClass(scalars[after])
        if isMidWord(scalars[index]) && left == .letter && right == .letter { return true }
        return isMidNum(scalars[index]) && left == .digit && right == .digit
    }

    /// Is the character at `index` inside the same word as the sigma? (transparent characters yes)
    private static func inWord(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        switch wordClass(scalars[index]) {
        case .letter, .digit, .attached, .ignorable:
            return true
        case .other:
            return joins(scalars, index)
        }
    }

    /// `ConditionalSpecialCasing.isFinalCased`: in the word before the sigma there is a "cased"
    /// character and none after it.
    private static func isFinalSigma(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        var casedBefore = false
        var i = index - 1
        while i >= 0 && inWord(scalars, i) {
            if scalars[i].properties.isCased {
                casedBefore = true
                break
            }
            i -= 1
        }
        guard casedBefore else { return false }
        i = index + 1
        while i < scalars.count && inWord(scalars, i) {
            if scalars[i].properties.isCased { return false }
            i += 1
        }
        return true
    }
}
