import Foundation
import Testing
@testable import MCLCore

/// Java reference of the readers' edge inputs: `Fixtures/io-edge-java.tsv` over the inputs
/// `Fixtures/io-edge/` (format in a maintainer-only probe, section "Formát").
///
/// A shared helper of the ADIF gates (`AdifEdgeParityTests`) and Cabrillo: parsing the TSV (rows `V`, `F`,
/// `Q`, `R`), reverse escaping by UTF-16 units (`\N` = Java `null`) and comparison
/// QSO tuples with these rules:
/// - text fields are compared with the normalisation `null ≡ ""` and it is **counted**
///   how many times Java returned an empty string, which Swift cannot tell from `null`;
/// - a lone surrogate (a Swift `String` does not carry it, `U+FFFD` results) is tolerated **only**
///   for files from `surrogateAllowlist` and only where Java really has a lone surrogate.
struct IoEdgeFixture {

    /// Java text by UTF-16 units; `nil` = Java `null`.
    typealias Units = [UInt16]?

    /// Row `F`.
    struct FileRow {
        let name: String
        let reader: String
        let sha256: String
        let bytes: Int
        let decoding: String
        let read: String
        let records: String
    }

    /// Columns of a QSO tuple in a `Q` row (after `file` and `index`).
    static let qsoColumns: [String] = [
        "call", "freqHz", "band", "mode", "timestampUtc", "rstSent", "rstRcvd", "serialSent",
        "serialRcvd", "exchangeSent", "exchangeRcvd", "operator", "comment", "xqso",
    ]

    /// Text fields of the model where Swift holds `""` instead of Java `null`.
    static let textColumns: Set<String> = [
        "call", "rstSent", "rstRcvd", "exchangeSent", "exchangeRcvd", "operator", "comment",
    ]

    /// The only documented case of a lone surrogate in Java's output (`<COMMENT:1>` cuts off
    /// the first half of an emoji); a deliberate divergence from Java v1.1.1.
    static let surrogateAllowlist: Set<String> = ["AR5b-pulka-surrogatu.adi"]

    var version: [String: String] = [:]
    var files: [FileRow] = []
    /// file → QSO tuples in index order
    var qsos: [String: [[Units]]] = [:]
    /// file → record index → (key, value) in Java `String.compareTo` order
    var records: [String: [Int: [([UInt16], Units)]]] = [:]

    static func load() throws -> IoEdgeFixture {
        let url = try #require(Bundle.module.url(forResource: "io-edge-java", withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var fx = IoEdgeFixture()
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch cols[0] {
            case "V":
                fx.version[cols[1]] = cols[2]
            case "F":
                let row = FileRow(
                    name: cols[1], reader: cols[2], sha256: cols[3], bytes: Int(cols[4]) ?? -1,
                    decoding: cols[5], read: cols[6], records: cols[7])
                fx.files.append(row)
            case "Q":
                let tuple: [Units] = cols[3...].map { unescape($0) }
                fx.qsos[cols[1], default: []].append(tuple)
                #expect(Int(cols[2]) == fx.qsos[cols[1]]!.count - 1, "Q index \(cols[1])")
            case "R":
                let record = Int(cols[2]) ?? -1
                let key = unescape(cols[3]) ?? []
                fx.records[cols[1], default: [:]][record, default: []].append((key, unescape(cols[4])))
            default:
                Issue.record("unknown row: \(line)")
            }
        }
        return fx
    }

    static func inputURL(_ name: String) throws -> URL {
        let dir = try #require(Bundle.module.url(forResource: "io-edge", withExtension: nil))
        return dir.appendingPathComponent(name)
    }

    /// Reverse escaping of the probe: `\\`, `\t`, `\n`, `\r`, `\uXXXX`; `\N` = `null`.
    static func unescape(_ text: String) -> Units {
        if text == "\\N" { return nil }
        let units = Array(text.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var i = 0
        while i < units.count {
            let unit = units[i]
            guard unit == 0x5C, i + 1 < units.count else {
                out.append(unit)
                i += 1
                continue
            }
            switch units[i + 1] {
            case 0x5C: out.append(0x5C)
            case 0x74: out.append(0x09)
            case 0x6E: out.append(0x0A)
            case 0x72: out.append(0x0D)
            case 0x75:
                let hex = String(decoding: units[(i + 2)..<(i + 6)], as: UTF16.self)
                out.append(UInt16(hex, radix: 16)!)
                i += 6
                continue
            default:
                Issue.record("unknown escaping in \(text)")
                out.append(units[i + 1])
            }
            i += 2
        }
        return out
    }

    /// Back to the probe's shape (for a readable report of mismatches).
    static func escape(_ units: Units) -> String {
        guard let units else { return "\\N" }
        var out = ""
        for unit in units {
            switch unit {
            case 0x5C: out += "\\\\"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(unit)!)
            default:
                let hex = String(unit, radix: 16).uppercased()
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            }
        }
        return out
    }

    /// The tuple of a Swift QSO in the columns `qsoColumns` (text fields never `nil`).
    static func tuple(_ q: Qso) -> [Units] {
        func text(_ s: String) -> Units { Array(s.utf16) }
        func opt(_ s: String?) -> Units { s.map { Array($0.utf16) } }
        let millis: String? = q.timestampUtc.map {
            String(Int64(($0.timeIntervalSince1970 * 1000).rounded()))
        }
        let band: String? = q.band.map { String(describing: $0).uppercased() }
        let mode: String? = q.mode.map { String(describing: $0).uppercased() }
        var row: [Units] = [text(q.call), text(String(q.freqHz)), opt(band), opt(mode), opt(millis)]
        row += [text(q.rstSent), text(q.rstRcvd), opt(q.serialSent.map { String($0) })]
        row += [opt(q.serialRcvd.map { String($0) }), text(q.exchangeSent), text(q.exchangeRcvd)]
        row += [text(q.operator), text(q.comment), text(q.xqso ? "true" : "false")]
        return row
    }

    /// Comparison counters — they are printed, nothing is hidden here.
    struct Stats {
        var comparedFields = 0
        /// Java returned `""` (not `null`) in a text field — Swift cannot tell it from `null`.
        var javaEmptyNotNull = 0
        /// How many times the exception for a lone surrogate was applied (`surrogateAllowlist`).
        var surrogateAllowances = 0
    }

    /// Match of two values; for files from `surrogateAllowlist` Swift may have `U+FFFD` where
    /// Java has a lone surrogate (and only there).
    static func same(
        java: Units, swift: Units, file: String, stats: inout Stats
    ) -> Bool {
        if java == swift { return true }
        guard surrogateAllowlist.contains(file), let java, let swift, java.count == swift.count else {
            return false
        }
        for i in java.indices where java[i] != swift[i] {
            guard swift[i] == 0xFFFD, isLoneSurrogate(java, at: i) else { return false }
        }
        stats.surrogateAllowances += 1
        return true
    }

    /// The unit at `index` is an unpaired surrogate.
    static func isLoneSurrogate(_ units: [UInt16], at index: Int) -> Bool {
        let unit = units[index]
        if UTF16.isLeadSurrogate(unit) {
            return index + 1 >= units.count || !UTF16.isTrailSurrogate(units[index + 1])
        }
        if UTF16.isTrailSurrogate(unit) {
            return index == 0 || !UTF16.isLeadSurrogate(units[index - 1])
        }
        return false
    }

    /// Compares the Java and Swift QSO tuples of one file; mismatches as lines of text.
    static func compareQsos(
        file: String, java: [[Units]], swift: [Qso], stats: inout Stats
    ) -> [String] {
        var out: [String] = []
        if java.count != swift.count {
            out.append("\(file): QSO count java=\(java.count) swift=\(swift.count)")
        }
        for (index, (javaRow, qso)) in zip(java, swift).enumerated() {
            let swiftRow = tuple(qso)
            for (column, name) in qsoColumns.enumerated() {
                var javaValue = javaRow[column]
                stats.comparedFields += 1
                if textColumns.contains(name) {
                    if javaValue == [] { stats.javaEmptyNotNull += 1 }
                    if javaValue == nil { javaValue = [] }
                }
                if !same(java: javaValue, swift: swiftRow[column], file: file, stats: &stats) {
                    out.append("\(file) QSO \(index) \(name): java=\(escape(javaValue)) swift=\(escape(swiftRow[column]))")
                }
            }
        }
        return out
    }
}
