@testable import MCLCore
import Testing

/// The Digital Interface's helpers: Letters/Figures, the Master.scp search in garbage text, the validity routines and
/// the text received while transmitting.
@Suite struct DigitalRxToolsTests {

    @Test func lettersFiguresSwapTheShift() {
        #expect(LettersFigures.convert("TOO") == "599")
        #expect(LettersFigures.convert("ue") == "73")
        #expect(LettersFigures.convert("599") == "TOO")
        #expect(LettersFigures.convert("WT") == "25")
        #expect(LettersFigures.convert("X/Y") == "/X6")
        #expect(LettersFigures.convert("A B=") == "- ?=")
    }

    @Test func garbageSearchFindsTheLastAndLongestKnownCall() {
        let known: Set<String> = ["DL1ABC", "K1ZZ", "DL1AB"]
        let contains: (String) -> Bool = { known.contains($0) }
        let found = ScpGarbageSearch.find("XXDL1ABCQQ", contains: contains)
        #expect(found?.call == "DL1ABC" && found?.start == 2 && found?.end == 8)
        #expect(ScpGarbageSearch.find("dl1abcEEk1zzT", contains: contains)?.call == "K1ZZ")
        #expect(ScpGarbageSearch.find("QQQQQ", contains: contains) == nil)
        #expect(ScpGarbageSearch.find("K1Z", contains: contains) == nil)
    }

    @Test func validityModes() {
        #expect(DigitalCallValidity.generic.highlight(verified: false) == false)
        #expect(DigitalCallValidity.resources.highlight(verified: false) == nil)
        #expect(DigitalCallValidity.resources.highlight(verified: true) == false)
        #expect(DigitalCallValidity.combined.highlight(verified: false) == true)
        #expect(DigitalCallValidity.combined.highlight(verified: true) == false)
        #expect(DigitalCallValidity.from("nonsense") == .combined)
    }

    @Test func transmittedRangesFollowTheTrim() {
        let stream = RxTextStream(maxChars: 10)
        stream.append("AB ")
        stream.append("OK1XOE", transmitting: true)
        stream.append(" ", transmitting: true)
        #expect(stream.transmitted == [3..<10])
        #expect(stream.isTransmitted(5) && !stream.isTransmitted(1))
        stream.append("DL")
        #expect(stream.text == " OK1XOE DL")
        #expect(stream.transmitted == [1..<8])
        stream.clear()
        #expect(stream.transmitted.isEmpty)
    }
}
