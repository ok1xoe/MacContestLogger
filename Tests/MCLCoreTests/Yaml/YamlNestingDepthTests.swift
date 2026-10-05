import Foundation
import Testing
@testable import MCLCore

/// Nesting depth of collections: above `YamlParser.maxNestingDepth` a syntax error,
/// **never a process crash** (I1).
///
/// The reader is recursive and the definition is also read by `DefinitionUpdater` from the network on a Swift
/// concurrency thread with a 512 KB stack. Before the limit the debug build crashed
/// with a stack overflow (SIGBUS) already around 11 flow levels with an anchor and a tag.
/// The tests therefore run on **their own thread with 512 KB** — as small as the
/// pool threads, regardless of what swift-testing runs them on.
///
/// Java (Jackson `StreamReadConstraints.maxNestingDepth`) reads up to a depth of 1000
/// and rejects deeper input with position -1:-1 (measured `ProbeErr`); we reject already
/// above 16 — a deliberate divergence from Java v1.1.1.
@Suite struct YamlNestingDepthTests {

    enum Outcome: Sendable, Equatable {
        case parsed
        case failed(YamlError)
        case other(String)
    }

    /// Runs `body` on a thread with a 512 KB stack and waits for the result.
    static func onSmallStack(_ body: @escaping @Sendable () -> Outcome) async -> Outcome {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: body())
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    static func parse(_ text: String) async -> Outcome {
        await onSmallStack {
            do {
                _ = try YamlParser.parseDocument(text)
                return .parsed
            } catch let error as YamlError {
                return .failed(error)
            } catch {
                return .other("\(error)")
            }
        }
    }

    static let limit = YamlParser.maxNestingDepth

    /// Inputs with exactly `depth` nested collections (the root counts).
    /// Each is a different recursive path of the reader; `flowAnchorTag` and `flowMapTag`
    /// are the most expensive (an anchor and a tag on every level).
    static let constructs: [(name: String, text: @Sendable (Int) -> String)] = [
        ("flowSequence", { d in
            "a: " + String(repeating: "[", count: d - 1) + String(repeating: "]", count: d - 1) + "\n"
        }),
        ("flowMapping", { d in
            "a: " + String(repeating: "{a: ", count: d - 1) + "1" + String(repeating: "}", count: d - 1) + "\n"
        }),
        ("flowAnchorTag", { d in
            "a: " + String(repeating: "[&a !!seq ", count: d - 1) + "1"
                + String(repeating: "]", count: d - 1) + "\n"
        }),
        ("flowMapTag", { d in
            "a: " + String(repeating: "{a: &x !!map ", count: d - 1) + "1"
                + String(repeating: "}", count: d - 1) + "\n"
        }),
        ("flowPairInSequence", { d in
            // `[a: [a: …]]` — a sequence and a single-pair map, both are a level.
            let pairs = (d - 1) / 2
            let tail = (d - 1) % 2 == 1 ? "[]" : "1"
            return "k: " + String(repeating: "[a: ", count: pairs) + tail
                + String(repeating: "]", count: pairs) + "\n"
        }),
        ("blockSequenceInline", { d in
            String(repeating: "- ", count: d) + "x\n"
        }),
        ("blockSequence", { d in
            (0..<(d - 1)).map { String(repeating: " ", count: $0) + "-\n" }.joined()
                + String(repeating: " ", count: d - 1) + "- x\n"
        }),
        ("blockMapping", { d in
            (0..<(d - 1)).map { String(repeating: " ", count: $0) + "k:\n" }.joined()
                + String(repeating: " ", count: d - 1) + "k: 1\n"
        }),
        ("blockMappingAnchorTag", { d in
            (0..<(d - 1)).map { String(repeating: " ", count: $0) + "k: &a !!map\n" }.joined()
                + String(repeating: " ", count: d - 1) + "k: 1\n"
        }),
        ("explicitKey", { d in
            (0..<(d - 1)).map { String(repeating: " ", count: $0) + "? k\n"
                + String(repeating: " ", count: $0) + ":\n" }.joined()
                + String(repeating: " ", count: d - 1) + "k: 1\n"
        }),
    ]

    @Test func limitCoversRealDefinitions() {
        // The deepest definition in `contest-data` has 7 levels, the test one
        // `type-deep-condition.yaml` 9; the limit must leave a reserve.
        #expect(Self.limit >= 16)
    }

    @Test(arguments: 0..<constructs.count)
    func depthAtLimitParses(_ index: Int) async {
        let construct = Self.constructs[index]
        let outcome = await Self.parse(construct.text(Self.limit))
        #expect(outcome == .parsed, "\(construct.name)")
    }

    @Test(arguments: 0..<constructs.count)
    func depthOverLimitIsSyntaxError(_ index: Int) async {
        let construct = Self.constructs[index]
        let outcome = await Self.parse(construct.text(Self.limit + 1))
        guard case .failed(let error) = outcome else {
            Issue.record("\(construct.name): \(outcome)")
            return
        }
        #expect(error.kind == .syntax, "\(construct.name)")
        #expect(error.message.contains("zanoření"), "\(construct.name): \(error)")
    }

    /// Far above the limit: an error, not a crash. A flow and a block sequence on one
    /// line have 10,000 levels (above the Java thousand). Blocks by lines have
    /// indentation growing with depth, so the text grows quadratically; 300 levels
    /// are enough — that is above the depth where the debug build without a limit crashed (19–104
    /// levels depending on the path), and the test stays fast.
    @Test(arguments: 0..<constructs.count)
    func veryDeepInputIsRejectedWithoutCrash(_ index: Int) async {
        let construct = Self.constructs[index]
        let lineBased = ["blockSequence", "blockMapping", "blockMappingAnchorTag", "explicitKey"]
        let depth = lineBased.contains(construct.name) ? 300 : 10_000
        let outcome = await Self.parse(construct.text(depth))
        guard case .failed(let error) = outcome else {
            Issue.record("\(construct.name): \(outcome)")
            return
        }
        #expect(error.kind == .syntax, "\(construct.name)")
    }

    /// The error position is the start of the first collection above the limit (the Java one is -1:-1,
    /// there is nothing for the positions to match).
    @Test func errorPointsAtFirstCollectionOverLimit() async {
        // `a: ` + 16× `[`: the root map is level 1, `[` at column 4 level 2,
        // the seventeenth level is the sixteenth bracket at column 19.
        let flow = await Self.parse("a: " + String(repeating: "[", count: 16) + String(repeating: "]", count: 16))
        #expect(flow == .failed(YamlError(
            message: "příliš hluboké zanoření: víc než 16 úrovní map a sekvencí", line: 1, column: 19)))
        // The column is in code points as for other errors: `é` composed of
        // two code points shifts the brackets one column further.
        let composed = await Self.parse("e\u{301}: " + String(repeating: "[", count: 16)
                                        + String(repeating: "]", count: 16))
        guard case .failed(let error) = composed else {
            Issue.record("\(composed)")
            return
        }
        #expect(error.line == 1 && error.column == 20, "\(error)")
        // A block map: the seventeenth level starts at line 17, column 17.
        let blockMapping = Self.constructs.first { $0.name == "blockMapping" }!
        let block = await Self.parse(blockMapping.text(17))
        guard case .failed(let blockError) = block else {
            Issue.record("\(block)")
            return
        }
        #expect(blockError.line == 17 && blockError.column == 17)
    }

    /// A chain of tags on an explicit key (`? !a !a !a … x`) was walked by the reader
    /// recursively, one tag at a time; Java rejects two tags on a node, now the reader does too,
    /// right at the second.
    @Test func tagChainOnExplicitKeyIsRejectedWithoutCrash() async {
        let outcome = await Self.parse("? " + String(repeating: "!a ", count: 10_000) + "x\n")
        guard case .failed(let error) = outcome else {
            Issue.record("\(outcome)")
            return
        }
        #expect(error.kind == .syntax)
        // Java reports the end of the last event before the error: 1:1 (the start of the map).
        #expect(error.line == 1)
    }

    /// Lines that contain only a tag or an anchor (`a: !t` + `  !t` + …) were read by the reader
    /// recursively per line without a nesting counter and from ~100 lines crashed
    /// (NEW-1). Java rejects a second tag or anchor of a node even across
    /// lines; the positions are Java's (measured `ProbeErr`).
    @Test func propertyOnlyLineChainsAreRejectedWithoutCrash() async {
        let chains: [(name: String, text: String, line: Int, column: Int)] = [
            ("tag", "a: !t\n" + String(repeating: "  !t\n", count: 10_000) + "  x\n", 1, 6),
            ("anchor", "a: &x\n" + String(repeating: "  &x\n", count: 10_000) + "  1\n", 1, 6),
            ("alternating", "a: !t\n" + String(repeating: "  &x\n  !t\n", count: 5_000) + "  1\n", 2, 5),
            ("sequence", "- !t\n" + String(repeating: "  !t\n", count: 10_000), 1, 5),
        ]
        for chain in chains {
            let outcome = await Self.parse(chain.text)
            guard case .failed(let error) = outcome else {
                Issue.record("\(chain.name): \(outcome)")
                continue
            }
            #expect(error.kind == .syntax && error.line == chain.line && error.column == chain.column,
                    "\(chain.name): \(error)")
        }
    }

    /// One tag and one anchor per node across lines are legal and the tag is
    /// applied to the scalar on the next line (previously it was silently dropped: `a: !!str` +
    /// `  1` was a number). Values measured on Java (`ProbeErr --values`).
    @Test func propertiesOnEarlierLineApplyLikeJava() throws {
        let cases: [(String, String)] = [
            ("a: &x\n  !!str x\n", #"["","map"] ["/a","str","x"]"#),
            ("a: !!str\n  1\n", #"["","map"] ["/a","str","1"]"#),
            ("a: !!str\n  &x 1\n", #"["","map"] ["/a","str","1"]"#),
            ("a: !!int\n  \"1\"\n", #"["","map"] ["/a","int","1","1"]"#),
            ("a: !!float\n  1\n", #"["","map"] ["/a","double","1.0","1"]"#),
            ("a: !!null\n  x\n", #"["","map"] ["/a","null"]"#),
            ("- !!str\n  1\n", #"["","seq"] ["/[0]","str","1"]"#),
            ("!!str\n1\n", #"["","str","1"]"#),
            ("a: &x !t\n  1\n", #"["","map"] ["/a","str","1"]"#),
            ("a: &x\n  !!str\n    x\n", #"["","map"] ["/a","str","x"]"#),
            ("a: !!map\n  !x b: 1\n", #"["","map"] ["/a","map"] ["/a/b","int","1","1"]"#),
            ("a: !t\n  [1]\n", #"["","map"] ["/a","seq"] ["/a/[0]","int","1","1"]"#),
            ("a: !!str\n", #"["","map"] ["/a","str",""]"#),
        ]
        for (text, java) in cases {
            let swift = JavaYamlParityTests.canonicalLines(try YamlParser.parse(text)).joined(separator: " ")
            #expect(swift == java, "\(text.debugDescription)")
        }
        // A second tag or anchor of a node across lines: an error at the Java position.
        for (text, line, column) in [("a: &x\n  &y 1\n", 1, 6), ("a: &x\n  !!str\n    &y 1\n", 2, 8),
                                     ("a: !!str &x\n  !!int 1\n", 1, 12), ("a: !t\n  !u [1]\n", 1, 6)] {
            do {
                _ = try YamlParser.parse(text)
                Issue.record("\(text.debugDescription) accepted")
            } catch let error as YamlError {
                #expect(error.kind == .syntax && error.line == line && error.column == column,
                        "\(text.debugDescription): \(error)")
            }
        }
    }

    /// The whole definition path (`DefinitionEditing.check` = parser, decoder
    /// with the recursive `Condition.not`, validator) on 512 KB: at the limit it passes,
    /// above it it is a definition error, not a crash.
    @Test func definitionCheckWithDeepConditionOnSmallStack() async {
        func definition(nots: Int) -> String {
            // Root (1) → stationClasses (2) → item (3) → `not` maps → inner map.
            """
            schemaVersion: 1
            id: t
            metadata: { name: T }
            period: { durationHours: 48 }
            bands: [160m]
            modes: [CW]
            stationClasses:
              - id: dx
                when: \(String(repeating: "{not: ", count: nots)){ownDxcc: true}\(String(repeating: "}", count: nots))

            """
        }
        let atLimit = definition(nots: Self.limit - 4)
        let overLimit = definition(nots: Self.limit - 3)
        let deep = definition(nots: 10_000)
        for (text, shouldLoad) in [(atLimit, true), (overLimit, false), (deep, false)] {
            let outcome = await Self.onSmallStack {
                let check = DefinitionEditing.check(text, fileId: nil, knownSets: [])
                if check.definition != nil { return .parsed }
                return .other(check.issues.first?.message ?? "")
            }
            if shouldLoad {
                #expect(outcome == .parsed)
            } else {
                guard case .other(let message) = outcome else {
                    Issue.record("\(outcome)")
                    continue
                }
                #expect(message.contains("zanoření"), "\(message)")
            }
        }
    }
}

/// A port of Jackson in `JavaYamlErrorLocator` knows the Java limit of 1000 (measured
/// `ProbeErr`: 1000 levels OK, 1001 "Document nesting depth (1001) exceeds the
/// maximum allowed (1000…)" at -1:-1, flow and block).
@Suite struct JavaYamlLocatorNestingTests {

    static func flow(_ depth: Int) -> String {
        "a: " + String(repeating: "[", count: depth - 1) + String(repeating: "]", count: depth - 1) + "\n"
    }

    static func accepted(_ text: String) -> Bool {
        if case .success = JavaYamlErrorLocator.locate(text) { return true }
        return false
    }

    @Test func javaLimitIsThousand() {
        #expect(Self.accepted(Self.flow(1000)))
        #expect(JavaYamlErrorLocator.locate(Self.flow(1001)) == .failure(line: -1, column: -1))
        #expect(Self.accepted(String(repeating: "- ", count: 1000) + "x\n"))
        #expect(JavaYamlErrorLocator.locate(String(repeating: "- ", count: 1001) + "x\n")
                == .failure(line: -1, column: -1))
    }
}
