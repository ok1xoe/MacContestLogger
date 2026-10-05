import Foundation
import Testing
@testable import MCLCore

/// Flow notation (`{}`, `[]`) and comments. All expectations are **measured on a
/// running Java** (`YamlObjectMapper.create().readTree`).
@Suite struct YamlFlowTests {

    // MARK: - flow map and sequence

    @Test func flowMapping() throws {
        #expect(try YamlParser.parse("period: { durationHours: 48 }\n")
            == ["period": ["durationHours": 48]])
        #expect(try YamlParser.parse("a: {x: 1, y: dva}\n") == ["a": ["x": 1, "y": "dva"]])
    }

    @Test func flowSequence() throws {
        #expect(try YamlParser.parse("bands: [160m, 80m, 40m]\n")
            == ["bands": ["160m", "80m", "40m"]])
    }

    /// `{ id: wve, when: { dxccIn: [US, CA] } }` — flow in flow, as our
    /// definitions have it.
    @Test func flowNestedInFlow() throws {
        #expect(try YamlParser.parse("x: { id: wve, when: { dxccIn: [US, CA] } }\n")
            == ["x": ["id": "wve", "when": ["dxccIn": ["US", "CA"]]]])
        #expect(try YamlParser.parse("a: [[1,[2]],{b: {c: [3]}}]\n")
            == ["a": [[1, [2]], ["b": ["c": [3]]]]])
        #expect(try YamlParser.parse("a: {x: [1,2], y: []}\n") == ["a": ["x": [1, 2], "y": []]])
    }

    @Test func flowInsideBlockSequence() throws {
        #expect(try YamlParser.parse("s:\n  - { id: wve }\n  - { id: dx }\n")
            == ["s": [["id": "wve"], ["id": "dx"]]])
        #expect(try YamlParser.parse("s:\n  - [1, 2]\n") == ["s": [[1, 2]]])
        #expect(try YamlParser.parse("- {a: 1}\n- {b: 2}\n") == [["a": 1], ["b": 2]])
        #expect(try YamlParser.parse("a:\n  - - {x: 1}\n") == ["a": [[["x": 1]]]])
        #expect(try YamlParser.parse("s:\n  - a: 1\n    b: [2,3]\n")
            == ["s": [["a": 1, "b": [2, 3]]]])
    }

    @Test func emptyFlowCollections() throws {
        #expect(try YamlParser.parse("a: {}\n") == ["a": .mapping(YamlMapping())])
        #expect(try YamlParser.parse("a: []\n") == ["a": []])
        #expect(try YamlParser.parse("a: {  }\n") == ["a": .mapping(YamlMapping())])
        #expect(try YamlParser.parse("a: [  ]\n") == ["a": []])
        #expect(try YamlParser.parse("a: [[], {}, [{}]]\n")
            == ["a": [[], .mapping(YamlMapping()), [.mapping(YamlMapping())]]])
    }

    @Test func flowAtDocumentRoot() throws {
        #expect(try YamlParser.parse("{a: 1, b: 2}\n") == ["a": 1, "b": 2])
        #expect(try YamlParser.parse("[1, 2]\n") == [1, 2])
        #expect(try YamlParser.parse("[]\n") == [])
        #expect(try YamlParser.parse("{}\n") == .mapping(YamlMapping()))
    }

    /// A flow may be the value of a key on the next line and deep inside a block.
    @Test func flowAsValueOnFollowingLine() throws {
        #expect(try YamlParser.parse("a:\n  [1, 2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a:\n  {x: 1}\n") == ["a": ["x": 1]])
        #expect(try YamlParser.parse("a:\n  b: {c: [1, {d: 2}]}\n")
            == ["a": ["b": ["c": [1, ["d": 2]]]]])
    }

    // MARK: - trailing comma and empty items

    @Test func trailingComma() throws {
        #expect(try YamlParser.parse("a: [1, 2,]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: {x: 1,}\n") == ["a": ["x": 1]])
        #expect(try YamlParser.parse("a: [ {x: 1,}, ]\n") == ["a": [["x": 1]]])
        #expect(try YamlParser.parse("a: [a, ]\n") == ["a": ["a"]])
    }

    /// An empty item is an error in Java, not `null`.
    @Test func emptyEntryThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1,,2]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [,1]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [,]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: 1,,y: 2}\n") }
    }

    // MARK: - typing and original spelling in a flow

    /// Scalars inside a flow are typed by the **same rules** as outside it:
    /// `160m` text, `48` number, `yes` boolean, `007` octal.
    @Test func flowScalarsUseTheSameTyping() throws {
        let v = try YamlParser.parse("a: [160m, 48, yes, null, 007, 1e3, 3.0, \"48\"]\n")
        #expect(v["a"][0] == .string("160m"))
        #expect(v["a"][1] == .int(48))
        #expect(v["a"][2] == .bool(true))
        #expect(v["a"][3] == .null)
        #expect(v["a"][4] == .int(7))
        #expect(v["a"][5] == .double(1000.0))
        #expect(v["a"][6] == .double(3.0))
        #expect(v["a"][7] == .string("48"))
        #expect(try YamlParser.parse("a: [~, null, NULL, Null]\n") == ["a": [.null, .null, .null, .null]])
        #expect(try YamlParser.parse("a: ['', \"\"]\n") == ["a": ["", ""]])
    }

    /// And just like outside a flow it keeps the **original spelling** for a `String` field
    /// (Java: `[1e3]` into `List<String>` gives "1e3").
    @Test func flowScalarKeepsOriginalSpelling() throws {
        let v = try YamlParser.parse("a: [1e3, 007, +5, yes, 2.50, 0x10, \"48\", 160m]\n")
        #expect(v.value("a", default: [String]()) == ["1e3", "007", "+5", "yes", "2.50", "0x10", "48", "160m"])
    }

    // MARK: - flow map keys

    @Test func flowMappingKeys() throws {
        // A key is always text, even if it looks like a number or a bool.
        #expect(try YamlParser.parse("a: {48: x, true: y}\n") == ["a": ["48": "x", "true": "y"]])
        #expect(try YamlParser.parse("a: {\"x y\": 1}\n") == ["a": ["x y": 1]])
        #expect(try YamlParser.parse("a: {'it''s': 1}\n") == ["a": ["it's": 1]])
        #expect(try YamlParser.parse("a: {\"a\\tb\": 1}\n") == ["a": ["a\tb": 1]])
        // A colon right after a quoted key **is** a separator (always in a flow).
        #expect(try YamlParser.parse("a: {\"x\":1}\n") == ["a": ["x": 1]])
        // A colon inside a plain scalar is not a separator: the key is "x:1".
        #expect(try YamlParser.parse("a: {x:1}\n") == ["a": ["x:1": .null]])
        #expect(try YamlParser.parse("a: {a:b: 1}\n") == ["a": ["a:b": 1]])
        #expect(try YamlParser.parse("a: {a:b}\n") == ["a": ["a:b": .null]])
    }

    @Test func flowMappingMissingValueIsNull() throws {
        #expect(try YamlParser.parse("a: {x}\n") == ["a": ["x": .null]])
        #expect(try YamlParser.parse("a: {x, y}\n") == ["a": ["x": .null, "y": .null]])
        #expect(try YamlParser.parse("a: {x: , y: 1}\n") == ["a": ["x": .null, "y": 1]])
        #expect(try YamlParser.parse("a: {x: ~, y: null}\n") == ["a": ["x": .null, "y": .null]])
    }

    /// `[x: y]` is a single-pair map — YAML allows it and Java reads it that way.
    @Test func singlePairMappingInFlowSequence() throws {
        #expect(try YamlParser.parse("a: [x: y]\n") == ["a": [["x": "y"]]])
        #expect(try YamlParser.parse("a: [x: y, z]\n") == ["a": [["x": "y"], "z"]])
        #expect(try YamlParser.parse("a: [x:]\n") == ["a": [["x": .null]]])
        #expect(try YamlParser.parse("a: [x:,y]\n") == ["a": [["x": .null], "y"]])
    }

    /// A duplicate key in a flow map behaves as in a block one: the last
    /// value wins, the key keeps its original position.
    @Test func duplicateKeyInFlowMapping() throws {
        #expect(try YamlParser.parse("a: {k: 1, k: 2}\n") == ["a": ["k": 2]])
        let v = try YamlParser.parse("a: {x: 1, y: 2, x: 3}\n")
        #expect(v["a"].keys == ["x", "y"])
        #expect(v["a"]["x"] == .int(3))
    }

    // MARK: - plain scalar in a flow

    @Test func plainScalarInFlow() throws {
        #expect(try YamlParser.parse("a: [x y, z]\n") == ["a": ["x y", "z"]])
        #expect(try YamlParser.parse("a: [x  ,  y ]\n") == ["a": ["x", "y"]])
        #expect(try YamlParser.parse("a: [x:y]\n") == ["a": ["x:y"]])
        #expect(try YamlParser.parse("a: [12:30]\n") == ["a": ["12:30"]])
        #expect(try YamlParser.parse("a: [x'y]\n") == ["a": ["x'y"]])
        #expect(try YamlParser.parse("a: [-x]\n") == ["a": ["-x"]])
        #expect(try YamlParser.parse("a: [x-y]\n") == ["a": ["x-y"]])
        #expect(try YamlParser.parse("a: ['x' , \"y\"]\n") == ["a": ["x", "y"]])
        // A tab inside a plain scalar is valid text, a trailing one is dropped.
        #expect(try YamlParser.parse("a: [a\tb]\n") == ["a": ["a\tb"]])
        #expect(try YamlParser.parse("a: [1\t,2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: [1\t]\n") == ["a": [1]])
    }

    /// Inside a flow, `{`, `}`, `[`, `]` and `,` also end a plain scalar — so
    /// `[x}y]` is an error, whereas in a block `a: 1]` is simply text.
    @Test func flowIndicatorsEndPlainScalar() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [x}y]\n") }
        #expect(try YamlParser.parse("a: 1]\n") == ["a": "1]"])
        #expect(try YamlParser.parse("a: 1,2\n") == ["a": "1,2"])
        #expect(try YamlParser.parse("a: 1[2]\n") == ["a": "1[2]"])
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: ,x\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: }\n") }
    }

    /// A dash with a space is a block-sequence indicator in a flow → error.
    @Test func blockSequenceInsideFlowThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [- y]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [\n - 1\n]\n") }
    }

    /// A second colon after a value is an error (Java: `{x: y: z}`, `[a: b: c]`).
    @Test func secondColonInFlowThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: y: z}\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [a: b: c]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: [1]: 2}\n") }
    }

    /// An empty key in a flow map is an error, not a `null` key.
    @Test func emptyKeyInFlowThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {: 1}\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: 1, : 2}\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [x, : 1]\n") }
    }

    /// A collection as a map key is rejected by Jackson ("Expected a field name").
    @Test func collectionAsFlowKeyThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("{a: 1}: v\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [{b: 1}: 2]\n") }
    }

    // MARK: - flow across several lines

    @Test func flowSpanningLines() throws {
        #expect(try YamlParser.parse("a: [1,\n  2,\n  3]\n") == ["a": [1, 2, 3]])
        #expect(try YamlParser.parse("a: {\n  x: 1,\n  y: 2\n}\n") == ["a": ["x": 1, "y": 2]])
        // Indentation inside a flow does not matter — it may continue even at column 0.
        #expect(try YamlParser.parse("a: [1,\n2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a:\n  b: [1,\n2]\n") == ["a": ["b": [1, 2]]])
        #expect(try YamlParser.parse("a: [\n]\n") == ["a": []])
        #expect(try YamlParser.parse("a: {\n}\n") == ["a": .mapping(YamlMapping())])
        #expect(try YamlParser.parse("a: [1,\n\n  2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: [1,   \n  2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("[1,\n2]\n") == [1, 2])
    }

    /// A line inside a flow that looks like a block key is a single-pair map —
    /// a flow is not governed by indentation (measured: `a: [1,\nb: 2]` → `[1,{"b":2}]`).
    @Test func flowIgnoresBlockStructure() throws {
        #expect(try YamlParser.parse("a: [1,\nb: 2]\n") == ["a": [1, ["b": 2]]])
        #expect(try YamlParser.parse("a: {x: 1,\n  y: 2}\nb: 3\n") == ["a": ["x": 1, "y": 2], "b": 3])
        #expect(try YamlParser.parse("a: [1\n]\nb: 2\n") == ["a": [1], "b": 2])
        #expect(try YamlParser.parse("a: [1]\nb:\n  - 2\n") == ["a": [1], "b": [2]])
        #expect(try YamlParser.parse("s:\n  - { id: a,\n      x: 1 }\n  - { id: b }\n")
            == ["s": [["id": "a", "x": 1], ["id": "b"]]])
        #expect(try YamlParser.parse("a:\n  b: [1,\n  2]\n  c: 3\n") == ["a": ["b": [1, 2], "c": 3]])
    }

    /// Multi-line scalars inside a flow: plain folds, quoted too.
    @Test func multilineScalarsInsideFlow() throws {
        #expect(try YamlParser.parse("a: [x\n  y]\n") == ["a": ["x y"]])
        #expect(try YamlParser.parse("a: [\"x\n  y\"]\n") == ["a": ["x y"]])
        #expect(try YamlParser.parse("a: [x\n  y\n]\n") == ["a": ["x y"]])
        #expect(try YamlParser.parse("a: {k: \"x\n  y\"}\n") == ["a": ["k": "x y"]])
        // An empty line gives a line break, not a space.
        #expect(try YamlParser.parse("a: [x\n\n  y]\n") == ["a": ["x\ny"]])
    }

    /// A flow map key **must not** span onto the next line (Java rejects it),
    /// a value may.
    @Test func flowKeyMustNotSpanLines() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x\n  y: 1}\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [x\n  y: 1]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [\"x\n  y\": 1]\n") }
    }

    // MARK: - unclosed and unpaired brackets

    @Test func unclosedFlowThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1, 2\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: 1\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [{x: 1]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [\"xy]\n") }
    }

    @Test func mismatchedBracketsThrow() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1, 2}\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: 1]\n") }
    }

    @Test func textAfterFlowThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1] x\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: 1} y\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1]: 2\n") }
    }

    /// An error in a flow carries the line and column of the opening bracket.
    @Test func unclosedFlowErrorPosition() throws {
        do {
            _ = try YamlParser.parse("a: [1, 2\n")
            Issue.record("it should have thrown an error")
        } catch let e as YamlError {
            // Java: the end of the last event (scalar `2`), not the bracket.
            #expect(e.kind == .syntax)
            #expect(e.line == 1)
            #expect(e.column == 9)
        }
    }

    // MARK: - comments

    @Test func commentOnItsOwnLine() throws {
        #expect(try YamlParser.parse("# c\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("a:\n  # c\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a:\n    # c\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a:\n  # c\n\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a:\n  b: 1\n# c\nc: 2\n") == ["a": ["b": 1], "c": 2])
        #expect(try YamlParser.parse("#a: 1\nb: 2\n") == ["b": 2])
        #expect(try YamlParser.parse("- 1\n# c\n- 2\n") == [1, 2])
        #expect(try YamlParser.parse("a:\n  - 1\n  # c\n  - 2\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("# nic\n") == .null)
    }

    @Test func commentAfterValue() throws {
        #expect(try YamlParser.parse("a: 1 # c\n") == ["a": 1])
        #expect(try YamlParser.parse("a: b #c\n") == ["a": "b"])
        #expect(try YamlParser.parse("a: 1 #c\n") == ["a": 1])
        #expect(try YamlParser.parse("a: \"b\" # c\n") == ["a": "b"])
        #expect(try YamlParser.parse("a: 1\t# c\n") == ["a": 1])
        #expect(try YamlParser.parse("a: x #c\nb: 2\n") == ["a": "x", "b": 2])
    }

    /// A comment is recognized only where `#` has nothing but a space before it
    /// (or is at the start of a token). `a: 1# c` is therefore the text "1# c".
    @Test func hashWithoutWhitespaceIsNotAComment() throws {
        #expect(try YamlParser.parse("a: 1# c\n") == ["a": "1# c"])
        #expect(try YamlParser.parse("a: b#c\n") == ["a": "b#c"])
        #expect(try YamlParser.parse("a: x y#z\n") == ["a": "x y#z"])
        #expect(try YamlParser.parse("a:#c\n") == .string("a:#c"))
        #expect(try YamlParser.parse("a: [b#c]\n") == ["a": ["b#c"]])
    }

    @Test func hashInsideQuotedScalarIsNotAComment() throws {
        #expect(try YamlParser.parse("a: \"b # c\"\n") == ["a": "b # c"])
        #expect(try YamlParser.parse("a: 'b # c'\n") == ["a": "b # c"])
        #expect(try YamlParser.parse("a: '#'\n") == ["a": "#"])
        // Not even on a continuation line of a multi-line quoted scalar.
        #expect(try YamlParser.parse("a: \"x\n# y\n  z\"\n") == ["a": "x # y z"])
        #expect(try YamlParser.parse("a: 'x\n# y\n  z'\n") == ["a": "x # y z"])
        #expect(try YamlParser.parse("a: \"x\n  # y\"\n") == ["a": "x # y"])
        // An apostrophe in the middle of a plain scalar does not open a quoted span.
        #expect(try YamlParser.parse("a: b'c # d\n") == ["a": "b'c"])
    }

    @Test func commentInsteadOfValue() throws {
        #expect(try YamlParser.parse("a: # c\n") == ["a": .null])
        #expect(try YamlParser.parse("a: #\n") == ["a": .null])
        #expect(try YamlParser.parse("a: # c\n  b: 1\n") == ["a": ["b": 1]])
        #expect(try YamlParser.parse("a: # c\n  - 1\n") == ["a": [1]])
        #expect(try YamlParser.parse("a:\n  - # c\n  - 2\n") == ["a": [.null, 2]])
    }

    /// A comment **ends** a plain scalar; an indented continuation after it is then
    /// an error (measured: Java rejects `a: x / # c / y`).
    @Test func commentTerminatesPlainScalar() throws {
        #expect(try YamlParser.parse("a: x\n  # c\n") == ["a": "x"])
        #expect(try YamlParser.parse("a: x\n  # c\nb: 2\n") == ["a": "x", "b": 2])
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: x\n  # c\n  y\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: x\n\n  # c\n  y\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: x\n  y\n  # c\n  z\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: x #c\n  y\n") }
    }

    /// At the document root Jackson reads one value and **silently
    /// drops** the rest — for a scalar and a flow collection alike (measured).
    @Test func rootValueIgnoresTrailingContent() throws {
        #expect(try YamlParser.parse("hello\n# c\nworld\n") == .string("hello"))
        #expect(try YamlParser.parse("hello\n# c\nb: 2\n") == .string("hello"))
        #expect(try YamlParser.parse("[1, 2]\nb: 3\n") == [1, 2])
        #expect(try YamlParser.parse("{a: 1}\nb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("\"x\"\nb: 2\n") == .string("x"))
        // A block collection at the root, on the contrary, complains about foreign content (as Java does).
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("- 1\nx\n") }
    }

    // MARK: - comments and flow

    @Test func commentsAroundFlow() throws {
        #expect(try YamlParser.parse("a: [1, 2] # c\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: [1, # c\n  2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: { x: 1, # c\n  y: 2 }\n") == ["a": ["x": 1, "y": 2]])
        #expect(try YamlParser.parse("a: [\n  # c\n  1 ]\n") == ["a": [1]])
        #expect(try YamlParser.parse("a: [1,\n# c\n2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: [\n# c\n# d\n1]\n") == ["a": [1]])
        #expect(try YamlParser.parse("a: [ # c\n 1]\n") == ["a": [1]])
        #expect(try YamlParser.parse("a: { # c\n x: 1}\n") == ["a": ["x": 1]])
        #expect(try YamlParser.parse("a: [1,\n2] # c\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: [1] # c\nb: 2\n") == ["a": [1], "b": 2])
        // `#` right after `,` is a comment — a token is only awaited there.
        #expect(try YamlParser.parse("a: [1,#c\n2]\n") == ["a": [1, 2]])
        #expect(try YamlParser.parse("a: {#c\nx: 1}\n") == ["a": ["x": 1]])
        // A comment ends a plain scalar; only `,` may continue.
        #expect(try YamlParser.parse("a: [x #c\n, y]\n") == ["a": ["x", "y"]])
    }

    @Test func commentBreakingFlowThrows() throws {
        // `#c]` is entirely a comment, so the sequence stays unclosed.
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [b #c]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [#c]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [ #c]\n") }
        // A comment ends a plain scalar, so `y` on the next line is extra.
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [x\n# c\ny]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [x,#c\n,y]\n") }
    }

    @Test func tabAtTokenPositionInFlowThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [\t1]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x:\t1}\n") }
    }

    /// A comment inside a document must not be mistaken for a document marker.
    @Test func commentAndDocumentMarkers() throws {
        #expect(try YamlParser.parse("# c\n---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("---\n# c\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n# ---\nb: 2\n") == ["a": 1, "b": 2])
    }

    // MARK: - a quote in the middle of a plain scalar (scanner, not a heuristic)

    /// A quote **in the middle** of a plain scalar does not open a quoted span, so
    /// a comment after it is recognized normally. This can be decided only by walking the line
    /// from the start (`scanLine`), not by looking at one preceding character.
    @Test func quoteInsidePlainScalarIsNotAQuotedScalar() throws {
        #expect(try YamlParser.parse("name: Field Day 'B # jen SSB\n") == ["name": "Field Day 'B"])
        #expect(try YamlParser.parse("list:\n  - a-'b: 1\n") == ["list": [["a-'b": 1]]])
        #expect(try YamlParser.parse("a-'b: 1\n") == ["a-'b": 1])
        #expect(try YamlParser.parse("x: 1\na-'b: 2\n") == ["x": 1, "a-'b": 2])
        #expect(try YamlParser.parse("a: b\"c # d\n") == ["a": "b\"c"])
        #expect(try YamlParser.parse("a: b\" c # d\n") == ["a": "b\" c"])
        #expect(try YamlParser.parse("a: don't # c\n") == ["a": "don't"])
        #expect(try YamlParser.parse("a: x'y\n") == ["a": "x'y"])
        #expect(try YamlParser.parse("- a'b # c\n") == ["a'b"])
        #expect(try YamlParser.parse("a: -'b # c\n") == ["a": "-'b"])
        #expect(try YamlParser.parse("a'b: 1 # c\n") == ["a'b": 1])
        // A quote right after a colon without a space: the colon does not separate the key,
        // so it is the root plain scalar "a:'x" (measured).
        #expect(try YamlParser.parse("a:'x # y'\n") == .string("a:'x"))
    }

    /// A space **inside** a plain scalar does not return us to a token position — the scalar
    /// continues, so even a further quote opens nothing.
    @Test func quoteAfterSpaceInsidePlainScalar() throws {
        #expect(try YamlParser.parse("a: x 'y z' # c\n") == ["a": "x 'y z'"])
        #expect(try YamlParser.parse("a: 1 'x # y\n") == ["a": "1 'x"])
        #expect(try YamlParser.parse("a: 1 'x' # y\n") == ["a": "1 'x'"])
        #expect(try YamlParser.parse("a: aa bb 'cc # dd\n") == ["a": "aa bb 'cc"])
    }

    /// At a token position, on the contrary, a quote opens a quoted scalar — a `#` in it
    /// is then not a comment.
    @Test func quoteAtTokenPositionOpensQuotedScalar() throws {
        #expect(try YamlParser.parse("'a # b': 1\n") == ["a # b": 1])
        #expect(try YamlParser.parse("- 'x # y'\n") == ["x # y"])
        #expect(try YamlParser.parse("a: ['x # y', z]\n") == ["a": ["x # y", "z"]])
        #expect(try YamlParser.parse("a: [x, 'y # z']\n") == ["a": ["x", "y # z"]])
        #expect(try YamlParser.parse("a: {k: 'v # w'}\n") == ["a": ["k": "v # w"]])
        #expect(try YamlParser.parse("a: {'k # j': 1}\n") == ["a": ["k # j": 1]])
        // A dash without a space is not an indicator, so `'` is in the middle of a scalar.
        #expect(try YamlParser.parse("-'x # y'\n") == .string("-'x"))
    }

    @Test func quotesInPlainScalarStillThrowWhereJavaDoes() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: 'x' 'y' # c\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [x'y # z]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: ,'b # c\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: x [1: 2]\n") }
    }

    // MARK: - quoted key of a block map

    /// A quoted key is unfolded the same as a quoted value — Java has
    /// a key with a tab in `"a\tb": 1` (measured). Flow keys always did that through
    /// `scanQuoted`, block ones did not.
    @Test func quotedBlockKeyIsUnescaped() throws {
        #expect(try YamlParser.parse("\"a\\tb\": 1\n") == ["a\tb": 1])
        #expect(try YamlParser.parse("\"a\\u0041b\": 1\n") == ["aAb": 1])
        #expect(try YamlParser.parse("\"a\\nb\": 1\n") == ["a\nb": 1])
        #expect(try YamlParser.parse("'a''b': 1\n") == ["a'b": 1])
        #expect(try YamlParser.parse("\"x\": 1\n") == ["x": 1])
        #expect(try YamlParser.parse("a:\n  \"b\\tc\": 1\n") == ["a": ["b\tc": 1]])
        #expect(try YamlParser.parse("- \"b\\tc\": 1\n") == [["b\tc": 1]])
        // An invalid escape in a key is an error, as in a value.
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("\"a\\zb\": 1\n") }
    }

    /// An empty key **in quotes** is valid, an unquoted one is not (measured).
    @Test func emptyBlockKey() throws {
        #expect(try YamlParser.parse("\"\": 1\n") == ["": 1])
        #expect(try YamlParser.parse("'': 1\n") == ["": 1])
        #expect(throws: YamlError.self) { _ = try YamlParser.parse(": 1\n") }
    }

    // MARK: - a tab where a token is expected

    /// After a closed node (flow collection, quoted scalar) and after a key
    /// separator Java rejects a tab. We must not accept more than it does.
    @Test func tabWhereTokenIsExpectedThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("b: [1] \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("d: \"x\" \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1]\t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: \"x\"\t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: 'x' \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: {x: 1} \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("- [1] \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: \t\n  b: 1\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1,\t\n2]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1, \t\n2]\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("\"x\"\t\n") }
        // A tab before a comment is still at a token position.
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1] \t# c\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: 1\n\t\nb: 2\n") }
        // A node closed only on a continuation line (which is read literally).
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: \"x\n  y\" \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: [1,\n2] \t\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a:\n  b: [1] \t\n") }
    }

    /// After a plain scalar a tab passes — `scanPlainSpaces` swallows it.
    @Test func trailingTabAfterPlainScalarIsFine() throws {
        #expect(try YamlParser.parse("a: 1 \t\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\t\n") == ["a": 1])
        #expect(try YamlParser.parse("a: x\n  y \t\n") == ["a": "x y"])
        #expect(try YamlParser.parse("a: [1\t]\n") == ["a": [1]])
        #expect(try YamlParser.parse("a: [a\tb]\n") == ["a": ["a\tb"]])
        #expect(try YamlParser.parse("a: [1] \n") == ["a": [1]])
        #expect(try YamlParser.parse("a: \"x\" \n") == ["a": "x"])
    }

    // MARK: - kind and position of the error

    /// The reader rests on distinguishing "unsupported construct" from "syntax
    /// error", so for flow errors `kind` and position are pinned as well.
    @Test func flowErrorKindsAndPositions() throws {
        do {
            _ = try YamlParser.parse("a: [? b]\n")
            Issue.record("it should have thrown an error")
        } catch let e as YamlError {
            #expect(e.kind == .unsupported)
            #expect(e.line == 1)
            #expect(e.column == 5)
        }
        do {
            _ = try YamlParser.parse("a: [1, 2}\n")
            Issue.record("it should have thrown an error")
        } catch let e as YamlError {
            #expect(e.kind == .syntax)
            #expect(e.line == 1)
            #expect(e.column == 9)
        }
        do {
            _ = try YamlParser.parse("s:\n  - {x\n    y: 1}\n")
            Issue.record("it should have thrown an error")
        } catch let e as YamlError {
            #expect(e.kind == .syntax)
            #expect(e.line == 3)
            #expect(e.column == 6)
        }
        do {
            _ = try YamlParser.parse("a: [x}y]\n")
            Issue.record("it should have thrown an error")
        } catch let e as YamlError {
            #expect(e.kind == .syntax)
            #expect(e.line == 1)
        }
    }

    // MARK: - real data

    /// Exact lines from `contest-data/contests/arrl-dx-cw.yaml`.
    @Test func realContestDefinitionFlow() throws {
        let v = try YamlParser.parse("""
        period: { durationHours: 48 }
        bands: [160m, 80m, 40m, 20m, 15m, 10m]
        stationClasses:
          - { id: wve, when: { dxccIn: [US, CA, K, VE] } }
          - { id: dx,  when: { not: { dxccIn: [US, CA, K, VE] } } }
        exchange:
          sent:
            - { id: power, type: TEXT, source: FROM_STATION }     # výkon (např. 100, KW)
        multipliers:
          - { id: areas, set: na_areas, from: state, scope: PER_BAND, appliesWhen: { workedClass: wve } }
        """)
        #expect(v["period"].value("durationHours", default: 0) == 48)
        #expect(v.value("bands", default: [String]()) == ["160m", "80m", "40m", "20m", "15m", "10m"])
        #expect(v["stationClasses"][0].value("id", default: "") == "wve")
        #expect(v["stationClasses"][0]["when"].value("dxccIn", default: [String]()) == ["US", "CA", "K", "VE"])
        #expect(v["stationClasses"][1]["when"]["not"].value("dxccIn", default: [String]()) == ["US", "CA", "K", "VE"])
        #expect(v["exchange"]["sent"][0].value("source", default: "") == "FROM_STATION")
        #expect(v["exchange"]["sent"][0].keys == ["id", "type", "source"])
        #expect(v["multipliers"][0]["appliesWhen"].value("workedClass", default: "") == "wve")
        #expect(v["multipliers"][0].value("scope", default: "") == "PER_BAND")
    }
}
