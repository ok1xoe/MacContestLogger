import Foundation
import Testing
@testable import MCLCore

/// Node positions from `YamlParser.parseDocument`. Every number in the tables is
/// **measured on a running Java** (Jackson 2.22.0 + SnakeYAML 2.5): the probe walked the
/// `YAMLParser` tokens and for every value printed `currentTokenLocation()`
/// (start) and `currentLocation()` (end). Jackson's type errors point at these two positions,
/// so the line and column in the message that the user sees for a bad
/// contest definition rest on them.
@Suite struct YamlPositionsTests {

    /// The expected position of one node. `end == nil` means "the end is not
    /// checked" (collections and block scalars do not have it).
    struct Expected: Sendable {
        let path: YamlPath
        let start: YamlPosition
        let end: YamlPosition?

        init(_ path: YamlPath, _ start: (Int, Int), _ end: (Int, Int)? = nil) {
            self.path = path
            self.start = YamlPosition(line: start.0, column: start.1)
            self.end = end.map { YamlPosition(line: $0.0, column: $0.1) }
        }
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let yaml: String
        let expected: [Expected]
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "block map", yaml: "id: cq-ww\nschemaVersion: 1\nmeta:\n  name: CQ WW\n  count: 48\n", expected: [
            Expected([], (1, 1)),
            Expected(["id"], (1, 5), (1, 10)),
            Expected(["schemaVersion"], (2, 16), (2, 17)),
            Expected(["meta"], (4, 3)),
            Expected(["meta", "name"], (4, 9), (4, 14)),
            Expected(["meta", "count"], (5, 10), (5, 12)),
        ]),
        Case(name: "block sequences (indented and at the key level)",
             yaml: "bands:\n  - 160m\n  - 80m\nmodes:\n- CW\n- SSB\n", expected: [
            Expected(["bands"], (2, 3)),
            Expected(["bands", 0], (2, 5), (2, 9)),
            Expected(["bands", 1], (3, 5), (3, 8)),
            Expected(["modes"], (5, 1)),
            Expected(["modes", 0], (5, 3), (5, 5)),
            Expected(["modes", 1], (6, 3), (6, 6)),
        ]),
        Case(name: "nested flow {} and []",
             yaml: "a: {x: 1, y: [2, {z: \"q\"}], w: {}}\nb: [ [1, 2], {k: v} ]\n", expected: [
            Expected(["a"], (1, 4)),
            Expected(["a", "x"], (1, 8), (1, 9)),
            Expected(["a", "y"], (1, 14)),
            Expected(["a", "y", 0], (1, 15), (1, 16)),
            Expected(["a", "y", 1], (1, 18)),
            Expected(["a", "y", 1, "z"], (1, 22), (1, 25)),
            Expected(["a", "w"], (1, 32)),
            Expected(["b"], (2, 4)),
            Expected(["b", 0], (2, 6)),
            Expected(["b", 0, 0], (2, 7), (2, 8)),
            Expected(["b", 0, 1], (2, 10), (2, 11)),
            Expected(["b", 1], (2, 14)),
            Expected(["b", 1, "k"], (2, 18), (2, 19)),
        ]),
        Case(name: "quoted and multi-line scalars",
             yaml: "a: \"dq\"\nb: 'sq'\nc: \"multi\n  line\"\nd: plain\n  continued\ne: after\n", expected: [
            Expected(["a"], (1, 4), (1, 8)),
            Expected(["b"], (2, 4), (2, 8)),
            Expected(["c"], (3, 4), (4, 8)),
            Expected(["d"], (5, 4), (6, 12)),
            Expected(["e"], (7, 4), (7, 9)),
        ]),
        Case(name: "value on the next line, comment after the value",
             yaml: "key:\n  value-on-next-line\nk2:\n\n    99999999999\nk3:   spaced   # c\n", expected: [
            Expected(["key"], (2, 3), (2, 21)),
            Expected(["k2"], (5, 5), (5, 16)),
            Expected(["k3"], (6, 7), (6, 13)),
        ]),
        Case(name: "a tag and an anchor start the node",
             yaml: "a: !!int 42\nb: &x 7\nc: !!map\n  d: 1\ne: &y\n  - 1\nf: !!str 99\n", expected: [
            Expected(["a"], (1, 4), (1, 12)),
            Expected(["b"], (2, 4), (2, 8)),
            Expected(["c"], (3, 4)),
            Expected(["c", "d"], (4, 6), (4, 7)),
            Expected(["e"], (5, 4)),
            Expected(["e", 0], (6, 5), (6, 6)),
            Expected(["f"], (7, 4), (7, 12)),
        ]),
        Case(name: "explicit key and a map/sequence after a dash",
             yaml: "? ex\n: val\nl:\n  - name: a\n    n: 1\n  - - x\n    - y\n", expected: [
            Expected(["ex"], (2, 3), (2, 6)),
            Expected(["l"], (4, 3)),
            Expected(["l", 0], (4, 5)),
            Expected(["l", 0, "name"], (4, 11), (4, 12)),
            Expected(["l", 0, "n"], (5, 8), (5, 9)),
            Expected(["l", 1], (6, 5)),
            Expected(["l", 1, 0], (6, 7), (6, 8)),
            Expected(["l", 1, 1], (7, 7), (7, 8)),
        ]),
        Case(name: "flow across several lines, a single-pair map in a sequence",
             yaml: "s: [x: 1, y]\nt: {a: 1,\n  b: [2,\n    3]}\n", expected: [
            Expected(["s"], (1, 4)),
            Expected(["s", 0], (1, 5)),
            Expected(["s", 0, "x"], (1, 8), (1, 9)),
            Expected(["s", 1], (1, 11), (1, 12)),
            Expected(["t"], (2, 4)),
            Expected(["t", "a"], (2, 8), (2, 9)),
            Expected(["t", "b"], (3, 6)),
            Expected(["t", "b", 0], (3, 7), (3, 8)),
            Expected(["t", "b", 1], (4, 5), (4, 6)),
        ]),
        // Columns in code points: `e\u{301}` is two, 😀 one, a flag two.
        Case(name: "column in Unicode code points",
             yaml: "e: \"e\u{301}\"\nf: {g: \"\u{1F600}\", h: 1, i: \"\u{FF21}\u{301}\", j: 2}\nk: [\u{1F1E8}\u{1F1FF}, 3]\n",
             expected: [
            Expected(["e"], (1, 4), (1, 8)),
            Expected(["f"], (2, 4)),
            Expected(["f", "g"], (2, 8), (2, 11)),
            Expected(["f", "h"], (2, 16), (2, 17)),
            Expected(["f", "i"], (2, 22), (2, 26)),
            Expected(["f", "j"], (2, 31), (2, 32)),
            Expected(["k"], (3, 4)),
            Expected(["k", 0], (3, 5), (3, 7)),
            Expected(["k", 1], (3, 9), (3, 10)),
        ]),
        Case(name: "CRLF", yaml: "a: 1\r\nb:\r\n  c: 2\r\n", expected: [
            Expected(["a"], (1, 4), (1, 5)),
            Expected(["b"], (3, 3)),
            Expected(["b", "c"], (3, 6), (3, 7)),
        ]),
        Case(name: "U+2028 is a line break", yaml: "a: 1\u{2028}b: 2\n", expected: [
            Expected(["a"], (1, 4), (1, 5)),
            Expected(["b"], (2, 4), (2, 5)),
        ]),
        Case(name: "scalar after ---", yaml: "--- 5\n", expected: [
            Expected([], (1, 5), (1, 6)),
        ]),
        Case(name: "map under ---", yaml: "---\na: 1\n", expected: [
            Expected([], (2, 1)),
            Expected(["a"], (2, 4), (2, 5)),
        ]),
        Case(name: "block scalars", yaml: "a: |\n  text\n  more\nb: >\n  folded\nc: 3\n", expected: [
            Expected(["a"], (1, 4)),
            Expected(["b"], (4, 4)),
            Expected(["c"], (6, 4), (6, 5)),
        ]),
        Case(name: "maps in a sequence, explicit ~",
             yaml: "x:\n  - a: 1\n    b: [1, 2]\n  -\n    c: 3\n  - \n  - ~\n", expected: [
            Expected(["x"], (2, 3)),
            Expected(["x", 0], (2, 5)),
            Expected(["x", 0, "a"], (2, 8), (2, 9)),
            Expected(["x", 0, "b"], (3, 8)),
            Expected(["x", 0, "b", 0], (3, 9), (3, 10)),
            Expected(["x", 0, "b", 1], (3, 12), (3, 13)),
            Expected(["x", 1], (5, 5)),
            Expected(["x", 1, "c"], (5, 8), (5, 9)),
            Expected(["x", 3], (7, 5), (7, 6)),
        ]),
        Case(name: "scalars of various types", yaml: "a: 1.5\nb: -0x1F\nc: 1e3\nd: true\ne: null\nf: \"\"\n", expected: [
            Expected(["a"], (1, 4), (1, 7)),
            Expected(["b"], (2, 4), (2, 9)),
            Expected(["c"], (3, 4), (3, 7)),
            Expected(["d"], (4, 4), (4, 8)),
            Expected(["e"], (5, 4), (5, 8)),
            Expected(["f"], (6, 4), (6, 6)),
        ]),
    ]

    private func start(_ document: YamlDocument, _ path: YamlPath) -> YamlPosition? {
        document.positions.position(of: path).map { YamlPosition(line: $0.line, column: $0.column) }
    }

    private func at(_ line: Int, _ column: Int) -> YamlPosition { YamlPosition(line: line, column: column) }

    @Test(arguments: cases)
    func positionMatchesJava(_ testCase: Case) throws {
        let document = try YamlParser.parseDocument(testCase.yaml)
        for expected in testCase.expected {
            let start = document.positions.position(of: expected.path)
            #expect(start.map { YamlPosition(line: $0.line, column: $0.column) } == expected.start,
                    "start \(expected.path)")
            if let end = expected.end {
                let actual = document.positions.endPosition(of: expected.path)
                #expect(actual.map { YamlPosition(line: $0.line, column: $0.column) } == end,
                        "end \(expected.path)")
            }
        }
    }

    /// Positions must not change the tree: `parseDocument` returns the same root as `parse`.
    @Test(arguments: cases)
    func treeIsTheSameAsParse(_ testCase: Case) throws {
        #expect(try YamlParser.parseDocument(testCase.yaml).root == YamlParser.parse(testCase.yaml))
    }

    /// The whole `contest-data/` corpus: `parseDocument` gives the same tree as `parse`
    /// (byte equality with Java is guarded by `JavaYamlParityTests`), every non-null
    /// node has a start and no recorded position points outside the tree.
    @Test func corpusPositionsCoverEveryNode() throws {
        let root = try ContestDataLayoutTests.contestDataRoot()
        let files = try JavaYamlParityTests.yamlFiles()
        #expect(!files.isEmpty)
        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            let document = try YamlParser.parseDocument(text)
            #expect(document.root == (try YamlParser.parse(text)), "\(relative): different tree")
            var visited: Set<YamlPath> = []
            func walk(_ value: YamlValue, _ path: YamlPath) {
                visited.insert(path)
                switch value {
                case .null:
                    return
                case .mapping(let mapping):
                    #expect(document.positions.position(of: path) != nil, "\(relative) \(path)")
                    for pair in mapping.pairs { walk(pair.value, path.appending(key: pair.key)) }
                case .sequence(let items):
                    #expect(document.positions.position(of: path) != nil, "\(relative) \(path)")
                    for (index, item) in items.enumerated() { walk(item, path.appending(index: index)) }
                default:
                    #expect(document.positions.position(of: path) != nil, "\(relative) \(path)")
                }
            }
            walk(document.root, .root)
            let stray = document.positions.paths.filter { !visited.contains($0) }
            #expect(stray.isEmpty, "\(relative): positions outside the tree \(stray)")
        }
    }

    /// An omitted value has no position (`null` causes no type error), the path
    /// outside the document neither.
    @Test func missingNodesHaveNoPosition() throws {
        let document = try YamlParser.parseDocument("a:\nb: [1]\n")
        #expect(document.positions.position(of: ["a"]) == nil)
        #expect(document.positions.position(of: ["zzz"]) == nil)
        #expect(document.positions.position(of: ["b", 5]) == nil)
        #expect(document.positions.endPosition(of: ["b"]) == nil)
    }

    /// A BOM at the start of the file: Java drops it and counts columns without it (measured
    /// `\u{FEFF}a: 1` → `a` at 1:4). In Swift the file decoding drops it already
    /// (`Utf8Text.decodeStrippingBom`, as the loaders read), the parser does not see it.
    /// Foundation cannot be relied on: on macOS 15 `String(data:encoding: .utf8)`
    /// keeps the BOM (measured in CI), on macOS 26 it strips it.
    @Test func bomIsStrippedByLoaderDecoding() throws {
        let data = Data([0xEF, 0xBB, 0xBF] + Array("a: 1\nb: x\n".utf8))
        let text = try #require(Utf8Text.decodeStrippingBom(data))
        let document = try YamlParser.parseDocument(text)
        #expect(document.positions.position(of: ["a"])?.column == 4)
        #expect(document.positions.position(of: ["b"])?.line == 2)
    }

    /// A duplicate key: in the map the last occurrence and its position win; the earlier
    /// occurrence moves with its positions under `.shadowedKey`, because Java
    /// reads it too when mapping to a record (as a stream). Measured:
    /// `a: 1` + `a: {x: 2}` gives tokens `/a` 1:4 and `/a` 2:4, `/a/x` 2:8.
    @Test func duplicateKeyKeepsShadowedOccurrence() throws {
        let document = try YamlParser.parseDocument("a: 1\na: {x: 2}\nb: [1]\na: [3]\n")
        #expect(document.root["a"] == [3])
        #expect(document.shadowedValues(of: ["a"]) == [1, ["x": 2]])
        #expect(start(document, ["a"]) == at(4, 4))
        #expect(start(document, ["a", 0]) == at(4, 5))
        #expect(start(document, [.shadowedKey("a", occurrence: 0)]) == at(1, 4))
        #expect(start(document, [.shadowedKey("a", occurrence: 1)]) == at(2, 4))
        #expect(start(document, [.shadowedKey("a", occurrence: 1), "x"]) == at(2, 8))
        #expect(document.positions.position(of: ["a", "x"]) == nil)
        #expect(document.shadowedValues(of: ["b"]).isEmpty)
    }

    /// A duplicate inside an overwritten occurrence moves with it.
    @Test func nestedDuplicateMovesWithShadowedParent() throws {
        let document = try YamlParser.parseDocument("m: {k: 1, k: 2}\nm: {k: 3}\n")
        let shadowedM: YamlPath = [.shadowedKey("m", occurrence: 0)]
        #expect(document.shadowedValues(of: ["m"]) == [["k": 2]])
        #expect(document.shadowedValues(of: shadowedM.appending(key: "k")) == [1])
        #expect(document.shadowedValues(of: ["m", "k"]).isEmpty)
        #expect(start(document, shadowedM.appending(.shadowedKey("k", occurrence: 0))) == at(1, 8))
        #expect(start(document, shadowedM.appending(key: "k")) == at(1, 14))
        #expect(start(document, ["m", "k"]) == at(2, 8))
    }

    /// A duplicate in a flow map and with an explicit key; a `null` value
    /// also overwrites a duplicate.
    @Test func duplicateInFlowAndExplicitKey() throws {
        let flow = try YamlParser.parseDocument("{a: [1], a}\n")
        #expect(flow.root["a"] == .null)
        #expect(flow.shadowedValues(of: ["a"]) == [[1]])
        #expect(start(flow, [.shadowedKey("a", occurrence: 0)]) == at(1, 5))
        let explicit = try YamlParser.parseDocument("? a\n: 1\n? a\n: x\n")
        #expect(explicit.shadowedValues(of: ["a"]) == [1])
        #expect(start(explicit, ["a"]) == at(4, 3))
    }

    /// An empty input has no document; `---` and `~` have one (root `null`).
    /// The end-of-input position is where Java reports "No content to map"
    /// (measured: `""` → 1:1, `# c\n` → 2:1, `\n\n` → 3:1, `# c` → 1:4; a lone
    /// directive `%YAML 1.1` is not a document either → 2:1).
    @Test func emptyStreamAndEndOfInput() throws {
        for (text, line, column) in [("", 1, 1), ("# c\n", 2, 1), ("\n\n", 3, 1), ("# c", 1, 4),
                                   ("%YAML 1.1\n", 2, 1), ("  \n# x\n   ", 3, 4)] {
            let document = try YamlParser.parseDocument(text)
            #expect(document.isEmptyStream, "\(text.debugDescription)")
            #expect(document.positions.endOfInput == YamlPosition(line: line, column: column),
                    "\(text.debugDescription)")
        }
        for text in ["---\n", "~\n", "--- ~\n", "%YAML 1.1\n---\n", "---\n# c\n"] {
            let document = try YamlParser.parseDocument(text)
            #expect(!document.isEmptyStream, "\(text.debugDescription)")
            #expect(document.root == .null)
        }
    }
}
