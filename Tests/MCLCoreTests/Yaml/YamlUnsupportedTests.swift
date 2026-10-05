import Foundation
import Testing
@testable import MCLCore

/// The reader's error arm: constructs outside our subset are **never swallowed
/// as text**, they always throw `YamlError`.
///
/// All expectations are measured on a running Java (Jackson 2.22.0 + SnakeYAML
/// 2.5, `YamlObjectMapper.create().readTree`). Java
/// **reads** the remaining constructs (it drops an anchor, returns an alias as the anchor name);
/// we reject them, but loudly and with the kind `.unsupported`, so that the caller can tell
/// "we cannot do this" from "the file is broken". A half-read definition would show up
/// only as a wrong score in the contest.
///
/// Tags and block scalars have **not** been in the list of rejected constructs
/// — there rejection lost to the principle "we must not refuse what Java loads".
///
/// For every error the `kind`, line **and column** are pinned — a bare "it threw
/// an error" would not distinguish an unsupported construct from a syntax one.
@Suite struct YamlUnsupportedTests {

    /// Verifies that the input throws a `YamlError` of the given kind at the given position.
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

    // MARK: - aliases

    // An anchor (`&x`) has **not** been in this suite: Java drops it
    // and keeps the value (`a: &x 1` → `1`), which is sensible behaviour, so the
    // reader copies it. The tables are in `YamlAnchorTests`; the rejected **malformed** shapes
    // of an anchor (empty name, two anchors, foreign character in the name) too.

    /// Jackson does **not expand** an alias — it returns the anchor name as text (`b: *x` → "x",
    /// even if there is no anchor `x`). Silently returning such a value would be worse
    /// than an error.
    @Test func aliasIsUnsupported() {
        expectError("a: *x\n", .unsupported, line: 1, column: 4)
        expectError("a: *x # c\n", .unsupported, line: 1, column: 4)
        expectError("a: {b: *c}\n", .unsupported, line: 1, column: 8)
        expectError("a: [1, *c]\n", .unsupported, line: 1, column: 8)
        expectError("*x: 1\n", .unsupported, line: 1, column: 1)
    }

    /// The merge key `<<` is **not a construct** — Jackson merges nothing and takes it as an
    /// ordinary key (measured: `<<: 1` gives `{"<<":1}`). We copy that; it fails loudly
    /// only on an alias in its value, which is the only shape that makes sense to write.
    @Test func mergeKeyIsAnOrdinaryKeyLikeInJava() throws {
        #expect(try YamlParser.parse("a:\n  <<: 1\n  y: 2\n") == ["a": ["<<": 1, "y": 2]])
        #expect(try YamlParser.parse("a: {<<: 1}\n") == ["a": ["<<": 1]])
        #expect(try YamlParser.parse("a:\n  <<:\n    b: 1\n") == ["a": ["<<": ["b": 1]]])
        // `derived:\n  <<: *base` — the alias fails, not `<<`.
        expectError("base:\n  x: 1\nderived:\n  <<: *base\n", .unsupported, line: 4, column: 7)
    }

    // MARK: - type tags and block scalars: supported

    /// Tags and block scalars are **not** in this suite: Java reads them, so
    /// rejecting them would mean that a definition the Java application loads
    /// is refused by the Swift one — and refusing a contest definition in the middle of a contest is
    /// the worst possible failure. Detailed tables are in `YamlBlockScalarTests`.
    @Test func tagsAndBlockScalarsAreNoLongerRejected() throws {
        #expect(try YamlParser.parse("a: !!str 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!int \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!str 001\n") == ["a": "001"])
        #expect(try YamlParser.parse("a: |\n  text\n  dalsi\n") == ["a": "text\ndalsi\n"])
        #expect(try YamlParser.parse("a: >\n  text\n") == ["a": "text\n"])
        #expect(try YamlParser.parse("- |\n  x\n") == ["x\n"])
    }

    // MARK: - explicit key

    /// The reader reads an explicit key in a **block** map, because Java
    /// handles it correctly **and above all because our writer produces it** (a key
    /// that is empty, multi-line or ≥128 UTF-16 units). If the reader
    /// rejected it, the definition editor would break in the middle of editing a contest.
    /// Detailed tables are in `YamlExplicitKeyTests`.
    @Test func explicitKeyInBlockMappingIsRead() throws {
        #expect(try YamlParser.parse("? a\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? a\n? b\n") == ["a": .null, "b": .null])
        #expect(try YamlParser.parse("?\n") == ["": .null])
        #expect(try YamlParser.parse("a:\n  ? b\n  : 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("- ? b\n") == [["b": .null]])
        #expect(try YamlParser.parse("- ?\n") == [["": .null]])
    }

    /// Where `? ` is **not** a key it remains an error — and where Java rejects it,
    /// it is `.syntax`, not "we cannot do this".
    @Test func explicitKeyOutsideKeyPositionThrows() {
        // At a value position Java rejects it ("mapping keys are not allowed here";
        // Jackson reports the end of key `a`, 1:2) — so it is a syntax error,
        // not an unsupported construct.
        expectError("a: ? b\n", .syntax, line: 1, column: 2)
        expectError("a: ?\n", .syntax, line: 1, column: 2)
        expectError("a: !!str ? b\n", .syntax, line: 1, column: 2)
        // In a flow `?` is an indicator even without a space after it. Java reads `[? b]`
        // (`[{"b":null}]`), we do not — but loudly. The writer never produces a flow with content
        // (only empty `{}`/`[]`), so this does not break symmetry.
        expectError("a: [? b]\n", .unsupported, line: 1, column: 5)
        expectError("a: {? b: 1}\n", .unsupported, line: 1, column: 5)
        expectError("a: [1, ? b]\n", .unsupported, line: 1, column: 8)
    }

    // MARK: - syntax errors (a different kind)

    /// `%`, `@` and `` ` `` at a token position are rejected by Java too ("found character … that
    /// cannot start any token"), so it is not "we cannot do this" but `.syntax`.
    @Test func reservedCharactersAreSyntaxErrors() {
        expectError("a: %neco\n", .syntax, line: 1, column: 2)
        expectError("a: @neco\n", .syntax, line: 1, column: 2)
        expectError("a: `neco\n", .syntax, line: 1, column: 2)
        expectError("a: [@x]\n", .syntax, line: 1, column: 5)
    }

    /// A tab: in indentation and where a separator is expected. Java rejects both,
    /// including an indented comment and an "empty" line with a tab.
    @Test func tabsAreSyntaxErrors() {
        expectError("a:\n\tb: 1\n", .syntax, line: 1, column: 2)
        expectError("a:\tb\n", .syntax, line: 1, column: 2)
        expectError("a: 1\n\t# c\n", .syntax, line: 1, column: 5)
        expectError("a: 1\n\t\nb: 2\n", .syntax, line: 1, column: 5)
    }

    // MARK: - what a construct is NOT (Java reads it as text, and so do we)

    /// These characters are indicators **only at a token position**. In the middle of a plain
    /// scalar and in a key they are ordinary characters and Java reads them so — if the
    /// reader rejected them, it would refuse files that the Java application loads.
    @Test func indicatorsInsidePlainScalarsStayText() throws {
        #expect(try YamlParser.parse("a: b&c\n") == ["a": "b&c"])
        #expect(try YamlParser.parse("a: b*c\n") == ["a": "b*c"])
        #expect(try YamlParser.parse("a: x!y\n") == ["a": "x!y"])
        #expect(try YamlParser.parse("a: 50%\n") == ["a": "50%"])
        #expect(try YamlParser.parse("a: x|y\n") == ["a": "x|y"])
        #expect(try YamlParser.parse("a: x>y\n") == ["a": "x>y"])
        #expect(try YamlParser.parse("a: ?x\n") == ["a": "?x"])
        #expect(try YamlParser.parse("a: x\ty\n") == ["a": "x\ty"])
        #expect(try YamlParser.parse("a|b: 1\n") == ["a|b": 1])
        #expect(try YamlParser.parse("a>b: 1\n") == ["a>b": 1])
        // `?` without a space after it is text, even if it is the whole key.
        #expect(try YamlParser.parse("?: 1\n") == ["?": 1])
        // In quotes anything is an indicator, even `*x` as a key.
        #expect(try YamlParser.parse("\"*x\": 1\n") == ["*x": 1])
        #expect(try YamlParser.parse("a: \"&x\"\n") == ["a": "&x"])
    }

    // MARK: - document markers (`---`, `...`) are NOT errors

    /// A leading `---` really is in the data (`bandplan.yaml`, `digi_frequencies.yaml`)
    /// and Jackson **quietly** drops a second document — it returns only the first.
    /// The rule "no change of behaviour" overrides the principle of loudness here: a definition
    /// that the Java application loads must not be rejected by the Swift one.
    @Test func documentMarkersAreNotErrors() throws {
        #expect(try YamlParser.parse("---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("---\na: 1\n---\nb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n---\nb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n...\n") == ["a": 1])
        #expect(try YamlParser.parse("---\n") == .null)
        // A marker with content is only a boundary in the **next** document too.
        #expect(try YamlParser.parse("a: 1\n--- b: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n... b\n") == ["a": 1])
        #expect(try YamlParser.parse("hello\n--- x\n") == .string("hello"))
        // Without a space after the marker it is not a marker — it is a key.
        #expect(try YamlParser.parse("---x: 1\n") == ["---x": 1])
    }

    /// A lone `...` without content is rejected by Java ("expected the node content, but
    /// found '<document end>'") — the only exception among the document markers.
    @Test func endMarkerWithoutContentThrows() {
        expectError("...\n", .syntax, line: 1, column: 1)
        expectError("...\na: 1\n", .syntax, line: 1, column: 1)
    }

    /// Content on the line with a **leading** `---` is split by shapes, not
    /// across the board. Java handles a scalar, a block scalar, a tag and a flow collection
    /// **correctly**, so we read them; a block map it silently mangles (`--- a: 1` gives
    /// "a" and drops the rest), so we reject it; and on a block sequence
    /// and an explicit key Java itself errors. All measured.
    ///
    /// The writer **writes** a root scalar, `{}` and `[]` on this line, so
    /// without this the reader could not read what it has just written.
    @Test func leadingMarkerContentFollowsJava() throws {
        // Java handles it correctly → we read it.
        #expect(try YamlParser.parse("--- null\n") == .null)
        #expect(try YamlParser.parse("--- ~\n") == .null)
        #expect(try YamlParser.parse("--- 1\n") == .int(1))
        #expect(try YamlParser.parse("--- 1.5\n") == .double(1.5))
        #expect(try YamlParser.parse("--- true\n") == .bool(true))
        #expect(try YamlParser.parse("--- hello world\n") == .string("hello world"))
        #expect(try YamlParser.parse("--- \"x y\"\n") == .string("x y"))
        #expect(try YamlParser.parse("--- 'a # b'\n") == .string("a # b"))
        #expect(try YamlParser.parse("--- \"a: 1\"\n") == .string("a: 1"))
        #expect(try YamlParser.parse("--- ---\n") == .string("---"))
        #expect(try YamlParser.parse("--- {}\n") == .mapping(YamlMapping()))
        #expect(try YamlParser.parse("--- []\n") == .sequence([]))
        #expect(try YamlParser.parse("--- [1,2]\n") == [1, 2])
        #expect(try YamlParser.parse("--- {a: 1, b: 2}\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("--- |\n  x\n") == .string("x\n"))
        #expect(try YamlParser.parse("--- |-\n  x\n") == .string("x"))
        #expect(try YamlParser.parse("--- >\n  x\n") == .string("x\n"))
        #expect(try YamlParser.parse("--- !!str 1\n") == .string("1"))
        #expect(try YamlParser.parse("--- !!int \"7\"\n") == .int(7))
        #expect(try YamlParser.parse("--- !!map\na: 1\n") == ["a": 1])
        // A comment after the marker is not content.
        #expect(try YamlParser.parse("--- # c\n") == .null)
        #expect(try YamlParser.parse("--- # c\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("--- 1 # c\n") == .int(1))
        // Folding and dropping the rest is the same as for a root node without a marker.
        #expect(try YamlParser.parse("--- hello\nworld\n") == .string("hello world"))
        #expect(try YamlParser.parse("--- null\nb: 3\n") == .string("null b"))
        #expect(try YamlParser.parse("--- [1,2]\nb: 3\n") == [1, 2])
        #expect(try YamlParser.parse("--- 1\n---\nb: 2\n") == .int(1))
        // The root is a scalar before ": " and Java does not read the rest (content after the root node is copied from Java — we used to reject it
        // as `.unsupported`). The key "--- a" does not arise from it.
        #expect(try YamlParser.parse("--- a: 1\n") == .string("a"))
        #expect(try YamlParser.parse("--- a:\n") == .string("a"))
        #expect(try YamlParser.parse("--- \"x\": 1\n") == .string("x"))
        #expect(try YamlParser.parse("--- !!str a: 1\n") == .string("a"))
        // Java itself errors → `.syntax` at the same column.
        expectError("--- - 1\n", .syntax, line: 1, column: 4)
        expectError("--- -\n", .syntax, line: 1, column: 4)
        expectError("--- ? a\n", .syntax, line: 1, column: 4)
        // An alias stays unsupported here too; an anchor, on the contrary, is dropped and the content
        // after it is read (measured: `--- &x 1` is `1`, `--- &x` is `null`).
        expectError("--- *x\n", .unsupported, line: 1, column: 5)
    }

    // MARK: - directives (`%YAML`, `%TAG`)

    /// Java drops a directive at the start of the stream and reads the document — even an unknown one.
    /// Rejecting it would mean refusing a file that the Java application loads.
    @Test func leadingDirectivesAreIgnoredLikeInJava() throws {
        #expect(try YamlParser.parse("%YAML 1.2\n---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("%YAML 1.1\n---\na: yes\n") == ["a": .bool(true, raw: "yes")])
        #expect(try YamlParser.parse("%TAG ! tag:example.com,2000:\n---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("%FOO bar\n---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("%YAML 1.2\n%TAG ! tag:x,2000:\n---\na: 1\n") == ["a": 1])
        // Comments and empty lines around the directive do no harm.
        #expect(try YamlParser.parse("# c\n%YAML 1.2\n---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("%YAML 1.2\n# c\n---\na: 1\n") == ["a": 1])
        // A directive without content is an empty document (Java `NullNode`/`MissingNode`).
        #expect(try YamlParser.parse("%YAML 1.2\n---\n") == .null)
        #expect(try YamlParser.parse("%YAML 1.2\n") == .null)
    }

    /// What Java rejects on directives we reject too — at the same positions.
    @Test func malformedDirectivesThrow() {
        // After a directive `---` must follow ("expected '<document start>'").
        expectError("%YAML 1.2\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%YAML 1.2\n...\n", .syntax, line: 1, column: 1)
        // Two `%YAML` directives ("found duplicate YAML directive").
        expectError("%YAML 1.2\n%YAML 1.1\n---\na: 1\n", .syntax, line: 1, column: 1)
        // A lone `%` and a name glued to the value.
        expectError("%\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%YAML1.2\n---\na: 1\n", .syntax, line: 1, column: 1)
        expectError("%YAML\t1.2\n---\na: 1\n", .syntax, line: 1, column: 1)
        // An indented directive is not a directive ("found character '%' …").
        expectError("  %YAML 1.2\n---\na: 1\n", .syntax, line: 1, column: 1)
    }

    // MARK: - never half a document

    /// A construct in the middle of a definition brings down the **whole** file, not just its key —
    /// and the error points to its line. This is the point of this whole suite: a definition
    /// that is loaded halfway shows up only as a wrong score in the contest.
    @Test func unsupportedConstructFailsTheWholeDocument() throws {
        let text = """
        schemaVersion: 1
        id: test
        scoring:
          base: *b
          other: 2
        """
        expectError(text, .unsupported, line: 4, column: 9)
        // A block scalar in the middle of a definition is no longer a construct outside the subset:
        // it is read, because Java reads it too.
        let withBlockScalar = """
        id: test
        notes: |
          dlouhý text
        bands: [160m]
        """
        #expect(try YamlParser.parse(withBlockScalar) == [
            "id": "test", "notes": "dlouhý text\n", "bands": ["160m"],
        ])
    }
}
