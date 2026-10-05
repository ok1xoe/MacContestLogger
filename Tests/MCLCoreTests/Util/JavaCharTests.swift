import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// Tests of `JavaChar` — character predicates and conversions by UTF-16 units.
///
/// Values are measured on Java v1.1.1 (JDK 21.0.2, locale `en_US`) by a sweep
/// over the whole BMP. Two things from that sweep are worth writing down:
///
/// - `Character.isDigit(char)` coincides with our implementation (category `Nd`)
///   **completely**: 370 points in the BMP, zero differences;
/// - `Character.isLetterOrDigit(char)` and the upper/lower-case mapping
///   diverge only by the **Unicode version**. JDK 21 carries Unicode 15.0, the Swift
///   stdlib on macOS a newer one, so Swift knows 16 extra letters
///   (`088F 0C5C 0CDC 1C89 1C8A A7CB…A7DC A7F1`) and 8 new upper/lower pairs
///   (`019B 0264 1C8A A7CD A7CF A7D3 A7D5 A7DB`). None of them is in `[A-Z0-9/]`,
///   so they do not affect callsigns or word boundaries in real text. The tests here
///   therefore verify specific stable points, not sums that would
///   rot with a macOS update.
@Suite struct JavaCharTests {

    /// A "digit" is the whole category `Nd`, not just ASCII — and a surrogate unit is not.
    @Test func isDigitCoversCategoryNd() {
        #expect(JavaChar.isDigit(0x30))
        #expect(JavaChar.isDigit(0x39))
        #expect(!JavaChar.isDigit(0x2F))
        #expect(!JavaChar.isDigit(0x3A))
        #expect(!JavaChar.isDigit(0x41))
        #expect(JavaChar.isDigit(0x0661)) // Arabic-Indic one
        #expect(JavaChar.isDigit(0x09E7)) // Bengali one
        #expect(JavaChar.isDigit(0xFF10)) // fullwidth zero
        #expect(!JavaChar.isDigit(0x00B2)) // superscript two is `No`, not `Nd`
        #expect(!JavaChar.isDigit(0x2160)) // Roman numeral one is `Nl`
        #expect(!JavaChar.isDigit(0xD835)) // half of a surrogate pair
        #expect(!JavaChar.isDigit(0xDFCE))
    }

    /// Letter or digit — `_`, `/`, a non-breaking space and a combining
    /// character do not belong to it. This is exactly what holds the word boundary in `CallsignScanner`.
    @Test func isLetterOrDigitMatchesJava() {
        #expect(JavaChar.isLetterOrDigit(0x41))
        #expect(JavaChar.isLetterOrDigit(0x7A))
        #expect(JavaChar.isLetterOrDigit(0x35))
        #expect(!JavaChar.isLetterOrDigit(0x5F)) // _
        #expect(!JavaChar.isLetterOrDigit(0x2F)) // /
        #expect(!JavaChar.isLetterOrDigit(0x2D)) // -
        #expect(!JavaChar.isLetterOrDigit(0x20))
        #expect(!JavaChar.isLetterOrDigit(0x00A0))
        #expect(!JavaChar.isLetterOrDigit(0x0308)) // combining diaeresis is `Mn`
        #expect(JavaChar.isLetterOrDigit(0x00E9)) // é
        #expect(JavaChar.isLetterOrDigit(0x00DF)) // ß
        #expect(JavaChar.isLetterOrDigit(0x0661))
        #expect(JavaChar.isLetterOrDigit(0x4E00)) // CJK
        #expect(!JavaChar.isLetterOrDigit(0x2028))
    }

    /// `Character.isLetter(char)`: categories `Lu Ll Lt Lm Lo` — not a digit,
    /// not `Nl` (Roman numeral one, `〇`), not combining characters, not `_` nor half of
    /// a surrogate pair. On JDK 21 there are 48965 letters in the BMP (= `isLetterOrDigit`
    /// 49335 minus 370 digits `Nd`).
    @Test func isLetterMatchesJava() {
        let letters: [UInt16] = [
            0x41, 0x7A, 0xE9, 0xDF, 0x02B0, 0x01C5, 0x4E00, 0xAA, 0xBA, 0xB5, 0x3005, 0x2E2F,
        ]
        for unit in letters {
            #expect(JavaChar.isLetter(unit), "U+\(String(unit, radix: 16))")
        }
        let nonLetters: [UInt16] = [
            0x5F, 0x35, 0x0661, 0x2160, 0x0308, 0xD835, 0xDFCE, 0xA0, 0x3007, 0x0345, 0x2E, 0x20,
        ]
        for unit in nonLetters {
            #expect(!JavaChar.isLetter(unit), "U+\(String(unit, radix: 16))")
        }
    }

    /// Simple (1:1) mapping `Character.toUpperCase(char)`: where Java
    /// has no simple mapping, the character stays — even if a full mapping exists.
    @Test func simpleCaseMappingKeepsCharacterWhenFullMappingIsLonger() {
        #expect(JavaChar.toUpperCase(0x61) == 0x41)
        #expect(JavaChar.toUpperCase(0x41) == 0x41)
        #expect(JavaChar.toUpperCase(0x31) == 0x31)
        #expect(JavaChar.toUpperCase(0x00E9) == 0x00C9)
        #expect(JavaChar.toUpperCase(0x00B5) == 0x039C) // µ → Μ
        // The full mapping is longer than one unit → Java leaves the character.
        #expect(JavaChar.toUpperCase(0x00DF) == 0x00DF) // ß, fully "SS"
        #expect(JavaChar.toUpperCase(0x0149) == 0x0149) // ŉ, fully "ʼN"
        #expect(JavaChar.toUpperCase(0x0390) == 0x0390) // ΐ, fully three units
        // 27 Greek points with iota subscript **do** have a simple mapping,
        // even though the full mapping is two characters — hence they are in the table of exceptions.
        #expect(JavaChar.toUpperCase(0x1F80) == 0x1F88)
        #expect(JavaChar.toUpperCase(0x1F97) == 0x1F9F)
        #expect(JavaChar.toUpperCase(0x1FB3) == 0x1FBC)
        #expect(JavaChar.toUpperCase(0x1FC3) == 0x1FCC)
        #expect(JavaChar.toUpperCase(0x1FF3) == 0x1FFC)
    }

    /// Simple `Character.toLowerCase(char)`. The only BMP point where the full
    /// and simple mappings differ is `U+0130` (İ) — fully `i` + `U+0307`.
    @Test func simpleLowerCaseMapping() {
        #expect(JavaChar.toLowerCase(0x41) == 0x61)
        #expect(JavaChar.toLowerCase(0x61) == 0x61)
        #expect(JavaChar.toLowerCase(0x00C9) == 0x00E9)
        #expect(JavaChar.toLowerCase(0x0130) == 0x0069)
        #expect(JavaChar.toLowerCase(0x0131) == 0x0131) // ı stays
    }

    /// `equalsIgnoreCase`: `nil` gives `false`, a different UTF-16 length too.
    @Test func equalsIgnoreCaseFollowsJava() {
        #expect(JavaChar.equalsIgnoreCase("OK1XOE", "ok1xoe"))
        #expect(JavaChar.equalsIgnoreCase("OK1XOE", "OK1XOE"))
        #expect(JavaChar.equalsIgnoreCase("ok1xoe", "Ok1XoE"))
        #expect(!JavaChar.equalsIgnoreCase("OK1XOE", nil))
        #expect(!JavaChar.equalsIgnoreCase("OK1XOE", "OK1XO"))
        // And the other way round: shorter on the left. The length check must be for equality, not for
        // "fits" — otherwise a prefix would pass as a match.
        #expect(!JavaChar.equalsIgnoreCase("OK1XO", "OK1XOE"))
        #expect(!JavaChar.equalsIgnoreCase("OK1XOE", "DL1ABC"))
        #expect(JavaChar.equalsIgnoreCase("", ""))
        // ß vs SS: Java does not consider them equal (the length differs) and neither do we.
        #expect(!JavaChar.equalsIgnoreCase("\u{00DF}", "SS"))
        #expect(JavaChar.equalsIgnoreCase("STRA\u{00DF}E", "stra\u{00DF}e"))
    }

    /// Java `equalsIgnoreCase` tries **three** comparisons: direct, after
    /// `toUpperCase` and finally after `toLowerCase(toUpperCase(…))`. The last step
    /// is needed for pairs where the uppercase letters differ but the lowercase ones agree — without
    /// it these matches would fall through. Measured in Java, all return `true`.
    @Test func equalsIgnoreCaseNeedsTheLowercaseFallback() {
        #expect(JavaChar.equalsIgnoreCase("\u{00DF}", "\u{1E9E}")) // ß vs ẞ
        #expect(JavaChar.equalsIgnoreCase("\u{00DF}AB", "\u{1E9E}AB"))
        #expect(JavaChar.equalsIgnoreCase("K", "\u{212A}")) // K vs the Kelvin sign
        #expect(JavaChar.equalsIgnoreCase("\u{00C5}", "\u{212B}")) // Å vs the ångström sign
        // These, on the other hand, are satisfied by the second comparison (the uppercase letters already agree).
        #expect(JavaChar.equalsIgnoreCase("\u{0131}", "I")) // ı vs I
        #expect(JavaChar.equalsIgnoreCase("\u{0130}", "i")) // İ vs i
    }

    /// The regex `\s` without `UNICODE_CHARACTER_CLASS` is just `[ \t\n\u{0B}\f\r]`.
    @Test func regexSpaceIsAsciiOnly() {
        for unit: UInt16 in [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D] {
            #expect(JavaChar.isRegexSpace(unit))
        }
        for unit: UInt16 in [0x00, 0x08, 0x0E, 0x1C, 0x1F, 0x00A0, 0x2003, 0x2028, 0x3000] {
            #expect(!JavaChar.isRegexSpace(unit))
        }
    }

    /// `Character.isWhitespace(char)` over all 65,536 UTF-16 units (`TextTokens.words`)
    /// against JDK 21.0.2 (maintainer-only probe, row `WS.table`):
    /// 25 units — U+0009…U+000D, U+001C…U+001F, space, U+1680, U+2000…U+2006, U+2008…U+200A,
    /// U+2028, U+2029, U+205F, U+3000. **Not** NBSP (U+00A0), U+2007, U+202F, U+0085, U+200B
    /// nor half of a surrogate pair. Fingerprint = SHA-256 of the rows `XXXX\n` (hex uppercase).
    @Test func isWhitespaceUnitMatchesJava() {
        let expected: [UInt16] = [
            0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x001C, 0x001D, 0x001E, 0x001F, 0x0020,
            0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2008, 0x2009,
            0x200A, 0x2028, 0x2029, 0x205F, 0x3000,
        ]
        var actual: [UInt16] = []
        var hasher = SHA256()
        for value in 0...0xFFFF {
            let unit = UInt16(value)
            guard JavaChar.isWhitespace(unit) else { continue }
            actual.append(unit)
            let hex: String = String(value, radix: 16).uppercased()
            let line: String = String(repeating: "0", count: 4 - hex.count) + hex + "\n"
            hasher.update(data: Data(line.utf8))
        }
        let digest: String = hasher.finalize().map { byte in
            let text = String(byte, radix: 16)
            return byte < 16 ? "0" + text : text
        }.joined()
        #expect(actual == expected)
        #expect(digest == "a03bc39e2147086371f708086534e13ea1327ee08fc123b2ca3b99b866b7d065")
    }
}
