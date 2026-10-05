import Foundation
import Testing
@testable import MCLCore

/// Block scalars (`|`, `>`) and type tags (`!!str`, `!!int`…).
///
/// An earlier version rejected both as unsupported. That was a mistake: **Java reads both**,
/// so a definition the Java application loads would be rejected by the Swift one — and rejection
/// in the middle of a contest is the worst possible failure. A long `description: |` is entirely
/// common and `!!str 001` keeps the leading zeros, which matters for serial numbers
/// in the exchange.
///
/// **All expectations are measured on a running Java** (Jackson 2.22.0 + SnakeYAML
/// 2.5, `YamlObjectMapper.create().readTree`) (measured).
/// For every error the kind, line and column are pinned.
@Suite struct YamlBlockScalarTests {

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

    // MARK: - the shape this is done for

    /// A long contest description — a realistic shape of `description: |` + indented lines.
    @Test func longContestDescription() throws {
        let text = """
        id: test
        description: |
          Prvni radek popisu.
          Druhy radek popisu.

          Odstavec po prazdnem radku.
        bands: [160m, 80m]
        """
        #expect(try YamlParser.parse(text + "\n") == [
            "id": "test",
            "description": "Prvni radek popisu.\nDruhy radek popisu.\n\nOdstavec po prazdnem radku.\n",
            "bands": ["160m", "80m"],
        ])
    }

    // MARK: - literal `|` and folded `>`, chomping (`-`, `+`)

    /// Basics: `|` keeps line breaks, `>` folds them into a space. Without a chomping indicator
    /// exactly **one** trailing line break stays ("clip").
    @Test func literalKeepsBreaksFoldedJoinsThem() throws {
        #expect(try YamlParser.parse("a: |\n  text\n  dalsi\n") == ["a": "text\ndalsi\n"])
        #expect(try YamlParser.parse("a: >\n  text\n  dalsi\n") == ["a": "text dalsi\n"])
        #expect(try YamlParser.parse("a: >\n  a\n  b\n  c\n") == ["a": "a b c\n"])
    }

    /// Chomping: `-` drops the trailing line break, `+` keeps **all** of them.
    @Test func chompingIndicators() throws {
        #expect(try YamlParser.parse("a: |-\n  text\n  dalsi\n") == ["a": "text\ndalsi"])
        #expect(try YamlParser.parse("a: |+\n  text\n  dalsi\n") == ["a": "text\ndalsi\n"])
        #expect(try YamlParser.parse("a: >-\n  text\n  dalsi\n") == ["a": "text dalsi"])
        #expect(try YamlParser.parse("a: >+\n  text\n  dalsi\n") == ["a": "text dalsi\n"])
    }

    /// Trailing empty lines — the only place where `clip`, `-` and `+` differ.
    /// Measured: clip keeps one line break, `-` none, `+` all.
    @Test func trailingBlankLinesAndChomping() throws {
        #expect(try YamlParser.parse("a: |\n  text\n\n\nb: 2\n") == ["a": "text\n", "b": 2])
        #expect(try YamlParser.parse("a: |-\n  text\n\n\nb: 2\n") == ["a": "text", "b": 2])
        #expect(try YamlParser.parse("a: |+\n  text\n\n\nb: 2\n") == ["a": "text\n\n\n", "b": 2])
        #expect(try YamlParser.parse("a: >\n  text\n\n\nb: 2\n") == ["a": "text\n", "b": 2])
        #expect(try YamlParser.parse("a: >-\n  text\n\n\nb: 2\n") == ["a": "text", "b": 2])
        #expect(try YamlParser.parse("a: >+\n  text\n\n\nb: 2\n") == ["a": "text\n\n\n", "b": 2])
        // At the end of the file: three empty lines, `+` keeps all three.
        #expect(try YamlParser.parse("a: |\n  x\n\n\n\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("a: |+\n  x\n\n\n\n") == ["a": "x\n\n\n\n"])
        #expect(try YamlParser.parse("a: |-\n  x\n\n\n\n") == ["a": "x"])
    }

    /// A file that does not end with a line break: then there is **no** trailing line break even with clip
    /// and `+` (measured: `a: |` + `  x` without a line break gives "x", not "x\n").
    @Test func noFinalLineBreakInFile() throws {
        #expect(try YamlParser.parse("a: |\n  x") == ["a": "x"])
        #expect(try YamlParser.parse("a: |-\n  x") == ["a": "x"])
        #expect(try YamlParser.parse("a: |+\n  x") == ["a": "x"])
        #expect(try YamlParser.parse("a: >\n  x\n  y") == ["a": "x y"])
        #expect(try YamlParser.parse("a: |") == ["a": ""])
    }

    /// Empty lines inside: for `|` break for break, for `>` N empty lines = N line breaks.
    @Test func blankLinesInside() throws {
        #expect(try YamlParser.parse("a: |\n  jeden\n\n  dva\n") == ["a": "jeden\n\ndva\n"])
        #expect(try YamlParser.parse("a: >\n  jeden\n\n  dva\n") == ["a": "jeden\ndva\n"])
        #expect(try YamlParser.parse("a: >\n  jeden\n\n\n  dva\n") == ["a": "jeden\n\ndva\n"])
        // A leading empty line is preserved.
        #expect(try YamlParser.parse("a: |\n\n  text\n") == ["a": "\ntext\n"])
        #expect(try YamlParser.parse("a: >\n\n  text\n") == ["a": "\ntext\n"])
    }

    /// An empty block. `a: |` is an **empty text**, not `null` (measured).
    @Test func emptyBlockIsEmptyStringNotNull() throws {
        #expect(try YamlParser.parse("a: |\n") == ["a": ""])
        #expect(try YamlParser.parse("a: >\n") == ["a": ""])
        #expect(try YamlParser.parse("a: |+\n") == ["a": ""])
        #expect(try YamlParser.parse("a: |\nb: 2\n") == ["a": "", "b": 2])
        // Only empty lines: clip gives empty, `+` turns them into line breaks.
        #expect(try YamlParser.parse("a: |\n\n\nb: 2\n") == ["a": "", "b": 2])
        #expect(try YamlParser.parse("a: |+\n\n\nb: 2\n") == ["a": "\n\n", "b": 2])
    }

    // MARK: - lines indented more than the block

    /// A more-indented line **keeps** its indentation and for `>` cancels folding — even
    /// for the line break **before** it and **after** it. This is the least obvious
    /// rule of a folded scalar, so it is measured shape by shape.
    @Test func moreIndentedLinesSuppressFolding() throws {
        #expect(try YamlParser.parse("a: |\n  jeden\n    dva\n  tri\n") == ["a": "jeden\n  dva\ntri\n"])
        #expect(try YamlParser.parse("a: >\n  jeden\n    dva\n  tri\n") == ["a": "jeden\n  dva\ntri\n"])
        #expect(try YamlParser.parse("a: >\n  jeden\n    dva\n") == ["a": "jeden\n  dva\n"])
        // Two more-indented lines in a row: the line break between them is literal too.
        #expect(try YamlParser.parse("a: >\n  jeden\n    dva\n    tri\n  ctyri\n")
                == ["a": "jeden\n  dva\n  tri\nctyri\n"])
        // An empty line before a more-indented one: the line breaks do not merge.
        #expect(try YamlParser.parse("a: >\n  jeden\n\n    dva\n  tri\n")
                == ["a": "jeden\n\n  dva\ntri\n"])
        // An empty line after a more-indented one: neither.
        #expect(try YamlParser.parse("a: >\n  jeden\n    dva\n\n  tri\n")
                == ["a": "jeden\n  dva\n\ntri\n"])
    }

    /// A whitespace-only line: when it is **longer** than the block indentation, it is content
    /// (and behaves like a more-indented line); when shorter, it is an empty line.
    @Test func whitespaceOnlyLines() throws {
        #expect(try YamlParser.parse("a: |\n  x\n    \n  y\n") == ["a": "x\n  \ny\n"])
        #expect(try YamlParser.parse("a: >\n  x\n    \n  y\n") == ["a": "x\n  \ny\n"])
        #expect(try YamlParser.parse("a: |\n  x\n \n  y\n") == ["a": "x\n\ny\n"])
        #expect(try YamlParser.parse("a: |\n  text\n    \nb: 2\n") == ["a": "text\n  \n", "b": 2])
        #expect(try YamlParser.parse("a: |+\n  text\n    \nb: 2\n") == ["a": "text\n  \n", "b": 2])
        #expect(try YamlParser.parse("a: |+\n  x\n    \n\nb: 2\n") == ["a": "x\n  \n\n", "b": 2])
    }

    /// Trailing spaces on a content line are content — even for a folded scalar,
    /// where a folding space is added to them (measured: "x   y").
    @Test func trailingSpacesOnContentLinesAreContent() throws {
        #expect(try YamlParser.parse("a: |\n  x  \n  y\n") == ["a": "x  \ny\n"])
        #expect(try YamlParser.parse("a: |-\n  x  \n") == ["a": "x  "])
        #expect(try YamlParser.parse("a: >\n  x  \n  y\n") == ["a": "x   y\n"])
    }

    // MARK: - explicit indentation (`|2`)

    /// The number after `|` gives the content indentation **relative to the enclosing collection**, not
    /// absolute: `a: |2` at level zero = 2, `c: |2` under an indentation of 4 = 6.
    @Test func explicitIndentationIndicator() throws {
        #expect(try YamlParser.parse("a: |2\n   text\n    dalsi\n") == ["a": " text\n  dalsi\n"])
        #expect(try YamlParser.parse("a: |2\n  text\n  dalsi\n") == ["a": "text\ndalsi\n"])
        #expect(try YamlParser.parse("a:\n  b: |2\n     x\n      y\n") == ["a": ["b": " x\n  y\n"]])
        #expect(try YamlParser.parse("a:\n  b: |1\n   x\n") == ["a": ["b": "x\n"]])
        #expect(try YamlParser.parse("a:\n  b:\n    c: |2\n       x\n") == ["a": ["b": ["c": " x\n"]]])
        // Indicators in both orders.
        #expect(try YamlParser.parse("a: |2-\n   text\n\n") == ["a": " text"])
        #expect(try YamlParser.parse("a: |-2\n   text\n\n") == ["a": " text"])
        #expect(try YamlParser.parse("a: >2-\n   x\n") == ["a": " x"])
        #expect(try YamlParser.parse("a: |\n\n   text\n") == ["a": "\ntext\n"])
        #expect(try YamlParser.parse("a: |2\n\n   text\n") == ["a": "\n text\n"])
    }

    /// Automatic indentation detection takes the **maximum** of the leading whitespace-only
    /// lines and the first content one. A whitespace line longer than the content therefore empties
    /// the block and Java then rejects the content — we copy that.
    @Test func automaticIndentationDetection() throws {
        #expect(try YamlParser.parse("a: |\n x\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("a:\n  b: |\n   x\n    y\n") == ["a": ["b": "x\n y\n"]])
        #expect(try YamlParser.parse("a: |\n \n   x\n") == ["a": "\nx\n"])
        expectError("a: |\n    \n  x\n", .syntax, line: 3, column: 1)
        expectError("a: |\n\n    \n  x\n", .syntax, line: 4, column: 1)
    }

    // MARK: - a block in a sequence, at the root, on the next line

    @Test func blockScalarInSequencesAndAtRoot() throws {
        #expect(try YamlParser.parse("- |\n  x\n- 2\n") == ["x\n", 2])
        #expect(try YamlParser.parse("a:\n  - |\n    x\n  - 2\n") == ["a": ["x\n", 2]])
        #expect(try YamlParser.parse("a:\n- |\n  x\n") == ["a": ["x\n"]])
        #expect(try YamlParser.parse("- - |\n    x\n") == [["x\n"]])
        #expect(try YamlParser.parse("|\n  x\n") == .string("x\n"))
        #expect(try YamlParser.parse(">\n  x\n") == .string("x\n"))
        // The indicator on its own line under the key.
        #expect(try YamlParser.parse("a:\n  |\n  x\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("a:\n  |\n    x\n") == ["a": "x\n"])
        // Explicit indentation in a sequence follows the column of the dash.
        #expect(try YamlParser.parse("- |2\n  x\n") == ["x\n"])
        #expect(try YamlParser.parse("- |1\n x\n") == ["x\n"])
        #expect(try YamlParser.parse("- |2\n   x\n") == [" x\n"])
        #expect(try YamlParser.parse("a:\n  - |2\n    x\n") == ["a": ["x\n"]])
        // At the root the content may be indented any amount, but not to zero (the block is then
        // empty and Jackson silently drops the rest of the document).
        #expect(try YamlParser.parse("|\nx\n") == .string(""))
    }

    // MARK: - typing and block content

    /// A block scalar is **always text**, even if the content looks like a number,
    /// a boolean or `null`.
    @Test func blockScalarIsAlwaysText() throws {
        #expect(try YamlParser.parse("a: |\n  48\n") == ["a": "48\n"])
        #expect(try YamlParser.parse("a: |-\n  48\n") == ["a": "48"])
        #expect(try YamlParser.parse("a: >-\n  48\n") == ["a": "48"])
        #expect(try YamlParser.parse("a: |-\n  yes\n") == ["a": "yes"])
        #expect(try YamlParser.parse("a: |-\n  null\n") == ["a": "null"])
    }

    /// Inside a block there are no indicators or comments — `#`, `-` and `:` are content.
    @Test func indicatorsInsideBlockAreContent() throws {
        #expect(try YamlParser.parse("a: |\n  x\n  # neni komentar\n  y\n")
                == ["a": "x\n# neni komentar\ny\n"])
        #expect(try YamlParser.parse("a: |\n  x\n  # porad blok\nb: 2\n")
                == ["a": "x\n# porad blok\n", "b": 2])
        #expect(try YamlParser.parse("a: |\n  x\n# komentar\nb: 2\n") == ["a": "x\n", "b": 2])
        #expect(try YamlParser.parse("a: |\n  - x\n") == ["a": "- x\n"])
        #expect(try YamlParser.parse("a: >\n  - x\n") == ["a": "- x\n"])
        #expect(try YamlParser.parse("a: |\n  b: 1\n") == ["a": "b: 1\n"])
        #expect(try YamlParser.parse("a: |\n  Příliš žluťoučký\n") == ["a": "Příliš žluťoučký\n"])
    }

    /// A tab **after** the block indentation is content; a tab **in** the indentation ends
    /// the block and Java rejects it ("cannot start any token") — both measured.
    @Test func tabsInsideBlockScalars() throws {
        #expect(try YamlParser.parse("a: |\n  x\ty\n") == ["a": "x\ty\n"])
        #expect(try YamlParser.parse("a: |\n  \tx\n") == ["a": "\tx\n"])
        #expect(try YamlParser.parse("a: |\n  x\n   \ty\n") == ["a": "x\n \ty\n"])
        #expect(try YamlParser.parse("a: |\n  x\n  \ty\n") == ["a": "x\n\ty\n"])
        #expect(try YamlParser.parse("a: >\n  x\n  \ty\n") == ["a": "x\n\ty\n"])
        expectError("a: |\n\tx\n", .syntax, line: 2, column: 1)
        expectError("a: |\n  x\n\t\n  y\n", .syntax, line: 3, column: 1)
        expectError("a: |\n  x\n \ty\n", .syntax, line: 3, column: 1)
        expectError("a: |4\n    x\n   \ty\n", .syntax, line: 3, column: 1)
    }

    /// A tab in indentation outside a block scalar must remain an error even after
    /// its reporting was deferred (it used to be reported by the line splitting).
    @Test func tabsOutsideBlockScalarsStillFail() throws {
        expectError("a: x\n\t\n  y\n", .syntax, line: 1, column: 5)
        expectError("a: x\n\t\nb: 2\n", .syntax, line: 1, column: 5)
        expectError("a: [1,\n\t\n2]\n", .syntax, line: 1, column: 6)
        expectError("a: 1\n  \t\nb: 2\n", .syntax, line: 1, column: 5)
        expectError("a: 1\n\t# c\n", .syntax, line: 1, column: 5)
        expectError("a:\n\tb: 1\n", .syntax, line: 1, column: 2)
    }

    /// A comment may follow the block header, but must have a space before it.
    @Test func commentAfterBlockHeader() throws {
        #expect(try YamlParser.parse("a: | # pozn\n  text\n") == ["a": "text\n"])
        #expect(try YamlParser.parse("a: > # pozn\n  text\n") == ["a": "text\n"])
        #expect(try YamlParser.parse("a: |- # c\n  x\n") == ["a": "x"])
        #expect(try YamlParser.parse("a: |2 # c\n   x\n") == ["a": " x\n"])
        #expect(try YamlParser.parse("a:    |\n  x\n") == ["a": "x\n"])
        expectError("a: >-# c\n  x\n", .syntax, line: 1, column: 2)
    }

    // MARK: - bad block header

    /// What Java rejects on the header we reject too — and at the same positions
    /// (column = SnakeYAML's "problem mark").
    @Test func malformedBlockHeaderThrows() {
        expectError("a: | text\n  x\n", .syntax, line: 1, column: 2)
        expectError("a: |-+\n  x\n", .syntax, line: 1, column: 2)
        expectError("a: |+-\n  x\n", .syntax, line: 1, column: 2)
        expectError("a: |0\n  text\n", .syntax, line: 1, column: 2)
        expectError("a: |00\n  x\n", .syntax, line: 1, column: 2)
        expectError("a: |10\n          text\n", .syntax, line: 1, column: 2)
        expectError("a: |\t\n  x\n", .syntax, line: 1, column: 2)
        expectError("a: | \t\n  x\n", .syntax, line: 1, column: 2)
        // `|` and `>` in the role of a key: Java expects indicators after them, not a colon.
        expectError("|: 1\n", .syntax, line: 1, column: 1)
        expectError(">: 1\n", .syntax, line: 1, column: 1)
        // In flow notation `|` is a character that must not start a token — `.syntax`.
        expectError("a: [|]\n", .syntax, line: 1, column: 5)
        expectError("a: {b: |}\n", .syntax, line: 1, column: 6)
    }

    /// Content that does not fit the block (indented too little) is rejected by Java as
    /// a syntax error on that content.
    @Test func contentBelowBlockIndentThrows() {
        expectError("a: |4\n  text\n", .syntax, line: 2, column: 1)
        expectError("a: |9\n  x\n", .syntax, line: 2, column: 1)
        expectError("a:\n  b: |2\n   x\n", .syntax, line: 3, column: 1)
        expectError("a: >\n   jeden\n  dva\n", .syntax, line: 3, column: 1)
        expectError("a: |\n   x\n  y\nb: 2\n", .syntax, line: 3, column: 1)
        expectError("a: |\n    x\n  y\nb: 2\n", .syntax, line: 3, column: 1)
        expectError("a: |\nx\n", .syntax, line: 2, column: 1)
        expectError("a:\n  b: |\n  x\n", .syntax, line: 3, column: 1)
    }

    // MARK: - a block and block/document boundaries

    @Test func blockScalarEndsAtLowerIndentOrDocumentBoundary() throws {
        #expect(try YamlParser.parse("a:\n  b: |\n    x\n  c: 2\n") == ["a": ["b": "x\n", "c": 2]])
        #expect(try YamlParser.parse("a:\n  b: |\n    x\n  c: 2\nd: 3\n")
                == ["a": ["b": "x\n", "c": 2], "d": 3])
        #expect(try YamlParser.parse("a: |\n  x\nb: 2\n") == ["a": "x\n", "b": 2])
        #expect(try YamlParser.parse("a: |\n  x\n---\nb: 2\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("a: |\r\n  x\r\n  y\r\n") == ["a": "x\ny\n"])
    }

    // MARK: - type tags

    /// `!!str` keeps the **original spelling** — that is the scenario tags are
    /// worth the effort for: `!!str 001` for a serial number in the exchange.
    @Test func stringTagPreservesLeadingZeros() throws {
        #expect(try YamlParser.parse("a: !!str 001\n") == ["a": "001"])
        #expect(try YamlParser.parse("a:\n  b: !!str 001\n") == ["a": ["b": "001"]])
        #expect(try YamlParser.parse("a: !!str   001\n") == ["a": "001"])
        #expect(try YamlParser.parse("a: !!str 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!str 1e3\n") == ["a": "1e3"])
        #expect(try YamlParser.parse("a: !!str 2.50\n") == ["a": "2.50"])
        #expect(try YamlParser.parse("a: !!str yes\n") == ["a": "yes"])
        #expect(try YamlParser.parse("a: !!str null\n") == ["a": "null"])
        #expect(try YamlParser.parse("a: !!str ~\n") == ["a": "~"])
        #expect(try YamlParser.parse("a: !!str 160m\n") == ["a": "160m"])
        #expect(try YamlParser.parse("a: !!str \"x\"\n") == ["a": "x"])
        #expect(try YamlParser.parse("a: !!str 'x'\n") == ["a": "x"])
        #expect(try YamlParser.parse("a: !!str x y\n") == ["a": "x y"])
        #expect(try YamlParser.parse("a: !!str x\n  y\n") == ["a": "x y"])
        #expect(try YamlParser.parse("a: !!str 1#c\n") == ["a": "1#c"])
        #expect(try YamlParser.parse("a: !!str 1 # c\n") == ["a": "1"])
    }

    /// `!!int`, `!!bool` and `!!null` retype; what does not convert stays text.
    @Test func intBoolAndNullTags() throws {
        #expect(try YamlParser.parse("a: !!int \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!int 007\n") == ["a": .int(7, raw: "007")])
        #expect(try YamlParser.parse("a: !!int 010\n") == ["a": 8])
        #expect(try YamlParser.parse("a: !!int 0x10\n") == ["a": 16])
        #expect(try YamlParser.parse("a: !!int 0X10\n") == ["a": 16])
        #expect(try YamlParser.parse("a: !!int 0b11\n") == ["a": 3])
        #expect(try YamlParser.parse("a: !!int 1_000\n") == ["a": 1000])
        #expect(try YamlParser.parse("a: !!int -7\n") == ["a": -7])
        #expect(try YamlParser.parse("a: !!int +7\n") == ["a": 7])
        // What does not convert to an integer is text (not an error).
        #expect(try YamlParser.parse("a: !!int abc\n") == ["a": "abc"])
        #expect(try YamlParser.parse("a: !!int 1.5\n") == ["a": "1.5"])
        #expect(try YamlParser.parse("a: !!int 1:30\n") == ["a": "1:30"])
        #expect(try YamlParser.parse("a: !!int \" 7 \"\n") == ["a": " 7 "])
        // `!!bool` takes a wider set of words than implicit typing — including `y`/`n`
        // and mixed case (measured: `a: y` is the text "y", but `!!bool y` is true).
        #expect(try YamlParser.parse("a: !!bool yes\n") == ["a": .bool(true, raw: "yes")])
        #expect(try YamlParser.parse("a: !!bool y\n") == ["a": .bool(true, raw: "y")])
        #expect(try YamlParser.parse("a: !!bool N\n") == ["a": .bool(false, raw: "N")])
        #expect(try YamlParser.parse("a: !!bool off\n") == ["a": .bool(false, raw: "off")])
        #expect(try YamlParser.parse("a: !!bool yEs\n") == ["a": .bool(true, raw: "yEs")])
        #expect(try YamlParser.parse("a: !!bool True\n") == ["a": .bool(true, raw: "True")])
        #expect(try YamlParser.parse("a: !!bool 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!bool abc\n") == ["a": "abc"])
        // `!!null` discards the content.
        #expect(try YamlParser.parse("a: !!null x\n") == ["a": .null])
        #expect(try YamlParser.parse("a: !!null yes\n") == ["a": .null])
    }

    /// Unlike `!!int`, `!!float` **rejects a malformed spelling** — just like
    /// Java ("Malformed numeric value").
    @Test func floatTag() throws {
        #expect(try YamlParser.parse("a: !!float 1\n") == ["a": .double(1.0, raw: "1")])
        #expect(try YamlParser.parse("a: !!float \"1.5\"\n") == ["a": 1.5])
        #expect(try YamlParser.parse("a: !!float 1e3\n") == ["a": .double(1000.0, raw: "1e3")])
        #expect(try YamlParser.parse("a: !!float 1.\n") == ["a": .double(1.0, raw: "1.")])
        #expect(try YamlParser.parse("a: !!float 2_5.5\n") == ["a": .double(25.5, raw: "2_5.5")])
        expectError("a: !!float abc\n", .syntax, line: 1, column: 15)
        expectError("a: !!float .inf\n", .syntax, line: 1, column: 16)
    }

    /// A tag that Java does not know is **neither dropped nor rejected** — it makes the value
    /// text. This is the point where the assignment diverged from Java (the assignment wanted a loud
    /// error); Java won, otherwise the Swift application would reject files that the
    /// Java one loads.
    @Test func unknownAndLocalTagsYieldStrings() throws {
        #expect(try YamlParser.parse("a: !!foo 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !x 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !x \"7\"\n") == ["a": "7"])
        #expect(try YamlParser.parse("a: !moje 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !x/y 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !x[1] 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!str%20x 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!binary aGk=\n") == ["a": "aGk="])
        #expect(try YamlParser.parse("a: !!timestamp 2020-01-01\n") == ["a": "2020-01-01"])
        #expect(try YamlParser.parse("a: !!!\n") == ["a": ""])
        // The verbatim form of a tag.
        #expect(try YamlParser.parse("a: !<tag:yaml.org,2002:str> 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !<tag:yaml.org,2002:int> \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !<tag:yaml.org,2002:bool> yes\n")
                == ["a": .bool(true, raw: "yes")])
        #expect(try YamlParser.parse("a: !<tag:example.com,2000:x> 1\n") == ["a": "1"])
        // Jackson cuts the name after the prefix at the first comma, so `!!int,x` is an int.
        #expect(try YamlParser.parse("a: !!int,x \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!int,foo 7\n") == ["a": 7])
        // The `%TAG` directive is dropped and a tag from it is unknown → text.
        #expect(try YamlParser.parse("%TAG !e! tag:example.com,2000:\n---\na: !e!foo 1\n")
                == ["a": "1"])
    }

    /// Percent escapes in the tag URI are **decoded** (`ScannerImpl.scanTagUri`),
    /// so `!!%69%6e%74 "7"` is `int`, not text. It is a silent difference of **type** —
    /// it would not show on `!!%73%74%72 001`, "001" comes out the same either way.
    @Test func percentEscapesInTagsAreDecoded() throws {
        #expect(try YamlParser.parse("a: !!%69%6e%74 \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!%69%6E%74 \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !<tag:yaml.org,2002:%69%6e%74> \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !<%74ag:yaml.org,2002:int> \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!in%74 \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!%69nt \"7\"\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!%66%6c%6f%61%74 7\n") == ["a": .double(7, raw: "7")])
        #expect(try YamlParser.parse("a: !!%62%6f%6f%6c yes\n") == ["a": .bool(true, raw: "yes")])
        #expect(try YamlParser.parse("a: !!%6e%75%6c%6c x\n") == ["a": .null])
        #expect(try YamlParser.parse("a: !!%73%74%72 001\n") == ["a": "001"])
        // The name is cut at the comma after decoding the same as without escapes.
        #expect(try YamlParser.parse("a: !!int%2Cx \"7\"\n") == ["a": 7])
        // Only the URI part is decoded, not the "handle": `!%21%21int` is `!` + `!!int`,
        // i.e. a local tag → text (measured).
        #expect(try YamlParser.parse("a: !%21%21int \"7\"\n") == ["a": "7"])
        // A contiguous run of escapes is one UTF-8 sequence: `%C4%8D` is "č".
        #expect(try YamlParser.parse("a: !!%C4%8D 1\n") == ["a": "1"])
        // `%25` is "%", so after decoding it is no known type.
        #expect(try YamlParser.parse("a: !!%25 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!%2521 1\n") == ["a": "1"])
        #expect(try YamlParser.parse("a: !!int%00 \"7\"\n") == ["a": "7"])
        // Java reads the pair with `Integer.parseInt(…, 16)`, so it accepts a sign too.
        #expect(try YamlParser.parse("a: !!%+1 1\n") == ["a": "1"])
    }

    /// A malformed escape in a tag is **rejected** by Java — so we reject it too, so that
    /// it does not silently become text. The column points to the start of the tag,
    /// the same as a tag in a SnakeYAML error.
    @Test func brokenPercentEscapeInTagThrows() {
        expectError("a: !!%zz 1\n", .syntax, line: 1, column: 2)
        expectError("a: !!% 1\n", .syntax, line: 1, column: 2)
        expectError("a: !!%2 1\n", .syntax, line: 1, column: 2)
        expectError("a: !!%C4 1\n", .syntax, line: 1, column: 2)
        expectError("a: !!%-1 1\n", .syntax, line: 1, column: 2)
        expectError("  a: !!%zz 1\n", .syntax, line: 1, column: 4)
        expectError("a: 1\nb: !!%zz 1\n", .syntax, line: 2, column: 2)
    }

    /// A lone `!` (non-specific tag) behaves **as if there were no tag**: it is typed
    /// implicitly, an empty value is `null`.
    @Test func nonSpecificTagBehavesLikeNoTag() throws {
        #expect(try YamlParser.parse("a: ! 1\n") == ["a": 1])
        #expect(try YamlParser.parse("a: !\n") == ["a": .null])
        #expect(try YamlParser.parse("a: ! yes\n") == ["a": .bool(true, raw: "yes")])
        #expect(try YamlParser.parse("! a: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("a: !\n  b: 1\n") == ["a": ["b": 1]])
    }

    /// An empty value with **any** tag except `!` is an empty text, not
    /// `null` — even for `!!int` and `!!null` (measured, it is unexpected).
    @Test func emptyValueWithExplicitTagIsEmptyString() throws {
        #expect(try YamlParser.parse("a: !!str\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!int\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!bool\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!float\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!null\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!foo\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !x\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!str1\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!str \"\"\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!int \"\"\n") == ["a": ""])
        #expect(try YamlParser.parse("a: !!str\nb: 2\n") == ["a": "", "b": 2])
        #expect(try YamlParser.parse("- !!str\n- 2\n") == ["", 2])
        // Without a tag an empty value is still `null`.
        #expect(try YamlParser.parse("a:\n") == ["a": .null])
    }

    /// A tag on a collection is **dropped** — it does not retype even a map to a sequence.
    @Test func tagsOnCollectionsAreIgnored() throws {
        #expect(try YamlParser.parse("a: !!seq [1,2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: !!map\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a: !!map [1,2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: !!seq\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a: !!str\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a: !!str [1,2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: !!int [1]\n") == ["a": [1]])
        #expect(try YamlParser.parse("a: !!seq\n  - 1\n") == ["a": [1]])
        #expect(try YamlParser.parse("a: !!seq\n- 1\n") == ["a": [1]])
        #expect(try YamlParser.parse("- !!seq [1]\n") == [[1]])
        #expect(try YamlParser.parse("!!map\na: 1\n") == ["a": 1])
    }

    /// A tag in a key is dropped (the key is still the text of the value after it).
    @Test func tagsOnKeysAreIgnored() throws {
        #expect(try YamlParser.parse("!!str a: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("!!str a: 1\nb: 2\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("!!int 1: x\ny: 2\n") == ["1": "x", "y": 2])
        #expect(try YamlParser.parse("a:\n  !!str b: 1\n") == ["a": ["b": 1]])
        // A colon is a valid tag character, so `!!str:` is the whole tag and `1`
        // is the value — Java returns a scalar here, not a map (measured).
        #expect(try YamlParser.parse("!!str: 1\n") == .string("1"))
        #expect(try YamlParser.parse("b: !!str: 1\n") == ["b": "1"])
    }

    /// A tag on a block scalar: `!!str`/unknown change nothing, `!!int`/`!!bool`
    /// try to retype the chomped content and `!!null` always wins.
    @Test func tagsOnBlockScalars() throws {
        #expect(try YamlParser.parse("a: !!str |\n  x\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("a: !!str >\n  x\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("a: !!foo |\n  x\n") == ["a": "x\n"])
        #expect(try YamlParser.parse("a: !!str |2\n   x\n") == ["a": " x\n"])
        #expect(try YamlParser.parse("- !!str |\n    x\n") == ["x\n"])
        // A line break at the end prevents conversion to a number, `|-` lets it through.
        #expect(try YamlParser.parse("a: !!int |\n  7\n") == ["a": "7\n"])
        #expect(try YamlParser.parse("a: !!int |-\n  7\n") == ["a": 7])
        #expect(try YamlParser.parse("a: !!bool |-\n  yes\n") == ["a": .bool(true, raw: "yes")])
        #expect(try YamlParser.parse("a: !!float |-\n  1\n") == ["a": .double(1.0, raw: "1")])
        #expect(try YamlParser.parse("a: !!null |\n  x\n") == ["a": .null])
    }

    /// Tags in flow notation.
    @Test func tagsInsideFlow() throws {
        #expect(try YamlParser.parse("a: [!!str 1, 2]\n") == ["a": ["1", 2]])
        #expect(try YamlParser.parse("a: {b: !!str 1}\n") == ["a": ["b": "1"]])
        #expect(try YamlParser.parse("a: [!!foo 1]\n") == ["a": ["1"]])
        #expect(try YamlParser.parse("a: [!!int \"7\"]\n") == ["a": [7]])
        #expect(try YamlParser.parse("a: [! 1]\n") == ["a": [1]])
        #expect(try YamlParser.parse("a: [!!seq [1]]\n") == ["a": [[1]]])
    }

    /// A bad tag is an error — and at the same positions as in Java.
    @Test func malformedTagsThrow() {
        // After a tag there must be a space or end of line.
        expectError("a: !!str\t1\n", .syntax, line: 1, column: 2)
        expectError("a: !!str#x 1\n", .syntax, line: 1, column: 2)
        // A lone `!!` without a name.
        expectError("a: !! 1\n", .syntax, line: 1, column: 2)
        // Two tags in a row.
        expectError("a: !!str !!int 1\n", .syntax, line: 1, column: 9)
        // A colon in a value after a tag is still an error.
        expectError("a: !!str b: 1\n", .syntax, line: 1, column: 11)
        // An anchor next to a tag is **read** (in both orders) —
        // the tables are in `YamlAnchorTests`. Two anchors after a tag are an error.
        expectError("a: !!str &x &y 1\n", .syntax, line: 1, column: 12)
    }

    // MARK: - cosmetic findings

    /// The column for **rejected** content after `--- ` must be computed, not reported
    /// as a fixed 5. The reader reads a scalar and a flow collection, because Java
    /// does not mangle them — see `YamlUnsupportedTests.leadingMarkerContentFollowsJava`.
    /// `--- a: 1` is read as Java does, "a" (Java does not read
    /// the rest after the root); an alias stayed rejected.
    @Test func leadingMarkerContentColumnIsComputed() throws {
        #expect(try YamlParser.parse("--- a: 1\n") == .string("a"))
        #expect(try YamlParser.parse("---   a: 1\n") == .string("a"))
        expectError("---   *x\n", .unsupported, line: 1, column: 7)
        expectError("---   - 1\n", .syntax, line: 1, column: 4)
        #expect(try YamlParser.parse("---   1\n") == .int(1))
        #expect(try YamlParser.parse("--- [1,2]\n") == [1, 2])
    }

    /// A tab after the opening `---` is reported by Java as a **syntax** error at
    /// the tab, not as an unsupported construct.
    @Test func tabAfterLeadingMarkerIsSyntaxError() {
        expectError("--- \ta: 1\n", .syntax, line: 1, column: 4)
        expectError("---\ta: 1\n", .syntax, line: 1, column: 4)
    }

    /// A tab after a **later** marker is not an error — the document just ends there
    /// and Jackson returns the first one (measured).
    @Test func tabAfterLaterMarkerJustEndsTheDocument() throws {
        #expect(try YamlParser.parse("a: 1\n---\tb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n--- \tb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n...\tb\n") == ["a": 1])
    }
}
