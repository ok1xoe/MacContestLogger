import Testing
@testable import MCLCore

/// `JavaFormat` against a table measured on JDK 21 (`JavaFormatMeasured.format`, probe
/// a maintainer-only probe): the specifiers used by
/// `io/` (`LogExports`, `AdifWriter`, `EdiExporter`) and `QtcPlanner.cabrilloLine`.
@Suite struct JavaFormatTests {

    /// The whole measured table — `%.1f`, `%9.1f`, `%.6f`, `%d` with widths, `%03d`,
    /// `%s` with widths by UTF-16 (non-ASCII, emoji, a combining character, `null`), `%n`
    /// and whole row patterns from `LogExports.text`/`summary` and `QtcPlanner.cabrilloLine`.
    @Test func matchesJavaMeasuredTable() {
        for row in JavaFormatMeasured.format {
            let actual = JavaFormat.format(row.pattern, arguments: row.args)
            #expect(actual == row.expected, "\(row.locale) \(row.pattern) \(String(describing: row.args))")
        }
    }

    /// Anchors measured on Java v1.1.1: where the Java HALF_UP over the decimal expansion
    /// diverges from C `printf` (`String(format:)` gives 14025.0, 14025.1, 7000.2, 1.4).
    @Test func halfUpOverShortestDecimal() {
        #expect(JavaFormat.format("%.1f", 14025.05) == "14025.1")
        #expect(JavaFormat.format("%.1f", 14025.15) == "14025.2")
        #expect(JavaFormat.format("%.1f", 7000.25) == "7000.3")
        #expect(JavaFormat.format("%.1f", 7000.35) == "7000.4")
        #expect(JavaFormat.format("%.1f", 1.45) == "1.5")
        #expect(JavaFormat.format("%.1f", 0.15) == "0.2")
        #expect(JavaFormat.format("%.1f", 2.675) == "2.7")
    }

    /// The sign by `Double.compare(value, 0.0)`: `-0.0` and a negative number
    /// rounded to zero carry it; `NaN`/`Infinity` are aligned as text.
    @Test func signsAndSpecialValues() {
        #expect(JavaFormat.format("%.1f", -0.04) == "-0.0")
        #expect(JavaFormat.format("%.6f", -0.0) == "-0.000000")
        #expect(JavaFormat.format("%9.1f", .double(.nan)) == "      NaN")
        #expect(JavaFormat.format("%9.1f", .double(-.infinity)) == "-Infinity")
        #expect(JavaFormat.format("%.1f", 9.95) == "10.0")
        #expect(JavaFormat.format("%.6f", 2.5e-7) == "0.000000")
        #expect(JavaFormat.format("%.6f", 5e-7) == "0.000001")
    }

    /// The `%s` width by UTF-16 units: emoji are 2, `é` from a combining mark 2.
    @Test func widthCountsUtf16Units() {
        #expect(JavaFormat.format("%-5s|", "Mód") == "Mód  |")
        #expect(JavaFormat.format("%5s", "😀") == "   😀")
        #expect(JavaFormat.format("%-6s|", "e\u{301}") == "e\u{301}    |")
        #expect(JavaFormat.format("%-4s|", .string(nil)) == "null|")
        #expect(JavaFormat.format("%-13s|", "K1ABCDEFGHIJKLMNOP") == "K1ABCDEFGHIJKLMNOP|")
    }

    /// `%03d` pads zeros after the sign; `%-2d` aligns left; `%n` is `\n`; `%%`.
    @Test func integersAndLiterals() {
        #expect(JavaFormat.format("%03d", -5) == "-05")
        #expect(JavaFormat.format("%03d", 7) == "007")
        #expect(JavaFormat.format("%03d", 12345) == "12345")
        #expect(JavaFormat.format("%3d/%-2d|", 3, 10) == "  3/10|")
        #expect(JavaFormat.format("%d", .int(Int.min)) == "-9223372036854775808")
        #expect(JavaFormat.format("a%nb%%") == "a\nb%")
        #expect(JavaFormat.format("násobiče %d · skóre", 3) == "násobiče 3 · skóre")
    }

    /// Patterns on which Java throws an exception: `format` would end in `preconditionFailure`,
    /// `failure` returns the same exception name as JDK 21 (and the order of checks).
    @Test func rejectsWhatJavaRejects() {
        for row in JavaFormatMeasured.rejected {
            #expect(JavaFormat.failure(row.pattern, arguments: row.args) == row.exception, "\(row.pattern)")
        }
        for row in JavaFormatMeasured.format {
            #expect(JavaFormat.failure(row.pattern, arguments: row.args) == nil, "\(row.pattern)")
        }
    }

    /// A notation Java accepts but `JavaFormat` does not — also a crash, not a silent different output.
    @Test func unsupportedJavaSyntaxIsRejected() {
        let unsupported: [(String, [JavaFormat.Arg])] = [
            ("%x", [.int(7)]), ("%+d", [.int(7)]), ("%,d", [.int(7)]), ("% d", [.int(7)]), ("%(d", [.int(7)]),
            ("%1$s", [.string("a")]), ("%S", [.string("a")]), ("%e", [.double(1)]), ("%tH", [.int(1)]),
            ("%#s", [.string("a")]), ("%<s", [.string("a")]),
        ]
        for (pattern, args) in unsupported {
            #expect(JavaFormat.failure(pattern, arguments: args) == JavaFormat.Failure.unsupported, "\(pattern)")
        }
    }

    /// `%.Ns` truncates by UTF-16 units; a cut in the middle of a pair gives in Java a lone
    /// half (`\uD83D`), which a Swift `String` does not carry → `U+FFFD`.
    @Test func precisionTruncatesUtf16Units() {
        #expect(JavaFormat.format("%.3s", "abcdef") == "abc")
        #expect(JavaFormat.format("%.2s", "😀x") == "😀")
        #expect(JavaFormat.format("%-5.2s|", .string(nil)) == "nu   |")
        #expect(JavaFormat.format("%.1s", "😀x") == "\u{FFFD}")
    }

    /// The `0` flag for `%f`: zeros after the sign, `NaN`/`Infinity` with spaces.
    @Test func zeroPadFixed() {
        #expect(JavaFormat.format("%09.1f", 14025.05) == "0014025.1")
        #expect(JavaFormat.format("%09.1f", -7.25) == "-000007.3")
        #expect(JavaFormat.format("%09.1f", .double(.nan)) == "      NaN")
        #expect(JavaFormat.format("%010.6f", .double(-.infinity)) == " -Infinity")
    }

    /// A single value without a pattern — the same as `%.Nf`.
    @Test func fixedMatchesFormat() {
        #expect(JavaFormat.fixed(14025.05, precision: 1) == "14025.1")
        #expect(JavaFormat.fixed(10368.100123, precision: 6) == "10368.100123")
        #expect(JavaFormat.fixed(1.0e23, precision: 1) == "100000000000000000000000.0")
        #expect(JavaFormat.fixed(-1.45, precision: 1) == "-1.5")
    }

    /// `JavaDouble.decimalDigits` (the fast path for `%f`) gives the same expansion as
    /// `significand` (verified against `Double.toString`) — random bit patterns
    /// over the whole range (a deterministic LCG) and edge values.
    @Test func decimalDigitsAgreeWithSignificand() {
        var values: [Double] = [Double.leastNonzeroMagnitude, .leastNormalMagnitude, .greatestFiniteMagnitude,
                                1e23, 5e-324, 0.1, 1, 10, 14025.05, 9_007_199_254_740_992]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for _ in 0..<20_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let value = Double(bitPattern: state >> 1)
            if value.isFinite && value > 0 { values.append(value) }
        }
        for value in values {
            let reference = JavaDouble.significand(value)
            let fast = JavaDouble.decimalDigits(value)
            let digits = String(decoding: fast.digits.map { $0 + 0x30 }, as: UTF8.self)
            #expect(digits == reference.digits && fast.exponent == reference.exponent, "\(value)")
        }
    }

    /// `null` for `%d` and `%f`: Java (`Formatter.printInteger`/`printFloat`) prints `"null"` like `%s` — it truncates the
    /// precision, pads the width with spaces, the `0` flag does not apply (found by the Java parity suite, `i18n.FMT`, JDK 21 values).
    @Test func nullArgumentOfNumericConversionPrintsNull() {
        #expect(JavaFormat.format("%d", .string(nil)) == "null")
        #expect(JavaFormat.format("%.1f", .string(nil)) == "n")
        #expect(JavaFormat.format("%05.1f", .string(nil)) == "    n")
        #expect(JavaFormat.format("%d%d", .string(nil), .int(3_000_000_000)) == "null3000000000")
    }
}
