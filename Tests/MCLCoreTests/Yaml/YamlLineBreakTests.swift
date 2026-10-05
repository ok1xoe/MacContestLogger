import Foundation
import Testing
@testable import MCLCore

/// Line breaks according to SnakeYAML: `\n`, `\r\n`, `\r`, NEL (U+0085), U+2028
/// and U+2029 — and **how they fold**.
///
/// A port of `ScannerImpl.scanLineBreak`: the first four are reported as `"\n"` and a single
/// such break folds **into a space**, whereas U+2028 and U+2029 are returned literally
/// and fold **as themselves**. This is not cosmetic: they are full-fledged breaks,
/// so a comment ends on them, a map splits and block-scalar indentation is measured.
/// Before this was fixed, the reader made ordinary mid-line characters of them
/// and silently lost map keys.
///
/// All measured on a running Java (Jackson 2.22.0 + SnakeYAML 2.5,
/// `YamlObjectMapper.create().readTree`).
@Suite struct YamlLineBreakTests {

    private let ls = "\u{2028}"
    private let ps = "\u{2029}"
    private let nel = "\u{85}"

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

    /// A group of consecutive breaks: the first `"\n"` folds into a space only if
    /// it is alone in the group; otherwise it is dropped and the rest is printed literally.
    /// U+2028/U+2029 always come out as themselves.
    @Test func breakGroupsFoldLikeInJava() throws {
        #expect(try YamlParser.parse("a: x\n  y\n") == ["a": .string("x y")])
        #expect(try YamlParser.parse("a: x\(ls)  y\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: x\(ps)  y\n") == ["a": .string("x\(ps)y")])
        #expect(try YamlParser.parse("a: x\n\n  y\n") == ["a": .string("x\ny")])
        #expect(try YamlParser.parse("a: x\(ls)\(ls)  y\n") == ["a": .string("x\(ls)\(ls)y")])
        #expect(try YamlParser.parse("a: x\(ls)\n  y\n") == ["a": .string("x\(ls)\ny")])
        #expect(try YamlParser.parse("a: x\n\(ls)  y\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: x\n\(ls)\n  y\n") == ["a": .string("x\(ls)\ny")])
        #expect(try YamlParser.parse("a: x\(ls)\n\n  y\n") == ["a": .string("x\(ls)\n\ny")])
        #expect(try YamlParser.parse("a: x\n\n\(ls)  y\n") == ["a": .string("x\n\(ls)y")])
        #expect(try YamlParser.parse("a: x\(ps)\(ls)  y\n") == ["a": .string("x\(ps)\(ls)y")])
        // More spaces after a break and before it are stripped the same as for "\n".
        #expect(try YamlParser.parse("a: x\(ls)      y\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: x  \(ls)  y\n") == ["a": .string("x\(ls)y")])
        // Two separate breaks in a row, each with its own group.
        #expect(try YamlParser.parse("a: x\(ls)  y\(ls)  z\n") == ["a": .string("x\(ls)y\(ls)z")])
        #expect(try YamlParser.parse("a: x\(ls)  y\n  z\n") == ["a": .string("x\(ls)y z")])
        #expect(try YamlParser.parse("a: x\n  y\(ls)  z\n") == ["a": .string("x y\(ls)z")])
        #expect(try YamlParser.parse("a: x\(ls)  y\(nel)  z\n") == ["a": .string("x\(ls)y z")])
        // Without indentation after a break it is an error in Java — the continuation line
        // is not more indented than the map. Java reports it at the end of the last event
        // (scalar `x`, 1:5), not on the line where the error is.
        expectError("a: x\(ls)y\n", .syntax, line: 1, column: 5)
        expectError("a: x\(nel)y\n", .syntax, line: 1, column: 5)
    }

    /// NEL is `"\n"` for SnakeYAML, so it folds into a space.
    @Test func nelFoldsLikeNewline() throws {
        #expect(try YamlParser.parse("a: x\(nel)  y\n") == ["a": .string("x y")])
        #expect(try YamlParser.parse("a: \"x\(nel)  y\"\n") == ["a": .string("x y")])
        #expect(try YamlParser.parse("a: |\n  x\(nel)  y\n") == ["a": .string("x\ny\n")])
        #expect(try YamlParser.parse("a: |\n  x\(nel)    y\n") == ["a": .string("x\n  y\n")])
        // A break in a key: the map falls apart into a root scalar, resp. into two keys.
        #expect(try YamlParser.parse("a\(nel)b: 1\n") == .string("a b"))
        #expect(try YamlParser.parse("a: 1\(nel)b: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: 1\(nel)") == ["a": 1])
    }

    /// Quoted scalars fold by the same rule, and a backslash
    /// in double quotes swallows the **first** break of the group, even if it is U+2028.
    @Test func quotedScalarsFoldTheSameWay() throws {
        #expect(try YamlParser.parse("a: 'x\(ls)  y'\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: 'x\(ls)y'\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: 'x\(ls)  y\(ls)  z'\n") == ["a": .string("x\(ls)y\(ls)z")])
        #expect(try YamlParser.parse("a: 'x\(ls)\(ls)  y'\n") == ["a": .string("x\(ls)\(ls)y")])
        #expect(try YamlParser.parse("a: 'x\(ls)   '\n") == ["a": .string("x\(ls)")])
        // In single quotes a backslash is an ordinary character.
        #expect(try YamlParser.parse("a: 'x\\\(ls)  y'\n") == ["a": .string("x\\\(ls)y")])
        #expect(try YamlParser.parse("a: \"x\(ls)  y\"\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: \"x\(ls)y\"\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: \"x\(ls)\(ls)  y\"\n") == ["a": .string("x\(ls)\(ls)y")])
        #expect(try YamlParser.parse("a: \"x\(ls)\n  y\"\n") == ["a": .string("x\(ls)\ny")])
        #expect(try YamlParser.parse("a: \"x\\Ly\"\n") == ["a": .string("x\(ls)y")])
        // A backslash swallows the first break, the rest of the group remains.
        #expect(try YamlParser.parse("a: \"x\\\(ls)  y\"\n") == ["a": .string("xy")])
        #expect(try YamlParser.parse("a: \"x\\\n  y\"\n") == ["a": .string("xy")])
        #expect(try YamlParser.parse("a: \"x\\\(ls)\(ls)  y\"\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: \"x\\\(ls)\n  y\"\n") == ["a": .string("x\ny")])
        #expect(try YamlParser.parse("a: \"x\\\n\(ls)  y\"\n") == ["a": .string("x\(ls)y")])
    }

    /// A block scalar: the break is taken **from the line**, so U+2028 stays itself,
    /// and the block indentation is measured after such a break too.
    @Test func blockScalarsUseTheRealBreak() throws {
        #expect(try YamlParser.parse("a: |\n  x\(ls)  y\n") == ["a": .string("x\(ls)y\n")])
        #expect(try YamlParser.parse("a: |\n  x\(ls)\n") == ["a": .string("x\(ls)")])
        #expect(try YamlParser.parse("a: |-\n  x\(ls)  y\n") == ["a": .string("x\(ls)y")])
        #expect(try YamlParser.parse("a: |+\n  x\(ls)  y\n") == ["a": .string("x\(ls)y\n")])
        #expect(try YamlParser.parse("a: |+\n  x\(ls)  y\(ls)\(ls)\n")
            == ["a": .string("x\(ls)y\(ls)\(ls)\n")])
        #expect(try YamlParser.parse("a: |\n  x\(ls)\(ls)  y\n") == ["a": .string("x\(ls)\(ls)y\n")])
        #expect(try YamlParser.parse("a: |\n  x\(ls)\n  y\n") == ["a": .string("x\(ls)\ny\n")])
        #expect(try YamlParser.parse("a: |\n  x\(ls)    y\n") == ["a": .string("x\(ls)  y\n")])
        #expect(try YamlParser.parse("a: |\n  x\n  y\(ls)\n") == ["a": .string("x\ny\(ls)")])
        // Folding of `>` into a space applies only to "\n"; U+2028 does not fold.
        #expect(try YamlParser.parse("a: >\n  x\n  y\n") == ["a": .string("x y\n")])
        #expect(try YamlParser.parse("a: >\n  x\(ls)  y\n") == ["a": .string("x\(ls)y\n")])
        #expect(try YamlParser.parse("a: >\n  x\(ls)\(ls)  y\n") == ["a": .string("x\(ls)\(ls)y\n")])
        // Without indentation after a break Java errors.
        expectError("a: |\n  x\(ls)y\n", .syntax, line: 3, column: 1)
    }

    /// U+2028/U+2029 are **structure**, not just a different folding: a map splits on them,
    /// a comment ends with them and indentation is measured anew after them. This is the
    /// part the reader used to silently lose.
    @Test func lineSeparatorsAreStructuralBreaks() throws {
        #expect(try YamlParser.parse("a: 1\(ls)b: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: 1\(ls)\(ls)b: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: 1 # c\(ls)b: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a:\(ls)  \(ls)  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a: 1\(ls)") == ["a": 1])
        // A key with a break: at the root the map becomes a scalar, because Jackson
        // reads one value and drops the rest.
        #expect(try YamlParser.parse("a\(ls)  b: 1\n") == .string("a\(ls)b"))
        #expect(try YamlParser.parse("a\(ls)b: 1\n") == .string("a\(ls)b"))
        #expect(try YamlParser.parse("x\(ls)  y\n") == .string("x\(ls)y"))
        // A document marker after such a break ends the document.
        #expect(try YamlParser.parse("a: x\(ls)---\n") == ["a": .string("x")])
        #expect(try YamlParser.parse("a: 1\(ls)---\(ls)b: 2\n") == ["a": 1])
        // Flow notation follows the same rule.
        #expect(try YamlParser.parse("a: [x\(ls)  y]\n") == ["a": .sequence([.string("x\(ls)y")])])
        #expect(try YamlParser.parse("a: [x\(ls)\(ls)  y]\n") == ["a": .sequence([.string("x\(ls)\(ls)y")])])
    }

    /// `\r\n` and a lone `\r` stay `"\n"` — splitting goes by Unicode scalars,
    /// so `\r\n` (one grapheme in Swift) does not fall into two breaks.
    @Test func carriageReturnsStillCountAsOneNewline() throws {
        #expect(try YamlParser.parse("a: 1\r\nb: 2\r\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: 1\rb: 2\r") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("a: x\r\n  y\r\n") == ["a": .string("x y")])
        #expect(try YamlParser.parse("a: x\r  y\r") == ["a": .string("x y")])
        #expect(try YamlParser.parse("a: |\r\n  x\r\n  y\r\n") == ["a": .string("x\ny\n")])
        // `\r\n` at the end of the file gives one trailing break, not two.
        #expect(try YamlParser.parse("a: |\r\n  x\r\n") == ["a": .string("x\n")])
    }
}
