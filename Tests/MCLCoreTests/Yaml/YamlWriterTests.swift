import Foundation
import Testing
@testable import MCLCore

/// YAML writing. All expected outputs are **measured on Java 21** —
/// `YamlObjectMapper.create().writerWithDefaultPrettyPrinter().writeValueAsString(tree)`
/// over a `JsonNode` tree built to correspond to the `YamlValue` tree on the left
/// (the table "measured Jackson output").
///
/// This is not about "some valid YAML": `BandPlanFile.write` writes the user's file,
/// so every difference in format is a change to the content of their data.
@Suite struct YamlWriterTests {

    /// Writes and compares with the text measured on Java.
    private func expectWrite(_ value: YamlValue, _ expected: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(YamlWriter.write(value) == expected, sourceLocation: sourceLocation)
    }

    // MARK: - document shape

    @Test func documentStartsWithMarkerAndEndsWithOneBreak() {
        expectWrite(.mapping(["a": .int(1)]), "---\na: 1\n")
    }

    @Test func rootScalarSitsOnTheMarkerLine() {
        expectWrite(.string("ahoj"), "--- \"ahoj\"\n")
        expectWrite(.null, "--- null\n")
        expectWrite(.mapping(YamlMapping()), "--- {}\n")
        expectWrite(.sequence([]), "--- []\n")
    }

    // MARK: - scalars

    @Test func scalarKinds() {
        expectWrite(.mapping([
            "emptyMap": .mapping(YamlMapping()),
            "emptySeq": .sequence([]),
            "nullValue": .null,
            "intValue": .int(48),
            "doubleValue": .double(1843.0),
            "boolValue": .bool(true),
            "boolFalse": .bool(false),
            "text": .string("hello"),
        ]), """
        ---
        emptyMap: {}
        emptySeq: []
        nullValue: null
        intValue: 48
        doubleValue: 1843.0
        boolValue: true
        boolFalse: false
        text: "hello"

        """)
    }

    /// Text is **always** in double quotes (`MINIMIZE_QUOTES` is off),
    /// so it cannot happen that `"48"` comes back as a number or `"~"` as
    /// `null`. That is exactly what the round-trip is about.
    @Test func stringsThatWouldReadBackAsAnotherTypeGetQuotes() {
        expectWrite(.mapping([
            "a": .string("48"), "b": .string("true"), "c": .string("~"), "d": .string("001"),
            "e": .string("1e3"), "f": .string(""), "g": .string("null"), "h": .string("yes"),
            "i": .string("-"), "j": .string("160m"),
        ]), """
        ---
        a: "48"
        b: "true"
        c: "~"
        d: "001"
        e: "1e3"
        f: ""
        g: "null"
        h: "yes"
        i: "-"
        j: "160m"

        """)
    }

    /// Escapes in double quotes according to `Emitter.ESCAPE_REPLACEMENTS`.
    /// Diacritics, emoji and BOM go to the output **literally** (`allowUnicode`),
    /// whereas control characters as `\x01`.
    @Test func specialCharactersMatchSnakeYamlEscapes() {
        expectWrite(.mapping([
            "nl": .string("a\nb"), "tab": .string("a\tb"), "quote": .string("a\"b"),
            "backslash": .string("a\\b"), "czech": .string("příšerně žluťoučký"),
            "emoji": .string("\u{1F600}"), "ctrl": .string("a\u{1}b"), "del": .string("a\u{7F}b"),
            "nbsp": .string("a\u{A0}b"), "nel": .string("a\u{85}b"), "lsep": .string("a\u{2028}b"),
            "psep": .string("a\u{2029}b"), "bom": .string("a\u{FEFF}b"), "cr": .string("a\rb"),
            "nul": .string("\u{0}"), "esc": .string("a\u{1B}b"),
            "trailingSpace": .string("a "), "leadingSpace": .string(" a"), "onlyNl": .string("\n"),
        ]), """
        ---
        nl: "a\\nb"
        tab: "a\\tb"
        quote: "a\\"b"
        backslash: "a\\\\b"
        czech: "příšerně žluťoučký"
        emoji: "\u{1F600}"
        ctrl: "a\\x01b"
        del: "a\\x7fb"
        nbsp: "a\\_b"
        nel: "a\\Nb"
        lsep: "a\\Lb"
        psep: "a\\Pb"
        bom: "a\u{FEFF}b"
        cr: "a\\rb"
        nul: "\\0"
        esc: "a\\eb"
        trailingSpace: "a "
        leadingSpace: " a"
        onlyNl: "\\n"

        """)
    }

    // MARK: - keys

    /// When Jackson quotes a key (`StringQuotingChecker.Default.needToQuoteName`)
    /// and when SnakeYAML picks single quotes because without quotes the
    /// key would not be valid.
    ///
    /// Note `160m` and `-x`: for "looks like a number" Jackson looks **only at the
    /// first character**, so it quotes them even though they are not numbers (measured).
    @Test func keyQuotingMatchesJackson() {
        let cases: [(String, String)] = [
            ("abc", "abc"),
            ("48", "\"48\""),
            ("true", "\"true\""),
            ("null", "\"null\""),
            ("~", "\"~\""),
            ("on", "\"on\""),
            ("off", "\"off\""),
            ("No", "\"No\""),
            ("Y", "\"Y\""),
            ("160m", "\"160m\""),
            ("0x1f", "\"0x1f\""),
            ("00", "\"00\""),
            ("1.5", "\"1.5\""),
            (".inf", "\".inf\""),
            ("-", "\"-\""),
            ("-x", "\"-x\""),
            ("---x", "\"---x\""),
            ("a\tb", "\"a\\tb\""),
            ("with space", "with space"),
            ("x  y", "x  y"),
            ("a:b", "a:b"),
            ("x:y", "x:y"),
            ("a#b", "a#b"),
            ("a,b", "a,b"),
            ("a\"b", "a\"b"),
            ("a'b", "a'b"),
            ("x'", "x'"),
            ("čeština", "čeština"),
            ("a\u{A0}b", "a\u{A0}b"),
            ("a: b", "'a: b'"),
            ("x:", "'x:'"),
            ("#c", "'#c'"),
            ("?", "'?'"),
            (":", "':'"),
            ("*x", "'*x'"),
            ("&x", "'&x'"),
            ("!x", "'!x'"),
            ("%x", "'%x'"),
            ("@x", "'@x'"),
            ("`x", "'`x'"),
            (">x", "'>x'"),
            ("|x", "'|x'"),
            ("{x", "'{x'"),
            ("[x", "'[x'"),
            (",x", "',x'"),
            ("'x", "'''x'"),
            (" a", "' a'"),
            ("a ", "'a '"),
        ]
        for (key, written) in cases {
            expectWrite(.mapping([key: .string("v")]), "---\n\(written): \"v\"\n")
        }
    }

    /// A key that does not fit on one line (empty, multi-line or from 128
    /// characters) is written by Java in the **explicit form** `? key` / `: value`.
    /// Measured: 127 characters is still a simple key, 128 is not.
    @Test func longEmptyAndMultilineKeysUseExplicitForm() {
        expectWrite(.mapping([String(repeating: "k", count: 127): .string("v")]),
                    "---\n\(String(repeating: "k", count: 127)): \"v\"\n")
        expectWrite(.mapping([String(repeating: "k", count: 128): .string("v")]),
                    "---\n? \(String(repeating: "k", count: 128))\n: \"v\"\n")
        expectWrite(.mapping(["": .string("v")]), "---\n? \"\"\n: \"v\"\n")
        expectWrite(.mapping(["a\nb": .string("v")]), "---\n? \"a\\nb\"\n: \"v\"\n")
    }

    // MARK: - structure

    /// A block sequence in a map is **not indented** (`INDENT_ARRAYS` is off),
    /// so `- ` stands at the key's column. Exactly this shape is what `bandplan.yaml`
    /// written by Java has.
    @Test func sequenceInMappingIsNotIndented() {
        expectWrite(.mapping(["regions": .mapping(["R1": .sequence([
            .mapping(["band": .string(""), "cw": .string("1810-1838")]),
            .mapping(["band": .string(""), "digi": .string("1838-1840")]),
        ])])]), """
        ---
        regions:
          R1:
          - band: ""
            cw: "1810-1838"
          - band: ""
            digi: "1838-1840"

        """)
    }

    @Test func sequenceKinds() {
        let seq: [YamlValue] = [
            .int(1), .string("dva"), .null, .bool(true),
            .sequence([.int(1), .int(2)]),
            .mapping(["k": .string("v")]),
            .sequence([]), .mapping(YamlMapping()),
        ]
        expectWrite(.mapping(["seq": .sequence(seq)]), """
        ---
        seq:
        - 1
        - "dva"
        - null
        - true
        - - 1
          - 2
        - k: "v"
        - []
        - {}

        """)
        expectWrite(.sequence(seq), """
        ---
        - 1
        - "dva"
        - null
        - true
        - - 1
          - 2
        - k: "v"
        - []
        - {}

        """)
    }

    @Test func deepNesting() {
        expectWrite(.mapping([
            "a": .mapping(["b": .mapping(["c": .mapping(["x": .int(1)])])]),
            "seqOfSeq": .sequence([.sequence([.mapping(["deep": .string("y")])])]),
        ]), """
        ---
        a:
          b:
            c:
              x: 1
        seqOfSeq:
        - - deep: "y"

        """)
    }

    @Test func mappingKeepsKeyOrder() {
        var map = YamlMapping()
        map.set("z", .int(1))
        map.set("a", .int(2))
        map.set("m", .int(3))
        expectWrite(.mapping(map), "---\nz: 1\na: 2\nm: 3\n")
    }

    // MARK: - line wrapping

    /// `SPLIT_LINES` wraps double-quoted text at column 80: the break is hidden
    /// behind `\`, and when the continuation starts with a space, another `\` introduces it.
    /// The lengths are measured one character at a time around the boundary.
    @Test func longValuesFoldAtColumn80() {
        func spaced(_ length: Int) -> String {
            var text = ""
            for i in 0..<length {
                text.append(Character(UnicodeScalar(UInt8(97 + (i % 4)))))
                if i % 5 == 4 { text.append(" ") }
            }
            return text
        }
        // 60 characters: fits on a line without a break.
        expectWrite(.mapping(["k": .string(spaced(60))]), """
        ---
        k: "abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd "

        """)
        // 68 characters: the first break.
        expectWrite(.mapping(["k": .string(spaced(68))]), """
        ---
        k: "abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda\\
          \\ bcd"

        """)
        expectWrite(.mapping(["k": .string(spaced(69))]), """
        ---
        k: "abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda\\
          \\ bcda"

        """)
        // 160 characters: wraps twice.
        expectWrite(.mapping(["k": .string(spaced(160))]), """
        ---
        k: "abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda\\
          \\ bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda bcdab cdabc dabcd abcda bcdab\\
          \\ cdabc dabcd abcda bcdab cdabc dabcd "

        """)
    }

    /// A non-BMP character is counted **in UTF-16 units** in the wrapping arithmetic,
    /// and moreover exactly as crookedly as Java does it: after printing a two-unit
    /// character it moves `end` by one unit, so in the wrapping test it gets
    /// `end - start == -1` and the boundary `end < length - 1` is one unit higher.
    /// The port by scalars gave `-2` and the break fell one character elsewhere — an emoji
    /// in a contest `description:` is realistic. All values measured on Java.
    @Test func nonBmpCharactersBreakLikeJava() {
        let emoji = "\u{1F600}"
        func a(_ count: Int) -> String { String(repeating: "a ", count: count) }
        func e(_ count: Int) -> String { String(repeating: emoji, count: count) }

        // 37× "a " still fits, 38× no longer and the break falls AFTER the emoji.
        expectWrite(.mapping(["v": .string(a(37) + emoji + "b")]),
                    "---\nv: \"" + a(37) + emoji + "b\"\n")
        expectWrite(.mapping(["v": .string(a(38) + emoji + "b")]),
                    "---\nv: \"" + a(38) + emoji + "\\\n  b\"\n")
        // 39× already wraps at the space BEFORE the emoji, so `\ ` introduces it.
        expectWrite(.mapping(["v": .string(a(39) + emoji + "b")]),
                    "---\nv: \"" + a(38) + "a\\\n  \\ " + emoji + "b\"\n")
        // All emoji: 39 fit, from 40 it wraps after the 39th character.
        expectWrite(.mapping(["v": .string(e(39))]), "---\nv: \"" + e(39) + "\"\n")
        expectWrite(.mapping(["v": .string(e(40))]),
                    "---\nv: \"" + e(39) + "\\\n  " + emoji + "\"\n")
        expectWrite(.mapping(["v": .string(e(41))]),
                    "---\nv: \"" + e(39) + "\\\n  " + e(2) + "\"\n")
        // The highest code point is still "printable" for SnakeYAML, it goes literally.
        expectWrite(.mapping(["v": .string(a(38) + "\u{10FFFF}" + "b")]),
                    "---\nv: \"" + a(38) + "\u{10FFFF}" + "\\\n  b\"\n")
        // A check that it is not about "outside ASCII": a BMP character is one unit,
        // so at the same place it does not break yet.
        expectWrite(.mapping(["v": .string(a(38) + "日b")]),
                    "---\nv: \"" + a(38) + "日b\"\n")
    }

    /// Text without spaces is **not wrapped** — SnakeYAML wraps only at spaces.
    @Test func longValueWithoutSpacesIsNotFolded() {
        let text = String(repeating: "x", count: 200)
        expectWrite(.mapping(["k": .string(text)]), "---\nk: \"\(text)\"\n")
    }

    /// The indentation of a continuation line is the value's indentation, not the key's.
    @Test func foldIndentFollowsNesting() {
        let text = "slovo jedno slovo druhe slovo treti slovo ctvrte slovo pate slovo seste slovo sedme"
        expectWrite(.mapping(["uroven": .mapping(["hluboko": .string(text)])]), """
        ---
        uroven:
          hluboko: "slovo jedno slovo druhe slovo treti slovo ctvrte slovo pate slovo seste\\
            \\ slovo sedme"

        """)
        expectWrite(.sequence([.mapping(["t": .string(text + " slovo osme")])]), """
        ---
        - t: "slovo jedno slovo druhe slovo treti slovo ctvrte slovo pate slovo seste slovo\\
            \\ sedme slovo osme"

        """)
    }

    /// A key is never wrapped (`split = !simpleKeyContext && splitLines`).
    @Test func keysAreNeverFolded() {
        let key = "klic jeden klic dva klic tri klic ctyri klic pet klic sest klic sedm klic osm"
        expectWrite(.mapping([key: .string("v")]), "---\n\(key): \"v\"\n")
    }

    // MARK: - Double the Java way

    /// `Double.toString` boundaries measured on Java 21. Swift `String(Double)` gives
    /// different text for the same values (`0.0003333333333` versus `3.333333333E-4`),
    /// so this is the difference that would otherwise rewrite the frequencies in the user's
    /// file.
    @Test func doubleFormattingMatchesJava() {
        let cases: [(Double, String)] = [
            (1e-3, "0.001"),
            (1e-4, "1.0E-4"),
            (1e7, "1.0E7"),
            (9_999_999.0, "9999999.0"),
            (0.1, "0.1"),
            (1843.0, "1843.0"),
            (3.333333333e-4, "3.333333333E-4"),
            (1e6, "1000000.0"),
            (1e21, "1.0E21"),
            (0.0, "0.0"),
            (-0.0, "-0.0"),
            (0.5, "0.5"),
            (2.5, "2.5"),
            (1.0 / 3.0, "0.3333333333333333"),
            (123_456_789.123, "1.23456789123E8"),
            (-1843.5, "-1843.5"),
            (1e-5, "1.0E-5"),
            (Double.leastNonzeroMagnitude, "4.9E-324"),
            (Double.greatestFiniteMagnitude, "1.7976931348623157E308"),
            (Double.nan, "NaN"),
            (Double.infinity, "Infinity"),
            (-Double.infinity, "-Infinity"),
        ]
        for (value, text) in cases {
            expectWrite(.mapping(["d": .double(value)]), "---\nd: \(text)\n")
        }
    }

    /// `Double.MIN_VALUE` is the value where "the shortest spelling" is not enough: Java takes
    /// at least two significant digits, so it writes `4.9E-324`, not `5E-324`, which would
    /// also be read back without loss.
    @Test func javaKeepsAtLeastTwoSignificantDigits() {
        expectWrite(.double(Double.leastNonzeroMagnitude), "--- 4.9E-324\n")
        expectWrite(.double(1e-323), "--- 9.9E-324\n")
        expectWrite(.double(1.5e-323), "--- 1.5E-323\n")
    }

    @Test func intFormatting() {
        expectWrite(.mapping([
            "zero": .int(0), "neg": .int(-5), "maxInt": .int(2_147_483_647),
            "minLong": .int(Int.min), "maxLong": .int(9_223_372_036_854_775_807),
        ]), """
        ---
        zero: 0
        neg: -5
        maxInt: 2147483647
        minLong: -9223372036854775808
        maxLong: 9223372036854775807

        """)
    }

    // MARK: - round-trip

    /// Scalars the writer can produce — one representative **for every branch**
    /// of `YamlEmitter.node` and every style that can come out of `chooseStyle`.
    ///
    /// There are also values whose writing used to break the reader (`Int.min`),
    /// and values at line-wrapping boundaries, because that makes the output fall apart into several
    /// lines and the reader must fold it back.
    static let writerScalarKinds: [YamlValue] = [
        .null,
        .bool(true),
        .bool(false),
        .int(0),
        .int(-48),
        .int(Int.max),
        .int(Int.min),
        .int(Int.min + 1),
        .double(1843.0),
        .double(3.333333333e-4),
        .double(1e7),
        .double(1e-3),
        .double(-0.0),
        .double(Double.leastNonzeroMagnitude),
        .double(Double.greatestFiniteMagnitude),
        .string(""),
        .string("hello"),
        .string("48"),
        .string("true"),
        .string("~"),
        .string("001"),
        .string("1e3"),
        .string("160m"),
        .string("---"),
        .string("  mezery  "),
        .string("a\nb\tc\"d\\e"),
        .string("a\rb"),
        .string("a\u{85}b"),
        .string("a\u{2028}b"),
        .string("příšerně žluťoučký kůň 😀 日本"),
        .string("a\u{1}b\u{7F}c\u{A0}d"),
        .string(String(repeating: "slovo ", count: 40)),
        .sequence([]),
        .mapping(YamlMapping()),
    ]

    /// Keys that the writer sends through the **simple** (`k: v`) and the **explicit**
    /// (`? k` / `: v`) path of `YamlEmitter.blockMapping`. An empty key, a multi-line one
    /// or one with ≥128 UTF-16 units falls into the explicit one.
    /// Line-break characters (NEL, U+2028, U+2029) **must** be here: the writer
    /// writes them literally into a plain key, and that is exactly where the reader diverged
    /// from Java. Without them the filter in `roundTripThroughWriterCoversEveryValueKind`
    /// would be dead code and the property would not cover those cases at all.
    static let writerKeyKinds: [String] = [
        "a",
        "",
        "a\nb",
        "a\r\nb",
        "a\u{85}b",
        "a\u{2028}b",
        "a\u{2029}b",
        "\u{2028}",
        "\u{2028}ab",
        "ab\u{2028}",
        "a\u{2028}b\u{2028}c",
        "a\u{2028}b: c",
        "1\u{2028}b",
        "a\u{2028}b\nc",
        String(repeating: "k", count: 127),
        String(repeating: "k", count: 128),
        String(repeating: "k", count: 129),
        String(repeating: "ab ", count: 43),
        String(repeating: "ab ", count: 30) + "\n" + String(repeating: "cd ", count: 30),
        "true", "48", "a: b", "#c", "*x", "\t", " a", "a ", "'x", "čeština 😀",
    ]

    /// Values that appear after the explicit colon (`: value`) — including
    /// those where a whole block starts on that line (`: x: 1`, `: - 1`).
    static let writerValueKinds: [YamlValue] = [
        .int(1), .null, .string("v"), .mapping(YamlMapping()), .sequence([]),
        .mapping(["x": .int(1)]), .sequence([.int(1), .int(2)]),
        .mapping(["x": .sequence([.mapping(["y": .null])])]),
    ]

    /// **A property, not an enumeration:** `parse(write(v)) == v` for every kind of value
    /// that the writer can produce, in all positions where it can produce it.
    ///
    /// Why this way: the writer can write a file that the reader rejects —
    /// and `DefinitionEditing` reads a definition, change it and write it, so
    /// it would break in the middle of editing a contest. An enumeration of today's known cases
    /// would not cover a branch that somebody adds to the writer tomorrow; a cross catalog
    /// (scalar kind × position, key kind × value kind) does.
    ///
    /// Two exceptions are **measured** and have their own tests, so that it is visible they are
    /// deliberate — and both are cases where the round-trip does not pass **even in Java**:
    /// infinite and NaN doubles (`nonFiniteDoublesComeBackAsText`) and a key with NEL
    /// (`nelInKeyFollowsJava`). U+2028 and U+2029 in a key
    /// **pass**, see `YamlLineBreakTests`.
    @Test func roundTripThroughWriterCoversEveryValueKind() throws {
        var cases: [YamlValue] = []
        for scalar in Self.writerScalarKinds {
            cases.append(scalar)                                       // document root
            cases.append(.mapping(["v": scalar]))                      // value in a map
            cases.append(.sequence([scalar]))                          // sequence item
            cases.append(.mapping(["a": .sequence([.mapping(["b": scalar])])]))  // nested
        }
        for key in Self.writerKeyKinds {
            // A key with NEL is the only exception: the writer writes it literally, NEL is
            // a line break and folds into a space, so the round-trip does not pass **even
            // in Java** (measured — see `nelInKeyFollowsJava`). U+2028 and U+2029
            // fold as themselves, so they pass.
            guard !key.unicodeScalars.contains("\u{85}") else { continue }
            for value in Self.writerValueKinds {
                cases.append(.mapping([key: value]))
            }
            cases.append(.mapping(["a": .mapping([key: .int(1)])]))
            cases.append(.sequence([.mapping([key: .int(1)])]))
            cases.append(.mapping([key: .int(1), "z": .int(2)]))
            cases.append(.mapping(["z": .int(2), key: .int(1)]))
        }
        // Two explicit keys in a row and their mixing with simple ones.
        cases.append(.mapping(["": .int(1), "a\nb": .int(2)]))
        cases.append(.mapping(["": .int(1), "a": .int(2)]))
        cases.append(.mapping(["a": .int(2), "": .int(1)]))
        cases.append(.sequence([.mapping(["": .int(1)]), .mapping(["a\nb": .int(2)])]))
        // Structures.
        cases.append(.sequence([.int(1), .string("dva"), .null, .bool(true), .double(0.5)]))
        cases.append(.sequence([.sequence([.int(1), .sequence([.int(2)])])]))
        cases.append(.sequence([.mapping(["a": .sequence([])]),
                                .mapping(["b": .mapping(YamlMapping())])]))
        cases.append(.mapping(["a": .int(1), "b": .sequence([.mapping(["c": .null])])]))

        #expect(cases.count == 480)  // so that the enumeration does not vanish through a silent rewrite of the catalog
        for value in cases {
            let text = YamlWriter.write(value)
            do {
                let back = try YamlParser.parse(text)
                #expect(back == value, "round-trip diverged on: \(text.debugDescription)")
            } catch {
                Issue.record("the reader rejected what the writer wrote (\(text.debugDescription)): \(error)")
            }
        }
    }

    /// Three shapes that the writer used to produce and the reader rejected now pass —
    /// and they pass with the **correct output** too, so it is visible what exactly it was about.
    /// (The property is guarded by `roundTripThroughWriterCoversEveryValueKind`; here are
    /// those three by name; they motivated the explicit-key support.)
    @Test func formerlyRefusedWrittenFormsNowRead() throws {
        // 1) Content on the `---` line: a root scalar and empty collections.
        #expect(YamlWriter.write(.null) == "--- null\n")
        #expect(try YamlParser.parse("--- null\n") == .null)
        #expect(YamlWriter.write(.string("ahoj")) == "--- \"ahoj\"\n")
        #expect(try YamlParser.parse("--- \"ahoj\"\n") == .string("ahoj"))
        #expect(YamlWriter.write(.mapping(YamlMapping())) == "--- {}\n")
        #expect(try YamlParser.parse("--- {}\n") == .mapping(YamlMapping()))
        #expect(YamlWriter.write(.sequence([])) == "--- []\n")
        #expect(try YamlParser.parse("--- []\n") == .sequence([]))
        // 2) Explicit key `? `.
        #expect(YamlWriter.write(.mapping(["": .string("v")])) == "---\n? \"\"\n: \"v\"\n")
        #expect(try YamlParser.parse("---\n? \"\"\n: \"v\"\n") == ["": "v"])
        #expect(YamlWriter.write(.mapping(["a\nb": .string("v")])) == "---\n? \"a\\nb\"\n: \"v\"\n")
        #expect(try YamlParser.parse("---\n? \"a\\nb\"\n: \"v\"\n") == ["a\nb": "v"])
        let long = String(repeating: "k", count: 128)
        #expect(YamlWriter.write(.mapping([long: .string("v")])) == "---\n? \(long)\n: \"v\"\n")
        #expect(try YamlParser.parse("---\n? \(long)\n: \"v\"\n") == [long: "v"])
        // 3) `Int.min` — the only value whose unsigned magnitude overflowed.
        #expect(YamlWriter.write(.mapping(["v": .int(Int.min)]))
            == "---\nv: -9223372036854775808\n")
        #expect(try YamlParser.parse("---\nv: -9223372036854775808\n") == ["v": .int(Int.min)])
    }

    /// The writer writes `NaN` and `±Infinity` with Java `Double.toString` (`NaN`,
    /// `Infinity`), but no YAML makes a number of it — **not even Jackson**
    /// (measured: `a: NaN` is the text "NaN", `a: Infinity` the text "Infinity").
    /// The round-trip thus does not pass even in Java; we copy that asymmetry, so
    /// these values are not in the property's catalog.
    @Test func nonFiniteDoublesComeBackAsText() throws {
        #expect(YamlWriter.write(.mapping(["v": .double(.nan)])) == "---\nv: NaN\n")
        #expect(try YamlParser.parse("a: NaN\n") == ["a": "NaN"])
        #expect(try YamlParser.parse("a: Infinity\n") == ["a": "Infinity"])
        #expect(try YamlParser.parse("a: -Infinity\n") == ["a": "-Infinity"])
        #expect(try YamlParser.parse("--- NaN\n") == .string("NaN"))
    }

    /// The writer writes a key with NEL (U+0085) **literally** (`isAllowUnicode` is
    /// on), and NEL is a line break for SnakeYAML, so it folds into a space:
    /// `? a<NEL>  b` is read in Java as the key "a b", not "a<NEL>b".
    /// The round-trip thus does not pass **even in Java** — we agree with Java,
    /// and that is what should hold.
    @Test func nelInKeyFollowsJava() throws {
        #expect(YamlWriter.write(.mapping(["a\u{85}b": .int(1)])) == "---\n? a\u{85}  b\n: 1\n")
        #expect(try YamlParser.parse("---\n? a\u{85}  b\n: 1\n") == ["a b": 1])
        // Measured outside an explicit key too.
        #expect(try YamlParser.parse("a: x\u{85}  y\n") == ["a": "x y"])
        #expect(try YamlParser.parse("a\u{85}b: 1\n") == .string("a b"))
        #expect(try YamlParser.parse("a: 1\u{85}b: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: \"x\u{85}  y\"\n") == ["a": "x y"])
        #expect(try YamlParser.parse("a: |\n  x\u{85}  y\n") == ["a": "x\ny\n"])
    }

    /// The writer writes a key with U+2028 / U+2029 **literally** (measured on the bytes
    /// of Jackson's output: `3f 20 61 e2 80 a8 20 20 62`), and the reader reads it back since fix
    /// round 1 — because U+2028/U+2029 fold **as themselves**,
    /// not into a space. The round-trip thus **passes**, as in Java.
    ///
    /// Escaping them on write was not possible: Jackson leaves them literal in a plain and a single-quoted
    /// key (it escapes them only in double quotes), so
    /// escaping would break the byte match with Jackson.
    @Test func lineSeparatorInKeyRoundTrips() throws {
        for separator in ["\u{2028}", "\u{2029}"] {
            let key = "a\(separator)b"
            let written = YamlWriter.write(.mapping([key: .int(1)]))
            #expect(written == "---\n? a\(separator)  b\n: 1\n")
            #expect(try YamlParser.parse(written) == [key: 1])
        }
        // Shapes the writer produces for a key with U+2028 at the edges
        // (switches to single quotes) — measured on Java.
        let ls = "\u{2028}"
        #expect(try YamlParser.parse("---\n? '\(ls)  '\n: 1\n") == [ls: 1])
        #expect(try YamlParser.parse("---\n? '\(ls)  ab'\n: 1\n") == ["\(ls)ab": 1])
        #expect(try YamlParser.parse("---\n? 'ab\(ls)  '\n: 1\n") == ["ab\(ls)": 1])
        #expect(try YamlParser.parse("---\n? a\(ls)  b\(ls)  c\n: 1\n") == ["a\(ls)b\(ls)c": 1])
        #expect(try YamlParser.parse("---\n? 'a\(ls)  b: c'\n: 1\n") == ["a\(ls)b: c": 1])
        #expect(try YamlParser.parse("---\n- ? a\(ls)    b\n  : 1\n") == [["a\(ls)b": 1]])
        #expect(try YamlParser.parse("---\na:\n  ? a\(ls)    b\n  : 1\n") == ["a": ["a\(ls)b": 1]])
    }

    /// A value that was a block scalar in the source is written as a double-quoted
    /// text — and reads back to the same tree. Jackson never writes block scalars
    /// (`LITERAL_BLOCK_STYLE` is off).
    @Test func roundTripOfValueReadFromBlockScalar() throws {
        let source = try YamlParser.parse("a: |\n  prvni\n  druhy\nb: >\n  slozeny text\n")
        let text = YamlWriter.write(source)
        #expect(text == "---\na: \"prvni\\ndruhy\\n\"\nb: \"slozeny text\\n\"\n")
        #expect(try YamlParser.parse(text) == source)
    }

    /// The shape that `contest-data/bandplan.yaml` written by Java has. On the whole
    /// file it is measured (`write(parse(bandplan)) == bandplan`
    /// byte by byte); here is the start of the file literally, so that a test guards it.
    @Test func bandplanShapeIsReproduced() throws {
        let original = """
        ---
        regions:
          R1:
          - band: ""
            cw: "1810-1838"
          - band: ""
            digi: "1838-1840"
          - band: ""
            phone: "1840-2000"
          R2:
          - band: ""
            cw: "1800-1900"

        """
        #expect(YamlWriter.write(try YamlParser.parse(original)) == original)
    }
}
