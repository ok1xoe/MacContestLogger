/// `String.format(locale, pattern, args)` for `tr(cs, args)` (Kotlin `tr(cs).format(*args)`, `I18n.kt:55`) —
/// the pattern is a **translation from the user's file**, so nothing may crash here: `render` returns `nil` wherever
/// Java would throw an exception, and also where Java accepts the notation but it is not supported here (not `preconditionFailure` like
/// `JavaFormat.format`).
///
/// Parsing like JDK 21 `Formatter.parse` (`%[index$][flags][width][.precision][tT]conversion`, flag `<` =
/// previous argument, `%%`/`%n` take no argument and ignore an explicit index) and argument order like
/// `Formatter.format` (the ordinary index grows only for specifiers without an index, `%2$s %s` takes the 2nd and then the 1st).
/// Each specifier is then formatted by `JavaFormat` (measured `%s`, `%d`, `%f`, `%%`, `%n` with `-`, `0`,
/// width, precision). In addition:
/// - `%S`: precision, then upper case (`JavaText.toUpperCase`, ß → SS), then width (`Formatter.print`);
/// - `%f`: the decimal separator of the **default locale** (`cs_CZ` comma, `en_US` dot) — the caller passes it;
///   digits stay ASCII (locales with other digits, e.g. `ar_EG`, are not emulated).
///
/// Not supported (→ `nil`, Java would succeed): `%x %X %o %e %E %g %G %a %A %b %B %c %C %h %H`, `%t…`, flags
/// `+ ␣ ( , #`, width or precision above 100 000. Measured by the `T.format` rows of the maintainer-only probe.
enum TranslationFormat {

    static let maxWidth = 100_000

    private struct Spec {
        var explicitIndex: Int?
        var previous = false
        var flags = ""
        var width = ""
        var precision = ""
        var conversion: Unicode.Scalar = "s"
    }

    static func render(_ pattern: String, _ args: [Translator.Arg], decimalSeparator: String) -> String? {
        let scalars: [Unicode.Scalar] = Array(pattern.unicodeScalars)
        var out = ""
        var last = -1
        var lastOrdinary = -1
        var i = 0
        while i < scalars.count {
            let c: Unicode.Scalar = scalars[i]
            if c != "%" {
                out.unicodeScalars.append(c)
                i += 1
                continue
            }
            guard let spec = parseSpec(scalars, &i) else { return nil }
            if spec.conversion == "%" || spec.conversion == "n" {
                guard let text = text(spec) else { return nil }
                out += text
                continue
            }
            let index: Int
            if spec.previous {
                index = last
            } else if let explicit = spec.explicitIndex {
                index = explicit - 1
            } else {
                lastOrdinary += 1
                index = lastOrdinary
            }
            last = index
            guard index >= 0, index < args.count else { return nil }
            guard let text = argument(spec, args[index].javaFormat, decimalSeparator) else { return nil }
            out += text
        }
        return out
    }

    // MARK: - parsing

    /// Specifier from `%` at `i`; moves `i` past it. `nil` = a Java exception during parsing
    /// (`UnknownFormatConversion`, `IllegalFormatArgumentIndex`, `DuplicateFormatFlags`…) or an unsupported notation.
    private static func parseSpec(_ s: [Unicode.Scalar], _ i: inout Int) -> Spec? {
        var spec = Spec()
        var j: Int = i + 1
        // (\d+\$)?
        var k: Int = j
        while k < s.count && isDigit(s[k]) { k += 1 }
        if k > j && k < s.count && s[k] == "$" {
            let digits = String(String.UnicodeScalarView(s[j..<k]))
            guard let index = Int(digits), index > 0, index <= Int(Int32.max) else {
                return nil
            }
            spec.explicitIndex = index
            j = k + 1
        }
        // [-#+ 0,(<]*
        while j < s.count, "-#+ 0,(<".unicodeScalars.contains(s[j]) {
            if spec.flags.unicodeScalars.contains(s[j]) || (s[j] == "<" && spec.previous) {
                return nil
            }
            if s[j] == "<" {
                spec.previous = true
            } else {
                spec.flags.unicodeScalars.append(s[j])
            }
            j += 1
        }
        // (\d+)?
        let widthStart: Int = j
        while j < s.count && isDigit(s[j]) { j += 1 }
        spec.width = String(String.UnicodeScalarView(s[widthStart..<j]))
        // (\.\d+)?
        if j + 1 < s.count && s[j] == "." && isDigit(s[j + 1]) {
            let precisionStart: Int = j
            j += 1
            while j < s.count && isDigit(s[j]) { j += 1 }
            spec.precision = String(String.UnicodeScalarView(s[precisionStart..<j]))
        }
        guard j < s.count else { return nil }
        // [tT]? and the conversion: date/time and conversions other than S d f % n are not supported
        let conversion: Unicode.Scalar = s[j]
        guard "sSdf%n".unicodeScalars.contains(conversion) else { return nil }
        guard isSmall(spec.width), isSmall(String(spec.precision.dropFirst())) else { return nil }
        if (conversion == "%" || conversion == "n") && spec.previous {
            return nil  // IllegalFormatFlagsException
        }
        spec.conversion = conversion
        i = j + 1
        return spec
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool {
        c >= "0" && c <= "9"
    }

    private static func isSmall(_ digits: String) -> Bool {
        digits.isEmpty || (digits.count <= 6 && (Int(digits) ?? Int.max) <= maxWidth)
    }

    // MARK: - format

    private static func javaPattern(_ spec: Spec, conversion: Unicode.Scalar) -> String {
        var text = "%" + spec.flags + spec.width + spec.precision
        text.unicodeScalars.append(conversion)
        return text
    }

    private static func text(_ spec: Spec) -> String? {
        let pattern: String = javaPattern(spec, conversion: spec.conversion)
        if JavaFormat.failure(pattern, arguments: []) != nil {
            return nil
        }
        return JavaFormat.format(pattern, arguments: [])
    }

    private static func argument(_ spec: Spec, _ arg: JavaFormat.Arg, _ separator: String) -> String? {
        let upper: Bool = spec.conversion == "S"
        let conversion: Unicode.Scalar = upper ? "s" : spec.conversion
        let full: String = javaPattern(spec, conversion: conversion)
        if JavaFormat.failure(full, arguments: [arg]) != nil {
            return nil
        }
        if upper {
            // After validating the whole notation `%s` carries only `-` from the flags — that belongs to the width, precision separately.
            let narrow: String = "%" + spec.precision + "s"
            let text: String = JavaText.toUpperCase(JavaFormat.format(narrow, arguments: [arg]))
            return justify(text, width: Int(spec.width), left: spec.flags.contains("-"))
        }
        let text: String = JavaFormat.format(full, arguments: [arg])
        if conversion == "f" && separator != "." {
            return text.replacingOccurrences(of: ".", with: separator)
        }
        return text
    }

    /// `Formatter.appendJustified`: width in UTF-16 units.
    private static func justify(_ text: String, width: Int?, left: Bool) -> String {
        guard let width, text.utf16.count < width else { return text }
        let padding = String(repeating: " ", count: width - text.utf16.count)
        return left ? text + padding : padding + text
    }
}
