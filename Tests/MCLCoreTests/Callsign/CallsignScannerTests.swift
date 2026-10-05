import Testing
@testable import MCLCore

/// Tests of finding callsigns in decoded text. The first five mirror the Java
/// `CallsignScannerTest`; the rest are cases **measured on Java v1.1.1**
/// (locale `en_US`, JDK 21.0.2).
@Suite struct CallsignScannerTests {

    /// Java `scanVraciVolackySPozicemiVTextu`.
    @Test func scanReturnsCallsignsWithPositions() {
        let hits = CallsignScanner.scan("CQ TEST OK1XOE OK1XOE")
        #expect(hits.count == 2)
        #expect(hits[0].call == "OK1XOE")
        #expect(hits[0].start == 8)
        #expect(hits[0].end == 14)
        #expect(hits[1].start == 15)
    }

    /// Java `scanZvladaMalaPismenaAVraciVelka`.
    @Test func scanHandlesLowercaseAndReturnsUppercase() {
        let hits = CallsignScanner.scan("de sp9/ok1xoe/p k")
        #expect(hits.count == 1)
        #expect(hits[0].call == "SP9/OK1XOE/P")
        #expect(hits[0].start == 3)
    }

    /// Java `scanIgnorujeReportyACisla`.
    @Test func scanIgnoresReportsAndNumbers() {
        #expect(CallsignScanner.scan("599 5NN 15 TU").isEmpty)
    }

    /// Java `recentVraciOdNejnovejsiBezVlastniVolacky`.
    @Test func recentReturnsNewestFirstWithoutOwnCallsign() {
        #expect(
            CallsignScanner.recent("CQ TEST OK2XYZ  OK1XOE 5NN 15 TU DL1ABC 599 *E", myCall: "OK1XOE")
                == ["DL1ABC", "OK2XYZ"])
    }

    /// Java `recentOdstranujeDuplicity`.
    @Test func recentRemovesDuplicates() {
        #expect(CallsignScanner.recent("DL1ABC DL1ABC DL1ABC", myCall: "OK1XOE") == ["DL1ABC"])
    }

    /// `nil` and empty input give an empty list, not `nil`.
    @Test func emptyInputGivesEmptyResult() {
        #expect(CallsignScanner.scan(nil).isEmpty)
        #expect(CallsignScanner.scan("").isEmpty)
        #expect(CallsignScanner.recent(nil, myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("   ", myCall: "OK1XOE").isEmpty)
    }

    /// Word boundary: a finding must not neighbour a letter, a digit or `/`.
    /// Punctuation and an underscore may be neighbours (`_` is not `isLetterOrDigit`).
    @Test func scanRequiresWholeWordBoundaries() {
        #expect(CallsignScanner.scan("OK1XOE/").isEmpty)
        #expect(CallsignScanner.scan("/OK1XOE").isEmpty)
        #expect(CallsignScanner.scan("OK1XOE1").isEmpty)
        #expect(CallsignScanner.scan("A/B/OK1XOE/C/D").isEmpty)
        #expect(CallsignScanner.scan("SP9/OK1XOE/P/X").isEmpty)
        #expect(CallsignScanner.scan("-OK1XOE-") == [.init(start: 1, end: 7, call: "OK1XOE")])
        #expect(CallsignScanner.scan(".OK1XOE.") == [.init(start: 1, end: 7, call: "OK1XOE")])
        #expect(CallsignScanner.scan("_OK1XOE_") == [.init(start: 1, end: 7, call: "OK1XOE")])
        // A combining character and a non-breaking space are not a letter/digit.
        #expect(CallsignScanner.scan("\u{0308}OK1XOE") == [.init(start: 1, end: 7, call: "OK1XOE")])
        #expect(CallsignScanner.scan("OK1XOE\u{0308}") == [.init(start: 0, end: 6, call: "OK1XOE")])
        #expect(CallsignScanner.scan("\u{00a0}OK1XOE\u{00a0}") == [.init(start: 1, end: 7, call: "OK1XOE")])
        // `é`, on the other hand, is a letter, so the finding falls out.
        #expect(CallsignScanner.scan("\u{00E9}OK1XOE").isEmpty)
        #expect(CallsignScanner.scan("OK1XOE\u{00E9}").isEmpty)
        // The regex itself takes even what is not a callsign, if the whole word satisfies the pattern.
        #expect(CallsignScanner.scan("XOK1XOE") == [.init(start: 0, end: 7, call: "XOK1XOE")])
        #expect(CallsignScanner.scan("OK1XOEX") == [.init(start: 0, end: 7, call: "OK1XOEX")])
        #expect(
            CallsignScanner.scan("OK1XOE,DL1ABC")
                == [.init(start: 0, end: 6, call: "OK1XOE"), .init(start: 7, end: 13, call: "DL1ABC")])
    }

    /// **A recorded divergence.** Java matches over the uppercased text, but
    /// verifies boundaries over the original; when uppercasing lengthens
    /// (`ß→SS`), the indices diverge. Up to six "ß" Java coincidentally returns
    /// an empty list (the start check hits a callsign character), from seven
    /// it **crashes** with `StringIndexOutOfBoundsException`. Here an unverifiable
    /// finding is dropped and the scan continues — so an empty list in both bands.
    @Test func scanSurvivesUppercasingThatChangesLength() {
        #expect(CallsignScanner.scan("\u{00DF} ok1xoe").isEmpty)       // Java: empty
        #expect(CallsignScanner.scan("\u{00DF}  ok1xoe").isEmpty)      // Java: empty
        #expect(CallsignScanner.scan("a\u{00DF}b ok1xoe dl1abc").isEmpty)  // Java: empty
        #expect(CallsignScanner.scan("\u{FB01} ok1xoe").isEmpty)       // Java: empty
        // The shortest reproduction of the exception that fell out of the corpus: "ﬁ1X" is three
        // units, the uppercased "FI1X" four, the finding is 0..4 and Java reaches for
        // `charAt(4)` in a three-character text.
        #expect(CallsignScanner.scan("\u{FB01}1X").isEmpty)
        #expect(CallsignScanner.scan("\u{00DF}").isEmpty)              // Java: empty
        // From here Java throws an exception; we return an empty list.
        #expect(CallsignScanner.scan(String(repeating: "\u{00DF}", count: 7) + " ok1xoe").isEmpty)
        #expect(CallsignScanner.scan(String(repeating: "\u{00DF}", count: 9) + " ok1xoe").isEmpty)
        #expect(CallsignScanner.scan(String(repeating: "\u{0390}", count: 4) + " ok1xoe").isEmpty)
        // A lengthening **after** the callsign does not shift the indices, the finding stays.
        #expect(CallsignScanner.scan("ok1xoe \u{00DF}") == [.init(start: 0, end: 6, call: "OK1XOE")])
        // A non-breaking space does not change the length, so two findings next to each other pass.
        #expect(
            CallsignScanner.scan("ok1xoe\u{00a0}dl1abc")
                == [.init(start: 0, end: 6, call: "OK1XOE"), .init(start: 7, end: 13, call: "DL1ABC")])
    }

    /// `recent` splits words with the Java regex `\s` = `[ \t\n\u{0B}\f\r]`.
    /// A non-breaking space and U+001C…U+001F do not separate words, even though Java
    /// `trim()` drops them from the edges.
    @Test func recentSplitsOnJavaRegexWhitespaceOnly() {
        #expect(CallsignScanner.recent("DL1ABC\u{0B}OK2XYZ", myCall: "OK1XOE") == ["OK2XYZ", "DL1ABC"])
        #expect(CallsignScanner.recent("DL1ABC\u{00a0}OK2XYZ", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("DL1ABC\u{1C}OK2XYZ", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("\u{00DF} dl1abc", myCall: "OK1XOE") == ["DL1ABC"])
    }

    /// `recent` filters: own callsign regardless of letter case,
    /// an asterisk from a CW correction and words only from `[0-9TN]`. Note that `TU` does not
    /// fall into `[0-9TN]+` (`U` is not in the set) — it is dropped only because it is not a
    /// callsign. `myCall == nil` drops nothing.
    @Test func recentFiltersReportsCorrectionsAndOwnCallsign() {
        #expect(CallsignScanner.recent("DL1ABC", myCall: nil) == ["DL1ABC"])
        #expect(CallsignScanner.recent("dl1abc ok1xoe", myCall: "ok1xoe") == ["DL1ABC"])
        #expect(CallsignScanner.recent("TN TU 599 5NN DL1ABC", myCall: "OK1XOE") == ["DL1ABC"])
        #expect(CallsignScanner.recent("DL1ABC* DL2ABC", myCall: "OK1XOE") == ["DL2ABC"])
    }

    /// Word boundaries are verified by **UTF-16 units**, not by graphemes.
    /// A combining character sticks to the preceding letter into one grapheme in Swift,
    /// so `Array(text.unicodeScalars)`-per-grapheme would shift the indices
    /// and the findings would vanish. Measured on Java: `scan("OK1XOE\u{0308}DL1ABC")` gives
    /// `[(0,6,OK1XOE),(7,13,DL1ABC)]`, a version over graphemes gives an empty list.
    @Test func scanIndexesByUtf16UnitsNotGraphemes() {
        #expect(
            CallsignScanner.scan("OK1XOE\u{0308}DL1ABC")
                == [.init(start: 0, end: 6, call: "OK1XOE"), .init(start: 7, end: 13, call: "DL1ABC")])
        #expect(
            CallsignScanner.scan("OK1XOE\u{0308} DL1ABC")
                == [.init(start: 0, end: 6, call: "OK1XOE"), .init(start: 8, end: 14, call: "DL1ABC")])
        #expect(CallsignScanner.scan("A\u{0308}OK1XOE") == [.init(start: 2, end: 8, call: "OK1XOE")])
        #expect(
            CallsignScanner.scan("OK1XOE\u{0301}DL1ABC\u{0301}OK2XYZ")
                == [
                    .init(start: 0, end: 6, call: "OK1XOE"),
                    .init(start: 7, end: 13, call: "DL1ABC"),
                    .init(start: 14, end: 20, call: "OK2XYZ"),
                ])
        #expect(
            CallsignScanner.scan("\u{0308}OK1XOE\u{0308}DL1ABC\u{0308}")
                == [.init(start: 1, end: 7, call: "OK1XOE"), .init(start: 8, end: 14, call: "DL1ABC")])
    }

    /// `recent` requires a match of the **whole** word (Java `Matcher.matches()`),
    /// not just a substring — and for both patterns. `XXDL1ABCXX` contains a callsign, but
    /// the whole word is not a callsign; `599X`, on the other hand, does not fill `[0-9TN]+` entirely, so it
    /// **does not pass** the report filter and is a callsign.
    @Test func recentRequiresTheWholeWordToMatch() {
        #expect(CallsignScanner.recent("XXDL1ABCXX DL1ABC", myCall: "OK1XOE") == ["DL1ABC"])
        #expect(CallsignScanner.recent("XXDL1ABCXX", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("(DL1ABC)", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("DL1ABC.", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("599X DL1ABC", myCall: "OK1XOE") == ["DL1ABC", "599X"])
        #expect(CallsignScanner.recent("599X", myCall: "OK1XOE") == ["599X"])
        #expect(CallsignScanner.recent("5NN1T DL1ABC", myCall: "OK1XOE") == ["DL1ABC"])
        #expect(CallsignScanner.recent("TN9T", myCall: "OK1XOE").isEmpty)
    }

    /// `recent` drops the edges with Java `trim()` (characters ≤ U+0020), not Swift
    /// `.whitespacesAndNewlines`. The two sets diverge both ways:
    /// a non-breaking space is dropped by Swift trim and not by Java, control characters on the contrary
    /// are dropped by Java and not by Swift trim. Without trim not even the control ones would be removed,
    /// because `\s` in Java contains only `[ \t\n\u{0B}\f\r]`.
    @Test func recentTrimsWithJavaTrimNotSwiftWhitespace() {
        // Non-breaking and wide spaces are not dropped by Java → the word is not a callsign.
        #expect(CallsignScanner.recent("\u{00a0}DL1ABC", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("DL1ABC\u{00a0}", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("\u{2007}DL1ABC", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("\u{3000}DL1ABC", myCall: "OK1XOE").isEmpty)
        #expect(CallsignScanner.recent("\u{7F}DL1ABC", myCall: "OK1XOE").isEmpty)
        // Control characters ≤ U+0020 are dropped by Java even though `\s` does not know them.
        #expect(CallsignScanner.recent("\u{01}DL1ABC\u{01}", myCall: "OK1XOE") == ["DL1ABC"])
        #expect(CallsignScanner.recent("\u{1F}DL1ABC\u{0E}", myCall: "OK1XOE") == ["DL1ABC"])
    }

    /// The own callsign is compared with Java `equalsIgnoreCase`, which first
    /// requires the **same length** in UTF-16 units. A word that is only a prefix of
    /// `myCall` is therefore not dropped.
    @Test func recentOwnCallsignComparisonNeedsEqualLength() {
        #expect(CallsignScanner.recent("DL1AB", myCall: "DL1ABC") == ["DL1AB"])
        #expect(CallsignScanner.recent("DL1ABC", myCall: "DL1AB") == ["DL1ABC"])
        #expect(CallsignScanner.recent("DL1ABC", myCall: "dl1abc").isEmpty)
    }

    /// The pattern is a public constant and must be verbatim the Java one.
    @Test func patternIsTheJavaOne() {
        #expect(
            CallsignScanner.callsignPattern
                == "(?:[A-Z0-9]{1,3}/)?[A-Z0-9]{1,3}[0-9][A-Z0-9]{0,3}[A-Z](?:/[A-Z0-9]{1,4})?")
    }
}
