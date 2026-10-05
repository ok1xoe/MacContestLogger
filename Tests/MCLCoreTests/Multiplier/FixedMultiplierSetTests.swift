import Foundation
import Testing
@testable import MCLCore

/// `FixedMultiplierSet` against Java. The `rows` table is **generated from running
/// Java**: the `ProbeSets` probe (Java v1.1.1, `build/classes/java/main`) built
/// `new FixedMultiplierSet(…)` with parameters from `Spec.make()` and for each input
/// printed `normalize(v)` (state, key, reason) and `isExpected(v)`. The Java tests
/// call the set only via the registry, these rows are new — measured, not guessed.
///
/// The main trap: an `INTEGER` set tries the ASCII shape `\d+`, but
/// the canonical key is made by `Integer.parseInt`, which accepts `+`, Unicode digits
/// and only the `int` range. Hence `"+7"` and Arabic `"١٤"` are invalid in `normalize`,
/// and yet `isExpected` returns `true`.
@Suite struct FixedMultiplierSetTests {

    /// Set parameters as the probe passed them to the Java constructor.
    enum Spec: String, Sendable {
        case cq, integer, grid, keyLengthZero, keyLengthNegative, text, nullKeyType
        case patternDigit, patternSpace, patternDot, patternWord, patternDigitInteger
        case patternEmpty, patternWhole, patternCaseInsensitive, patternLowercase
        case patternThenTruncate, nullAndEmptyKey

        func make() throws -> FixedMultiplierSet {
            switch self {
            case .cq:
                // like `cq_zones.yaml`
                try FixedMultiplierSet(id: "cq_zones", keyType: .INTEGER, values: FixedMultiplierSetTests.range(1, 40),
                                       keyPattern: "^([1-9]|[1-3][0-9]|40)$")
            case .integer:
                try FixedMultiplierSet(id: "i", keyType: .INTEGER, values: FixedMultiplierSetTests.range(1, 5), keyPattern: nil)
            case .grid:
                // like `grid_fields.yaml`: an empty set, key truncated to 2 characters
                try FixedMultiplierSet(id: "grid_fields", keyType: .TEXT, values: [], keyPattern: nil,
                                       keyLength: 2)
            case .keyLengthZero:
                try FixedMultiplierSet(id: "g0", keyType: .TEXT, values: [MultiplierValue(key: "AB", label: "x")],
                                       keyPattern: nil, keyLength: 0)
            case .keyLengthNegative:
                try FixedMultiplierSet(id: "gn", keyType: .TEXT, values: [MultiplierValue(key: "AB", label: "x")],
                                       keyPattern: nil, keyLength: -1)
            case .text:
                // keys from the definition are not normalised: " ab " and "x" are never expected
                try FixedMultiplierSet(id: "t", keyType: .TEXT, values: [
                    MultiplierValue(key: "STRASSE", label: "s"),
                    MultiplierValue(key: " ab ", label: "raw"),
                    MultiplierValue(key: "x", label: "lower"),
                ], keyPattern: nil)
            case .nullKeyType:
                try FixedMultiplierSet(id: "n", keyType: nil, values: [MultiplierValue(key: "AB", label: "x")],
                                       keyPattern: nil)
            case .patternDigit: try pattern("\\d+")
            case .patternSpace: try pattern("A\\sB")
            case .patternDot: try pattern("A.B")
            case .patternWord: try pattern("\\w+")
            case .patternDigitInteger:
                try FixedMultiplierSet(id: "p", keyType: .INTEGER, values: [], keyPattern: "\\d+")
            case .patternEmpty: try pattern("")
            case .patternWhole: try pattern("AB")
            case .patternCaseInsensitive: try pattern("(?i)[a-z]+")
            case .patternLowercase: try pattern("[a-z]+")
            case .patternThenTruncate:
                try FixedMultiplierSet(id: "p", keyType: .TEXT, values: [], keyPattern: "[A-R]{2}[0-9]{2}",
                                       keyLength: 2)
            case .nullAndEmptyKey:
                try FixedMultiplierSet(id: nil, keyType: .TEXT, values: [
                    MultiplierValue(key: nil, label: nil),
                    MultiplierValue(key: "", label: "e"),
                ], keyPattern: nil)
            }
        }

        private func pattern(_ p: String) throws -> FixedMultiplierSet {
            try FixedMultiplierSet(id: "p", keyType: .TEXT, values: [], keyPattern: p)
        }
    }

    struct Row: CustomTestStringConvertible, Sendable {
        let spec: Spec
        let input: String?
        let resolution: Resolution
        let expected: Bool

        init(_ spec: Spec, _ input: String?, _ resolution: Resolution, expected: Bool) {
            self.spec = spec
            self.input = input
            self.resolution = resolution
            self.expected = expected
        }

        var testDescription: String {
            "\(spec) \(input.map { String(reflecting: $0) } ?? "nil")"
        }
    }

    static func range(_ min: Int, _ max: Int) -> [MultiplierValue] {
        (min...max).map { MultiplierValue(key: String($0), label: String($0)) }
    }

    /// Measured by the `ProbeSets` probe (output `sets-out.txt`).
    static let rows: [Row] = [
        // CQ
        .init(.cq, " 07 ", .valid("7"), expected: true),
        .init(.cq, "014", .valid("14"), expected: true),
        .init(.cq, "7\u{A}", .valid("7"), expected: true),
        .init(.cq, "+7", .invalid("očekáváno číslo: +7"), expected: true),
        .init(.cq, "-3", .invalid("očekáváno číslo: -3"), expected: false),
        .init(.cq, "99999999999", .invalid("neodpovídá formátu: 99999999999"), expected: false),
        .init(.cq, "\u{661}\u{664}", .invalid("očekáváno číslo: \u{661}\u{664}"), expected: true),
        .init(.cq, "\u{A0}7", .invalid("očekáváno číslo: \u{A0}7"), expected: false),
        .init(.cq, "7", .valid("7"), expected: true),
        .init(.cq, "40", .valid("40"), expected: true),
        .init(.cq, "41", .invalid("neodpovídá formátu: 41"), expected: false),
        .init(.cq, "0", .invalid("neodpovídá formátu: 0"), expected: false),
        .init(.cq, "", .invalid("prázdná hodnota"), expected: false),
        .init(.cq, "  ", .invalid("prázdná hodnota"), expected: false),
        .init(.cq, "\u{2003}", .invalid("prázdná hodnota"), expected: false),
        .init(.cq, "\u{A0}", .invalid("očekáváno číslo: \u{A0}"), expected: false),
        .init(.cq, nil, .invalid("prázdná hodnota"), expected: false),
        .init(.cq, "\u{FF11}\u{FF14}", .invalid("očekáváno číslo: \u{FF11}\u{FF14}"), expected: true),
        .init(.cq, "2147483647", .invalid("neodpovídá formátu: 2147483647"), expected: false),
        .init(.cq, "2147483648", .invalid("neodpovídá formátu: 2147483648"), expected: false),
        .init(.cq, "\u{2003}7\u{2003}", .invalid("očekáváno číslo: \u{2003}7\u{2003}"), expected: false),
        .init(.cq, "\u{B}7", .valid("7"), expected: true),
        .init(.cq, "\u{1C}7", .valid("7"), expected: true),
        .init(.cq, "0007", .valid("7"), expected: true),
        // INT
        .init(.integer, "99999999999", .valid("99999999999"), expected: false),
        // outside `int`: `parseInt` fails and the text stays with its zeros (a Swift `Int` would drop them)
        .init(.integer, "099999999999", .valid("099999999999"), expected: false),
        .init(.integer, "0002147483648", .valid("0002147483648"), expected: false),
        .init(.integer, "00003", .valid("3"), expected: true),
        .init(.integer, "\u{663}", .invalid("očekáváno číslo: \u{663}"), expected: true),
        .init(.integer, "+3", .invalid("očekáváno číslo: +3"), expected: true),
        .init(.integer, "03", .valid("3"), expected: true),
        .init(.integer, "3 ", .valid("3"), expected: true),
        .init(.integer, "x", .invalid("očekáváno číslo: x"), expected: false),
        .init(.integer, "-0", .invalid("očekáváno číslo: -0"), expected: false),
        // GRID
        .init(.grid, "jo80", .valid("JO"), expected: false),
        .init(.grid, " jo80 ", .valid("JO"), expected: false),
        .init(.grid, "JO80kk", .valid("JO"), expected: false),
        .init(.grid, "JO", .valid("JO"), expected: false),
        .init(.grid, "j", .valid("J"), expected: false),
        .init(.grid, "", .invalid("prázdná hodnota"), expected: false),
        .init(.grid, nil, .invalid("prázdná hodnota"), expected: false),
        // KL0
        .init(.keyLengthZero, "abc", .valid("ABC"), expected: false),
        .init(.keyLengthZero, "ab", .valid("AB"), expected: true),
        // KLNEG
        .init(.keyLengthNegative, "abc", .valid("ABC"), expected: false),
        // TEXT
        .init(.text, "straße", .valid("STRASSE"), expected: true),
        .init(.text, "STRASSE", .valid("STRASSE"), expected: true),
        .init(.text, "ab", .valid("AB"), expected: false),
        .init(.text, " ab ", .valid("AB"), expected: false),
        .init(.text, "x", .valid("X"), expected: false),
        .init(.text, "X", .valid("X"), expected: false),
        .init(.text, "\u{FB01}", .valid("FI"), expected: false),
        .init(.text, "\u{131}", .valid("I"), expected: false),
        .init(.text, "\u{A0}", .valid("\u{A0}"), expected: false),
        .init(.text, "\u{A0}x\u{A0}", .valid("\u{A0}X\u{A0}"), expected: false),
        // NULLTYPE
        .init(.nullKeyType, "ab", .valid("AB"), expected: true),
        .init(.nullKeyType, "01", .valid("01"), expected: false),
        // PAT_D
        .init(.patternDigit, "12", .valid("12"), expected: false),
        .init(.patternDigit, "\u{661}\u{662}", .invalid("neodpovídá formátu: \u{661}\u{662}"), expected: false),
        .init(.patternDigit, "\u{FF11}", .invalid("neodpovídá formátu: \u{FF11}"), expected: false),
        // PAT_S
        .init(.patternSpace, "a b", .valid("A B"), expected: false),
        .init(.patternSpace, "a\u{A0}b", .invalid("neodpovídá formátu: a\u{A0}b"), expected: false),
        .init(.patternSpace, "a\u{B}b", .valid("A\u{B}B"), expected: false),
        .init(.patternSpace, "a\u{1C}b", .invalid("neodpovídá formátu: a\u{1C}b"), expected: false),
        // PAT_DOT
        .init(.patternDot, "a\u{B}b", .valid("A\u{B}B"), expected: false),
        .init(.patternDot, "a\u{85}b", .invalid("neodpovídá formátu: a\u{85}b"), expected: false),
        .init(.patternDot, "a\u{2028}b", .invalid("neodpovídá formátu: a\u{2028}b"), expected: false),
        .init(.patternDot, "a\u{C}b", .valid("A\u{C}B"), expected: false),
        .init(.patternDot, "axb", .valid("AXB"), expected: false),
        // PAT_W
        .init(.patternWord, "abc", .valid("ABC"), expected: false),
        .init(.patternWord, "é", .invalid("neodpovídá formátu: é"), expected: false),
        .init(.patternWord, "É", .invalid("neodpovídá formátu: É"), expected: false),
        // PAT_INT_D
        .init(.patternDigitInteger, "\u{661}\u{664}", .invalid("očekáváno číslo: \u{661}\u{664}"), expected: false),
        .init(.patternDigitInteger, "14", .valid("14"), expected: false),
        // PAT_EMPTY
        .init(.patternEmpty, "a", .invalid("neodpovídá formátu: a"), expected: false),
        .init(.patternEmpty, " ", .invalid("prázdná hodnota"), expected: false),
        // PAT_PART
        .init(.patternWhole, "abc", .invalid("neodpovídá formátu: abc"), expected: false),
        .init(.patternWhole, "ab", .valid("AB"), expected: false),
        // PAT_CI
        .init(.patternCaseInsensitive, "abc", .valid("ABC"), expected: false),
        .init(.patternCaseInsensitive, "ČR", .invalid("neodpovídá formátu: ČR"), expected: false),
        // PAT_LOWER
        .init(.patternLowercase, "abc", .invalid("neodpovídá formátu: abc"), expected: false),
        // PAT_TRUNC
        .init(.patternThenTruncate, "jo80", .valid("JO"), expected: false),
        .init(.patternThenTruncate, "jo8", .invalid("neodpovídá formátu: jo8"), expected: false),
        // NULLKEY
        .init(.nullAndEmptyKey, "", .invalid("prázdná hodnota"), expected: true),
        .init(.nullAndEmptyKey, " ", .invalid("prázdná hodnota"), expected: true),
        .init(.nullAndEmptyKey, "x", .valid("X"), expected: false),
    ]

    @Test(arguments: rows)
    func normalizeAndIsExpectedMatchJava(_ row: Row) throws {
        let set = try row.spec.make()
        #expect(set.normalize(row.input) == row.resolution)
        #expect(set.isExpected(row.input) == row.expected)
    }

    /// Truncation to `keyLength` goes by UTF-16 units (`substring`). A whole pair
    /// fits, a split one does not: Java returns `"A\uD83D"` (a lone half),
    /// a Swift `String` cannot carry it and gives `U+FFFD` — a deliberate
    /// divergence from Java v1.1.1.
    @Test func keyLengthCutsUtf16Units() throws {
        let grid = try Spec.grid.make()
        #expect(grid.normalize("😀a") == .valid("😀"))
        #expect(grid.normalize("a😀") == .valid("A\u{FFFD}"))
        #expect(grid.isExpected("a😀") == false)
    }

    @Test func emptySetClaimsEnumerableButExpectsNothing() throws {
        let set = try FixedMultiplierSet(id: "e", keyType: .TEXT, values: [], keyPattern: nil)
        #expect(set.id == "e")
        #expect(set.enumerable)
        #expect(set.values.isEmpty)
        #expect(set.isExpected("A") == false)
        #expect(set.deriveFromCallsign("OK1XOE") == .unsupported)
    }

    /// Java `LinkedHashMap.put`: the last value wins, the first position stays.
    @Test func duplicateKeyKeepsFirstPositionAndLastValue() throws {
        let set = try FixedMultiplierSet(id: "d", keyType: .TEXT, values: [
            MultiplierValue(key: "B", label: "b1"),
            MultiplierValue(key: "A", label: "a"),
            MultiplierValue(key: "B", label: "b2"),
            MultiplierValue(key: "C", label: "c"),
        ], keyPattern: nil)
        #expect(set.values == [
            MultiplierValue(key: "B", label: "b2"),
            MultiplierValue(key: "A", label: "a"),
            MultiplierValue(key: "C", label: "c"),
        ])
    }

    /// Keys by UTF-16 like a Java `LinkedHashMap`, not canonically like a Swift dictionary:
    /// `K` and KELVIN SIGN (U+212A), `É` composed and decomposed are **different** values
    /// (formerly a divergence; in the UI it was visible via `QsoMarks`, the row
    /// `M kelvin` of the `ViewsMeasuredTests` table). A duplicate by UTF-16 still applies as `put`.
    @Test func canonicallyEqualKeysStayApartLikeJava() throws {
        let set = try FixedMultiplierSet(id: "k", keyType: .TEXT, values: [
            MultiplierValue(key: "K", label: "k1"),
            MultiplierValue(key: "\u{212A}", label: "kelvin"),
            MultiplierValue(key: "\u{00C9}", label: "nfc"),
            MultiplierValue(key: "K", label: "k2"),
        ], keyPattern: nil)
        #expect(set.values.map(\.label) == ["k2", "kelvin", "nfc"])
        #expect(set.values.map { $0.key.map { Array($0.utf16) } } == [[0x4B], [0x212A], [0xC9]])
        #expect(set.isExpected("k"))
        #expect(set.isExpected("\u{212A}"))
        #expect(set.isExpected("\u{00E9}"))
        #expect(!set.isExpected("E\u{0301}"), "decomposed É is not a set key")
        let onlyKelvin = try FixedMultiplierSet(id: "kv", keyType: .TEXT,
                                                values: [MultiplierValue(key: "\u{212A}", label: "kelvin")],
                                                keyPattern: nil)
        #expect(!onlyKelvin.isExpected("K"), "K is not KELVIN SIGN")
    }

    @Test func valuesKeepDefinitionOrderAndNullKey() throws {
        let set = try Spec.nullAndEmptyKey.make()
        #expect(set.id == nil)
        #expect(set.values == [MultiplierValue(key: nil, label: nil), MultiplierValue(key: "", label: "e")])
        #expect(try Spec.cq.make().values.map(\.key) == (1...40).map { String($0) })
    }

    /// A bad pattern fails the constructor, like Java `Pattern.compile`
    /// (`PatternSyntaxException`) — not only the first `normalize`.
    @Test func invalidKeyPatternFailsAtConstruction() {
        do {
            _ = try FixedMultiplierSet(id: "bad", keyType: .TEXT, values: [], keyPattern: "[")
            Issue.record("a bad keyPattern should have failed already in the constructor")
        } catch {
            guard case .invalidPattern(let pattern, let message) = error else {
                Issue.record("expected .invalidPattern, got \(error)")
                return
            }
            #expect(pattern == "[")
            // Java getMessage() verbatim
            #expect(message == "Unclosed character class near index 0\n[\n^")
        }
    }
}
