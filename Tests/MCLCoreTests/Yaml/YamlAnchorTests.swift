import Foundation
import Testing
@testable import MCLCore

/// An anchor (`&name`) — the reader **reads and discards** it, just like Java.
///
/// The reader once rejected it as `.unsupported`. Combined
/// with `bandplan/`, which swallows errors, that meant a **silent** loss of a
/// hand-written file: Java loads it, we fell back to the built-in plan and the user
/// learned nothing. The rule is "copy Java where it behaves
/// sensibly, reject loudly where it silently does nonsense" — and with an anchor Java
/// behaves sensibly: it discards it and keeps the value.
///
/// All expectations are **measured on Java 21** (Jackson 2.22.0 + SnakeYAML 2.5,
/// `YamlObjectMapper.create().readTree`) with five `AnchorProbe*.java` against
/// `build/classes/java/main`. An alias (`*x`) stays rejected — there Java returns the
/// anchor name as text, which is nonsense (see `YamlUnsupportedTests`).
@Suite struct YamlAnchorTests {

    private func expectError(_ text: String, _ kind: YamlError.Kind,
                             line: Int? = nil, column: Int? = nil,
                             _ comment: Comment? = nil) {
        do {
            let value = try YamlParser.parse(text)
            Issue.record(comment ?? Comment(rawValue: "it should have thrown an error, got \(value)"))
        } catch let e as YamlError {
            #expect(e.kind == kind, comment ?? Comment(rawValue: "\(text.debugDescription): \(e)"))
            if let line { #expect(e.line == line, comment ?? Comment(rawValue: "\(e)")) }
            if let column { #expect(e.column == column, comment ?? Comment(rawValue: "\(e)")) }
        } catch {
            Issue.record(comment ?? Comment(rawValue: "a different error: \(error)"))
        }
    }

    // MARK: - anchor on a value

    @Test func anchorOnScalarValueIsDiscarded() throws {
        #expect(try YamlParser.parse("a: &x 1\n") == ["a": 1])
        #expect(try YamlParser.parse("a: &x hello\n") == ["a": "hello"])
        #expect(try YamlParser.parse("a: &x \"7000-7040\"\n") == ["a": "7000-7040"])
        #expect(try YamlParser.parse("a: &x true\n") == ["a": true])
        #expect(try YamlParser.parse("a: &x -1\n") == ["a": -1])
        // Two spaces after the name do no harm.
        #expect(try YamlParser.parse("a: &x  1\n") == ["a": 1])
    }

    /// An anchor without a value is `null` — even at the end of input without a line break.
    @Test func anchorWithoutValueIsNull() throws {
        #expect(try YamlParser.parse("a: &x\n") == ["a": .null])
        #expect(try YamlParser.parse("a: &x") == ["a": .null])
        #expect(try YamlParser.parse("a: &x\nb: 2\n") == ["a": .null, "b": 2])
        #expect(try YamlParser.parse("a: &x\nb: &y\n") == ["a": .null, "b": .null])
        // `&x1` is the name "x1", not an anchor "x" and a value "1".
        #expect(try YamlParser.parse("a: &x1\n") == ["a": .null])
    }

    /// Anchor name: alphanumeric characters, `_` and `-`; Java also accepts a non-Latin
    /// letter (`&kotvá`).
    @Test(arguments: ["&x", "&X", "&x9", "&1", "&x-y", "&x_y", "&x_1-2", "&kotvá", "&Ω"])
    func anchorNameShapes(anchor: String) throws {
        #expect(try YamlParser.parse("a: \(anchor) 1\n") == ["a": 1], "\(anchor)")
    }

    /// `&` in the middle or inside quotes is **not** an anchor, it is text.
    @Test func ampersandInsideScalarIsText() throws {
        #expect(try YamlParser.parse("a: 1 &x\n") == ["a": "1 &x"])
        #expect(try YamlParser.parse("a: \"&x\"\n") == ["a": "&x"])
        #expect(try YamlParser.parse("a: '&x'\n") == ["a": "&x"])
    }

    // MARK: - anchor on a key

    @Test func anchorOnKeyIsDiscarded() throws {
        #expect(try YamlParser.parse("&x a: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("&x a: 1\nb: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: &x\n&y b: 1\n") == ["a": .null, "b": 1])
        #expect(try YamlParser.parse("{&x a: 1}\n") == ["a": 1])
        #expect(try YamlParser.parse("{&x a: 1, b: 2}\n") == ["a": 1, "b": 2])
    }

    @Test func anchorOnExplicitKeyIsDiscarded() throws {
        #expect(try YamlParser.parse("? &x a\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? a\n: &x 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? &x !!str a\n: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("? !!str &x a\n: 1\n") == ["a": 1])
    }

    // MARK: - anchor with a tag (both orders)

    @Test func anchorCombinesWithTagInBothOrders() throws {
        #expect(try YamlParser.parse("a: &x !!int 1\n") == ["a": 1])
        #expect(try YamlParser.parse("a: !!int &x 1\n") == ["a": 1])
        #expect(try YamlParser.parse("a: &x !!str 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!str &x 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: &x !foo 1\n") == ["a": "1"])
        // The tag is applied even to a quoted value after the anchor.
        #expect(try YamlParser.parse("a: !!int &x \"1\"\n") == ["a": 1])
        // On a key too, in both orders.
        #expect(try YamlParser.parse("&x !!str a: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("!!str &x a: 1\n") == ["a": 1])
    }

    /// A tag and an anchor without a value on the line: the value is an empty scalar, or
    /// a collection from the following lines.
    @Test func tagWithAnchorAndNoValueOnTheLine() throws {
        #expect(try YamlParser.parse("a: !!int &x\n") == ["a": ""])
        #expect(try YamlParser.parse("a: &x !!int\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!map &x\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a: !!seq &x\n- 1\n- 2\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: &x !!seq\n- 1\n- 2\n") == ["a": [1, 2]])
    }

    // MARK: - anchor on a block scalar and on a collection

    @Test func anchorOnBlockScalar() throws {
        #expect(try YamlParser.parse("a: &x |\n  radek\n") == ["a": "radek\n"])
        #expect(try YamlParser.parse("a: &x >-\n  radek\n") == ["a": "radek"])
        #expect(try YamlParser.parse("a: &x |-\n  7000-7040\n") == ["a": "7000-7040"])
    }

    @Test func anchorOnCollection() throws {
        #expect(try YamlParser.parse("a: &x {b: 1}\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a: &x [1, 2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: &x\n  b: 1\n") == ["a": ["b": 1]])
        // A sequence indented the same as its key after the key — Java accepts it.
        #expect(try YamlParser.parse("a: &x\n- 1\n- 2\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: &x\n  - 1\n  - 2\n") == ["a": [1, 2]])
    }

    @Test func anchorOnSequenceEntry() throws {
        #expect(try YamlParser.parse("- &x 1\n- 2\n") == [1, 2])
        #expect(try YamlParser.parse("a:\n- &x 1\n- 2\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a:\n  - &x 1\n  - &y 2\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("- &x\n  b: 1\n") == [["b": 1]])
        #expect(try YamlParser.parse("- &x\n  - 1\n") == [[1]])
        // **After a dash** a dash indented the same is not a nested sequence —
        // it is another item, and the one with the anchor is `null` (measured: `[null,1]`).
        #expect(try YamlParser.parse("- &x\n- 1\n") == [.null, 1])
    }

    // MARK: - anchor in a flow

    @Test func anchorInFlow() throws {
        #expect(try YamlParser.parse("[&x 1, 2]\n") == [1, 2])
        #expect(try YamlParser.parse("{a: &x 1}\n") == ["a": 1])
        #expect(try YamlParser.parse("[&x [1]]\n") == [[1]])
        #expect(try YamlParser.parse("[&x !!str 1]\n") == ["1"])
        #expect(try YamlParser.parse("[!!str &x 1]\n") == ["1"])
        #expect(try YamlParser.parse("[!!int &x \"1\"]\n") == [1])
        // Without a value after the anchor the node is `null` — even inside a flow.
        #expect(try YamlParser.parse("[&x]\n") == [.null])
        #expect(try YamlParser.parse("[&x, 1]\n") == [.null, 1])
        #expect(try YamlParser.parse("{a: &x}\n") == ["a": .null])
        // With a tag it becomes an empty text (`[!!str]` alone is rejected by Java).
        #expect(try YamlParser.parse("[!!str &x]\n") == [""])
    }

    // MARK: - document root, duplicates, unused anchors

    @Test func anchorOnDocumentRoot() throws {
        #expect(try YamlParser.parse("&x 1\n") == .int(1))
        #expect(try YamlParser.parse("&x\n") == .null)
        #expect(try YamlParser.parse("&x\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("--- &x 1\n") == .int(1))
        #expect(try YamlParser.parse("--- &x\n") == .null)
        #expect(try YamlParser.parse("--- &x\nb: 1\n") == ["b": 1])
    }

    /// An anchor **need not** be used and may have the same name twice —
    /// Java reports none of that, because it does not remember anchors at all.
    @Test func duplicateAndUnusedAnchorsAreFine() throws {
        #expect(try YamlParser.parse("a: &x 1\nb: &x 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: &x 1\nb: 2\n") == ["a": 1, "b": 2])
    }

    /// Anchors on three levels at once — the shape that prompted this fix.
    @Test func anchorsAtEveryLevelOfABandplanFile() throws {
        let text = """
            regions:
              R1: &s
              - &r
                cw: &c "7000-7040"
            """
        #expect(try YamlParser.parse(text) == ["regions": ["R1": [["cw": "7000-7040"]]]])
    }

    // MARK: - malformed shapes that Java rejects too

    @Test func malformedAnchorsThrowLikeInJava() {
        // Empty name.
        expectError("a: &\n", .syntax, line: 1, column: 2)
        expectError("a: & 1\n", .syntax, line: 1, column: 2)
        // Two anchors on one node.
        expectError("a: &x &y 1\n", .syntax, line: 1, column: 6)
        expectError("&x &y a: 1\n", .syntax, line: 1, column: 4)
        expectError("a: !!int &x &y 1\n", .syntax, line: 1, column: 12)
        expectError("[&x &y 1]\n", .syntax, line: 1, column: 4)
        // A foreign character in the name (Java: "while scanning an anchor", resp.
        // "while parsing a block mapping").
        expectError("a: &x.y 1\n", .syntax, line: 1, column: 2)
        expectError("a: &x[1]\n", .syntax, line: 1, column: 2)
        expectError("a: &x{b: 1}\n", .syntax, line: 1, column: 2)
        expectError("a: &x,1\n", .syntax, line: 1, column: 6)
        expectError("a: &x]1\n", .syntax, line: 1, column: 6)
        expectError("a: &x}1\n", .syntax, line: 1, column: 6)
        // A block or an explicit key must not start after an anchor.
        expectError("a: &x - 1\n", .syntax, line: 1, column: 2)
        expectError("a: &x ? b\n", .syntax, line: 1, column: 2)
        // The error points to that colon, same as for a tag (`a: !!str b: 1`).
        expectError("a: &x b: 1\n", .syntax, line: 1, column: 8)
        // Two anchors on an explicit key.
        expectError("? &x &y a\n: 1\n", .syntax, line: 1, column: 6)
        expectError("? &x !!str &y a\n: 1\n", .syntax, line: 1, column: 12)
        // An alias after an anchor stays unsupported.
        expectError("&x *y: 1\n", .unsupported, line: 1, column: 4)
        expectError("!!str *y: 1\n", .unsupported, line: 1, column: 7)
    }

    /// `!` right after the anchor name (without a space) is taken by SnakeYAML **into the name**,
    /// so `a: &x!!str 1` is the number `1` in Java and `!!str` silently disappears — measured
    /// (`&x!!int 1` and `&x! 1` give `1` as well, `[&x!!str 1]` gives `[1]`
    /// and `&x!!str a: 1` gives `{"a":1}`). Silently swallowing a tag is nonsense,
    /// so we reject loudly. **With a space everything is fine**
    /// (`a: &x !!str 1` is "1"), and that is the shape people actually write.
    @Test func tagGluedToAnchorNameIsRefusedLoudly() {
        expectError("a: &x!!str 1\n", .syntax, line: 1, column: 6)
        expectError("a: &x!!int 1\n", .syntax, line: 1, column: 6)
        expectError("a: &x! 1\n", .syntax, line: 1, column: 6)
        expectError("[&x!!str 1]\n", .syntax, line: 1, column: 4)
        expectError("&x!!str a: 1\n", .syntax, line: 1, column: 3)
        // Control counterpart: with a space it is a tag and it is applied.
        #expect((try? YamlParser.parse("a: &x !!str 1\n")) == ["a": "1"])
    }

    /// **Recorded divergences.** Here SnakeYAML ends the anchor name even at a character
    /// after which it then **silently drops** or rewrites the value. We reject loudly,
    /// because silently losing what the user wrote is exactly the defect
    /// this suite guards against.
    ///
    /// | input | Java | us |
    /// |---|---|---|
    /// | `a: &x"q"` | `{"a":null}` — `"q"` vanishes | error |
    /// | `a: &x'q'` | `{"a":null}` | error |
    /// | `a: &x#k` | `{"a":null}` | error |
    /// | `a: &x%1` | `{"a":null}` | error |
    /// | `a: &x@1` | `{"a":null}` | error |
    /// | ``a: &x`1`` | `{"a":null}` | error |
    /// | `a: &x?1` | `{"a":null}` | error |
    /// | `a: &x:y 1` | `{"a":":y 1"}` — rewritten value | error |
    /// | `&x: 1` | `{"":1}` — an invented empty key | error |
    /// | `&x,1: 2` | `null` — the **whole document** vanishes | now `null` as in Java (content after the root is copied) |
    @Test func anchorNameTerminatorsJavaAcceptsAreRefusedLoudly() {
        expectError("a: &x\"q\"\n", .syntax, line: 1, column: 6)
        expectError("a: &x'q'\n", .syntax, line: 1, column: 6)
        expectError("a: &x#k\n", .syntax, line: 1, column: 6)
        expectError("a: &x%1\n", .syntax, line: 1, column: 6)
        expectError("a: &x@1\n", .syntax, line: 1, column: 6)
        expectError("a: &x`1\n", .syntax, line: 1, column: 6)
        expectError("a: &x?1\n", .syntax, line: 1, column: 6)
        expectError("a: &x:y 1\n", .syntax, line: 1, column: 6)
        expectError("&x: 1\n", .syntax, line: 1, column: 3)
        // `,`, `]` and `}` end an anchor **only inside a flow** (`[&x]` is `[null]`).
        // In a block at a key position Java makes `null` of the whole document from them:
        // the root is an anchor with an empty scalar and Java does not read the rest. Now
        // (content after the root is copied) the same — above all, a key ",1"
        // must not be produced (measured).
        #expect((try? YamlParser.parse("&x,1: 2\n")) == .null)
        #expect((try? YamlParser.parse("&x]1: 2\n")) == .null)
        #expect((try? YamlParser.parse("&x}1: 2\n")) == .null)
        expectError("? &x,1\n: 2\n", .syntax, line: 1, column: 5)
    }

    /// A tab after an anchor is rejected by Java too ("while scanning for the next token").
    @Test func tabAfterAnchorThrows() {
        expectError("a: &x\t1\n", .syntax)
    }
}
