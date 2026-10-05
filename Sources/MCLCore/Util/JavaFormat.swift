/// Subset of Java's `String.format` (`java.util.Formatter`) used by
/// the `io/` package (and `LogStatistics.pivot`, `QtcPlanner.cabrilloLine`).
///
/// Why not `String(format:)` (measured):
/// - Java's `%.Nf` rounds the **HALF_UP decimal decomposition** that `DoubleToDecimal`
///   assigns to a `double` (the same digits as `Double.toString`), whereas
///   C `printf` rounds the exact binary value to the nearest even:
///   `14025.05` → Java `14025.1`, `printf` `14025.0`; `0.15` → `0.2` vs `0.1`;
///   `2.5e-7` with `%.6f` → both `0.000000`;
/// - Java width (`%-5s`, `%9.1f`) is counted in **UTF-16 units**
///   (`"😀"` has 2), `String(format: "%-5s")` with non-ASCII gives garbage;
/// - `-0.0` and negative numbers that round to zero keep the sign
///   (`%.1f` of `-0.04` is `-0.0`), `NaN`/`Infinity` literally and aligned.
///
/// Locale: the output is locale-independent and matches Java under `en_US`
/// and `cs_CZ` for all supported specifiers — Java calls `%f` everywhere
/// with `Locale.US`/`ROOT` (point), `%d` gives ASCII digits under both (measured
/// also for `%03d` without locale in `EdiExporter`; in `ar_EG` Java would write `٠٠١`).
///
/// Supported (all measured against JDK 21, `JavaFormatMeasured.format`):
/// - `%%` (with `-` and width), `%n` (`\n` as on macOS);
/// - `%s` with `-`, width and precision — precision truncates to N **UTF-16 units**
///   (`%.1s` of `"😀x"` gives a lone half of a pair in Java; Swift's `String` does not
///   carry it, so `U+FFFD` comes out here — see `JavaChar.string`);
/// - `%d` with `-`, `0` and width (zeros after the sign: `%03d` of `-5` is `-05`);
/// - `%f` with `-`, `0`, width and precision (zeros after the sign: `%09.1f` of `-7.25`
///   is `-000007.3`; `NaN`/`Infinity` are padded with spaces even with `0`).
///
/// A notation for which Java would throw an exception (`%05s`, `%.2d`, `%-05d`, `%-d`,
/// `%0d`, `%--5d`, `%5n`, a missing or mismatched argument…) is a programmer
/// error — patterns are literals in the sources — and ends in `preconditionFailure` with the name
/// of the Java exception. Likewise a notation that Java accepts but is not supported here (`%x`, `%+d`,
/// `%,d`, `%1$s`, `%tH`…). `failure(_:arguments:)` detects this without crashing.
enum JavaFormat {

    /// Format argument. `%d` takes `int`, `%f` `double`, `%s` anything
    /// (`nil` as Java `null` → text `null`, also for `%d` and `%f`).
    enum Arg: Sendable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
        ExpressibleByStringLiteral {
        case int(Int)
        case double(Double)
        case string(String?)

        init(integerLiteral value: Int) { self = .int(value) }
        init(floatLiteral value: Double) { self = .double(value) }
        init(stringLiteral value: String) { self = .string(value) }
    }

    /// Why `String.format` would fail: the name of the Java exception
    /// (`MissingFormatWidthException`…), or `unsupported` for a notation
    /// that Java accepts but `JavaFormat` cannot handle.
    struct Failure: Error, Equatable, Sendable {
        static let unsupported = "unsupported"
        let javaClass: String
    }

    /// `String.format(Locale.ROOT, pattern, args…)`.
    static func format(_ pattern: String, _ args: Arg...) -> String {
        format(pattern, arguments: args)
    }

    /// `String.format(Locale.ROOT, pattern, args)`.
    static func format(_ pattern: String, arguments args: [Arg]) -> String {
        do {
            return try render(pattern, args)
        } catch {
            preconditionFailure("JavaFormat: " + error.javaClass + " ve vzoru " + pattern)
        }
    }

    /// Name of the Java exception that `String.format(pattern, args)` would throw
    /// (or `unsupported`), otherwise `nil` — for tests without crashing.
    static func failure(_ pattern: String, arguments args: [Arg]) -> String? {
        do {
            _ = try render(pattern, args)
            return nil
        } catch {
            return error.javaClass
        }
    }

    /// `%.<precision>f` of a single value (without width).
    static func fixed(_ value: Double, precision: Int) -> String {
        if value.isNaN { return "NaN" }
        // Java: `Double.compare(value, 0.0) == -1`, so also `-0.0`.
        let sign = value.sign == .minus ? "-" : ""
        if value.isInfinite { return sign + "Infinity" }
        if value == 0 {
            return sign + "0" + (precision > 0 ? "." + String(repeating: "0", count: precision) : "")
        }
        return sign + plain(abs(value), precision: precision)
    }

    // MARK: - Pattern parsing (Formatter.parse + FormatSpecifier.check*)

    private struct Spec {
        var leftJustify = false
        var zeroPad = false
        var width: Int?
        var precision: Int?
        var conversion: Unicode.Scalar = "%"
    }

    private enum Segment {
        case text(String)
        case spec(Spec)
    }

    /// The whole pattern is parsed and validated before anything is formatted — like
    /// `Formatter.parse`, so a notation error wins over an argument error.
    private static func render(_ pattern: String, _ args: [Arg]) throws(Failure) -> String {
        let segments = try parse(Array(pattern.unicodeScalars))
        var out = ""
        var next = 0
        for segment in segments {
            switch segment {
            case .text(let text):
                out += text
            case .spec(let spec):
                switch spec.conversion {
                case "%":
                    out += justify("%", spec)
                case "n":
                    out += "\n"
                default:
                    guard next < args.count else { throw Failure(javaClass: "MissingFormatArgumentException") }
                    out += try convert(args[next], spec)
                    next += 1
                }
            }
        }
        return out
    }

    private static func parse(_ scalars: [Unicode.Scalar]) throws(Failure) -> [Segment] {
        var segments: [Segment] = []
        var literal = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "%" else {
                literal.append(scalars[index])
                index += 1
                continue
            }
            if !literal.isEmpty {
                segments.append(.text(String(literal)))
                literal = String.UnicodeScalarView()
            }
            let spec = try parseSpec(scalars, &index)
            try check(spec)
            segments.append(.spec(spec))
        }
        if !literal.isEmpty { segments.append(.text(String(literal))) }
        return segments
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x30 && scalar.value <= 0x39
    }

    /// `%(\d+\$)?([-#+ 0,(<]*)?(\d+)?(\.\d+)?([tT])?([a-zA-Z%])` from `index` (at `%`).
    private static func parseSpec(_ scalars: [Unicode.Scalar], _ index: inout Int) throws(Failure) -> Spec {
        let unknown = Failure(javaClass: "UnknownFormatConversionException")
        var i = index + 1
        guard i < scalars.count else { throw unknown }
        var spec = Spec()
        // Argument index `1$` — Java accepts it, it is not used here.
        var probe = i
        while probe < scalars.count && isDigit(scalars[probe]) { probe += 1 }
        if probe > i && probe < scalars.count && scalars[probe] == "$" {
            throw Failure(javaClass: Failure.unsupported)
        }
        var seen: Set<UInt32> = []
        var otherFlag = false
        while i < scalars.count && "-#+ 0,(<".unicodeScalars.contains(scalars[i]) {
            let flag = scalars[i]
            guard seen.insert(flag.value).inserted else {
                throw Failure(javaClass: "DuplicateFormatFlagsException")
            }
            switch flag {
            case "-": spec.leftJustify = true
            case "0": spec.zeroPad = true
            default: otherFlag = true
            }
            i += 1
        }
        spec.width = readNumber(scalars, &i)
        if i < scalars.count && scalars[i] == "." {
            i += 1
            spec.precision = readNumber(scalars, &i)
            guard spec.precision != nil else { throw unknown }
        }
        guard i < scalars.count else { throw unknown }
        let conversion = scalars[i]
        let isLetter = (conversion.value >= 0x41 && conversion.value <= 0x5A)
            || (conversion.value >= 0x61 && conversion.value <= 0x7A)
        guard isLetter || conversion == "%" else { throw unknown }
        if conversion == "t" || conversion == "T" {
            throw Failure(javaClass: Failure.unsupported)
        }
        guard "bBhHsScCdoxXeEfgGaA%n".unicodeScalars.contains(conversion) else { throw unknown }
        guard "sdf%n".unicodeScalars.contains(conversion), !otherFlag else {
            throw Failure(javaClass: Failure.unsupported)
        }
        spec.conversion = conversion
        index = i + 1
        return spec
    }

    private static func readNumber(_ scalars: [Unicode.Scalar], _ index: inout Int) -> Int? {
        var value: Int?
        while index < scalars.count && isDigit(scalars[index]) {
            value = (value ?? 0) * 10 + Int(scalars[index].value - 0x30)
            index += 1
        }
        return value
    }

    /// `checkGeneral` / `checkInteger` / `checkFloat` / `checkText` in Java's order.
    private static func check(_ spec: Spec) throws(Failure) {
        switch spec.conversion {
        case "s":
            if spec.width == nil && spec.leftJustify {
                throw Failure(javaClass: "MissingFormatWidthException")
            }
            if spec.zeroPad { throw Failure(javaClass: "FormatFlagsConversionMismatchException") }
        case "d", "f":
            if spec.width == nil && (spec.leftJustify || spec.zeroPad) {
                throw Failure(javaClass: "MissingFormatWidthException")
            }
            if spec.leftJustify && spec.zeroPad { throw Failure(javaClass: "IllegalFormatFlagsException") }
            if spec.conversion == "d" && spec.precision != nil {
                throw Failure(javaClass: "IllegalFormatPrecisionException")
            }
        case "%":
            if spec.precision != nil { throw Failure(javaClass: "IllegalFormatPrecisionException") }
            if spec.zeroPad { throw Failure(javaClass: "IllegalFormatFlagsException") }
            if spec.width == nil && spec.leftJustify {
                throw Failure(javaClass: "MissingFormatWidthException")
            }
        default: // "n"
            if spec.precision != nil { throw Failure(javaClass: "IllegalFormatPrecisionException") }
            if spec.width != nil { throw Failure(javaClass: "IllegalFormatWidthException") }
            if spec.leftJustify || spec.zeroPad { throw Failure(javaClass: "IllegalFormatFlagsException") }
        }
    }

    // MARK: - Conversions

    private static func convert(_ arg: Arg, _ spec: Spec) throws(Failure) -> String {
        switch (spec.conversion, arg) {
        case ("d", .int(let value)):
            return zeroPadded(String(value), negative: value < 0, spec)
        case ("f", .double(let value)):
            let text = fixed(value, precision: spec.precision ?? 6)
            return value.isFinite ? zeroPadded(text, negative: value.sign == .minus, spec) : justify(text, spec)
        case ("s", .string(let value)):
            return string(value ?? "null", spec)
        case ("s", .int(let value)):
            return string(String(value), spec)
        case ("s", .double(let value)):
            return string(JavaDouble.toString(value), spec)
        case ("d", .string(nil)), ("f", .string(nil)):
            // `printInteger`/`printFloat`: prints `null` like `%s` (precision truncates, `0` does not apply)
            return string("null", spec)
        default:
            throw Failure(javaClass: "IllegalFormatConversionException")
        }
    }

    /// `%s`: precision truncates to N UTF-16 units (`substring(0, precision)`).
    private static func string(_ text: String, _ spec: Spec) -> String {
        guard let precision = spec.precision, precision < text.utf16.count else {
            return justify(text, spec)
        }
        return justify(JavaChar.string(Array(text.utf16.prefix(precision))), spec)
    }

    /// Flag `0`: zeros between the sign and digits up to the width (`localizedMagnitude`), otherwise spaces.
    private static func zeroPadded(_ text: String, negative: Bool, _ spec: Spec) -> String {
        guard spec.zeroPad, let width = spec.width, text.utf16.count < width else {
            return justify(text, spec)
        }
        let zeros = String(repeating: "0", count: width - text.utf16.count)
        return negative ? "-" + zeros + text.dropFirst() : zeros + text
    }

    /// Pads with spaces to the width in UTF-16 units (`Formatter.appendJustified`).
    private static func justify(_ text: String, _ spec: Spec) -> String {
        guard let width = spec.width else { return text }
        let length = text.utf16.count
        guard length < width else { return text }
        let padding = String(repeating: " ", count: width - length)
        return spec.leftJustify ? text + padding : padding + text
    }

    // MARK: - %.Nf

    /// `FormattedFPDecimal.plain` + `Formatter.addZeros` for a finite positive
    /// `magnitude`: decimal decomposition from `JavaDouble.significand`, rounded
    /// HALF_UP to `precision` decimal places, always with exactly that many places.
    private static func plain(_ magnitude: Double, precision: Int) -> String {
        let decimal = JavaDouble.decimalDigits(magnitude)
        if let text = plainInteger(decimal.digits, decimal.exponent, precision: precision) {
            return text
        }
        return plainDigits(decimal.digits, decimal.exponent, precision: precision)
    }

    private static let powersOfTen: [UInt64] = (0...19).map { power in
        var value: UInt64 = 1
        for _ in 0..<power { value *= 10 }
        return value
    }

    /// Fast path in integers like `FormattedFPDecimal.round` (`(f + 10^k/2) / 10^k`),
    /// when the result fits into 18 digits; otherwise `nil` and it is computed digit by digit.
    private static func plainInteger(_ digits: [UInt8], _ exponent: Int, precision: Int) -> String? {
        let count = digits.count
        guard count <= 18 else { return nil }
        var significand: UInt64 = 0
        for digit in digits {
            significand = significand * 10 + UInt64(digit)
        }
        // Value × 10^precision = significand × 10^scale.
        let scale = exponent - (count - 1) + precision
        let scaled: UInt64
        if scale >= 0 {
            guard count + scale <= 18 else { return nil }
            scaled = significand * powersOfTen[scale]
        } else if -scale <= 19 {
            let divisor = powersOfTen[-scale]
            scaled = significand / divisor + (significand % divisor >= divisor / 2 ? 1 : 0)
        } else {
            scaled = 0
        }
        var text = Array(String(scaled).utf8)
        if text.count <= precision {
            text.insert(contentsOf: [UInt8](repeating: 0x30, count: precision + 1 - text.count), at: 0)
        }
        if precision > 0 {
            text.insert(0x2E, at: text.count - precision)
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// General path over decimal digits (large numbers, large precision).
    private static func plainDigits(_ digits: [UInt8], _ exponent: Int, precision: Int) -> String {
        // Digits at positions 10^high … 10^-precision; outside the decomposition there are zeros.
        let high = max(exponent, 0)
        var out = [UInt8](repeating: 0, count: high + precision + 1)
        for index in digits.indices {
            let slot = high - exponent + index
            if slot < out.count { out[slot] = digits[index] }
        }
        // HALF_UP: the first discarded digit decides (the decomposition is finite and exact).
        var integerCount = high + 1
        let roundIndex = exponent + precision + 1
        if roundIndex >= 0 && roundIndex < digits.count && digits[roundIndex] >= 5 {
            var index = out.count - 1
            while index >= 0 && out[index] == 9 {
                out[index] = 0
                index -= 1
            }
            if index >= 0 {
                out[index] += 1
            } else {
                out.insert(1, at: 0)
                integerCount += 1
            }
        }
        var start = 0
        while start < integerCount - 1 && out[start] == 0 { start += 1 }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(out.count + 1)
        for index in start..<integerCount {
            bytes.append(out[index] + 0x30)
        }
        if precision > 0 {
            bytes.append(0x2E)
            for index in integerCount..<out.count {
                bytes.append(out[index] + 0x30)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
