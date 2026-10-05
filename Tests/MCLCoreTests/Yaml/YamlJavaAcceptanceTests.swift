import Foundation
import Testing
@testable import MCLCore

/// Inputs on which an earlier reader silently read something other than Java:
/// either a different **value**, or it accepted what Java **rejects**.
///
/// The tables are **measured on Java** (maintainer-only probe
/// --values`, `YamlObjectMapper.create().readTree(InputStream)`); the expected tree is
/// in the canonical format of `JavaYamlParityTests` (a node per line, here joined by a space),
/// so type, value and literal spelling of the scalar are compared. Positions of rejected
/// inputs are in `YamlSyntaxErrorPositionTests.measured` (a later block).
@Suite struct YamlJavaAcceptanceTests {

    private static func canonical(_ text: String) throws -> String {
        JavaYamlParityTests.canonicalLines(try YamlParser.parse(text)).joined(separator: " ")
    }

    /// Walks the table; prints a mismatch as "input: swift ≠ java".
    private static func check(_ table: [(String, String)]) {
        var mismatches: [String] = []
        for (text, java) in table {
            do {
                let swift = try canonical(text)
                if swift != java { mismatches.append("\(text.debugDescription): \(swift) ≠ \(java)") }
                // The decoder path (`parseDocument`) must give the same tree.
                let document = try YamlParser.parseDocument(text)
                let viaDocument = JavaYamlParityTests.canonicalLines(document.root).joined(separator: " ")
                if viaDocument != java {
                    mismatches.append("\(text.debugDescription): parseDocument \(viaDocument) ≠ \(java)")
                }
            } catch {
                mismatches.append("\(text.debugDescription): \(error), Java \(java)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(table.count):\n\(mismatches.joined(separator: "\n"))")
    }

    /// A table of cases, listed separately.
    @Test func briefCases() throws {
        #expect(try Self.canonical("key : value") == #"["","map"] ["/key","str","value"]"#)
        #expect(try Self.canonical("a : 1\nb: 2") == #"["","map"] ["/a","int","1","1"] ["/b","int","2","2"]"#)
        #expect(try Self.canonical("b:\n  a : 1") == #"["","map"] ["/b","map"] ["/b/a","int","1","1"]"#)
        #expect(try Self.canonical("id: x\nmodes : [CW]")
                == #"["","map"] ["/id","str","x"] ["/modes","seq"] ["/modes/[0]","str","CW"]"#)
        #expect(throws: YamlError.self) { _ = try YamlParser.parse("x : 1\ny: 2\nz: [") }
        do {
            _ = try YamlParser.parse("x : 1\ny: 2\nz: [")
        } catch let error as YamlError {
            #expect(error.kind == .syntax && error.line == 3 && error.column == 5)
        }
    }

    /// A space or tab before the key's colon. SnakeYAML ends a plain
    /// scalar at ": " and takes all of it as a simple key, so `key : value`
    /// is a map — in a block map, in a sequence item, with an anchor or tag and in a flow too.
    /// `a :b` (without a space after the colon) is not a key.
    @Test func keyWithBlanksBeforeColon() {
        Self.check(Self.keyColon)
    }

    static let keyColon: [(String, String)] = [
        ("key : value", #"["","map"] ["/key","str","value"]"#),
        ("a : 1\nb: 2", #"["","map"] ["/a","int","1","1"] ["/b","int","2","2"]"#),
        ("b:\n  a : 1", #"["","map"] ["/b","map"] ["/b/a","int","1","1"]"#),
        ("id: x\nmodes : [CW]", #"["","map"] ["/id","str","x"] ["/modes","seq"] ["/modes/[0]","str","CW"]"#),
        ("key\t: value", #"["","map"] ["/key","str","value"]"#),
        ("key \t : value", #"["","map"] ["/key","str","value"]"#),
        ("key   :   value", #"["","map"] ["/key","str","value"]"#),
        ("key :", #"["","map"] ["/key","null"]"#),
        ("key :\n  a: 1", #"["","map"] ["/key","map"] ["/key/a","int","1","1"]"#),
        ("key :\n- 1", #"["","map"] ["/key","seq"] ["/key/[0]","int","1","1"]"#),
        ("- a : 1\n  b : 2", #"["","seq"] ["/[0]","map"] ["/[0]/a","int","1","1"] ["/[0]/b","int","2","2"]"#),
        ("a b : c", #"["","map"] ["/a b","str","c"]"#),
        ("a : b\n  c", #"["","map"] ["/a","str","b c"]"#),
        ("a : # c\n  b: 1", #"["","map"] ["/a","map"] ["/a/b","int","1","1"]"#),
        ("a:\n  b : 1\n  c : 2\nd : 3", #"["","map"] ["/a","map"] ["/a/b","int","1","1"] ["/a/c","int","2","2"] ["/d","int","3","3"]"#),
        ("modes : [CW]\nid: x", #"["","map"] ["/modes","seq"] ["/modes/[0]","str","CW"] ["/id","str","x"]"#),
        ("a : |\n  x\n", #"["","map"] ["/a","str","x\n"]"#),
        ("a : &x 1", #"["","map"] ["/a","int","1","1"]"#),
        ("a : !!str 1", #"["","map"] ["/a","str","1"]"#),
        ("a  : \"x\"", #"["","map"] ["/a","str","x"]"#),
        ("&x a : 1", #"["","map"] ["/a","int","1","1"]"#),
        ("!!str a : 1", #"["","map"] ["/a","int","1","1"]"#),
        ("a:b : 1", #"["","map"] ["/a:b","int","1","1"]"#),
        ("http://x : 1", #"["","map"] ["/http:~1~1x","int","1","1"]"#),
        ("- a\n- b : c", #"["","seq"] ["/[0]","str","a"] ["/[1]","map"] ["/[1]/b","str","c"]"#),
        ("a :\n  - x\n  - y", #"["","map"] ["/a","seq"] ["/a/[0]","str","x"] ["/a/[1]","str","y"]"#),
        ("a: 1\nb :", #"["","map"] ["/a","int","1","1"] ["/b","null"]"#),
        ("\"a\" : 1", #"["","map"] ["/a","int","1","1"]"#),
        ("'a' : 1", #"["","map"] ["/a","int","1","1"]"#),
        ("{a : 1}", #"["","map"] ["/a","int","1","1"]"#),
        ("[a : 1]", #"["","seq"] ["/[0]","map"] ["/[0]/a","int","1","1"]"#),
        ("{a\t: 1}", #"["","map"] ["/a","int","1","1"]"#),
        ("a :b", #"["","str","a :b"]"#),
        ("a: x :y", #"["","map"] ["/a","str","x :y"]"#),
        ("a :# c", #"["","str","a :# c"]"#),
        ("a\r\nb : 1\r\n", #"["","str","a b"]"#),
        ("id: test\nname : Test\nbands : [20m, 40m]\nscoring :\n  qsoPoints : 1\n", #"["","map"] ["/id","str","test"] ["/name","str","Test"] ["/bands","seq"] ["/bands/[0]","str","20m"] ["/bands/[1]","str","40m"] ["/scoring","map"] ["/scoring/qsoPoints","int","1","1"]"#),
    ]

    /// A continuation line of a plain scalar is read from inside the scalar: indicators at its
    /// start are text, the scalar ends only at ": " or " #". A root scalar
    /// is also ended by a line starting with `---` in the first column (even `---1`) and Java
    /// does not read the rest.
    @Test func plainContinuationLines() {
        Self.check(Self.continuation)
    }

    static let continuation: [(String, String)] = [
        ("a\n{b: 1}", #"["","str","a {b"]"#),
        ("a\n[b: 1]", #"["","str","a [b"]"#),
        ("a\n  >b: 1", #"["","str","a >b"]"#),
        ("x\n  !# c", #"["","str","x !# c"]"#),
        ("x\n  !!str# c", #"["","str","x !!str# c"]"#),
        ("a: x\n  !# c", #"["","map"] ["/a","str","x !# c"]"#),
        ("x\n  ,# c", #"["","str","x ,# c"]"#),
        ("x\n  ! # c", #"["","str","x !"]"#),
        ("a: x\n  \" # c", #"["","map"] ["/a","str","x \""]"#),
        ("x\n  \"q: 1", #"["","str","x \"q"]"#),
        ("a\nb: 1", #"["","str","a b"]"#),
        ("x\n...1", #"["","str","x ...1"]"#),
        ("x\n---1", #"["","str","x"]"#),
        ("    ---1\n---1\n", #"["","str","---1"]"#),
        ("x\n\n---a b", #"["","str","x"]"#),
    ]

    /// A `!` tag (and `!<!>`): Jackson types implicitly even a quoted and a block
    /// scalar. Previously a recorded divergence "Empty tag `!` before a quoted
    /// scalar" (a deliberate divergence from Java v1.1.1).
    @Test func nonSpecificTagTypesEveryStyleImplicitly() {
        Self.check(Self.nonSpecificTag)
    }

    static let nonSpecificTag: [(String, String)] = [
        ("a: ! \"1\"", #"["","map"] ["/a","int","1","1"]"#),
        ("a: ! 'true'", #"["","map"] ["/a","bool","true","true"]"#),
        ("a: ! \"\"", #"["","map"] ["/a","null"]"#),
        ("a: ! \"~\"", #"["","map"] ["/a","null"]"#),
        ("a: ! \"null\"", #"["","map"] ["/a","null"]"#),
        ("a: ! >\n  1", #"["","map"] ["/a","int","1","1"]"#),
        ("a: ! \"0x10\"", #"["","map"] ["/a","int","16","0x10"]"#),
        ("a: ! \"1.5\"", #"["","map"] ["/a","double","1.5","1.5"]"#),
        ("[! \"1\"]", #"["","seq"] ["/[0]","int","1","1"]"#),
        ("{a: ! \"\"}", #"["","map"] ["/a","null"]"#),
        ("a: ! \"yes\"", #"["","map"] ["/a","bool","true","yes"]"#),
        ("a: !<!> \"1\"", #"["","map"] ["/a","int","1","1"]"#),
        ("a: ! |-\n  1", #"["","map"] ["/a","int","1","1"]"#),
        ("a: ! |\n", #"["","map"] ["/a","null"]"#),
        ("a: ! |\n  1\n", #"["","map"] ["/a","str","1\n"]"#),
        ("a: ! \"x\"", #"["","map"] ["/a","str","x"]"#),
        ("a: ! \" 1\"", #"["","map"] ["/a","str"," 1"]"#),
        ("a: ! \"1:30\"", #"["","map"] ["/a","str","1:30"]"#),
        ("a: ! 1", #"["","map"] ["/a","int","1","1"]"#),
    ]

    /// A trailing tab after a comment belongs to the comment. Previously we rejected it as a separator after a flow
    /// collection, a quoted scalar and an empty value.
    @Test func trailingTabAfterCommentIsAccepted() {
        Self.check(Self.tabAfterComment)
    }

    static let tabAfterComment: [(String, String)] = [
        ("a: 1 # c\t", #"["","map"] ["/a","int","1","1"]"#),
        ("a: [1] # c\t", #"["","map"] ["/a","seq"] ["/a/[0]","int","1","1"]"#),
        ("a: # c\t", #"["","map"] ["/a","null"]"#),
        ("a: \"x\" # c\t", #"["","map"] ["/a","str","x"]"#),
        ("a: [1,\n  2] # c\t", #"["","map"] ["/a","seq"] ["/a/[0]","int","1","1"] ["/a/[1]","int","2","2"]"#),
        ("a: {b: 1,\n  c: 2}   # c \t", #"["","map"] ["/a","map"] ["/a/b","int","1","1"] ["/a/c","int","2","2"]"#),
        ("- [1] # c\t", #"["","seq"] ["/[0]","seq"] ["/[0]/[0]","int","1","1"]"#),
        ("[1] # c\t", #"["","seq"] ["/[0]","int","1","1"]"#),
        ("\"x\" # c\t", #"["","str","x"]"#),
        ("{a: 1} # c\t", #"["","map"] ["/a","int","1","1"]"#),
        ("a: \"x\n  y\" # c\t", #"["","map"] ["/a","str","x y"]"#),
        ("modes: [CW, SSB] # druhy provozu\t\n", #"["","map"] ["/modes","seq"] ["/modes/[0]","str","CW"] ["/modes/[1]","str","SSB"]"#),
    ]

    /// What Java rejects and the reader would read is rejected by the safeguard
    /// `YamlParser.rejectWhatJavaRejects` — a syntax error with the Java position
    /// and its own text. Errors the reader recognizes itself keep their text.
    @Test func rejectedLikeJava() {
        let cases: [(String, Int, Int)] = [
            (",a: 1", 1, 1),
            ("]b: 1", 1, 1),
            ("\"a\\z\"b:\n", 1, 1),
            ("%YAML 11.3\n---\na: 1\n", 1, 1),
            ("a: &x\t", 1, 2),
            ("!    -", 1, 1),
        ]
        for (text, line, column) in cases {
            #expect(throws: YamlError(message: "neplatný zápis YAML", line: line, column: column)) {
                _ = try YamlParser.parse(text)
            }
            #expect(throws: YamlError(message: "neplatný zápis YAML", line: line, column: column)) {
                _ = try YamlParser.parseDocument(text)
            }
        }
    }

    // MARK: - fix 1

    /// The span of a continuation line before ": " at a root scalar: SnakeYAML strips
    /// only trailing spaces and tabs. NBSP and U+3000 are content — previously they were
    /// they were trimmed by `trimmingCharacters(in: .whitespaces)`.
    @Test func continuationHeadKeepsNonAsciiSpaces() {
        Self.check(Self.continuationHead)
    }

    static let continuationHead: [(String, String)] = [
        ("a\n\u{A0}b: c", #"["","str","a  b"]"#),
        ("a\n b\u{3000}: c", #"["","str","a b　"]"#),
        ("a\n\u{3000}b : c", #"["","str","a 　b"]"#),
        ("a\n b\u{A0}: c", #"["","str","a b "]"#),
        ("a\nb\u{A0}\t: c", #"["","str","a b "]"#),
        ("a\n\u{A0}: c", #"["","str","a  "]"#),
        ("a\n b  : c", #"["","str","a b"]"#),
    ]

    /// Java **does not read** content after the end of the root node (`readTree` and `readValue`
    /// of the loader, `FAIL_ON_TRAILING_TOKENS=false`) and silently drops it — even if it is wrong.
    /// We copy that (the client's decision): `  id: x` + `name: y` is `{"id":"x"}`
    /// and a definition with a mistakenly indented first line is loaded from that line only. The table
    /// also contains double quotes with a line break after a backslash, which were
    /// uncovered by this (`"x\\` + `"` is "x").
    @Test func contentAfterRootIsIgnoredLikeJava() {
        Self.check(Self.afterRoot)
    }

    static let afterRoot: [(String, String)] = [
        ("  id: x\nname: y", #"["","map"] ["/id","str","x"]"#),
        ("  schemaVersion: 1\nid: cq-ww\nname: CQ WW\n", #"["","map"] ["/schemaVersion","int","1","1"]"#),
        ("[1] x", #"["","seq"] ["/[0]","int","1","1"]"#),
        ("[1, 2]\nb: 3", #"["","seq"] ["/[0]","int","1","1"] ["/[1]","int","2","2"]"#),
        ("{a: 1} garbage", #"["","map"] ["/a","int","1","1"]"#),
        ("{a: 1}\n- x", #"["","map"] ["/a","int","1","1"]"#),
        ("x\n\t", #"["","str","x"]"#),
        ("1\n\t\nb: ", #"["","int","1","1"]"#),
        ("\"x\" y", #"["","str","x"]"#),
        ("'x'\n: 1", #"["","str","x"]"#),
        ("a\nb: 1", #"["","str","a b"]"#),
        ("x\n---1", #"["","str","x"]"#),
        (" - a\nb: 1", #"["","seq"] ["/[0]","str","a"]"#),
        ("  - a\n  - b\nc", #"["","seq"] ["/[0]","str","a"] ["/[1]","str","b"]"#),
        ("  a: |\n    x\n\nb: y", #"["","map"] ["/a","str","x\n"]"#),
        ("  a: |+\n    x\n\n\nb: y", #"["","map"] ["/a","str","x\n\n\n"]"#),
        ("|\n  x\nb", #"["","str","x\n"]"#),
        ("  a: 1\n  b: 2\n# c\nc: 3", #"["","map"] ["/a","int","1","1"] ["/b","int","2","2"]"#),
        ("  a:\n    b: 1\nc: [", #"["","map"] ["/a","map"] ["/a/b","int","1","1"]"#),
        ("a: 1\n...\nb: [", #"["","map"] ["/a","int","1","1"]"#),
        ("\"x\\\n\"", #"["","str","x"]"#),
        ("\"x\\ \n\"", #"["","str","x  "]"#),
        ("a: \"\\\n \"", #"["","map"] ["/a","str",""]"#),
        ("  a: 1\n b: 2", #"["","map"] ["/a","int","1","1"]"#),
        // A root with a tag or anchor not followed by content: an empty scalar.
        ("!!str }", #"["","str",""]"#),
        ("&x\n&y a", #"["","null"]"#),
        ("!\n!str a", #"["","null"]"#),
        ("&x &y 1", #"["","null"]"#),
        ("!!str !!int", #"["","str",""]"#),
        ("&x,1: 2\n", #"["","null"]"#),
        ("--- a: 1\n", #"["","str","a"]"#),
        ("a\nb::  2\n", #"["","str","a b:"]"#),
    ]

    /// A space or indicator followed by a character that joins into a grapheme
    /// (a combining character, U+FE0F, keycap…). The reader compares `Character`, so
    /// `" "` + U+0301 is not a space for it. A deliberate divergence from Java v1.1.1 ("a space
    /// and a combining character"); fix = a reader over
    /// `Unicode.Scalar`. Here is the **Java** value, under `withKnownIssue`.
    @Test func graphemeGluedToIndicatorKnownDivergence() {
        let cases: [(String, String)] = [
            ("a: x #\u{FE0F}\u{20E3} tag", #"["","map"] ["/a","str","x"]"#),
            ("a: 1 #\u{301}c", #"["","map"] ["/a","int","1","1"]"#),
            ("a: [x,\u{301}y]", #"["","map"] ["/a","seq"] ["/a/[0]","str","x"] ["/a/[1]","str","\#u{301}y"]"#),
        ]
        for (text, java) in cases {
            withKnownIssue("the reader works on graphemes, not code points") { () throws in
                let swift = try Self.canonical(text)
                #expect(swift == java)
            }
        }
    }
}
