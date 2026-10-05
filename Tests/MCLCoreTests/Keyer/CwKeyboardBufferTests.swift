import Testing
@testable import MCLCore

/// Port of `keyer/CwKeyboardBufferTest` (3) + `KB.*` measurements (maintainer-only probe) and `KKB.*`
/// (maintainer-only probe): positions in UTF-16, the separator only U+0020, Java `trim`, `\s` ASCII only.
@Suite struct CwKeyboardBufferTests {

    // MARK: - Port of CwKeyboardBufferTest

    @Test func wordByWord() {
        var b = CwKeyboardBuffer()
        #expect(b.onTextChanged("tn", wordByWord: true) == "")
        #expect(b.onTextChanged("tnx", wordByWord: true) == "")
        #expect(b.onTextChanged("tnx ", wordByWord: true) == "tnx")
        #expect(b.onTextChanged("tnx fe", wordByWord: true) == "")
        #expect(b.onTextChanged("tnx fer ", wordByWord: true) == "fer")
        #expect(b.flush("tnx fer qso") == "qso")
        #expect(b.flush("tnx fer qso") == "")
    }

    @Test func onEnterOnly() {
        var b = CwKeyboardBuffer()
        #expect(b.onTextChanged("pse qsy ", wordByWord: false) == "")
        #expect(b.flush("pse qsy up 2") == "pse qsy up 2")
        b.reset()
        #expect(b.sentUpTo == 0)
    }

    @Test func deletingDoesNotResend() {
        var b = CwKeyboardBuffer()
        _ = b.onTextChanged("abc ", wordByWord: true)
        #expect(b.onTextChanged("ab", wordByWord: true) == "")
        #expect(b.flush("ab") == "")
    }

    // MARK: - Measurements

    /// `KB.*` (research): one buffer over the whole sequence; `"tnx  "` returns "" and moves `sentUpTo` to 5.
    @Test func measuredResearchSequence() {
        var b = CwKeyboardBuffer()
        let steps: [(String, Bool)] = [
            ("t", true), ("tn", true), ("tnx ", true), ("tnx  ", true), ("tnx  fer", true), ("tnx  fer ", false),
            ("tnx", true), ("tnx fer qso ", true), ("", true), ("ab cd ", true),
        ]
        var rows: [String] = []
        for (text, wordByWord) in steps {
            let result = b.onTextChanged(text, wordByWord: wordByWord)
            rows.append(ProbeText.row("KB.onTextChanged", [ProbeText.esc(text), wordByWord ? "1" : "0",
                                                             ProbeText.esc(result), String(b.sentUpTo)]))
        }
        for text in ["ab cd ef", "ab"] {
            let result = b.flush(text)
            rows.append(ProbeText.row("KB.flush", [ProbeText.esc(text), ProbeText.esc(result), String(b.sentUpTo)]))
        }
        for text in ["  a  b\tc\u{00A0}d\u{2003}e  ", ""] {
            rows.append(ProbeText.row("KB.words", [ProbeText.esc(KeyerProbe.javaList(CwKeyboardBuffer.words(text)))]))
        }
        #expect(ProbeText.digest(rows) == "6e3669c3f5f209e67a307ce8931604e20a3aa0f2e0152ebc35b80bde8e5f17dd")
    }

    /// `KKB.step`: NBSP, U+2003, tab and U+0001 do not split words (not even in `onTextChanged`, only a space), `😀` = 2
    /// units, `trim` drops U+0001 at the edges, NBSP not; deleting below `sentUpTo` does not send the text again.
    @Test func measuredUnicodeSteps() {
        let scripts: [[(String, String)]] = [
            [("t", "1"), ("t\u{00A0}", "1"), ("t\u{00A0}x ", "1")],
            [("\u{1F600} ", "1"), ("\u{1F600} a\u{2003}b ", "1"), ("\u{1F600} a\u{2003}b c", "F")],
            [("ab\tcd", "1"), ("ab\tcd\t", "1"), ("ab\tcd\t ", "1")],
            [("abc def ", "1"), ("abc", "1"), ("abc def ", "1"), ("abc def", "F")],
            [("  x  ", "1"), ("  x  ", "1"), ("  x  y", "F")],
            [("x ", "0"), ("x y ", "1")],
            [("\u{0001}a\u{0001} ", "1"), ("\u{0001}a\u{0001} b\u{0001}", "F")],
            [("hello", "F"), ("hello world ", "1")],
            [("\u{017E}lu\u{0165} ", "1"), ("\u{017E}lu\u{0165} k\u{016F}\u{0148}\u{00A0}", "F")],
        ]
        var rows: [String] = []
        for (index, script) in scripts.enumerated() {
            var b = CwKeyboardBuffer()
            for (text, mode) in script {
                let result = mode == "F" ? b.flush(text) : b.onTextChanged(text, wordByWord: mode == "1")
                rows.append(ProbeText.row("KKB.step", [String(index), ProbeText.esc(text), mode,
                                                         ProbeText.esc(result), String(b.sentUpTo)]))
            }
        }
        #expect(rows.count == 24)
        #expect(ProbeText.digest(rows) == "20904fdcab55456ae4c4714fb44b82d3291ad7d9fc6505e707e3ab91c93528b7")
    }

    /// `KKB.words`: `split("\\s+")` ASCII only — NBSP, U+2003, U+0085, U+001C, U+200B do not split words;
    /// U+000B, `\f`, `\r` do; U+0001 at the edge is dropped by `trim`.
    @Test func measuredWords() {
        let inputs = ["a\u{00A0}b c", "a\u{2003}b", "a\u{0085}b", "a\u{001C}b", "a\u{000B}b\u{000C}c\rd", "\u{0001} a",
                      " \u{0001} ", "a\u{200B}b", "\u{1F600} \u{1F600}", "\t\ta\t\t", ""]
        let rows: [String] = inputs.map { text in
            ProbeText.row("KKB.words", [ProbeText.esc(text),
                                          ProbeText.esc(KeyerProbe.javaList(CwKeyboardBuffer.words(text)))])
        }
        #expect(ProbeText.digest(rows) == "d7b98d8b6c0f3ea3767f185c706cf9cf4f55d56494c23e1e1df358df07d1abc3")
        #expect(CwKeyboardBuffer.words("a\u{2003}b") == ["a\u{2003}b"])
    }
}
