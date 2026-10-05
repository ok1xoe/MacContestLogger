import Foundation
import Testing
@testable import MCLCore

/// Helpers of the parity tests against a maintainer-only probe (rows `area TAB input TAB result`).
enum ToolsParity {

    typealias Row = (input: String, result: String)

    /// The JVM rows of one area, in probe order.
    static func rows(_ area: String) -> [Row] {
        var out: [Row] = []
        for line in ToolsJava.tsv.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix(area + "\t") {
            let parts: [Substring] = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            out.append((String(parts[1]), parts.count > 2 ? String(parts[2]) : ""))
        }
        return out
    }

    /// Compares the Swift rows with the JVM rows of the area (count and every row).
    static func expect(_ area: String, _ swift: [Row], sourceLocation: SourceLocation = #_sourceLocation) {
        let java: [Row] = rows(area)
        #expect(!java.isEmpty, "no JVM rows for \(area)", sourceLocation: sourceLocation)
        #expect(swift.count == java.count, "\(area): \(swift.count) Swift rows, \(java.count) JVM rows",
                sourceLocation: sourceLocation)
        for (s, j) in zip(swift, java) where s.input != j.input || s.result != j.result {
            Issue.record("\(area)\nSwift: \(s.input) => \(s.result)\nJava:  \(j.input) => \(j.result)",
                         sourceLocation: sourceLocation)
        }
    }

    /// The probe's escaping: UTF-16 units < 0x20, > 0x7E and `\` as `\uxxxx` (lower-case hex).
    static func esc(_ text: String?) -> String {
        guard let text else { return "<null>" }
        var out = ""
        for unit in text.utf16 {
            if unit < 0x20 || unit > 0x7E || unit == 0x5C {
                out += "\\u" + String(format: "%04x", Int(unit))
            } else {
                out += String(UnicodeScalar(UInt8(unit)))
            }
        }
        return out
    }

    /// `Integer.toHexString(Float.floatToRawIntBits(f))`.
    static func bits(_ value: Float) -> String {
        String(value.bitPattern, radix: 16)
    }

    /// `Long.toHexString`-less `Double.doubleToLongBits`.
    static func doubleBits(_ value: Double) -> String {
        let canonicalNaN: Int64 = 0x7FF8_0000_0000_0000
        return String(value.isNaN ? canonicalNaN : Int64(bitPattern: value.bitPattern))
    }

    /// The time of the probe's `T0` (2026-10-04T12:34:56Z).
    static let t0: Date = Date(timeIntervalSince1970: 1_791_117_296)
    static let t0Instant: JavaInstant = JavaInstant(date: t0)

    static let cs: Translator = .source

    /// Java `Double.toString` for the values the rows print.
    static func javaDouble(_ value: Double) -> String {
        JavaDouble.toString(value)
    }

    /// Java `Float.toString` for the whole-number and short fractions the rows print.
    static func javaFloat(_ value: Float) -> String {
        if value.isNaN { return "NaN" }
        if value == value.rounded() && abs(value) < 1e7 { return String(format: "%.1f", Double(value)) }
        if abs(value) >= 1e7 { return javaDouble(Double(value)) }
        return "\(value)"
    }

    static func qso(_ call: String, _ band: String?, _ mode: Mode?, _ exchange: String) -> Qso {
        var q = Qso()
        q.call = call
        q.band = band.flatMap { Band.from(adif: $0) }
        q.mode = mode
        q.exchangeRcvd = exchange
        q.timestampUtc = t0
        return q
    }
}
