import Testing
@testable import MCLCore

/// Tests of `JavaDouble.parseDouble` / `JavaDouble.parse` — Java
/// `Double.parseDouble(String)` including the `NumberFormatException` text.
///
/// All values are measured on JDK 21.0.2 (a probe over
/// `FloatingDecimal.readJavaFormatString`). The value is compared **bitwise**
/// (`-0.0` is not `0.0`), an error by the literal text of the exception message — that shows
/// `Expression` v UI.
@Suite struct JavaDoubleParseTests {

    /// Expectation: the result bits, or the `NumberFormatException` message text.
    enum Expected {
        case bits(UInt64)
        case error(String)
    }

    private static func check(_ input: String, _ expected: Expected,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        switch expected {
        case .bits(let bits):
            do {
                let value = try JavaDouble.parse(input)
                #expect(value.bitPattern == bits, "„\(input)\"", sourceLocation: sourceLocation)
            } catch {
                Issue.record("\"\(input)\" threw \(error.message)", sourceLocation: sourceLocation)
            }
            #expect(JavaDouble.parseDouble(input)?.bitPattern == bits, sourceLocation: sourceLocation)
        case .error(let message):
            do {
                let value = try JavaDouble.parse(input)
                Issue.record("\"\(input)\" gave \(value), an error was expected", sourceLocation: sourceLocation)
            } catch {
                #expect(error.message == message, "„\(input)\"", sourceLocation: sourceLocation)
            }
            #expect(JavaDouble.parseDouble(input) == nil, sourceLocation: sourceLocation)
        }
    }

    private static let one: UInt64 = 0x3FF0_0000_0000_0000
    private static let infinity: UInt64 = 0x7FF0_0000_0000_0000
    private static let negativeInfinity: UInt64 = 0xFFF0_0000_0000_0000
    private static let nan: UInt64 = 0x7FF8_0000_0000_0000
    private static let negativeZero: UInt64 = 0x8000_0000_0000_0000

    /// The basic table.
    @Test func briefTable() {
        let table: [(String, Expected)] = [
            ("1", .bits(Self.one)),
            (" 1 ", .bits(Self.one)),
            ("1e400", .bits(Self.infinity)),
            ("-0", .bits(Self.negativeZero)),
            ("NaN", .bits(Self.nan)),
            ("nan", .error("For input string: \"nan\"")),
            ("Infinity", .bits(Self.infinity)),
            ("inf", .error("For input string: \"inf\"")),
            ("0x1p3", .bits(0x4020_0000_0000_0000)),
            ("1d", .bits(Self.one)),
            ("1f", .bits(Self.one)),
            ("1_0", .error("For input string: \"1_0\"")),
            (".", .error("For input string: \".\"")),
            ("1.", .bits(Self.one)),
            (".5", .bits(0x3FE0_0000_0000_0000)),
            ("+.5e-3", .bits(0x3F40_624D_D2F1_A9FC)),
            ("", .error("empty String")),
            ("\u{0661}", .error("For input string: \"\u{0661}\"")),
            ("\u{00A0}1\u{00A0}", .error("For input string: \"\u{00A0}1\u{00A0}\"")),
        ]
        for (input, expected) in table {
            Self.check(input, expected)
        }
    }

    /// Sign, `NaN` and `Infinity` — only exactly as written, without a suffix.
    @Test func signsAndSpecialValues() {
        let table: [(String, Expected)] = [
            ("-NaN", .bits(Self.nan)),
            ("+NaN", .bits(Self.nan)),
            ("+Infinity", .bits(Self.infinity)),
            ("-Infinity", .bits(Self.negativeInfinity)),
            ("NaNd", .error("For input string: \"NaNd\"")),
            ("Infinityf", .error("For input string: \"Infinityf\"")),
            ("Nan", .error("For input string: \"Nan\"")),
            ("INFINITY", .error("For input string: \"INFINITY\"")),
            ("NaN ", .bits(Self.nan)),
            ("+", .error("For input string: \"+\"")),
            ("-", .error("For input string: \"-\"")),
            ("  ", .error("empty String")),
            ("-.0", .bits(Self.negativeZero)),
            ("0.0e0", .bits(0)),
        ]
        for (input, expected) in table {
            Self.check(input, expected)
        }
    }

    /// Decimal notation: dots, exponent, type suffix, trailing garbage.
    @Test func decimalGrammar() {
        let table: [(String, Expected)] = [
            ("1..2", .error("multiple points")),
            ("1.2.3", .error("multiple points")),
            ("..", .error("multiple points")),
            (" 1..2 ", .error("multiple points")),
            ("1e", .error("For input string: \"1e\"")),
            ("1e+", .error("For input string: \"1e+\"")),
            ("1e5x", .error("For input string: \"1e5x\"")),
            ("1e5d", .bits(0x40F8_6A00_0000_0000)),
            ("1ed", .error("For input string: \"1ed\"")),
            ("1e5.5", .error("For input string: \"1e5.5\"")),
            ("1e0x", .error("For input string: \"1e0x\"")),
            ("e5", .error("For input string: \"e5\"")),
            ("-.e1", .error("For input string: \"-.e1\"")),
            ("1,5", .error("For input string: \"1,5\"")),
            ("1 0", .error("For input string: \"1 0\"")),
            ("\u{0661}\u{0664}", .error("For input string: \"\u{0661}\u{0664}\"")),
            ("1E2", .bits(0x4059_0000_0000_0000)),
            ("007", .bits(0x401C_0000_0000_0000)),
            ("0.1", .bits(0x3FB9_9999_9999_999A)),
            ("1e-5", .bits(0x3EE4_F8B5_88E3_68F1)),
            ("1.00000005E7", .bits(0x4163_12D0_1000_0000)),
            ("9007199254740993", .bits(0x4340_0000_0000_0000)),
        ]
        for (input, expected) in table {
            Self.check(input, expected)
        }
    }

    /// Range edges: underflow to zero, overflow to infinity, a huge exponent.
    @Test func rangeEdges() {
        let table: [(String, Expected)] = [
            ("1e-400", .bits(0)),
            ("-1e400", .bits(Self.negativeInfinity)),
            ("1e99999999999", .bits(Self.infinity)),
            ("1e-99999999999", .bits(0)),
            ("4.9e-324", .bits(1)),
            ("2.4703282292062328e-324", .bits(1)),
            ("1.7976931348623158e308", .bits(0x7FEF_FFFF_FFFF_FFFF)),
            ("1.7976931348623159e308", .bits(Self.infinity)),
        ]
        for (input, expected) in table {
            Self.check(input, expected)
        }
    }

    /// Hexadecimal notation: the exponent `p` is mandatory, ASCII digits only, no `_`.
    @Test func hexadecimalGrammar() {
        let table: [(String, Expected)] = [
            ("0x10", .error("For input string: \"0x10\"")),
            ("0x", .error("For input string: \"0x\"")),
            ("0x1p", .error("For input string: \"0x1p\"")),
            ("0x.p1", .error("For input string: \"0x.p1\"")),
            ("00x1p3", .error("For input string: \"00x1p3\"")),
            ("0x1_0p1", .error("For input string: \"0x1_0p1\"")),
            ("0x1p1_0", .error("For input string: \"0x1p1_0\"")),
            ("0x.8p1", .bits(Self.one)),
            ("0x1.8p1", .bits(0x4008_0000_0000_0000)),
            ("-0x1p3", .bits(0xC020_0000_0000_0000)),
            ("0x1p3d", .bits(0x4020_0000_0000_0000)),
            ("0X1P-2F", .bits(0x3FD0_0000_0000_0000)),
            ("0x1p99999999999", .bits(Self.infinity)),
            ("0x1p-1075", .bits(0)),
            ("0x1p-1074", .bits(1)),
            ("0x1.fffffffffffff8p1023", .bits(Self.infinity)),
            ("0x1.fffffffffffff7p1023", .bits(0x7FEF_FFFF_FFFF_FFFF)),
        ]
        for (input, expected) in table {
            Self.check(input, expected)
        }
    }

    /// Trimming is Java `trim()` (everything `<= U+0020`, so also `U+0000`), not
    /// `Character.isWhitespace`: `U+0085` and NBSP are not trimmed. The error
    /// message already carries the **trimmed** text.
    @Test func trimIsJavaTrimAndMessageIsTrimmed() {
        let table: [(String, Expected)] = [
            ("\t5\n", .bits(0x4014_0000_0000_0000)),
            ("5 ", .bits(0x4014_0000_0000_0000)),
            ("\u{0000} 1", .bits(Self.one)),
            ("\u{0085} 1", .error("For input string: \"\u{0085} 1\"")),
            (" abc ", .error("For input string: \"abc\"")),
            ("\t0x1\n", .error("For input string: \"0x1\"")),
        ]
        for (input, expected) in table {
            Self.check(input, expected)
        }
    }

    /// Earlier copies in `CtyDxccResolver` and in the YAML decoder delegate here.
    @Test func formerCopiesDelegate() {
        #expect(CtyDxccResolver.javaParseDouble("0x1p3d") == 8.0)
        #expect(CtyDxccResolver.javaParseDouble("nan") == nil)
        #expect(JacksonCoercion.parseDouble("1f") == 1.0)
        #expect(JacksonCoercion.parseDouble("inf") == nil)
    }
}
