import Foundation
import Testing
@testable import MCLCore

/// `ScpDatabase`, `PartialCheck` and `ScpDownloader.validate` against Java v1.1.1 (probe
/// a maintainer-only probe, table `ScpMeasured`): loading Latin-1 with all 256 bytes,
/// splitting lines also on a bare `\r`, uppercase without a locale (`ß` → `SS`, `ÿ` → U+0178, `µ` → U+039C),
/// comments, duplicates (also after uppercasing) and order; `find`/`contains`/`nPlusOne` with limits, whitespace,
/// surrogate pairs and canonically equivalent forms (equality by UTF-16, not Swift `==`); `merge` (rank,
/// source, length, `compareTo`), `isOneOff` by UTF-16 units; `validate` at the edges of 1,000 callsigns and 10 %.
@Suite struct ScpMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(ScpMeasured.rows, id)
    }

    private static func unescape(_ text: String) -> String {
        ProbeRows.unescape(text)
    }

    private static func optional(_ text: String) -> String? {
        text == "<null>" ? nil : unescape(text)
    }

    /// Java `List.toString` of escaped items.
    private static func list(_ items: [String]) -> String {
        ProbeRows.javaList(items.map { ProbeText.esc($0) })
    }

    /// The inverse of `list` — probe items are non-empty and without a comma.
    private static func parseList(_ text: String) -> [String] {
        let inner: Substring = text.dropFirst().dropLast()
        if inner.isEmpty { return [] }
        return inner.components(separatedBy: ", ").map { unescape($0) }
    }

    private static func dump(_ db: ScpDatabase) -> String {
        var all: [String] = []
        for i in 0..<db.size {
            all.append(db.get(i))
        }
        return "\(db.size) " + list(all)
    }

    private static func bytes(hex: String) -> [UInt8] {
        let digits: [UInt8] = Array(hex.utf8)
        var out: [UInt8] = []
        var i = 0
        while i + 1 < digits.count {
            let pair = String(decoding: digits[i...(i + 1)], as: UTF8.self)
            out.append(UInt8(pair, radix: 16)!)
            i += 2
        }
        return out
    }

    @Test func loadMatchesJava() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scp-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("f.scp")
        let rows = Self.rows("LOAD")
        #expect(rows.count == 930)
        for row in rows {
            try Data(Self.bytes(hex: row[0])).write(to: file)
            #expect(Self.dump(ScpDatabase.load(file.path)) == row[1], "\(row[0])")
        }
        let sub = dir.appendingPathComponent("adresar.scp")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let special: [String: String] = Dictionary(uniqueKeysWithValues: Self.rows("LOADX").map { ($0[0], $0[1]) })
        #expect(special.count == 3)
        #expect(Self.dump(ScpDatabase.load(dir.appendingPathComponent("neni.scp").path)) == special["missing"])
        #expect(Self.dump(ScpDatabase.load(sub.path)) == special["directory"])
        #expect(Self.dump(ScpDatabase.load(nil)) == special["null"])
    }

    @Test func findContainsAndNPlusOneMatchJava() {
        var databases: [String: ScpDatabase] = [:]
        for row in Self.rows("DB") {
            databases[row[0]] = ScpDatabase.of(row.dropFirst().map { Self.unescape($0) })
        }
        #expect(databases.count == 61)
        let rows = Self.rows("FIND")
        #expect(rows.count == 753)
        for row in rows {
            let db = databases[row[0]]!
            let query: String? = Self.optional(row[1])
            let limit = Int(row[2])!
            let found: String = Self.list(db.find(query, limit: limit))
            let contains: String = String(db.contains(query))
            let nPlusOne: String = Self.list(db.nPlusOne(query, limit: limit))
            #expect([found, contains, nPlusOne] == Array(row[3...5]), "\(row[0]) \(row[1]) \(row[2])")
        }
    }

    @Test func mergeMatchesJava() {
        let rows = Self.rows("PC")
        #expect(rows.count == 401)
        for row in rows {
            let merged = PartialCheck.merge(Self.optional(row[0]), logCalls: Self.parseList(row[2]),
                                            spotCalls: Self.parseList(row[3]), scpMatches: Self.parseList(row[4]),
                                            limit: Int(row[1])!)
            let text: String = ProbeRows.javaList(merged.map { ProbeText.esc($0.call) + "/\($0.source)" })
            #expect(text == row[5], "\(row)")
        }
    }

    @Test func nPlusOneAndIsOneOffMatchJava() {
        let rows = Self.rows("NP")
        #expect(rows.count == 300)
        for row in rows {
            let result = PartialCheck.nPlusOne(Self.optional(row[0]), candidates: Self.parseList(row[2]),
                                               limit: Int(row[1])!)
            #expect(Self.list(result) == row[3], "\(row)")
        }
        let pairs = Self.rows("ONE")
        #expect(pairs.count == 17)
        for row in pairs {
            #expect(String(PartialCheck.isOneOff(Self.unescape(row[0]), Self.unescape(row[1]))) == row[2], "\(row)")
        }
    }

    @Test func validateMatchesJava() {
        let rows = Self.rows("VAL")
        #expect(rows.count == 24)
        for row in rows {
            var text = ""
            for i in 0..<Int(row[0])! {
                text += "OK\(i)\n"
            }
            for i in 0..<Int(row[1])! {
                text += "BAD-\(i)\n"
            }
            let content: [UInt8] = Array(text.utf8) + Self.bytes(hex: row[2])
            let result: String
            do {
                result = String(try ScpDownloader.validate(content))
            } catch {
                result = "THROW IOException: " + (error.message ?? "null")
            }
            #expect(ProbeText.esc(result) == row[3], "\(row[0]) \(row[1]) \(row[2])")
        }
    }
}
