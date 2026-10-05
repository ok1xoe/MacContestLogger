import Foundation
@testable import MCLCore

/// The probe table a maintainer-only probe: rows `area \t input \t result`. Inputs of the
/// reducer, status and send rows are `key=value;…` with the values escaped (control characters, NBSP, backslash and `;`
/// as `\uXXXX`), `<null>` is Java `null`.
enum NetworkProbeTable {

    struct Row {
        let area: String
        let input: String
        let result: String
    }

    static let rows: [Row] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/jvm-probes/network.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Row(area: parts[0], input: parts[1], result: parts.count > 2 ? parts[2] : "")
        }
    }()

    static func area(_ name: String) -> [Row] {
        rows.filter { $0.area == name }
    }

    /// `key=value;…` → the unescaped values (`nil` for `<null>`).
    static func fields(_ spec: String) -> [String: String?] {
        var out: [String: String?] = [:]
        for part in spec.split(separator: ";", omittingEmptySubsequences: false) {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = String(part[part.startIndex..<eq])
            let raw = String(part[part.index(after: eq)...])
            out[key] = raw == "<null>" ? nil : unescape(raw)
        }
        return out
    }

    /// The probe's `esc`: control characters, DEL, NBSP and the backslash as `\uXXXX` (lower case), `<null>` for nil;
    /// with `semicolon` also `;`.
    static func esc(_ text: String?, semicolon: Bool = false) -> String {
        guard let text else { return "<null>" }
        var out: [UInt16] = []
        for unit in text.utf16 {
            let escaped: Bool = unit < 0x20 || unit == 0x7f || unit == 0xa0 || unit == 0x5c || (semicolon && unit == 0x3b)
            if escaped {
                out.append(contentsOf: Array(String(format: "\\u%04x", Int(unit)).utf16))
            } else {
                out.append(unit)
            }
        }
        return String(utf16CodeUnits: out, count: out.count)
    }

    /// `\uXXXX` → the UTF-16 unit.
    static func unescape(_ text: String) -> String {
        var units: [UInt16] = []
        let source = Array(text.utf16)
        var index = 0
        while index < source.count {
            if source[index] == 0x5C, index + 5 < source.count, source[index + 1] == 0x75,
               let value = UInt16(String(utf16CodeUnits: Array(source[(index + 2)..<(index + 6)]), count: 4),
                                  radix: 16) {
                units.append(value)
                index += 6
            } else {
                units.append(source[index])
                index += 1
            }
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}
