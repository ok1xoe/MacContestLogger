import Foundation
import Testing
@testable import MCLCore

/// Typing of unquoted scalars. The table is **measured on a running Java**
/// (Jackson 2.22.0 + SnakeYAML 2.5, `YamlObjectMapper.create()`), not derived
/// from the YAML spec — Jackson does not follow the spec in several places and our contest
/// definitions rest on Jackson.
@Suite struct YamlScalarTests {

    /// Parses `v: <raw>` and returns the value of key `v`.
    private func scalar(_ raw: String) throws -> YamlValue {
        let doc = try YamlParser.parse("v: \(raw)")
        return doc["v"]
    }

    // MARK: - integers

    @Test func plainIntegerIsInteger() throws {
        #expect(try scalar("48") == .int(48))
        #expect(try scalar("0") == .int(0))
    }

    @Test func quotedIntegerIsText() throws {
        #expect(try scalar("\"48\"") == .string("48"))
        #expect(try scalar("'48'") == .string("48"))
    }

    /// Jackson takes `007` as an **octal** number → 7, `010` → 8.
    @Test func leadingZeroIsOctal() throws {
        #expect(try scalar("007") == .int(7))
        #expect(try scalar("010") == .int(8))
        #expect(try scalar("00") == .int(0))
    }

    /// `08` cannot be octal and the decimal pattern does not allow a leading zero → text.
    @Test func invalidOctalIsText() throws {
        #expect(try scalar("08") == .string("08"))
    }

    @Test func signedIntegers() throws {
        #expect(try scalar("+5") == .int(5))
        #expect(try scalar("-0") == .int(0))
        #expect(try scalar("+007") == .int(7))
        #expect(try scalar("-007") == .int(-7))
    }

    @Test func hexAndBinary() throws {
        #expect(try scalar("0x10") == .int(16))
        #expect(try scalar("0xFF") == .int(255))
        #expect(try scalar("0b101") == .int(5))
        // a capital "X" is not known to the pattern
        #expect(try scalar("0XFF") == .string("0XFF"))
        #expect(try scalar("0o17") == .string("0o17"))
        #expect(try scalar("0x") == .string("0x"))
    }

    @Test func underscoresInNumbers() throws {
        #expect(try scalar("1_000") == .int(1000))
    }

    /// Sexagesimal system: SnakeYAML recognizes it with the INT tag, but Jackson's
    /// decoder does not compute it and returns **text**.
    @Test func sexagesimalStaysText() throws {
        #expect(try scalar("12:30") == .string("12:30"))
        #expect(try scalar("1:2:3") == .string("1:2:3"))
    }

    // MARK: - decimal numbers

    @Test func floatsAreDouble() throws {
        #expect(try scalar("3.0") == .double(3.0))
        #expect(try scalar(".5") == .double(0.5))
        #expect(try scalar("-.5") == .double(-0.5))
        #expect(try scalar("5.") == .double(5.0))
        #expect(try scalar("0.0") == .double(0.0))
        #expect(try scalar("-3.5") == .double(-3.5))
    }

    /// An exponent without a decimal point is also FLOAT according to SnakeYAML 2.x.
    @Test func exponentWithoutDotIsDouble() throws {
        #expect(try scalar("1e3") == .double(1000.0))
        #expect(try scalar("1E3") == .double(1000.0))
        #expect(try scalar("2e2") == .double(200.0))
        #expect(try scalar("1e-3") == .double(0.001))
        #expect(try scalar("1.0e2") == .double(100.0))
    }

    /// An unfinished exponent is not a number.
    @Test func incompleteExponentIsText() throws {
        #expect(try scalar("1e") == .string("1e"))
        #expect(try scalar("e3") == .string("e3"))
    }

    /// `.inf`/`.nan` are marked FLOAT by Jackson, but it cannot parse them
    /// and **throws an error**. We copy that: an error, not silent text.
    @Test func infinityAndNaNThrow() throws {
        #expect(throws: YamlError.self) { _ = try scalar(".inf") }
        #expect(throws: YamlError.self) { _ = try scalar("+.inf") }
        #expect(throws: YamlError.self) { _ = try scalar(".nan") }
    }

    // MARK: - text

    /// `bands: [160m, 80m, 40m]` stands on this — `160m` is **not** a number.
    @Test func bandNamesAreText() throws {
        #expect(try scalar("160m") == .string("160m"))
        #expect(try scalar("80m") == .string("80m"))
        #expect(try scalar("40m") == .string("40m"))
    }

    @Test func assortedPlainText() throws {
        #expect(try scalar("OK1XOE") == .string("OK1XOE"))
        #expect(try scalar("hello world") == .string("hello world"))
        #expect(try scalar("1.2.3") == .string("1.2.3"))
        #expect(try scalar("192.168.1.1") == .string("192.168.1.1"))
        #expect(try scalar("1,000") == .string("1,000"))
        #expect(try scalar("a:b") == .string("a:b"))
        #expect(try scalar(".5.5") == .string(".5.5"))
        #expect(try scalar("1 2") == .string("1 2"))
    }

    /// A date has the TIMESTAMP tag, which Jackson converts back to text.
    @Test func timestampIsText() throws {
        #expect(try scalar("2026-09-29") == .string("2026-09-29"))
    }

    @Test func plainScalarIsTrimmed() throws {
        #expect(try scalar("abc   ") == .string("abc"))
    }

    // MARK: - boolean values

    @Test func booleanWordsInAllThreeCasings() throws {
        #expect(try scalar("true") == .bool(true))
        #expect(try scalar("True") == .bool(true))
        #expect(try scalar("TRUE") == .bool(true))
        #expect(try scalar("false") == .bool(false))
        #expect(try scalar("False") == .bool(false))
        #expect(try scalar("FALSE") == .bool(false))
    }

    /// YAML 1.1 words `yes`/`no`/`on`/`off` are accepted by Jackson too.
    @Test func yesNoOnOffAreBooleans() throws {
        #expect(try scalar("yes") == .bool(true))
        #expect(try scalar("Yes") == .bool(true))
        #expect(try scalar("YES") == .bool(true))
        #expect(try scalar("no") == .bool(false))
        #expect(try scalar("NO") == .bool(false))
        #expect(try scalar("on") == .bool(true))
        #expect(try scalar("On") == .bool(true))
        #expect(try scalar("off") == .bool(false))
        #expect(try scalar("Off") == .bool(false))
    }

    /// A single-character `y`/`n` or mixed case is **not** a boolean.
    @Test func singleLetterAndMixedCaseAreText() throws {
        #expect(try scalar("y") == .string("y"))
        #expect(try scalar("n") == .string("n"))
        #expect(try scalar("T") == .string("T"))
        #expect(try scalar("F") == .string("F"))
        #expect(try scalar("yEs") == .string("yEs"))
    }

    @Test func quotedBooleanIsText() throws {
        #expect(try scalar("\"true\"") == .string("true"))
        #expect(try scalar("'yes'") == .string("yes"))
    }

    // MARK: - null

    @Test func nullWordsAndTilde() throws {
        #expect(try scalar("null") == .null)
        #expect(try scalar("Null") == .null)
        #expect(try scalar("NULL") == .null)
        #expect(try scalar("~") == .null)
    }

    @Test func emptyValueIsNull() throws {
        #expect(try YamlParser.parse("v:")["v"] == .null)
        #expect(try YamlParser.parse("v: ")["v"] == .null)
    }

    @Test func nullLikeTextIsNotNull() throws {
        #expect(try scalar("nulll") == .string("nulll"))
        #expect(try scalar("null null") == .string("null null"))
        #expect(try scalar("\"null\"") == .string("null"))
        #expect(try scalar("\"~\"") == .string("~"))
    }

    @Test func emptyQuotedScalarIsEmptyText() throws {
        #expect(try scalar("''") == .string(""))
        #expect(try scalar("\"\"") == .string(""))
    }

    // MARK: - quotes and escapes

    @Test func doubleQuotedEscapes() throws {
        #expect(try scalar(#""a\nb""#) == .string("a\nb"))
        #expect(try scalar(#""say \"hi\"""#) == .string("say \"hi\""))
        #expect(try scalar(#""é""#) == .string("é"))
        #expect(try scalar(#""a\tb""#) == .string("a\tb"))
    }

    /// In single quotes escapes are not unfolded, only `''` → `'`.
    @Test func singleQuotedHasNoEscapes() throws {
        #expect(try scalar(#"'a\nb'"#) == .string(#"a\nb"#))
        #expect(try scalar("'it''s'") == .string("it's"))
    }

    /// SnakeYAML does not accept `\/` or `\'` in double quotes — we must not
    /// accept more than Java.
    @Test func rejectedEscapesThrow() throws {
        #expect(throws: YamlError.self) { _ = try scalar(#""a\/b""#) }
        #expect(throws: YamlError.self) { _ = try scalar(#""a\'b""#) }
        #expect(throws: YamlError.self) { _ = try scalar(#""a\zb""#) }
        #expect(throws: YamlError.self) { _ = try scalar(#""\x4""#) }
    }

    /// Escapes that YAML has beyond JSON (measured that Java accepts them).
    @Test func yamlSpecificEscapes() throws {
        #expect(try scalar(#""a\Nb""#) == .string("a\u{85}b"))
        #expect(try scalar(#""a\_b""#) == .string("a\u{A0}b"))
        #expect(try scalar(#""a\Lb""#) == .string("a\u{2028}b"))
        #expect(try scalar(#""a\Pb""#) == .string("a\u{2029}b"))
        #expect(try scalar(#""a\eb""#) == .string("a\u{1B}b"))
        #expect(try scalar(#""\x41""#) == .string("A"))
        #expect(try scalar(#""\U0001F600""#) == .string("\u{1F600}"))
        #expect(try scalar(#""a\ b""#) == .string("a b"))
    }

    /// A backslash at the end of a line swallows the break: "ab", not "a b".
    @Test func escapedLineBreakSwallowsTheFold() throws {
        #expect(try YamlParser.parse("v: \"a\\\n  b\"\n")["v"] == .string("ab"))
    }

    /// Whitespace in a multi-line quoted scalar is stripped **around the
    /// break**, but the last line ends with a quote, so its trailing spaces
    /// are content. Measured on Java; found while proving `parse(write(v)) == v`,
    /// where a long text ending with a space broke into two lines and
    /// the space was silently lost.
    @Test func trailingBlanksOnTheClosingLineAreContent() throws {
        #expect(try YamlParser.parse("v: \"aaa\\\n  bbb \"\n")["v"] == .string("aaabbb "))
        #expect(try YamlParser.parse("v: \"aaa\\\n  bbb   \"\n")["v"] == .string("aaabbb   "))
        #expect(try YamlParser.parse("v: \"aaa\n  bbb \"\n")["v"] == .string("aaa bbb "))
        #expect(try YamlParser.parse("v: \"aaa\n  bbb   \"\n")["v"] == .string("aaa bbb   "))
        #expect(try YamlParser.parse("v: \"aaa\n  bbb \t\"\n")["v"] == .string("aaa bbb \t"))
        #expect(try YamlParser.parse("v: 'aaa\n  bbb '\n")["v"] == .string("aaa bbb "))
        #expect(try YamlParser.parse("v: \"aaa\\\n  bbb \\\n  ccc \"\n")["v"] == .string("aaabbb ccc "))
        // Before an **unquoted** break, on the contrary, trailing spaces are stripped.
        #expect(try YamlParser.parse("v: \"aaa \t\n  bbb\"\n")["v"] == .string("aaa bbb"))
        #expect(try YamlParser.parse("v: \"aaa   \\\n  bbb\"\n")["v"] == .string("aaa   bbb"))
        // `\ ` on a continuation line gives a space even when nothing follows it
        // (it used to fail with "text ends with a backslash").
        #expect(try YamlParser.parse("v: \"aaa\\\n  \\ \"\n")["v"] == .string("aaa "))
        #expect(try YamlParser.parse("v: \"aaa\\\n  \\  \"\n")["v"] == .string("aaa  "))
    }

    /// Empty lines **before the closing quote** are content too: one break
    /// folds into a space, every further one is a break (measured on Java).
    @Test func blankLinesBeforeTheClosingQuoteAreContent() throws {
        #expect(try YamlParser.parse("v: \"aaa\n   \"\n")["v"] == .string("aaa "))
        #expect(try YamlParser.parse("v: \"aaa\n\n   \"\n")["v"] == .string("aaa\n"))
        #expect(try YamlParser.parse("v: \"aaa\n\n\n   \"\n")["v"] == .string("aaa\n\n"))
        #expect(try YamlParser.parse("v: \"aaa\n\n\"\n")["v"] == .string("aaa\n"))
        #expect(try YamlParser.parse("v: 'aaa\n   '\n")["v"] == .string("aaa "))
        #expect(try YamlParser.parse("v: 'aaa\n\n   '\n")["v"] == .string("aaa\n"))
        // Inside a scalar the rule stays unchanged.
        #expect(try YamlParser.parse("v: \"aaa\n  bbb\n\n  ccc\"\n")["v"] == .string("aaa bbb\nccc"))
        #expect(try YamlParser.parse("v: \"aaa\n\n\n  bbb\"\n")["v"] == .string("aaa\n\nbbb"))
        // A plain scalar ends at an empty line, so its break is not content.
        #expect(try YamlParser.parse("v: aaa\n\nw: 1\n") == ["v": "aaa", "w": 1])
    }

    /// Around a break only **a space and a tab** are stripped (YAML `s-white`).
    /// A non-breaking space is content, even at the start of a continuation line
    /// (measured on Java character by character).
    @Test func nonBreakingSpaceIsNotStrippedAroundFolds() throws {
        #expect(try YamlParser.parse("v: \"x\n  \u{A0}y\"\n")["v"] == .string("x \u{A0}y"))
        #expect(try YamlParser.parse("v: \"x\n  y\u{A0}\"\n")["v"] == .string("x y\u{A0}"))
        #expect(try YamlParser.parse("v: \"x \u{A0}\n  y\"\n")["v"] == .string("x \u{A0} y"))
        #expect(try YamlParser.parse("v: \"x\u{A0}\"\n")["v"] == .string("x\u{A0}"))
    }

    @Test func unterminatedQuoteThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("v: \"abc") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("v: 'abc") }
    }

    // MARK: - typed reading

    @Test func typedReadingWithDefaults() throws {
        let doc = try YamlParser.parse("""
        id: cq-ww-cw
        hours: 48
        factor: 1.5
        flag: true
        """)
        #expect(doc.value("id", default: "") == "cq-ww-cw")
        #expect(doc.value("hours", default: 0) == 48)
        #expect(doc.value("factor", default: 0.0) == 1.5)
        #expect(doc.value("flag", default: false) == true)
    }

    @Test func missingKeyFallsBackToDefaultAndUnknownKeyIsIgnored() throws {
        let doc = try YamlParser.parse("known: 1\nunknown: 2\n")
        #expect(doc.value("known", default: 0) == 1)
        #expect(doc.value("chybi", default: 7) == 7)
        #expect(doc.value("chybi", default: "x") == "x")
        #expect(doc["chybi"] == .null)
    }

    @Test func wrongTypeFallsBackToDefault() throws {
        let doc = try YamlParser.parse("a: abc\nb:\n  - 1\n  - 2\nc: null\n")
        #expect(doc.value("a", default: 9) == 9)
        #expect(doc.value("b", default: "x") == "x")
        #expect(doc.value("c", default: "x") == "x")
    }

    /// Mild conversions copy Jackson: `"48"` → int 48, `3.7` → int 3,
    /// `48` → text "48", `1` → true, `"true"` → true, but `"yes"` **not**.
    @Test func lenientCoercionsMatchJackson() throws {
        #expect(YamlValue.string("48").value(default: 0) == 48)
        #expect(YamlValue.double(3.7).value(default: 0) == 3)
        #expect(YamlValue.int(1810).value(default: "") == "1810")
        #expect(YamlValue.bool(true).value(default: "") == "true")
        #expect(YamlValue.int(48).value(default: 0.0) == 48.0)
        #expect(YamlValue.string("3.5").value(default: 0.0) == 3.5)
        #expect(YamlValue.int(1).value(default: false) == true)
        #expect(YamlValue.int(0).value(default: true) == false)
        #expect(YamlValue.string("true").value(default: false) == true)
        #expect(YamlValue.string("yes").value(default: false) == false)
        #expect(YamlValue.bool(true).value(default: 9) == 9)
    }

    /// **The original spelling of a scalar must not be lost.** For a `String` field Java gives
    /// literally what is in the file (measured) — and `contest-data/` is a user-configurable
    /// directory, so anyone can write `power: 1e3`.
    @Test func scalarKeepsOriginalSpelling() throws {
        let cases = ["1e3", "1E3", "007", "010", "+5", "-0", "1_000", "5.", "2.50",
                     "0x10", "0b101", "3.0", "48",
                     "yes", "YES", "on", "off", "no", "TRUE", "True", "False"]
        for raw in cases {
            #expect(try scalar(raw).value(default: "") == raw, "spelling not preserved: \(raw)")
            #expect(try scalar(raw).rawText == raw)
        }
    }

    /// The value is still computed, the spelling is only extra.
    @Test func originalSpellingDoesNotChangeTheValue() throws {
        #expect(try scalar("1e3") == .double(1000.0))
        #expect(try scalar("007") == .int(7))
        #expect(try scalar("2.50") == .double(2.5))
        #expect(try scalar("yes") == .bool(true))
        #expect(try scalar("1e3").double == 1000.0)
        #expect(try scalar("007").int == 7)
    }

    /// Equality and hash **ignore** the spelling — otherwise the round-trip
    /// `parse(write(v)) == v` would fail. The same holds for maps and sequences.
    @Test func equalityIgnoresOriginalSpelling() throws {
        let seven = try scalar("007")
        #expect(seven == .int(7))
        #expect(seven.hashValue == YamlValue.int(7).hashValue)
        #expect(Set([seven, .int(7)]).count == 1)
        #expect(try YamlParser.parse("a: 007\nb: 1e3\n") == ["a": 7, "b": 1000.0])
        #expect(try YamlParser.parse("- 007\n") == [7])
    }

    /// For text the "original spelling" is the value itself after unfolding escapes, not the source
    /// with quotes (Java does it the same).
    @Test func quotedScalarRawTextIsTheUnescapedValue() throws {
        #expect(try scalar("\"48\"").rawText == "48")
        #expect(try scalar(#""a\nb""#).rawText == "a\nb")
        #expect(YamlValue.null.rawText == nil)
        #expect(YamlValue.sequence([]).rawText == nil)
    }

    @Test func strictAccessorsSeeOnlyTheirOwnCase() throws {
        #expect(YamlValue.int(48).int == 48)
        #expect(YamlValue.int(48).string == nil)
        #expect(YamlValue.string("48").int == nil)
        #expect(YamlValue.string("48").string == "48")
        #expect(YamlValue.double(1.5).double == 1.5)
        #expect(YamlValue.bool(false).bool == false)
        #expect(YamlValue.null.isNull)
        #expect(!YamlValue.string("").isNull)
    }
}
