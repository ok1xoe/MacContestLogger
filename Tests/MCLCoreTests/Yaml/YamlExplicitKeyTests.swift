import Foundation
import Testing
@testable import MCLCore

/// Explicit key of a block map (`? key` / `: value`).
///
/// Why the reader supports it: **the Jackson writer writes it.** A key that is empty,
/// multi-line or has ≥128 UTF-16 units (`ALLOW_LONG_KEYS` is off)
/// switches the `Emitter` to this shape, so without this path the reader
/// could not read what our writer has just written — and `DefinitionEditing`
/// would break in the middle of editing a contest.
///
/// All expectations are **measured on a running Java** (Jackson 2.22.0 +
/// SnakeYAML 2.5, `YamlObjectMapper.create().readTree`).
@Suite struct YamlExplicitKeyTests {

    private func expectError(_ text: String, _ kind: YamlError.Kind, line: Int, column: Int,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            let value = try YamlParser.parse(text)
            Issue.record("it should have thrown an error, but returned \(String(describing: value))",
                         sourceLocation: sourceLocation)
        } catch let e as YamlError {
            #expect(e.kind == kind, "kind: \(e)", sourceLocation: sourceLocation)
            #expect(e.line == line, "line: \(e)", sourceLocation: sourceLocation)
            #expect(e.column == column, "column: \(e)", sourceLocation: sourceLocation)
        } catch {
            Issue.record("an error other than YamlError: \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - key

    /// A key on the `?` line, in all scalar styles that Java accepts there.
    @Test func keyOnTheIndicatorLine() throws {
        #expect(try YamlParser.parse("? a\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? \"\"\n: 1\n") == ["": 1])
        #expect(try YamlParser.parse("? \"a\\nb\"\n: 1\n") == ["a\nb": 1])
        #expect(try YamlParser.parse("? 'a''b'\n: 1\n") == ["a'b": 1])
        // The key is the **original text** of the scalar, not its typed value.
        #expect(try YamlParser.parse("? null\n: 1\n") == ["null": 1])
        #expect(try YamlParser.parse("? ~\n: 1\n") == ["~": 1])
        #expect(try YamlParser.parse("? true\n: 1\n") == ["true": 1])
        #expect(try YamlParser.parse("? 1.5\n: 1\n") == ["1.5": 1])
        // A tag is not applied to the key, it is just dropped.
        #expect(try YamlParser.parse("? !!int 7\n: 1\n") == ["7": 1])
        #expect(try YamlParser.parse("? !!null x\n: 1\n") == ["x": 1])
        // A block scalar as a key.
        #expect(try YamlParser.parse("? |\n  abc\n: 1\n") == ["abc\n": 1])
        #expect(try YamlParser.parse("? >\n  ab\n: 1\n") == ["ab\n": 1])
        // Longer keys (127/128/129 characters are read the same in Java).
        for count in [127, 128, 129] {
            let key = String(repeating: "k", count: count)
            #expect(try YamlParser.parse("? \(key)\n: 1\n") == [key: 1])
        }
    }

    /// A key spanning further lines folds the same as any other scalar.
    @Test func keySpansFollowingLines() throws {
        #expect(try YamlParser.parse("? abc\n  def\n: 1\n") == ["abc def": 1])
        #expect(try YamlParser.parse("? 'ab ab\n  cd '\n: 1\n") == ["ab ab cd ": 1])
        #expect(try YamlParser.parse("? \"abc\n  def\"\n: 1\n") == ["abc def": 1])
        // Exactly the shape the writer produces for a key made of 43× "ab " (breaks at column 80).
        let written = YamlWriter.write(.mapping([String(repeating: "ab ", count: 43): .int(1)]))
        #expect(written.contains("\n? 'ab ab"))
        #expect(try YamlParser.parse(written) == [String(repeating: "ab ", count: 43): 1])
    }

    /// After a lone `?` the key is on more-indented lines; when there is nothing there,
    /// the key is empty (measured: a lone `?` gives `{"":null}`).
    @Test func keyOnFollowingLines() throws {
        #expect(try YamlParser.parse("?\n  abc\n: 1\n") == ["abc": 1])
        #expect(try YamlParser.parse("? \n  a\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("?\n: 1\n") == ["": 1])
        #expect(try YamlParser.parse("?\n") == ["": .null])
        #expect(try YamlParser.parse("?\n  ab\n  cd\n: 1\n") == ["ab cd": 1])
    }

    // MARK: - value

    /// A whole block **may** start on a line with an explicit colon — unlike
    /// a simple key, where Java rejects `v: abc:`.
    @Test func valueOnTheColonLine() throws {
        #expect(try YamlParser.parse("? a\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? a\n: null\n") == ["a": .null])
        #expect(try YamlParser.parse("? a\n: \"v\"\n") == ["a": "v"])
        #expect(try YamlParser.parse("? a\n: {}\n") == ["a": .mapping(YamlMapping())])
        #expect(try YamlParser.parse("? a\n: []\n") == ["a": .sequence([])])
        #expect(try YamlParser.parse("? a\n: [1,2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("? a\n: x: 1\n") == ["a": ["x": 1]])
        #expect(try YamlParser.parse("? a\n: - 1\n  - 2\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("? a\n: |\n  x\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("? a\n: !!str 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("? a\n: 1 # c\n") == ["a": 1])
        // A nested explicit key as a value.
        #expect(try YamlParser.parse("? a\n: ? b\n") == ["a": ["b": .null]])
    }

    /// A value on lines after the colon, and a missing value as `null`.
    @Test func valueOnFollowingLinesOrMissing() throws {
        #expect(try YamlParser.parse("? a\n:\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("? a\n:\n  - 1\n") == ["a": [1]])
        #expect(try YamlParser.parse("? a\n:\n- 1\n") == ["a": [1]])
        #expect(try YamlParser.parse("? a\n:\n") == ["a": .null])
        #expect(try YamlParser.parse("? \"\"\n:\n") == ["": .null])
        // Without a colon the value is `null` and the map continues.
        #expect(try YamlParser.parse("? a\n") == ["a": .null])
        #expect(try YamlParser.parse("? a\nb: 2\n") == ["a": .null, "b": 2])
        #expect(try YamlParser.parse("? a\n? b\n") == ["a": .null, "b": .null])
    }

    // MARK: - integration into the map

    @Test func mixesWithSimpleKeysAndNesting() throws {
        #expect(try YamlParser.parse("a: 1\n? b\n: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("? a\n: 1\nb: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("? a\n: 1\n? b\n: 2\nc: 3\n? d\n")
            == ["a": 1, "b": 2, "c": 3, "d": .null])
        // A duplicate key: the last wins, the position is kept.
        #expect(try YamlParser.parse("? a\n: 1\na: 2\n") == ["a": 2])
        // Nested and in a sequence.
        #expect(try YamlParser.parse("a:\n  ? b\n  : 1\n  c: 2\n") == ["a": ["b": 1, "c": 2]])
        #expect(try YamlParser.parse("- ? a\n  : 1\n  b: 2\n") == [["a": 1, "b": 2]])
        #expect(try YamlParser.parse("- ? a\n  : 1\n") == [["a": 1]])
        #expect(try YamlParser.parse("  ? a\n  : 1\n") == ["a": 1])
        // Comments and empty lines between `?` and `:` do no harm.
        #expect(try YamlParser.parse("? a # c\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? a\n# c\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? a\n\n: 1\n") == ["a": 1])
    }

    // MARK: - errors

    /// A collection cannot be a map key — Jackson reports "Expected a field name
    /// (Scalar value in YAML)" at the end of that event: for the flow shape after `{`/`[`,
    /// for the block one at its start (a block collection has zero width).
    @Test func collectionCannotBeAKey() {
        expectError("? a: 1\n", .syntax, line: 1, column: 3)
        expectError("? {a: 1}\n: 2\n", .syntax, line: 1, column: 4)
        expectError("? [1,2]\n: 1\n", .syntax, line: 1, column: 4)
        expectError("? - 1\n: 2\n", .syntax, line: 1, column: 3)
        expectError("? ? a\n: 1\n", .syntax, line: 1, column: 3)
    }

    /// A colon elsewhere than at the indentation of `?` is an error — and at the same positions
    /// as in Java. The position is the end of the last event Jackson received,
    /// not the colon's place: for the second colon it is the end of `1`.
    @Test func misplacedColonThrows() {
        // A more-indented colon.
        expectError("? a\n  : 1\n", .syntax, line: 2, column: 3)
        // A less-indented one.
        expectError("a:\n  ? b\n: 1\n", .syntax, line: 3, column: 1)
        // The second colon.
        expectError("? a\n: 1\n: 2\n", .syntax, line: 2, column: 4)
        // A colon without `?` ("expected <block end>, but found ':'").
        expectError(": 1\n", .syntax, line: 1, column: 1)
        // Without a space it is not a separator, so `:1` is not a key.
        expectError("? a\n:1\n", .syntax, line: 1, column: 4)
    }

    /// An alias stays unsupported even at the explicit key position — Jackson does not
    /// expand it and returns the anchor name as text.
    ///
    /// An anchor, on the contrary, is dropped (measured: `? &x a` + `: 1` is `{"a":1}`
    /// and `? a` + `: &x 1` is also `{"a":1}`) — the tables are in `YamlAnchorTests`.
    @Test func aliasStaysUnsupportedInExplicitKey() {
        expectError("? *x\n: 1\n", .unsupported, line: 1, column: 3)
        expectError("? a\n: *x\n", .unsupported, line: 2, column: 3)
    }

    /// `?` **without** a space after it is not an indicator and Java reads it as text.
    @Test func questionMarkWithoutSpaceIsPlainText() throws {
        #expect(try YamlParser.parse("?a: 1\n") == ["?a": 1])
        #expect(try YamlParser.parse("?: 1\n") == ["?": 1])
        #expect(try YamlParser.parse("a: ?x\n") == ["a": "?x"])
    }
}

/// The `%TAG` directive — the prefix of a tag namespace.
///
/// As long as `%TAG` was dropped, the **type** of the value diverged, i.e. that
/// silent and dangerous class of difference. All measured on a running Java.
@Suite struct YamlTagDirectiveTests {

    private func expectError(_ text: String, _ kind: YamlError.Kind, line: Int, column: Int,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            let value = try YamlParser.parse(text)
            Issue.record("it should have thrown an error, but returned \(String(describing: value))",
                         sourceLocation: sourceLocation)
        } catch let e as YamlError {
            #expect(e.kind == kind, "kind: \(e)", sourceLocation: sourceLocation)
            #expect(e.line == line, "line: \(e)", sourceLocation: sourceLocation)
            #expect(e.column == column, "column: \(e)", sourceLocation: sourceLocation)
        } catch {
            Issue.record("an error other than YamlError: \(error)", sourceLocation: sourceLocation)
        }
    }

    /// A prefix from `%TAG` is **applied** to tags — and changes the type, not just the text.
    @Test func tagPrefixChangesTheResolvedType() throws {
        // A remapped `!!` no longer belongs to the YAML namespace → text.
        #expect(try YamlParser.parse("%TAG !! tag:yaml.org,2002:\n---\na: !!int \"7\"\n")
            == ["a": 7])
        #expect(try YamlParser.parse("%TAG !! tag:example.com,2000:\n---\na: !!int \"7\"\n")
            == ["a": "7"])
        #expect(try YamlParser.parse("%TAG !! tag:example.com,2000:\n---\na: !!str 1\n")
            == ["a": "1"])
        // A named handle pointing into the YAML namespace, on the contrary, types.
        #expect(try YamlParser.parse("%TAG !e! tag:yaml.org,2002:\n---\na: !e!int \"7\"\n")
            == ["a": 7])
        #expect(try YamlParser.parse("%TAG !e! tag:yaml.org,2002:\n---\na: !e!float \"1.5\"\n")
            == ["a": 1.5])
        #expect(try YamlParser.parse("%TAG !ab_c-1! tag:yaml.org,2002:\n---\nk: !ab_c-1!int \"7\"\n")
            == ["k": 7])
        // The primary handle `!` too.
        #expect(try YamlParser.parse("%TAG ! tag:yaml.org,2002:\n---\na: !int \"7\"\n")
            == ["a": 7])
        #expect(try YamlParser.parse("%TAG ! tag:yaml.org,2002:\n---\na: !str 1\n")
            == ["a": "1"])
        #expect(try YamlParser.parse("%TAG ! tag:x,2000:\n---\na: !foo 1\n") == ["a": "1"])
        // A prefix of `!` (local namespace) → `!int`, i.e. text.
        #expect(try YamlParser.parse("%TAG !e! !\n---\nk: !e!int \"7\"\n") == ["k": "7"])
        // Escapes in the prefix are resolved (`%3A` is ":").
        #expect(try YamlParser.parse("%TAG !! tag%3Ayaml.org,2002%3A\n---\na: !!int \"7\"\n")
            == ["a": 7])
        // Escapes in the tag suffix too, even through a named handle.
        #expect(try YamlParser.parse("%TAG !e! tag:yaml.org,2002:\n---\na: !e!%69%6e%74 \"7\"\n")
            == ["a": 7])
        // The verbatim form and a lone `!` are not affected by the directive.
        #expect(try YamlParser.parse("%TAG !! tag:x,2000:\n---\nk: !<tag:yaml.org,2002:int> \"7\"\n")
            == ["k": 7])
        #expect(try YamlParser.parse("%TAG ! tag:x,2000:\n---\nk: ! 1\n") == ["k": 1])
        // Two different handles side by side and `%TAG` in any order with `%YAML`.
        #expect(try YamlParser.parse(
            "%TAG !a! tag:x,2000:\n%TAG !b! tag:yaml.org,2002:\n---\nk: !b!int \"7\"\n")
            == ["k": 7])
        #expect(try YamlParser.parse("%TAG !! tag:x,2000:\n%YAML 1.2\n---\na: 1\n") == ["a": 1])
        // A directive without a document is empty.
        #expect(try YamlParser.parse("%TAG !! tag:x,2000:\n") == .null)
        // The prefix applies to a tag at the key position too.
        #expect(try YamlParser.parse("%TAG !e! tag:yaml.org,2002:\n---\n!e!int \"7\": 1\n")
            == ["7": 1])
    }

    /// **Java rejects an undefined handle** ("found undefined tag handle !e!") —
    /// we used to silently make text of it, i.e. accept more than Java.
    @Test func undefinedTagHandleThrows() {
        expectError("a: !e!foo 1\n", .syntax, line: 1, column: 2)
        expectError("a: !e!int \"7\"\n", .syntax, line: 1, column: 2)
        expectError("a: [!e!foo 1]\n", .syntax, line: 1, column: 5)
        expectError("!e!foo a: 1\n", .syntax, line: 1, column: 1)
        // A handle declared in `%TAG` is used only for itself; `!x!` stays undefined.
        expectError("%TAG !e! tag:yaml.org,2002:\n---\na: !x!int \"7\"\n",
                    .syntax, line: 3, column: 2)
    }

    /// Java rejects a handle without a type name ("expected URI"). Jackson reports it
    /// at the end of key `a` (1:2), the last event before the error — the SnakeYAML
    /// position after the tag (1:6, 1:7) never reaches the user.
    @Test func handleWithoutTypeNameThrows() {
        expectError("a: !! 1\n", .syntax, line: 1, column: 2)
        expectError("a: !e! 1\n", .syntax, line: 1, column: 2)
    }

    /// A malformed shape of the `%TAG` directive — the positions are measured.
    @Test func malformedTagDirectiveThrows() {
        expectError("%TAG !!\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%TAG !!tag:a,2000:\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%TAG !a b! tag:x,2000:\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%TAG !! \n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%TAG e tag:a,2000:\n---\na: 1\n", .syntax, line: 1, column: 1)
        // A second directive for the same handle ("duplicate tag handle") — Java reports
        // 1:1, because until then it had emitted nothing but the stream start.
        expectError("%TAG !! tag:a,2000:\n%TAG !! tag:b,2000:\n---\na: 1\n",
                    .syntax, line: 1, column: 1)
        expectError("%TAG ! tag:x,2000:\n%TAG ! tag:y,2000:\n---\na: 1\n",
                    .syntax, line: 1, column: 1)
    }

    /// After the directive value only **spaces** and then end of line or
    /// a comment may follow (`ScannerImpl.scanDirectiveIgnoredLine`). As long as this was
    /// not checked, we accepted more than Java.
    ///
    /// Measured on Java: a comment with a space before `#` passes, without a space not,
    /// a tab not, and foreign text after the value not. An unknown directive Java
    /// **does not check at all** — `%FOO bar baz` passes.
    @Test func directiveIgnoredLineFollowsJava() throws {
        // Passes.
        #expect(try YamlParser.parse("%TAG !! tag:yaml.org,2002: # komentar\n---\na: !!int \"7\"\n")
            == ["a": 7])
        #expect(try YamlParser.parse("%TAG !! tag:x,2000: # c\n---\na: !!int \"7\"\n")
            == ["a": "7"])
        #expect(try YamlParser.parse("%TAG !! tag:yaml.org,2002: #\n---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("%TAG !! tag:yaml.org,2002:   \n---\na: !!int \"7\"\n")
            == ["a": 7])
        #expect(try YamlParser.parse("%YAML 1.2 # c\n---\na: 1\n") == ["a": 1])
        // An unknown directive name is not checked by Java, so the rest of the line passes.
        #expect(try YamlParser.parse("%FOO bar baz\n---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("%FOO bar #c\n---\na: 1\n") == ["a": 1])
        // It does not pass — positions measured on Java.
        expectError("%TAG !! tag:yaml.org,2002:# c\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%TAG !! tag:yaml.org,2002:\t# c\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%TAG !! tag:yaml.org,2002: junk\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%TAG !! tag:x,2000:\t\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%YAML 1.2 junk\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%YAML 1.2 1.3\n---\na: 1\n", .syntax, line: 1, column: 1)
    }

    /// `Int.min` is the only value whose unsigned magnitude overflowed —
    /// Java reads it, the writer produces it, and now we read it too.
    @Test func intMinIsReadLikeInJava() throws {
        #expect(try YamlParser.parse("a: -9223372036854775808\n") == ["a": .int(Int.min)])
        #expect(try YamlParser.parse("-9223372036854775808\n") == .int(Int.min))
        #expect(try YamlParser.parse("a: [-9223372036854775808]\n") == ["a": [.int(Int.min)]])
        #expect(try YamlParser.parse("-9223372036854775808: 1\n") == ["-9223372036854775808": 1])
        #expect(try YamlParser.parse("a: -0x8000000000000000\n") == ["a": .int(Int.min)])
        #expect(try YamlParser.parse("a: -9_223_372_036_854_775_808\n") == ["a": .int(Int.min)])
        #expect(try YamlParser.parse("a: !!int -9223372036854775808\n") == ["a": .int(Int.min)])
        #expect(try YamlParser.parse("a: !!int -0x8000000000000000\n") == ["a": .int(Int.min)])
        #expect(try YamlParser.parse("a: -9223372036854775807\n")
            == ["a": .int(Int.min + 1)])
        #expect(try YamlParser.parse("a: 9223372036854775807\n") == ["a": .int(Int.max)])
        // One further and Java already needs BigInteger — there the acknowledged divergence stays.
        expectError("a: -9223372036854775809\n", .unsupported, line: 1, column: 4)
        expectError("a: 9223372036854775808\n", .unsupported, line: 1, column: 4)
    }
}
