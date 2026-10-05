import Testing
@testable import MCLCore

/// Port of `digital/RxTextStreamTest` (9 tests; names translated).
@Suite struct RxTextStreamTests {

    @Test func emptyBufferHasNothingToFetch() {
        let s = RxTextStream(maxChars: 100)
        #expect(s.pending(0) == nil)
        #expect(s.text == "")
    }

    @Test func firstPollFetchesWholeBuffer() throws {
        let s = RxTextStream(maxChars: 100)
        let span = try #require(s.pending(5))
        #expect(span.start == 0)
        #expect(span.length == 5)
        s.append("CQ TE")
        #expect(s.text == "CQ TE")
    }

    @Test func nextPollFetchesOnlyTheIncrement() throws {
        let s = RxTextStream(maxChars: 100)
        _ = s.pending(5)
        s.append("CQ TE")
        #expect(s.pending(5) == nil)
        let span = try #require(s.pending(8))
        #expect(span.start == 5)
        #expect(span.length == 3)
        s.append("ST ")
        #expect(s.text == "CQ TEST ")
    }

    @Test func shorterReplyAdvancesOffsetOnlyByReceived() throws {
        let s = RxTextStream(maxChars: 100)
        _ = s.pending(8)
        s.append("CQ TE") // fldigi returned less than we wanted
        let span = try #require(s.pending(8))
        #expect(span.start == 5)
        #expect(span.length == 3)
    }

    @Test func bufferClearedInFldigiRestartsReadingFromStart() throws {
        let s = RxTextStream(maxChars: 100)
        _ = s.pending(7)
        s.append("CQ TEST")
        // fldigi reports a shorter buffer → the user cleared it in fldigi
        let span = try #require(s.pending(3))
        #expect(span.start == 0)
        #expect(span.length == 3)
        s.append("DL1")
        #expect(s.text == "CQ TESTDL1", "the history in the window stays")
    }

    @Test func textIsTruncatedToMaximum() {
        let s = RxTextStream(maxChars: 5)
        _ = s.pending(8)
        s.append("CQ TEST ")
        #expect(s.text == "TEST ")
    }

    @Test func controlCharactersAreDroppedNewlineStays() {
        let s = RxTextStream(maxChars: 100)
        _ = s.pending(10)
        s.append("CQ\u{7} TE\r\nST")
        #expect(s.text == "CQ TE\nST")
    }

    @Test func offsetAdvancesByOriginalNotByCleanedText() {
        let s = RxTextStream(maxChars: 100)
        _ = s.pending(6)
        s.append("CQ\u{7} TE") // 6 characters from fldigi, 5 displayed
        #expect(s.pending(6) == nil)
    }

    @Test func clearErasesTextButNotOffset() {
        let s = RxTextStream(maxChars: 100)
        _ = s.pending(7)
        s.append("CQ TEST")
        s.clear()
        #expect(s.text == "")
        #expect(s.pending(9) != nil)
        #expect(s.pending(9)?.start == 7)
    }
}
