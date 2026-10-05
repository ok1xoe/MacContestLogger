import Foundation
import Testing
@testable import MCLCore

/// `FrequencyText` against JDK 21 + kotlin-stdlib 2.1.20 (maintainer-only probe, `entry-probe.tsv`):
/// the private `parseFreqHz` of `ui/EntryPanel.kt:1989-1992` called via reflection, Kotlin
/// `String.toDoubleOrNull`/`toIntOrNull` and `String.format(Locale.US, "%.2f", …)`.
@Suite struct FrequencyTextTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let input: String
        let hz: Int64
        /// Kotlin `input.toDoubleOrNull()` on the raw (untrimmed) input.
        let double: Double?
        init(_ input: String, _ hz: Int64, _ double: Double?) {
            self.input = input
            self.hz = hz
            self.double = double
        }
        var testDescription: String { input.debugDescription }
    }

    struct IntCase: Sendable, CustomTestStringConvertible {
        let input: String
        /// Kotlin `input.toIntOrNull()`.
        let raw: Int32?
        /// Kotlin `input.trim().toIntOrNull()`.
        let trimmed: Int32?
        init(_ input: String, _ raw: Int32?, _ trimmed: Int32?) {
            self.input = input
            self.raw = raw
            self.trimmed = trimmed
        }
        var testDescription: String { input.debugDescription }
    }

    static let freqCases: [Case] = [
        Case("", 0, nil),
        Case("\u{0020}", 0, nil),
        Case("14074", 14074000, 14074.0),
        Case("14074.0", 14074000, 14074.0),
        Case("14074,5", 14074500, nil),
        Case("\u{0020}14074.25\u{0020}", 14074250, 14074.25),
        Case("14074.0005", 14074001, 14074.0005),
        Case("14074.0004999", 14074000, 14074.0004999),
        Case("0.0005", 1, 5.0E-4),
        Case("-0.0005", 0, -5.0E-4),
        Case("-0.0015", -1, -0.0015),
        Case("0.0015", 2, 0.0015),
        Case("-14074", -14074000, -14074.0),
        Case("+14074", 14074000, 14074.0),
        Case("1e3", 1000000, 1000.0),
        Case("1E3", 1000000, 1000.0),
        Case("1.5e-3", 2, 0.0015),
        Case("NaN", 0, .nan),
        Case("-NaN", 0, .nan),
        Case("Infinity", 9223372036854775807, .infinity),
        Case("-Infinity", -9223372036854775808, -.infinity),
        Case("+Infinity", 9223372036854775807, .infinity),
        Case("infinity", 0, nil),
        Case("nan", 0, nil),
        Case("inf", 0, nil),
        Case("0x1p3", 8000, 8.0),
        Case("0x1.8p1", 3000, 3.0),
        Case("0X10P0", 16000, 16.0),
        Case("0x10", 0, nil),
        Case("14074d", 14074000, 14074.0),
        Case("14074f", 14074000, 14074.0),
        Case("14074D", 14074000, 14074.0),
        Case("14074F", 14074000, 14074.0),
        Case("14074df", 0, nil),
        Case("1e19", 9223372036854775807, 1.0E19),
        Case("-1e19", -9223372036854775808, -1.0E19),
        Case("9.3e15", 9223372036854775807, 9.3E15),
        Case("9.3e18", 9223372036854775807, 9.3E18),
        Case("1e300", 9223372036854775807, 1.0E300),
        Case("14,074.5", 0, nil),
        Case("14.074.5", 0, nil),
        Case("1_000", 0, nil),
        Case(".5", 500, 0.5),
        Case("5.", 5000, 5.0),
        Case(".", 0, nil),
        Case("e5", 0, nil),
        Case("1e", 0, nil),
        Case("\u{00A0}14074\u{00A0}", 14074000, nil),
        Case("\u{2000}14074", 14074000, nil),
        Case("\u{0001}14074", 14074000, 14074.0),
        Case("14074\u{0085}", 0, nil),
        Case("\u{0661}\u{0664}", 0, nil),
        Case("14074\u{0020}", 14074000, 14074.0),
        Case("\u{0009}14074\u{000A}", 14074000, 14074.0),
        Case("1\u{0020}4074", 0, nil),
        Case("14074kHz", 0, nil),
        Case("3.5e3", 3500000, 3500.0),
        Case("7000.00", 7000000, 7000.0),
        Case("0.0004999999999999999", 0, 4.999999999999999E-4),
        Case("2.5e-3", 3, 0.0025),
        Case("-2.5e-3", -2, -0.0025),
        Case("1.0000005", 1000, 1.0000005),
        Case("4.5e-4", 0, 4.5E-4),
        Case("5e-4", 1, 5.0E-4),
        Case("1e-7", 0, 1.0E-7),
    ]

    static let intCases: [IntCase] = [
        IntCase("", nil, nil),
        IntCase("\u{0020}", nil, nil),
        IntCase("1", 1, 1),
        IntCase("+1", 1, 1),
        IntCase("-1", -1, -1),
        IntCase("+", nil, nil),
        IntCase("-", nil, nil),
        IntCase("007", 7, 7),
        IntCase("2147483647", 2147483647, 2147483647),
        IntCase("2147483648", nil, nil),
        IntCase("-2147483648", -2147483648, -2147483648),
        IntCase("-2147483649", nil, nil),
        IntCase("+2147483647", 2147483647, 2147483647),
        IntCase("1\u{0020}2", nil, nil),
        IntCase("1.0", nil, nil),
        IntCase("1e3", nil, nil),
        IntCase("\u{0661}\u{0662}", 12, 12),
        IntCase("\u{FF11}\u{FF12}", 12, 12),
        IntCase("0x10", nil, nil),
        IntCase("12a", nil, nil),
        IntCase("a12", nil, nil),
        IntCase("--1", nil, nil),
        IntCase("+-1", nil, nil),
        IntCase("99999999999", nil, nil),
        IntCase("\u{00A0}12", nil, 12),
        IntCase("12\u{00A0}", nil, 12),
        IntCase("\u{0020}12\u{0020}", nil, 12),
    ]

    /// Raw `double` bits → `String.format(Locale.US, "%.2f", value)`.
    static let formatCases: [(UInt64, String)] = [
        (0x0000000000000000, "0.00"),
        (0x40CB7D0000000000, "14074.00"),
        (0x40CB7D00A3D70A3D, "14074.01"),
        (0x40CB7D01EB851EB8, "14074.02"),
        (0x40CB7D0333333333, "14074.03"),
        (0x40CB7D1000000000, "14074.13"),
        (0x3F747AE147AE147B, "0.01"),
        (0x3F8EB851EB851EB8, "0.02"),
        (0x3F9999999999999A, "0.03"),
        (0x3FF0147AE147AE14, "1.01"),
        (0x4005666666666666, "2.68"),
        (0xBF747AE147AE147B, "-0.01"),
        (0x8000000000000000, "-0.00"),
        (0x4415AF1D78B58C40, "100000000000000000000.00"),
        (0x3DDB7CDFD9D7BDBB, "0.00"),
        (0x40AB580000000000, "3500.00"),
        (0x40BB5801479D4D83, "7000.00"),
        (0x4101997000000000, "144174.00"),
        (0x411A676000000000, "432600.00"),
        (0x40CB587F5C28F5C3, "14001.00"),
        (0x7FF8000000000000, "NaN"),
        (0x7FF0000000000000, "Infinity"),
        (0xFFF0000000000000, "-Infinity"),
        (0x4132D687E4189375, "1234567.89"),
        (0x4023FD70A3D70A3D, "10.00"),
        (0x3FC0000000000000, "0.13"),
    ]

    @Test(arguments: freqCases) func parseHzMatchesKotlin(_ c: Case) {
        #expect(FrequencyText.parseHz(c.input) == c.hz)
    }

    @Test(arguments: freqCases) func toDoubleOrNullMatchesKotlin(_ c: Case) {
        let actual: Double? = KotlinNumber.toDoubleOrNull(c.input)
        if let expected = c.double, expected.isNaN {
            #expect(actual?.isNaN == true)
        } else {
            #expect(actual == c.double)
        }
    }

    @Test(arguments: intCases) func toIntOrNullMatchesKotlin(_ c: IntCase) {
        #expect(KotlinNumber.toIntOrNull(c.input) == c.raw)
        #expect(KotlinNumber.toIntOrNull(KotlinText.trim(c.input)) == c.trimmed)
    }

    @Test func formatKHzMatchesJavaFormat() {
        for (bits, expected) in Self.formatCases {
            let value = Double(bitPattern: bits)
            #expect(FrequencyText.formatKHz(value) == expected, "value \(value)")
        }
    }

    /// `EntryPanel.kt:194, 801`: `String.format(Locale.US, "%.2f", hz / 1000.0)`.
    @Test func formatHzDividesByThousand() {
        #expect(FrequencyText.formatHz(14_074_000) == "14074.00")
        #expect(FrequencyText.formatHz(14_074_005) == "14074.01")
        #expect(FrequencyText.formatHz(7_000_004) == "7000.00")
        #expect(FrequencyText.formatHz(0) == "0.00")
        #expect(FrequencyText.formatHz(-1_500) == "-1.50")
    }

    /// The entry panel's guard (`EntryPanel.kt:193`) formats a tuned frequency and parses it back.
    @Test func formatThenParseKeepsTenHertzResolution() {
        #expect(FrequencyText.parseHz(FrequencyText.formatHz(14_074_000)) == 14_074_000)
        #expect(FrequencyText.parseHz(FrequencyText.formatHz(14_074_123)) == 14_074_120)
    }
}
