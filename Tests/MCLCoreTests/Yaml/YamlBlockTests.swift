import Foundation
import Testing
@testable import MCLCore

/// Block maps and sequences nested by indentation. Expected trees are
/// **measured on Java** (`ObjectMapper.readTree`).
@Suite struct YamlBlockTests {

    // MARK: - block maps

    @Test func flatMapping() throws {
        let v = try YamlParser.parse("a: 1\nb: dva\n")
        #expect(v == ["a": 1, "b": "dva"])
    }

    @Test func nestedMapping() throws {
        let v = try YamlParser.parse("""
        metadata:
          name: CQ WW
          organizer: CQ Magazine
        """)
        #expect(v == ["metadata": ["name": "CQ WW", "organizer": "CQ Magazine"]])
    }

    @Test func blankLinesAreIgnored() throws {
        let v = try YamlParser.parse("a: 1\n\n\nb: 2\n")
        #expect(v == ["a": 1, "b": 2])
    }

    @Test func keyWithoutValueIsNull() throws {
        #expect(try YamlParser.parse("a:\n") == ["a": .null])
    }

    @Test func quotedKey() throws {
        #expect(try YamlParser.parse("\"a b\": 1\n") == ["a b": 1])
        #expect(try YamlParser.parse("'a: b': 1\n") == ["a: b": 1])
    }

    /// A key is recognized by `:` followed by a space or end of line —
    /// `a:b` is therefore text, not a key (measured on Java).
    @Test func colonWithoutSpaceIsNotAKey() throws {
        #expect(try YamlParser.parse("v: http://example.com")["v"] == .string("http://example.com"))
    }

    @Test func mappingKeysKeepDocumentOrder() throws {
        let v = try YamlParser.parse("z: 1\na: 2\nm: 3\n")
        #expect(v.keys == ["z", "a", "m"])
    }

    // MARK: - block sequences

    @Test func topLevelSequence() throws {
        #expect(try YamlParser.parse("- 1\n- 2\n") == [1, 2])
    }

    @Test func sequenceUnderKeyIndented() throws {
        let v = try YamlParser.parse("""
        bands:
          - 160m
          - 80m
        """)
        #expect(v == ["bands": ["160m", "80m"]])
    }

    /// A sequence may be indented the same as its key — Jackson accepts it.
    @Test func sequenceUnderKeyAtSameIndent() throws {
        let v = try YamlParser.parse("bands:\n- 160m\n- 80m\n")
        #expect(v == ["bands": ["160m", "80m"]])
    }

    @Test func sequenceOfMappings() throws {
        let v = try YamlParser.parse("""
        rules:
          - id: a
            n: 1
          - id: b
            n: 2
        """)
        #expect(v == ["rules": [["id": "a", "n": 1], ["id": "b", "n": 2]]])
    }

    @Test func mappingInSequenceWithNestedSequence() throws {
        let v = try YamlParser.parse("""
        l:
          - a: 1
            b:
              - 2
        """)
        #expect(v == ["l": [["a": 1, "b": [2]]]])
    }

    @Test func deeplyNestedMix() throws {
        let v = try YamlParser.parse("""
        a:
          b: 1
          c:
            - x
            - y
        """)
        #expect(v == ["a": ["b": 1, "c": ["x", "y"]]])
    }

    @Test func dashWithoutValueThenNestedBlock() throws {
        let v = try YamlParser.parse("""
        l:
          -
            a: 1
        """)
        #expect(v == ["l": [["a": 1]]])
    }

    @Test func emptySequenceItemIsNull() throws {
        #expect(try YamlParser.parse("- 1\n-\n- 3\n") == [1, .null, 3])
    }

    // MARK: - the document as a whole

    @Test func bareScalarDocument() throws {
        #expect(try YamlParser.parse("hello") == .string("hello"))
        #expect(try YamlParser.parse("48") == .int(48))
    }

    /// An empty document is `null` (Java returns `MissingNode`, which for our
    /// callers behaves the same as a missing value).
    @Test func emptyDocumentIsNull() throws {
        #expect(try YamlParser.parse("") == .null)
        #expect(try YamlParser.parse("\n\n") == .null)
    }

    // MARK: - duplicate keys

    /// Jackson (LinkedHashMap) lets the **last one win** but the key
    /// **keeps its original position** — measured: `a: 1, b: 2, a: 3` → `{a:3, b:2}`.
    @Test func duplicateKeyLastWins() throws {
        let v = try YamlParser.parse("k: first\nk: second\n")
        #expect(v == ["k": "second"])
    }

    @Test func duplicateKeyKeepsFirstPosition() throws {
        let v = try YamlParser.parse("a: 1\nb: 2\na: 3\n")
        #expect(v.keys == ["a", "b"])
        #expect(v["a"] == .int(3))
        #expect(v["b"] == .int(2))
    }

    @Test func duplicateKeyReplacesWholeSubtree() throws {
        let v = try YamlParser.parse("""
        k:
          x: 1
        k:
          y: 2
        """)
        #expect(v == ["k": ["y": 2]])
    }

    // MARK: - wrong indentation

    @Test func extraIndentAfterScalarValueThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: 1\n  b: 2\n") }
    }

    @Test func inconsistentIndentInsideMappingThrows() throws {
        #expect(throws: YamlError.self) {
            _ = try YamlParser.parse("a:\n    b: 1\n  c: 2\n")
        }
    }

    @Test func mappingAndSequenceMixedAtSameLevelThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: 1\n- 2\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("- 1\nb: 2\n") }
    }

    /// A multi-line plain scalar is folded: a line break = a space (measured on Java).
    @Test func plainScalarFoldsAcrossLines() throws {
        #expect(try YamlParser.parse("hello\nworld\n") == .string("hello world"))
        #expect(try YamlParser.parse("v: aa\n  bb\n  cc\n")["v"] == .string("aa bb cc"))
        #expect(try YamlParser.parse("v: aa\n  bb\nw: 1\n") == ["v": "aa bb", "w": 1])
        #expect(try YamlParser.parse("- hello\n  world\n") == [.string("hello world")])
    }

    /// A quoted scalar may span further lines — `multipliers/iaru_hq.yaml`
    /// does it. An empty line inside gives a line break, not a space.
    @Test func quotedScalarFoldsAcrossLines() throws {
        #expect(try YamlParser.parse("v: \"aa\n  bb\n  cc\"\n")["v"] == .string("aa bb cc"))
        #expect(try YamlParser.parse("v: \"aa\n\n  bb\"\n")["v"] == .string("aa\nbb"))
        #expect(try YamlParser.parse("v: 'aa\n  bb'\n")["v"] == .string("aa bb"))
    }

    /// `---` at the start is in our data (`bandplan.yaml`) and it is still
    /// one document.
    @Test func leadingDocumentMarkerIsAccepted() throws {
        #expect(try YamlParser.parse("---\na: 1\n") == ["a": 1])
        #expect(try YamlParser.parse("---\n- 1\n") == [1])
    }

    /// A second document is **not an error**: Jackson quietly returns only the first
    /// (measured). We copy that.
    @Test func secondDocumentIsIgnoredNotRejected() throws {
        #expect(try YamlParser.parse("---\na: 1\n---\nb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n---\nb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("- 1\n---\n- 2\n") == [1])
        #expect(try YamlParser.parse("---\na: 1\n---\nb: 2\n---\nc: 3\n") == ["a": 1])
    }

    /// `...` also just ends the document.
    @Test func documentEndMarkerIsIgnoredNotRejected() throws {
        #expect(try YamlParser.parse("a: 1\n...\n") == ["a": 1])
        #expect(try YamlParser.parse("a: 1\n...\nb: 2\n") == ["a": 1])
        #expect(try YamlParser.parse("---\n...\n") == .null)
    }

    /// A lone `---` is an empty document; a lone `...` (without `---` and without
    /// content) is rejected by Java.
    @Test func markersWithoutContent() throws {
        #expect(try YamlParser.parse("---\n") == .null)
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("...\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("...\na: 1\n") }
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("\n...\n") }
    }

    /// An indented `...` is not a marker — it folds into the scalar.
    @Test func indentedEndMarkerIsJustText() throws {
        #expect(try YamlParser.parse("v: aa\n  ...\n")["v"] == .string("aa ..."))
    }

    /// A dash on a continuation line does **not** interrupt folding — inside a plain
    /// scalar it is just text (measured on Java).
    @Test func continuationLineStartingWithDashKeepsFolding() throws {
        #expect(try YamlParser.parse("a: x\n  - 1\n") == ["a": "x - 1"])
        #expect(try YamlParser.parse("- 1\n  - 2\n") == [.string("1 - 2")])
        #expect(try YamlParser.parse("a: x\n    - 1\n  - 2\n") == ["a": "x - 1 - 2"])
        // a dash indented the same is still another item
        #expect(try YamlParser.parse("- 1\n- 2\n") == [1, 2])
    }

    /// At the document root a scalar folds up to the colon and Jackson does not
    /// read the rest at all; inside a block map it is, on the contrary, an error.
    @Test func rootScalarFoldsUpToColonThenDocumentEnds() throws {
        #expect(try YamlParser.parse("hello\nb: 2\n") == .string("hello b"))
        #expect(try YamlParser.parse("hello\n  b: 2\n") == .string("hello b"))
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a: x\n  b: 2\n") }
    }

    /// A colon in a value does not start a block map — Java reports an error on `v: abc:`.
    @Test func colonInsideValueThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("v: abc:\n") }
    }

    @Test func tabInIndentationThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a:\n\tb: 1\n") }
    }

    /// A tab after a colon is rejected by Java too.
    @Test func tabAfterKeyThrows() throws {
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("a:\tb\n") }
    }

    /// A block scalar is **read** (Java supports it, so rejecting it would
    /// mean refusing a definition that the Java application loads).
    /// Detailed tables are in `YamlBlockScalarTests`.
    @Test func blockScalarIsRead() throws {
        #expect(try YamlParser.parse("v: |\n  text\n") == ["v": "text\n"])
    }

    /// An error always carries a line and a column (1-based) so the caller knows where to look.
    @Test func errorCarriesLineAndColumn() throws {
        do {
            _ = try YamlParser.parse("a: 1\n  b: 2\n")
            Issue.record("it should have thrown an error")
        } catch let e as YamlError {
            #expect(e.line == 2)
            #expect(e.column == 4)
            #expect(e.kind == .syntax)
            #expect(e.description.contains("2"))
        }
    }

    // MARK: - navigating the tree

    @Test func subscriptNavigationNeverTraps() throws {
        let v = try YamlParser.parse("""
        a:
          b:
            - c: 1
        """)
        #expect(v["a"]["b"][0]["c"] == .int(1))
        #expect(v["a"]["nic"]["hloub"] == .null)
        #expect(v["a"]["b"][9] == .null)
        #expect(v["a"]["b"]["neni-klic"] == .null)
        #expect(v[0] == .null)
    }

    @Test func sequenceAndMappingAccessors() throws {
        let v = try YamlParser.parse("bands:\n  - 160m\n  - 80m\n")
        #expect(v["bands"].sequence?.count == 2)
        #expect(v["bands"].value(default: [String]()) == ["160m", "80m"])
        #expect(v.mapping?.count == 1)
        #expect(v.has("bands"))
        #expect(!v.has("modes"))
    }

    /// A piece of a real contest definition — the block parts of `cq-ww-cw.yaml`.
    @Test func realContestDefinitionFragment() throws {
        let v = try YamlParser.parse("""
        schemaVersion: 1
        id: cq-ww-cw
        metadata:
          name: "CQ WW DX Contest — CW"
          organizer: "CQ Magazine"
        scoring:
          qsoPoints:
            mode: FIRST_MATCH
            default: 0
          total: "qsoPoints * multTotal"
        """)
        #expect(v.value("schemaVersion", default: 0) == 1)
        #expect(v.value("id", default: "") == "cq-ww-cw")
        #expect(v["metadata"].value("name", default: "") == "CQ WW DX Contest — CW")
        #expect(v["scoring"]["qsoPoints"].value("mode", default: "") == "FIRST_MATCH")
        #expect(v["scoring"]["qsoPoints"].value("default", default: -1) == 0)
        #expect(v["scoring"].value("total", default: "") == "qsoPoints * multTotal")
    }
}
