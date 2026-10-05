import Testing
@testable import MCLCore

/// Tests of `JavaRegex` — the Java regular-expression dialect over `NSRegularExpression`.
///
/// The main table (`JavaMeasuredRegex`) is measured on JDK 21.0.2 and covers
/// the dialect differences the adapter evens out (`\d \s \w \b` are ASCII in Java,
/// Java `.` and `$`/`^` have a different set of line terminators than ICU, `(?i)` is
/// ASCII only), syntax errors with the Java description and index, and patterns the project
/// really uses (`contest-data/` and the Java sources).
@Suite struct JavaRegexTests {

    /// Patterns the adapter **loudly rejects** (Java accepts them or rejects them differently).
    /// Each is a deliberate divergence from Java v1.1.1.
    static let refused: Set<String> = [
        "(?x)a b", "(?u)a", "(?U)a", "(?c)a",           // flags COMMENTS, UNICODE_CASE, UNICODE_CHARACTER_CLASS, CANON_EQ
        "\\G", "\\X", "\\b{g}", "\\N{LATIN SMALL LETTER A}",
        "(?i)(a)\\1",                                    // a back-reference without case sensitivity
        "\\p{javaLowerCase}", "\\p{IsLatin}", "\\p{InGreek}", "\\p{IsAlphabetic}",
        "\\p{IsAlpha}", "\\p{sc=Latin}", "\\p{Isgc}",    // scripts, blocks, Character.* methods
        "(?<=a+)b",                                      // an unbounded look-behind (ICU cannot do it)
        "a{16777216}", "a{0,16777216}", "a{16777216,}", // ICU has a repetition cap of 2^24 − 1
    ]

    /// Rows where Java provably differs and Swift cannot express it: after an
    /// empty match Java advances the search by one **UTF-16 unit**, so it finds
    /// an empty match even in the middle of a surrogate pair. ICU advances by code
    /// points and a Swift `String` cannot carry half a pair anyway.
    static let surrogateStepping: [(pattern: String, input: String, swiftFinds: String)] = [
        ("", "\u{1F600}", "0-0 2-2"),
        ("x*", "\u{1F600}", "0-0 2-2"),
    ]

    @Test func measuredMatchTable() {
        for row in JavaMeasuredRegex.matchTable {
            let label = "vzor \(row.pattern.debugDescription), vstup \(row.input.debugDescription)"
            if Self.refused.contains(row.pattern) {
                #expect(throws: JavaRegexError.self, "\(label) should be rejected") {
                    try JavaRegex(row.pattern)
                }
                if let error = compileError(row.pattern) {
                    #expect(error.kind == .unsupported, "\(label): \(error.message)")
                }
                continue
            }
            switch row.outcome {
            case .error(let reason, let index):
                do {
                    _ = try JavaRegex(row.pattern)
                    Issue.record("\(label): Java reports the error \"\(reason)\", the adapter accepted the pattern")
                } catch {
                    #expect(error.kind == .syntax, "\(label): \(error.message)")
                    #expect(error.reason == reason, "\(label)")
                    #expect(error.index == index, "\(label)")
                }
            case .ok(let matches, let finds, let groups):
                let regex: JavaRegex
                do {
                    regex = try JavaRegex(row.pattern)
                } catch {
                    Issue.record("\(label): the adapter rejected a valid pattern: \(error.message)")
                    continue
                }
                #expect(regex.matches(row.input) == matches, "\(label): matches()")
                let all = regex.allMatches(in: row.input)
                let swiftFinds = all.map { "\($0.range.lowerBound)-\($0.range.upperBound)" }
                    .joined(separator: " ")
                if let divergent = Self.surrogateStepping.first(where: {
                    $0.pattern == row.pattern && $0.input == row.input
                }) {
                    #expect(swiftFinds == divergent.swiftFinds, "\(label): the divergence changed")
                    #expect(swiftFinds != finds, "\(label): the divergence disappeared, move the row back")
                    continue
                }
                #expect(swiftFinds == finds, "\(label): find()")
                if let first = all.first {
                    let swiftGroups = (0..<regex.groupCount).map { first.group($0 + 1) }
                    #expect(swiftGroups == groups, "\(label): groups of the first find")
                    #expect(regex.firstMatch(in: row.input) == first, "\(label): firstMatch")
                } else {
                    #expect(regex.firstMatch(in: row.input) == nil, "\(label): firstMatch")
                }
            }
        }
    }

    @Test func measuredSplitTable() throws {
        for row in JavaMeasuredRegex.splitTable {
            let regex = try JavaRegex(row.pattern)
            #expect(regex.split(row.input, limit: row.limit) == row.result,
                    "split(\(row.pattern.debugDescription)) nad \(row.input.debugDescription), limit \(row.limit)")
            #expect(JavaText.split(row.input, regex: regex, limit: row.limit) == row.result)
        }
    }

    @Test func measuredReplaceFirstTable() throws {
        for row in JavaMeasuredRegex.replaceFirstTable {
            let regex = try JavaRegex(row.pattern)
            #expect(regex.replaceFirst(in: row.input, with: row.replacement) == row.result,
                    "replaceFirst(\(row.pattern.debugDescription)) nad \(row.input.debugDescription)")
        }
    }

    /// The error text is Java `PatternSyntaxException.getMessage()` character by character
    /// (measured with `ProbeMessage.java`): the description, "near index", the pattern and the caret,
    /// tabs in the pattern are repeated in the caret row. The caret is missing when the
    /// index is not less than the pattern length in UTF-16 units.
    @Test func syntaxErrorMessageIsJavas() {
        let measured: [(String, String)] = [
            ("(a", "Unclosed group near index 2\n(a"),
            ("\t**", "Dangling meta character '*' near index 2\n\t**\n\t ^"),
            ("a{2,1}", "Illegal repetition range near index 5\na{2,1}\n     ^"),
            ("[z-a]", "Illegal character range near index 3\n[z-a]\n   ^"),
            ("\\Qx\\E)", "Unmatched closing ')' near index 0\n\\Qx\\E)\n^"),
            ("\u{1F600})", "Unmatched closing ')' near index 0\n\u{1F600})\n^"),
            ("(?<=(a)\\1)b",
             "Look-behind group does not have an obvious maximum length near index 8\n(?<=(a)\\1)b\n        ^"),
        ]
        for (pattern, message) in measured {
            #expect(throws: JavaRegexError.self) { try JavaRegex(pattern) }
            if let error = compileError(pattern) {
                #expect(error.kind == .syntax)
                #expect(error.message == message, "pattern \(pattern.debugDescription)")
            }
        }
    }

    /// The rejection carries its own Czech description and is distinguishable from a syntax error.
    @Test func refusalIsDistinguishable() {
        if let error = compileError("\\p{IsLatin}") {
            #expect(error.kind == .unsupported)
            #expect(error.message.contains("IsLatin"))
            #expect(error.message.contains("\\p{IsLatin}"))
        } else {
            Issue.record("\\p{IsLatin} should have been rejected")
        }
    }

    /// Review focus no. 5: a user regex in `keyPattern`/`validation.regex`
    /// that behaves differently in the Java and ICU dialects — the result as in Java.
    @Test func dialectDifferencesFollowJava() throws {
        #expect(try !JavaRegex("\\d+").matches("\u{663}"))       // ICU: true
        #expect(try !JavaRegex("\\s").matches("\u{A0}"))         // ICU: true
        #expect(try JavaRegex("\\s").matches("\u{B}"))
        #expect(try !JavaRegex("\\w").matches("é"))              // ICU: true
        #expect(try JavaRegex(".").matches("\u{B}"))             // ICU: false
        #expect(try JavaRegex(".").matches("\u{C}"))             // ICU: false
        #expect(try !JavaRegex(".").matches("\u{85}"))
        #expect(try !JavaRegex("a$").matches("a\u{B}"))
        #expect(try JavaRegex("(?m)$").allMatches(in: "a\u{B}b").map(\.range) == [3..<3])
        #expect(try !JavaRegex("(?i)k").matches("\u{212A}"))     // ICU: true (Kelvin)
        #expect(try !JavaRegex("(?i)ss").matches("ß"))           // ICU: true
    }

    /// Unicode categories as in JDK 21 (Unicode 15.0). Measured by `ProbeTypes.java`
    /// over all code points: after masking points newer than 15.0 the
    /// only differences are U+0295 and U+1171E, which newer Unicode reclassified.
    @Test func unicodeCategoriesAreJava21s() throws {
        #expect(try !JavaRegex("\\p{L}").matches("\u{2EBF0}"))  // added in 15.1
        #expect(try JavaRegex("\\p{Cn}").matches("\u{2EBF0}"))
        #expect(try JavaRegex("\\p{Ll}").matches("\u{295}"))
        #expect(try !JavaRegex("\\p{Lo}").matches("\u{295}"))
        #expect(try JavaRegex("\\p{Mn}").matches("\u{1171E}"))
        #expect(try !JavaRegex("\\p{Mc}").matches("\u{1171E}"))
    }

    /// `Matcher.matches()` + `group(n)` as in `Tour.parse`.
    @Test func wholeMatchExposesGroups() throws {
        let format = try JavaRegex("(\\d{1,2})(\\d{2})/(\\d{1,4})")
        let match = try #require(format.wholeMatch("1200/30"))
        #expect(match.range == 0..<7)
        #expect(match.group(0) == "1200/30")
        #expect(match.group(1) == "12")
        #expect(match.group(2) == "00")
        #expect(match.group(3) == "30")
        #expect(format.wholeMatch("1200/30x") == nil)
        #expect(format.groupCount == 3)
        let optional = try JavaRegex("(a)?b")
        #expect(optional.wholeMatch("b")?.group(1) == nil)
        let named = try JavaRegex("(?<hh>\\d\\d):(?<mm>\\d\\d)")
        #expect(named.groupNames == ["hh": 1, "mm": 2])
    }

    /// `DefinitionEditing.withId`: `(?m)^id:\s*.*$` and the replacement verbatim — neither `$` nor
    /// `\` in the new id is interpreted (`Matcher.quoteReplacement`).
    @Test func replaceFirstIsLiteral() throws {
        let idLine = try JavaRegex("(?m)^id:\\s*.*$")
        #expect(idLine.replaceFirst(in: "id: a\nname: b", with: "id: $0\\1") == "id: $0\\1\nname: b")
        #expect(idLine.replaceFirst(in: "name: b", with: "id: x") == "name: b")
    }

    /// A compile error, or `nil` when the pattern compiled.
    private func compileError(_ pattern: String) -> JavaRegexError? {
        do {
            _ = try JavaRegex(pattern)
            return nil
        } catch {
            return error
        }
    }
}
