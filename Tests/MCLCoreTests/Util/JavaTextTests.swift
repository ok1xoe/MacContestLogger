import Testing
@testable import MCLCore

/// Tests of `JavaText` — three different Java whitespace sets.
///
/// Values are measured on Java v1.1.1 (behaviour of `String.trim()`,
/// `String.isBlank()` and `Character.isWhitespace`), because the prefix keys
/// in `DxccCodeIndex` and the emptiness of a callsign in `DxccResolver` stand on them.
@Suite struct JavaTextTests {

    /// `trim()` drops characters ≤ U+0020 — so also control characters, but **not** U+00A0.
    @Test func trimDropsControlCharactersButKeepsNonBreakingSpace() {
        #expect(JavaText.trim("  OK  ") == "OK")
        #expect(JavaText.trim("\t\nOK\r\n") == "OK")
        #expect(JavaText.trim("\u{01}OK\u{1F}") == "OK")
        #expect(JavaText.trim("\u{00a0}OK\u{00a0}") == "\u{00a0}OK\u{00a0}")
        #expect(JavaText.trim("OK\u{00a0}") == "OK\u{00a0}")
        #expect(JavaText.trim("   ") == "")
        #expect(JavaText.trim("") == "")
        #expect(JavaText.trim("O K") == "O K")
    }

    /// `isBlank()` goes by `Character.isWhitespace`, where U+00A0 (and U+2007,
    /// U+202F) is **not** white, whereas U+2003 or U+2028 are.
    @Test func isBlankFollowsCharacterIsWhitespace() {
        #expect(JavaText.isBlank(""))
        #expect(JavaText.isBlank(" \t\n\r\u{0B}\u{0C}"))
        #expect(JavaText.isBlank("\u{1C}\u{1F}"))
        #expect(JavaText.isBlank("\u{2003}"))
        #expect(JavaText.isBlank("\u{2028}\u{2029}"))
        #expect(!JavaText.isBlank("\u{00a0}"))
        #expect(!JavaText.isBlank("\u{2007}"))
        #expect(!JavaText.isBlank("\u{202F}"))
        #expect(!JavaText.isBlank("OK"))
        #expect(!JavaText.isBlank(" OK "))
        // Control characters outside the ranges 09–0D and 1C–1F are not white (not even in Java).
        #expect(!JavaText.isBlank("\u{01}"))
    }

    /// `String.strip()` goes by `Character.isWhitespace` — **not** by
    /// `trim()`. Measured on JDK 21.0.2: control U+0001 is kept by `strip` (`trim` drops
    /// it), U+0085 is kept by both, U+2003 and U+3000 are dropped only by `strip`,
    /// U+00A0 is kept by both.
    @Test func stripFollowsCharacterIsWhitespace() {
        #expect(JavaText.strip(" \u{85}a\u{85} ") == "\u{85}a\u{85}")
        #expect(JavaText.strip("\u{1}a\u{1}") == "\u{1}a\u{1}")
        #expect(JavaText.strip("\u{A0}a\u{A0}") == "\u{A0}a\u{A0}")
        #expect(JavaText.strip("\u{2003}a\u{3000}") == "a")
        #expect(JavaText.strip("\u{1C}a\u{1F}") == "a")
        #expect(JavaText.strip(" a ") == "a")
        #expect(JavaText.strip("") == "")
        #expect(JavaText.strip(" \t\n ") == "")
        #expect(JavaText.strip("a b") == "a b")
    }

    /// `String.split(regex, limit)` — measured on JDK 21.0.2. A positive limit
    /// keeps trailing empty parts, zero removes them, negative keeps them;
    /// an empty input gives `[""]` and a lone delimiter with limit 0 an empty array.
    @Test func splitFollowsJavaLimits() throws {
        let comma = try JavaRegex(",")
        #expect(JavaText.split("a,,b,,", regex: comma, limit: 0) == ["a", "", "b"])
        #expect(JavaText.split("a,,b,,", regex: comma, limit: 2) == ["a", ",b,,"])
        #expect(JavaText.split("a,,b,,", regex: comma, limit: 3) == ["a", "", "b,,"])
        #expect(JavaText.split("a,,b,,", regex: comma, limit: -1) == ["a", "", "b", "", ""])
        #expect(JavaText.split("a,,b,,", regex: comma, limit: 1) == ["a,,b,,"])
        for limit in [0, 1, 2, 3, -1] {
            #expect(JavaText.split("", regex: comma, limit: limit) == [""])
        }
        #expect(JavaText.split(",", regex: comma, limit: 0) == [])
        #expect(JavaText.split(",", regex: comma, limit: 2) == ["", ""])
        #expect(JavaText.split(",", regex: comma, limit: 3) == ["", ""])
        #expect(JavaText.split(",", regex: comma, limit: 1) == [","])
        // A leading empty part from a zero-width match is not produced (Java 8+).
        let beforeDigit = try JavaRegex("(?=\\d)")
        #expect(JavaText.split("a1b2c", regex: beforeDigit, limit: 0) == ["a", "1b", "2c"])
        #expect(JavaText.split("1a", regex: try JavaRegex("\\d"), limit: 0) == ["", "a"])
    }
}
