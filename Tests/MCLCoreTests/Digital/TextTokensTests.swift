import Testing
@testable import MCLCore

/// Port of `digital/TextTokensTest` (5 tests; names translated).
@Suite struct TextTokensTests {

    @Test func splitsWordsWithPositions() {
        let t = TextTokens.words("OK1K 599 15")
        #expect(t.count == 3)
        #expect(t[0].word == "OK1K")
        #expect(t[0].start == 0)
        #expect(t[0].end == 4)
        #expect(t[1].start == 5)
        #expect(t[2].word == "15")
        #expect(t[2].start == 9)
    }

    @Test func handlesMultipleSpacesAndNewlines() {
        let t = TextTokens.words("  CQ\n\n TEST  ")
        #expect(t.map(\.word) == ["CQ", "TEST"])
        #expect(t[0].start == 2)
        #expect(t[1].start == 7)
    }

    @Test func byLineKeepsPositionsInWholeText() {
        let text = "CQ OK1K\nW3LPL 599 05 NY\n"
        let lines = TextTokens.byLine(text)
        #expect(lines.count == 2)
        #expect(lines[0].map(\.word) == ["CQ", "OK1K"])
        let second = lines[1]
        #expect(second.map(\.word) == ["W3LPL", "599", "05", "NY"])
        #expect(second[0].start == 8, "the position must hold in the whole text, not in the row")
        let units = Array(text.utf16)
        #expect(String(decoding: units[second[3].start..<second[3].end], as: UTF16.self) == "NY")
    }

    @Test func byLineSkipsEmptyLines() {
        #expect(TextTokens.byLine("\n\n  \nOK1K\n").count == 1)
        #expect(TextTokens.byLine("").isEmpty)
        #expect(TextTokens.byLine(nil).isEmpty)
    }

    @Test func emptyTextReturnsNothing() {
        #expect(TextTokens.words("").isEmpty)
        #expect(TextTokens.words(nil).isEmpty)
        #expect(TextTokens.words("   ").isEmpty)
    }
}
