import Foundation
import Testing
@testable import MCLCore

/// Replays `LogbookMeasured` (the `Dupesheet.build`, `areaDigit` and
/// `LogWarnings.analyze` outputs measured on Java) and compares the **whole text** of the result, including the order of keys and messages.
@Suite struct LogbookMeasuredTests {

    /// `\uXXXX` → UTF-16 unit, `~` → nil (as in the probe).
    static func decode(_ text: String) -> String? {
        if text == "~" { return nil }
        let units = Array(text.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < units.count {
            if units[i] == 0x5C, i + 5 < units.count, units[i + 1] == 0x75 {
                let hex = String(decoding: units[(i + 2)..<(i + 6)], as: UTF16.self)
                out.append(UInt16(hex, radix: 16)!)
                i += 6
            } else {
                out.append(units[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// Java `show`: units < 0x20, > 0x7E and `\` as `\uXXXX`.
    static func show(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            if unit < 0x20 || unit > 0x7E || unit == 0x5C {
                let hex = String(unit, radix: 16, uppercase: true)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            } else {
                out.unicodeScalars.append(Unicode.Scalar(unit)!)
            }
        }
        return out
    }

    static func format(_ sheet: Dupesheet.Sheet) -> String {
        let entries = sheet.columns.map { "\($0.key)=[\($0.calls.joined(separator: ", "))]" }
        return show("{" + entries.joined(separator: ", ") + "}")
    }

    static func format(_ warnings: LogWarnings.Warnings) -> String {
        let entries = warnings.ids.map { "\($0)=[\(warnings[$0]!.joined(separator: ", "))]" }
        return show("{" + entries.joined(separator: ", ") + "}")
    }

    static func fields(_ spec: String) -> [ContestDefinition.ExchangeField]? {
        if spec == "~" { return nil }
        if spec == "-" { return [] }
        return spec.split(separator: " ").map { f in
            let p = f.split(separator: ":", omittingEmptySubsequences: false)
            return ContestDefinition.ExchangeField(
                id: decode(String(p[0])), type: p[1] == "~" ? nil : ContestDefinition.FieldType(rawValue: String(p[1]))!,
                required: true, source: nil, appliesWhen: nil, validation: nil)
        }
    }

    static func zones(_ spec: String) -> (String) -> Set<Int?>? {
        if spec == "~" { return { _ in nil } }
        if spec == "-" { return { _ in [] } }
        var rules: [(String, Set<Int?>)] = []
        for rule in spec.split(separator: " ") {
            let p = rule.split(separator: "=", omittingEmptySubsequences: false)
            let set = Set(p[1].split(separator: "/").map { $0 == "~" ? nil : Int($0)! })
            rules.append((String(p[0]), set))
        }
        return { call in
            for (prefix, set) in rules where prefix == "*" || call.utf16.starts(with: prefix.utf16) {
                return set
            }
            return []
        }
    }

    /// Rows where Swift deliberately differs (Java NPE → Swift lenient).
    /// Zone set `{null, 5}` and a zone outside it: Java's sort crashes, Swift puts `null` first.
    static let divergent: [String: String] = [
        "W\twarnings-fields\t5": "{2=[ITU z\\u00F3na 6 nesed\\u00ED k zemi (null/5)",
        "W\twarnings-fields\t6": "{2=[ITU z\\u00F3na 6 nesed\\u00ED k zemi (null/5)",
    ]

    /// All result rows with the computed Swift outputs.
    static func computed() -> [(key: String, swift: String)] {
        var out: [(key: String, swift: String)] = []
        var name = ""
        var log: [Qso] = []
        var query = 0
        for line in LogbookMeasured.cases.split(separator: "\n") {
            let p = line.components(separatedBy: " ¦ ")
            let key = "\(p[0])\t\(name)\t\(query)"
            switch p[0] {
            case "L":
                name = p[1]
                log = []
                query = 0
            case "Q":
                var q = Qso()
                q.id = p[1] == "~" ? nil : Int64(p[1])!
                q.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200)
                q.call = decode(p[2]) ?? ""
                q.freqHz = Int(p[3])!
                q.mode = p[4] == "~" ? nil : Mode(rawValue: p[4])!
                q.exchangeRcvd = decode(p[5]) ?? ""
                q.deleted = p[6].contains("d")
                q.xqso = p[6].contains("x")
                log.append(q)
            case "D":
                let scope = p[3] == "~" ? nil : ContestDefinition.Scope(rawValue: p[3])!
                out.append((key, format(Dupesheet.build(log, band: decode(p[1]), mode: decode(p[2]), scope: scope))))
                query += 1
            case "W":
                let f = fields(p[1])
                let scp: Set<String>? = p[2] == "~" ? nil : Set(p[2].split(separator: " ").map(String.init))
                let inScp: ((String) -> Bool)? = scp.map { set in { set.contains($0) } }
                let w = LogWarnings.analyze(log, receivedFields: { _ in f }, inScp: inScp,
                                            cqZones: zones(p[3]), ituZones: zones(p[4]))
                out.append((key, format(w)))
                query += 1
            case "A":
                out.append((key, show(String(Dupesheet.areaDigit(decode(p[1])!)))))
                query += 1
            default:
                Issue.record("unknown row \(line)")
            }
        }
        return out
    }

    @Test func everyResultMatchesJava() {
        #expect(LogbookMeasured.javaVersion == "21.0.2")
        let expected = LogbookMeasured.results.split(separator: "\n").map { line -> (String, String) in
            let p = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            return ("\(p[0])\t\(p[1])\t\(p[2])", String(p[3]))
        }
        let swift = Self.computed()
        #expect(swift.count == expected.count)
        var failures: [String] = []
        for ((key, java), (swiftKey, result)) in zip(expected, swift) {
            guard key == swiftKey else {
                failures.append("key \(key) against \(swiftKey)")
                continue
            }
            if let prefix = Self.divergent[key] {
                #expect(java == "EXC NullPointerException", "\(key)")
                if !result.hasPrefix(prefix) { failures.append("\(key) (odchylka): \(result)") }
            } else if java != result {
                failures.append("\(key)\n  Java:  \(java)\n  Swift: \(result)")
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    /// The table covers what it exists for.
    @Test func tableCoversOrderingAndEdges() {
        let results = LogbookMeasured.results
        #expect(results.split(separator: "\n").count == 67)
        // X-QSO in the Dupesheet
        #expect(results.contains("D\tdupesheet-inventory\t0\t{#=[ABCD/K7AB, RAEM, \\u00A0], 1=[K1ABC, OK1XOE], 2=[OK2XQ, W2XX]"))
        // generated logbook with 250 callsigns
        #expect(results.contains("W\tgen-500\t1\t{"))
    }
}
