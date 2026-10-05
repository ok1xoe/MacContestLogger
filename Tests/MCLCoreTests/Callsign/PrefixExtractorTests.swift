import Testing
@testable import MCLCore

/// Tests of the WPX prefix. Mirrors the Java `PrefixExtractorTest`, which is
/// a `@ParameterizedTest` with a `@CsvSource` of **ten** rows — here it is
/// `@Test(arguments:)` with the same ten.
///
/// The rest are cases **measured on Java v1.1.1** (locale `en_US`, JDK 21.0.2)
/// by a small `Probe.java` against `build/classes/java/main`. They are not designed
/// rules but a capture of the behaviour Java has today.
@Suite struct PrefixExtractorTests {

    /// Ten cases from the Java `@CsvSource`, verbatim.
    @Test(arguments: [
        ("OK1XOE", "OK1"),
        ("W3ABC", "W3"),
        ("2E0ABC", "2E0"),
        ("9A1AA", "9A1"),
        ("K1ABC/7", "K7"),
        ("DL/W1ABC", "DL0"),
        ("W1/OK1XOE", "W1"),
        ("G3ABC/P", "G3"),
        ("OK1XOE/MM", "OK1"),
        ("RAEM", "RA0"),
    ])
    func wpxPrefix(call: String, expected: String) {
        #expect(PrefixExtractor.wpx(call) == expected)
    }

    /// `nil` and blank input give an empty string, not `nil` and not an exception.
    /// Note: U+00A0 is **not** blank (Java `isBlank()` does not consider it
    /// whitespace), so it passes on and becomes the prefix `"\u{00A0}0"`.
    @Test func blankInputGivesEmptyString() {
        #expect(PrefixExtractor.wpx(nil) == "")
        #expect(PrefixExtractor.wpx("") == "")
        #expect(PrefixExtractor.wpx("   ") == "")
        #expect(PrefixExtractor.wpx("\t\n") == "")
        #expect(PrefixExtractor.wpx("\u{1C}\u{1F}") == "")
        #expect(PrefixExtractor.wpx("\u{00a0}") == "\u{00a0}0")
    }

    /// The edges are dropped by Java `trim()` (characters ≤ U+0020), not by Swift
    /// `.whitespacesAndNewlines`. A non-breaking space **stays** and changes the prefix —
    /// exactly the path by which a spot from a cluster or text pasted
    /// from the web gets into a callsign.
    @Test func trimUsesJavaWhitespaceSet() {
        #expect(PrefixExtractor.wpx("  OK1XOE  ") == "OK1")
        #expect(PrefixExtractor.wpx("\u{01}OK1XOE\u{01}") == "OK1")
        #expect(PrefixExtractor.wpx("\u{00a0}OK1XOE") == "\u{00a0}OK1")
        #expect(PrefixExtractor.wpx("OK1XOE\u{00a0}") == "OK1")
        #expect(PrefixExtractor.wpx("\u{2007}OK1XOE") == "\u{2007}OK1")
        #expect(PrefixExtractor.wpx("\u{3000}OK1XOE") == "\u{3000}OK1")
        #expect(PrefixExtractor.wpx("\u{7F}OK1XOE") == "\u{7F}OK1")
    }

    /// Uppercasing is the first transformation after trim.
    @Test func inputIsUppercased() {
        #expect(PrefixExtractor.wpx("ok1xoe") == "OK1")
        #expect(PrefixExtractor.wpx("Ok1XoE") == "OK1")
        #expect(PrefixExtractor.wpx("g3abc/p") == "G3")
    }

    /// **Measured existing behaviour, not a design.** Java code recognises as an
    /// area indicator only a token with **exactly one** ASCII digit (`t.matches("\\d")`).
    /// A two-digit `/12` therefore falls among ordinary parts, and because it is shorter than
    /// the callsign, it wins as the "portable prefix override" — `K1ABC/12` returns
    /// `"12"`, i.e. a prefix without letters. This is an open question;
    /// this test merely pins what Java does today.
    @Test func twoDigitTokenIsNotAnAreaIndicator() {
        #expect(PrefixExtractor.wpx("K1ABC/12") == "12")
        #expect(PrefixExtractor.wpx("OK1XOE/12") == "12")
        #expect(PrefixExtractor.wpx("K1ABC/12/P") == "12")
        #expect(PrefixExtractor.wpx("OK1XOE/123") == "123")
        #expect(PrefixExtractor.wpx("K1ABC/07") == "07")
        #expect(PrefixExtractor.wpx("/12") == "12")
        #expect(PrefixExtractor.wpx("12") == "12")
        // `DL/12`, on the other hand, returns `DL0`: is `DL` shorter than `12`? No — both have
        // two characters, so the **first** wins (strict `<` in Java `shortest`).
        #expect(PrefixExtractor.wpx("DL/12") == "DL0")
        // A one-digit indicator, on the other hand, works and the **last** one found is taken.
        #expect(PrefixExtractor.wpx("K1ABC/0") == "K0")
        #expect(PrefixExtractor.wpx("K1ABC/7/9") == "K9")
        #expect(PrefixExtractor.wpx("W1ABC/1/2") == "W2")
    }

    /// Degenerate inputs: only suffixes, empty parts, slashes at the edges.
    @Test func degenerateSlashForms() {
        #expect(PrefixExtractor.wpx("P") == "P0")
        #expect(PrefixExtractor.wpx("/P") == "P0")
        #expect(PrefixExtractor.wpx("MM/P") == "MM0")
        #expect(PrefixExtractor.wpx("OK1XOE/") == "OK1")
        #expect(PrefixExtractor.wpx("/OK1XOE") == "OK1")
        #expect(PrefixExtractor.wpx("//") == "0")
        #expect(PrefixExtractor.wpx("OK1XOE//P") == "OK1")
        #expect(PrefixExtractor.wpx("A/B") == "AB0")
        #expect(PrefixExtractor.wpx("AB/CD") == "AB0")
        #expect(PrefixExtractor.wpx("A") == "A0")
        #expect(PrefixExtractor.wpx("AB") == "AB0")
        #expect(PrefixExtractor.wpx("ABC") == "AB0")
        #expect(PrefixExtractor.wpx("1") == "1")
        #expect(PrefixExtractor.wpx("/1") == "1")
        #expect(PrefixExtractor.wpx("P/1") == "P1")
        #expect(PrefixExtractor.wpx("OK1XOE/P/7") == "OK7")
        #expect(PrefixExtractor.wpx("7/OK1XOE") == "OK7")
    }

    /// The prefix is cut by **UTF-16 units**, not by graphemes. `"AA\u{0308}B"`
    /// is four units for Java (`A`, `A`, `U+0308`, `B`) and `substring(0, 2)`
    /// of them is `"AA"` → `"AA0"`. Swift `prefix(2)` would give `"AÄ"` → `"AÄ0"`,
    /// i.e. a **different multiplier**.
    @Test func slicingIsByUtf16UnitsNotGraphemes() {
        #expect(PrefixExtractor.wpx("AA\u{0308}B") == "AA0")
        #expect(PrefixExtractor.wpx("AA\u{0308}") == "AA0")
        #expect(PrefixExtractor.wpx("A\u{0308}A\u{0308}B") == "A\u{0308}0")
        #expect(PrefixExtractor.wpx("A\u{0308}1X") == "A\u{0308}1")
        #expect(PrefixExtractor.wpx("AA\u{0308}1X") == "AA\u{0308}1")
        #expect(PrefixExtractor.wpx("\u{0308}A1X") == "\u{0308}A1")
        // A surrogate pair is two non-digit units for `Character.isDigit(char)`;
        // the last digit is only `1`.
        #expect(PrefixExtractor.wpx("\u{1D7CE}1X") == "\u{1D7CE}1")
        #expect(PrefixExtractor.wpx("OK1XOE\u{1F600}") == "OK1")
    }

    /// "Digit" is Java `Character.isDigit(char)`, i.e. the whole category `Nd`.
    /// Arabic-Indic and Bengali digits, however, are **not** an area indicator,
    /// because that is recognised by the regex `\d` = ASCII only.
    @Test func digitMeansUnicodeCategoryNd() {
        #expect(PrefixExtractor.wpx("OK\u{0661}XOE") == "OK\u{0661}")
        #expect(PrefixExtractor.wpx("OK\u{09E7}XOE") == "OK\u{09E7}")
        #expect(PrefixExtractor.wpx("AB\u{0660}") == "AB\u{0660}")
        #expect(PrefixExtractor.wpx("\u{0661}\u{0662}AB") == "\u{0661}\u{0662}")
        #expect(PrefixExtractor.wpx("K1ABC/\u{0661}") == "\u{0661}")
    }

    /// Uppercasing may change the length and the prefix is computed only from the uppercased text.
    @Test func uppercasingMayChangeLength() {
        #expect(PrefixExtractor.wpx("\u{00DF}AB") == "SS0")
        #expect(PrefixExtractor.wpx("ok1xoe\u{00DF}") == "OK1")
        #expect(PrefixExtractor.wpx("\u{FB01}1X") == "FI1")
        #expect(PrefixExtractor.wpx("\u{0149}AB") == "\u{02BC}N0")
        #expect(PrefixExtractor.wpx("\u{01F0}AB") == "J\u{030C}0")
        #expect(PrefixExtractor.wpx("i1abc") == "I1")
        #expect(PrefixExtractor.wpx("\u{0130} 1ABC") == "\u{0130} 1")
    }

    /// In the branch with a one-digit indicator the **longest** part is taken (Java
    /// `longest`), whereas without an indicator the **shortest** (`shortest`). Both
    /// functions have strict `>` / `<`, so on equal length the **first** wins.
    /// The previous ten cases did not distinguish this choice — `K1ABC/7` has only
    /// one part and the longest and the shortest of it come out the same.
    @Test func areaIndicatorPicksLongestPartAndFirstOnTies() {
        // Two parts: the longer wins, independent of order (the shortest would give DL7).
        #expect(PrefixExtractor.wpx("DL/W1ABC/7") == "W7")
        #expect(PrefixExtractor.wpx("W1ABC/DL/7") == "W7")
        #expect(PrefixExtractor.wpx("OK/OK1XOE/9") == "OK9")
        #expect(PrefixExtractor.wpx("DL/W1ABC/7/P") == "W7")
        // Same length → the first part in written order.
        #expect(PrefixExtractor.wpx("DL/OK/7") == "DL7")
        #expect(PrefixExtractor.wpx("OK/DL/7") == "OK7")
        #expect(PrefixExtractor.wpx("W1/K2/7") == "W7")
        #expect(PrefixExtractor.wpx("K2/W1/7") == "K7")
    }

    /// `normalizePortable` on a part with a digit calls `prefixOf`, so it shortens it only
    /// after the last digit — it does not return it whole. `W1/OK1XOE` from the ten cases did not
    /// distinguish this, because `prefixOf("W1")` is again `"W1"`.
    @Test func portableOverrideStillTrimsToLastDigit() {
        #expect(PrefixExtractor.wpx("W1X/OK1XOE") == "W1")
        #expect(PrefixExtractor.wpx("W1XY/OK1XOE") == "W1")
        #expect(PrefixExtractor.wpx("2E0X/OK1XOE") == "2E0")
        #expect(PrefixExtractor.wpx("OK1XOE/W1X") == "W1")
    }

    /// **All ten** suffixes of the `SUFFIXES` set are ignored entirely. The original
    /// tests covered only `P` and `MM`, so dropping any of the other
    /// eight went unnoticed. A control counterpart: similar-looking tokens
    /// that are **not** in the set behave like a portable prefix rewrite.
    @Test func allTenSuffixesAreIgnored() {
        for suffix in ["P", "M", "MM", "AM", "QRP", "A", "R", "LH", "B", "J"] {
            #expect(PrefixExtractor.wpx("OK1XOE/\(suffix)") == "OK1", "suffix \(suffix)")
        }
        #expect(PrefixExtractor.wpx("OK1XOE/N") == "N0")
        #expect(PrefixExtractor.wpx("OK1XOE/X") == "X0")
        #expect(PrefixExtractor.wpx("OK1XOE/Q") == "Q0")
        #expect(PrefixExtractor.wpx("OK1XOE/PP") == "PP0")
        #expect(PrefixExtractor.wpx("OK1XOE/AMM") == "AMM0")
        #expect(PrefixExtractor.wpx("OK1XOE/QR") == "QR0")
    }

    /// Part lengths (`longest`/`shortest`) are measured in **UTF-16 units**, like
    /// Java `String.length()`. `"A\u{0308}B"` has three units but only two
    /// graphemes, so a version over graphemes would pick a different part and give a different prefix.
    @Test func partLengthsAreCountedInUtf16Units() {
        // longest: three units > two; over graphemes it would be a 2:2 tie → "XY".
        #expect(PrefixExtractor.wpx("XY/A\u{0308}B/7") == "A\u{0308}7")
        #expect(PrefixExtractor.wpx("A\u{0308}B/XY/7") == "A\u{0308}7")
        #expect(PrefixExtractor.wpx("AB/A\u{0308}B/7") == "A\u{0308}7")
        #expect(PrefixExtractor.wpx("XYZ/A\u{0308}B\u{0308}C/7") == "A\u{0308}7")
        // shortest: two units < three; over graphemes it would be a 2:2 tie → "A\u{0308}B".
        #expect(PrefixExtractor.wpx("A\u{0308}B/XY") == "XY0")
        #expect(PrefixExtractor.wpx("XY/A\u{0308}B") == "XY0")
        #expect(PrefixExtractor.wpx("A\u{0308}BC/XYZW") == "A\u{0308}BC0")
    }

    /// The area indicator rewrites the **last** digit of the prefix, not the first.
    /// The difference shows only for a main part with several digits — and such an input
    /// was not in the tests before, yet it changes the multiplier.
    @Test func areaIndicatorReplacesTheLastDigitOfThePrefix() {
        #expect(PrefixExtractor.wpx("W1A2BC/7") == "W1A7")
        #expect(PrefixExtractor.wpx("K1A2B3C/7") == "K1A2B7")
        #expect(PrefixExtractor.wpx("OK1X2OE/9") == "OK1X9")
        #expect(PrefixExtractor.wpx("2E0A1BC/7") == "2E0A7")
        #expect(PrefixExtractor.wpx("W12ABC/7") == "W17")
        #expect(PrefixExtractor.wpx("DL/W1A2BC/7") == "W1A7")
    }

    /// A part **without** a digit is taken whole and `0` is appended — `normalizePortable`
    /// does not call `prefixOf` in this branch, so it is not cut to the first two
    /// units. `DL/W1ABC` did not distinguish this, because `DL` has exactly two characters.
    @Test func portableOverrideWithoutDigitKeepsTheWholePart() {
        #expect(PrefixExtractor.wpx("ABC/OK1XOE") == "ABC0")
        #expect(PrefixExtractor.wpx("ABCD/OK1XOE") == "ABCD0")
        #expect(PrefixExtractor.wpx("ABCDE/OK1XOE") == "ABCDE0")
        #expect(PrefixExtractor.wpx("OK1XOE/ABC") == "ABC0")
    }

    /// KG4 is not handled specially here — the WPX prefix comes out the ordinary way. The special
    /// cases of Guantánamo belong in `DxccSpecialCases`.
    @Test func kg4HasNoSpecialCaseHere() {
        #expect(PrefixExtractor.wpx("KG4XX") == "KG4")
        #expect(PrefixExtractor.wpx("KG4AA") == "KG4")
        #expect(PrefixExtractor.wpx("KG4A") == "KG4")
    }
}
