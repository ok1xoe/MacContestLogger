import Testing
@testable import MCLCore

/// `JavaText.replace` (`String.replace(CharSequence, CharSequence)`) a `JavaText.split(_:unit:)`
/// (`String.split` with one character) — JDK 21 behaviour ported from the `String` source.
@Suite struct JavaTextReplaceTests {

    @Test func replaceWorksOnUtf16Units() {
        #expect(JavaText.replace("a!b!", "!", "-") == "a-b-")
        #expect(JavaText.replace("aaa", "aa", "b") == "ba")
        #expect(JavaText.replace("ab", "", "-") == "-a-b-")
        #expect(JavaText.replace("", "", "x") == "x")
        #expect(JavaText.replace("abc", "x", "y") == "abc")
        // `!` + U+0301 is one grapheme in Swift, two units in Java — the `!` is replaced.
        #expect(JavaText.replace("!\u{301}", "!", "X") == "X\u{301}")
        #expect(JavaText.replace("\u{E9}", "e", "x") == "\u{E9}")
    }

    @Test func splitDropsTrailingEmptyStrings() {
        #expect(JavaText.split(",a,,", unit: 0x2C) == ["", "a"])
        #expect(JavaText.split("", unit: 0x2C) == [""])
        #expect(JavaText.split(",", unit: 0x2C) == [])
        #expect(JavaText.split("abc", unit: 0x2C) == ["abc"])
        #expect(JavaText.split(",\u{301}x", unit: 0x2C) == ["", "\u{301}x"])
    }
}
