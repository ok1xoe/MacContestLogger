import Foundation
import Testing
@testable import MCLCore

/// `CallHistory` and `CallHistoryUpdater` against Java v1.1.1 (probe
/// a maintainer-only probe, table `CallHistoryMeasured`):
/// parsing (BOM as a Java defect, `!!order!!`, missing and duplicate columns, duplicate callsigns,
/// `strip` vs `trim`, NBSP, U+3000, control characters, `ß`/`ÿ`/`µ`/`İ`/`Σ`, surrogate pairs, composed
/// and decomposed `Å`), reading a file (UTF-8 with BOM, CR, CRLF, Latin-1 after bad UTF-8, U+2028, U+0085),
/// `prefill`/`reverse`/`columnFor` for all field types, `withUpdates` + `toLines`, `save` (bytes,
/// permissions 0600, error texts) and `CallHistoryUpdater` over three definitions.
@Suite struct CallHistoryMeasuredTests {

    // MARK: - probe format

    /// The probe's `esc`: UTF-16 units < 0x20, > 0x7E and `\` as `\uXXXX`.
    static func esc(_ text: String?) -> String {
        guard let text else { return "null" }
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

    /// Java `Map.toString()` (`{k=v, k=v}`, a `null` value as `null`).
    static func javaMap(_ map: JavaLinkedMap<String>) -> String {
        let parts: [String] = map.entries.map { "\($0.key ?? "null")=\($0.value ?? "null")" }
        return "{" + parts.joined(separator: ", ") + "}"
    }

    static func javaList(_ items: [String]) -> String {
        "[" + items.joined(separator: ", ") + "]"
    }

    /// The probe's `dump`: size, columns and records in insertion order (by reflection from Java `byCall`).
    static func dump(_ history: CallHistory) -> String {
        var records: [String] = []
        for (key, record) in history.byCall.entries {
            records.append("\(key ?? "null"):\(javaMap(record ?? JavaLinkedMap()))")
        }
        let head = "size=\(history.size) cols=\(javaList(history.columns))"
        return "\(head) recs=[\(records.joined(separator: "; "))]"
    }

    /// Java `text.split(sep, -1)` for a literal separator (by UTF-16 units).
    static func split(_ text: String, _ separator: String) -> [String] {
        let units: [UInt16] = Array(text.utf16)
        let needle: [UInt16] = Array(separator.utf16)
        var parts: [String] = []
        var start = 0
        while true {
            let next: Int = JavaText.indexOf(units, needle, from: start)
            if next < 0 { break }
            parts.append(String(decoding: units[start..<next], as: UTF16.self))
            start = next + needle.count
        }
        parts.append(String(decoding: units[start...], as: UTF16.self))
        return parts
    }

    /// File rows from a probe column (`||`; an empty column = no rows).
    static func lines(_ joined: String) -> [String] {
        joined.isEmpty ? [] : split(joined, "||")
    }

    static func fields(_ spec: String) -> [ContestDefinition.ExchangeField] {
        split(spec, ";").map { item in
            let parts: [String] = split(item, ":")
            let type: ContestDefinition.FieldType? = parts[1] == "null" ? nil : ContestDefinition.FieldType(rawValue: parts[1])
            return CallHistoryTestSupport.field(parts[0], type)
        }
    }

    static func pairs(_ spec: String) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        if spec.isEmpty { return out }
        for item in split(spec, ";") {
            let units: [UInt16] = Array(item.utf16)
            let eq: Int = units.firstIndex(of: 0x3D)!
            out.put(String(decoding: units[..<eq], as: UTF16.self), String(decoding: units[(eq + 1)...], as: UTF16.self))
        }
        return out
    }

    static func updates(_ spec: String) -> JavaLinkedMap<JavaLinkedMap<String>> {
        var out = JavaLinkedMap<JavaLinkedMap<String>>()
        for entry in split(spec, " ;; ") {
            let callAndValues: [String] = split(entry, ">>")
            var values = JavaLinkedMap<String>()
            for pair in split(callAndValues[1], ",,") {
                let kv: [String] = split(pair, "==")
                values.put(kv[0], kv[1] == "<null>" ? nil : kv[1])
            }
            out.put(callAndValues[0], values)
        }
        return out
    }

    static func bytes(hex: String) -> [UInt8] {
        let units: [UInt8] = Array(hex.utf8)
        return stride(from: 0, to: units.count, by: 2).map {
            UInt8(String(decoding: units[$0..<($0 + 2)], as: UTF8.self), radix: 16)!
        }
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(CallHistoryMeasured.rows, id)
    }

    /// Compares column by column; prints at most 15 mismatches.
    private static func compare(_ id: String, _ rows: [[String]], expectedCount: Int,
                                _ actual: ([String]) throws -> String) rethrows {
        #expect(rows.count == expectedCount, "\(id)")
        var mismatches = 0
        for row in rows {
            let got: String = try actual(row)
            if got != row[row.count - 1] {
                mismatches += 1
                if mismatches <= 15 {
                    Issue.record("\(id) \(row.dropLast()): Swift \(got) ≠ Java \(row[row.count - 1])")
                }
            }
        }
        #expect(mismatches == 0, "\(id): \(mismatches) mismatches")
    }

    private static func histories() -> [String: CallHistory] {
        var out: [String: CallHistory] = [:]
        for row in rows("CH.history") {
            out[row[0]] = CallHistory.parse(lines(ProbeRows.unescape(row[1])))
        }
        return out
    }

    // MARK: - testy

    @Test func parseMatchesJava() {
        Self.compare("CH.parse", Self.rows("CH.parse"), expectedCount: 21) { row in
            Self.esc(Self.dump(CallHistory.parse(Self.lines(ProbeRows.unescape(row[0])))))
        }
    }

    @Test func bomBreaksTheOrderHeaderAsInJava() {
        // Decision 5: the Java defect is kept — a header with a BOM is the callsign record `\u{FEFF}!!ORDER!!`.
        let ch = CallHistory.parse(["\u{FEFF}!!Order!!,Call,Name,Exch1", "ok1abc,Pavel,15"])
        #expect(ch.columns == CallHistory.defaultOrder)
        #expect(ch.lookup("\u{FEFF}!!order!!")?["name"] == "Call")
        #expect(ch.lookup("OK1ABC")?["loc1"] == "15")
    }

    @Test func lookupMatchesJava() {
        Self.compare("CH.lookup", Self.rows("CH.lookup"), expectedCount: 9) { row in
            let ch = CallHistory.parse(Self.lines(ProbeRows.unescape(row[0])))
            let call: String? = row[1] == "null" ? nil : ProbeRows.unescape(row[1])
            return Self.esc(ch.lookup(call).map { "Optional[\(Self.javaMap($0))]" } ?? "Optional.empty")
        }
    }

    @Test func loadMatchesJava() throws {
        try CallHistoryTestSupport.withTemporaryDirectory { dir in
            var index = 0
            try Self.compare("CH.load", Self.rows("CH.load"), expectedCount: 13) { row in
                let path = "\(dir)/load\(index).txt"
                index += 1
                try Data(Self.bytes(hex: row[0])).write(to: URL(fileURLWithPath: path))
                return Self.esc(Self.dump(CallHistory.load(path)))
            }
        }
    }

    @Test func loadOfMissingOrUnreadableIsEmpty() throws {
        try CallHistoryTestSupport.withTemporaryDirectory { dir in
            #expect(CallHistory.load(nil).size == 0)
            #expect(CallHistory.load(dir + "/missing.txt").columns == CallHistory.defaultOrder)
            #expect(CallHistory.load(dir).size == 0, "directory: readAllLines fails twice → empty")
            let locked = dir + "/locked.txt"
            try Data("A1,x\n".utf8).write(to: URL(fileURLWithPath: locked))
            chmod(locked, 0o000)
            defer { chmod(locked, 0o600) }
            #expect(CallHistory.load(locked).size == 0)
        }
    }

    @Test func prefillMatchesJava() throws {
        let h = try #require(Self.histories()["H"])
        Self.compare("CH.prefill", Self.rows("CH.prefill"), expectedCount: 247) { row in
            let call: String? = row[1] == "null" ? nil : ProbeRows.unescape(row[1])
            let received: [ContestDefinition.ExchangeField]? = row[2] == "<null>" ? nil : Self.fields(row[2])
            return Self.esc(Self.javaMap(h.prefill(call, received)))
        }
    }

    @Test func reverseMatchesJava() throws {
        let h = try #require(Self.histories()["H"])
        Self.compare("CH.reverse", Self.rows("CH.reverse"), expectedCount: 862) { row in
            let received: [ContestDefinition.ExchangeField]? = row[2] == "<null>" ? nil : Self.fields(row[2])
            let found: [String] = h.reverse(Self.pairs(ProbeRows.unescape(row[1])), received, limit: Int(row[3])!)
            return Self.esc(Self.javaList(found))
        }
    }

    @Test func columnForMatchesJava() {
        let all = Self.histories()
        Self.compare("CH.columnFor", Self.rows("CH.columnFor"), expectedCount: 175) { row in
            guard let ch = all[row[0]], let field = Self.fields(row[1]).first else { return "?" }
            return Self.esc(ch.columnFor(field))
        }
    }

    @Test func withUpdatesAndToLinesMatchJava() {
        for row in Self.rows("CH.update") {
            let base = CallHistory.parse(Self.lines(ProbeRows.unescape(row[0])))
            let updated = base.withUpdates(Self.updates(ProbeRows.unescape(row[1])))
            #expect(Self.esc(Self.dump(updated)) == row[2], "\(row[1])")
            #expect(Self.esc(updated.toLines().joined(separator: "||")) == row[3], "\(row[1])")
        }
        #expect(Self.rows("CH.update").count == 7)
        let empty: [String]? = Self.rows("CH.toLines").first
        #expect(Self.esc(CallHistory.empty.toLines().joined(separator: "||")) == empty?[1])
    }

    @Test func saveWritesJavaBytesWithOwnerOnlyPermissions() throws {
        let rows: [String: [String]] = Dictionary(uniqueKeysWithValues: Self.rows("CH.save").map { ($0[0], $0) })
        try CallHistoryTestSupport.withTemporaryDirectory { dir in
            let saved = CallHistory.parse(["!!Order!!,Call,Name", "W1AW,Hiram"])
                .withUpdates(Self.updates("ok1xoe>>cqzone==15,,name==Tom\u{E1}\u{161}"))
            let nested = dir + "/nested/dir/ch.txt"
            try saved.save(nested)
            #expect(Self.hex(try Self.read(nested)) == rows["new"]?[1])
            #expect(Self.permissions(nested) == rows["new"]?[2])

            let existing = dir + "/existing.txt"
            try Data("old\n".utf8).write(to: URL(fileURLWithPath: existing))
            chmod(existing, 0o644)
            try CallHistory.empty.save(existing)
            #expect(Self.hex(try Self.read(existing)) == rows["overwrite"]?[1])
            #expect(Self.permissions(existing) == rows["overwrite"]?[2])

            let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir + "/nested/dir")
                .filter { $0.hasPrefix("callhistory") }
            #expect(String(leftovers.count) == rows["tmpLeft"]?[1])
        }
    }

    @Test func saveErrorsMatchJava() throws {
        let expected: [String: String] = Dictionary(uniqueKeysWithValues: Self.rows("CH.saveError").map { ($0[0], $0[1]) })
        #expect(expected.count == 5)
        try CallHistoryTestSupport.withTemporaryDirectory { dir in
            let plain = dir + "/plainfile"
            try Data("x".utf8).write(to: URL(fileURLWithPath: plain))
            let readOnly = dir + "/readonly"
            try FileManager.default.createDirectory(atPath: readOnly, withIntermediateDirectories: true)
            chmod(readOnly, 0o555)
            defer { chmod(readOnly, 0o755) }
            let full = dir + "/fulldir"
            try FileManager.default.createDirectory(atPath: full + "/inner", withIntermediateDirectories: true)
            let cases: [(String, String)] = [
                ("parentIsFile", plain + "/sub/ch.txt"), ("parentIsFileDirect", plain + "/ch.txt"),
                ("readOnlyDir", readOnly + "/ch.txt"), ("readOnlyDirSub", readOnly + "/sub/ch.txt"),
                ("targetIsNonEmptyDir", full),
            ]
            for (name, path) in cases {
                var message = "ok"
                do throws(CallHistorySaveError) {
                    try CallHistory.empty.save(path)
                } catch {
                    message = "\(error.exception): \(error.message)"
                }
                message = JavaText.replace(message, dir, "<work>")
                message = JavaText.replace(message, "callhistoryXXXXXXXXXX.tmp", "callhistory<n>.tmp")
                #expect(Self.esc(message) == expected[name], "\(name)")
            }
        }
    }

    @Test func updaterMatchesJava() throws {
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc)
        let defs = try ContestCatalog.fromDir(SessionFixture.contestData().appendingPathComponent("contests"))
        try Self.compare("CH.updater", Self.rows("CH.updater"), expectedCount: 6) { row in
            let def = try #require(defs.first { $0.id == row[0] })
            let session = ContestSession(definition: def, dxcc: dxcc, registry: registry, myCall: "OK1XOE", myGrid: nil)
            let historyLines: String = ProbeRows.unescape(row[1])
            let ch: CallHistory = historyLines.isEmpty ? .empty : CallHistory.parse(Self.lines(historyLines))
            let qsos: [Qso] = Self.split(ProbeRows.unescape(row[2]), ";").map(Self.qso)
            let result = try CallHistoryUpdater.updates(session, qsos, ch)
            let parts: [String] = result.entries.map { "\($0.key ?? "null")=\(Self.javaMap($0.value ?? JavaLinkedMap()))" }
            return Self.esc("{" + parts.joined(separator: ", ") + "}")
        }
    }

    /// A QSO from the probe column `minute|callsign|exchange|flags` (`null` minute = no time, `D` deleted, `X` X-QSO).
    private static func qso(_ spec: String) -> Qso {
        let f: [String] = split(spec, "|")
        var q = Qso()
        if f[0] != "null" {
            q.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200 + 60 * TimeInterval(Int(f[0])!))
        }
        q.call = f[1]
        q.freqHz = 14_200_000
        q.mode = .ssb
        q.exchangeRcvd = f[2]
        q.deleted = f[3].contains("D")
        q.xqso = f[3].contains("X")
        return q
    }

    private static func read(_ path: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    }

    /// `PosixFilePermissions.toString` (`rw-------`).
    private static func permissions(_ path: String) -> String {
        var info = stat()
        guard stat(path, &info) == 0 else { return "?" }
        let mode = Int(info.st_mode) & 0o777
        let letters: [Character] = ["r", "w", "x"]
        var out = ""
        for bit in 0..<9 {
            out.append(mode & (0o400 >> bit) != 0 ? letters[bit % 3] : "-")
        }
        return out
    }
}
