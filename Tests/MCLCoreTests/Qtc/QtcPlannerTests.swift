import Foundation
import Testing
@testable import MCLCore

/// Ported Java `qtc/QtcPlannerTest` (3 tests, Java v1.1.1).
@Suite struct QtcPlannerTests {

    static let base: Date = Date(timeIntervalSince1970: 1_786_190_400) // 2026-08-08T12:00:00Z

    static func qso(_ minute: Int, _ call: String, _ exch: String) -> Qso {
        var q = Qso()
        q.timestampUtc = base.addingTimeInterval(TimeInterval(60 * minute))
        q.call = call
        q.freqHz = 14_025_000
        q.mode = .cw
        q.exchangeRcvd = exch
        return q
    }

    static func rec(_ sent: Bool, _ partner: String, _ call: String, _ nr: Int) -> QtcRecord {
        QtcRecord(contestId: "wae", sent: sent, partnerCall: partner, groupNr: 1, groupSize: 10,
                  qsoTime: "1200", qsoCall: call, qsoSerial: nr,
                  at: Date(timeIntervalSince1970: 1_786_194_000), // 2026-08-08T13:00:00Z
                  freqHz: 14_025_000, mode: "CW")
    }

    @Test func candidatesSkipPartnerAndReported() {
        let log: [Qso] = [
            Self.qso(0, "DL1ABC", "599 1"),
            Self.qso(1, "OK1XOE", "599 2"),
            Self.qso(2, "G3ABC", "599 3"),
            Self.qso(3, "F5XX", "599 4"),
        ]
        let qtcs: [QtcRecord] = [Self.rec(true, "SP9ZZ", "DL1ABC", 1)]

        let c: [Qso] = QtcPlanner.candidates(log, "OK1XOE", qtcs, 10, 10)
        #expect(c.map(\.call) == ["G3ABC", "F5XX"])
        #expect(QtcPlanner.toLine(c[0]) == QtcPlanner.Line(time: "1202", call: "G3ABC", serial: 3))
    }

    @Test func limitPerStation() {
        var qtcs: [QtcRecord] = []
        for i in 0..<8 {
            qtcs.append(Self.rec(true, "OK1XOE", "X\(i)", i))
        }
        #expect(QtcPlanner.remainingFor("ok1xoe", qtcs, 10) == 2)
        let log: [Qso] = [Self.qso(0, "A1A", "599 1"), Self.qso(1, "B1B", "599 2"), Self.qso(2, "C1C", "599 3")]
        #expect(QtcPlanner.candidates(log, "OK1XOE", qtcs, 10, 10).count == 2)
    }

    @Test func parsingAndFormatting() {
        #expect(QtcPlanner.parseLine("930 w1aw 12") == QtcPlanner.Line(time: "0930", call: "W1AW", serial: 12))
        #expect(QtcPlanner.parseLine("nonsense") == nil)
        #expect(QtcPlanner.parseGroup("3/10")?.groupNr == 3)
        let cw: [String] = QtcPlanner.cwText(3, [QtcPlanner.Line(time: "1202", call: "G3ABC", serial: 3)])
        #expect(cw == ["QTC 3/1", "1202 G3ABC 3"])
        let line: String = QtcPlanner.cabrilloLine(Self.rec(false, "W1AW", "DL1ABC", 1), "OK1XOE")
        #expect(line.hasPrefix("QTC: 14025 CW 2026-08-08 1300 W1AW"), "\(line)")
        #expect(line.contains("OK1XOE"), "\(line)")
    }
}

/// `QtcPlanner` against Java v1.1.1 (maintainer-only probe, table
/// `QtcPlannerMeasured`): `serial` (ASCII `\d`, `\s`, NBSP, Arabic digits), `toLine` (before 1970,
/// fractions of a second, `ß` → `SS`), `parseLine`/`parseGroup` (length bounds, `trim` vs. `\s`, U+2028/U+0085,
/// `toUpperCase(ROOT)` outside ASCII), `cwText`, `remainingFor` (`equalsIgnoreCase` by UTF-16 units:
/// `ß`/`ẞ`, `İ`/`ı`; bounds `Integer.MIN/MAX_VALUE`) and `candidates` over synthetic logs.
@Suite struct QtcPlannerMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(QtcPlannerMeasured.rows, id)
    }

    private static func text(_ cell: String) -> String? {
        cell == "null" ? nil : ProbeRows.unescape(cell)
    }

    private static func line(_ line: QtcPlanner.Line?) -> String {
        guard let line else { return "Optional.empty" }
        return "Optional[\(line)]"
    }

    /// A QSO `minute,callsign,serialRcvd,exchange,flags` separated by `;` (the probe format).
    private static func log(_ spec: String) -> [Qso] {
        if spec.isEmpty { return [] }
        return spec.split(separator: ";", omittingEmptySubsequences: false).map { item in
            let f: [String] = item.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            var q = Qso()
            if f[0] != "-", let minute = Int(f[0]) {
                q.timestampUtc = QtcPlannerTests.base.addingTimeInterval(TimeInterval(60 * minute))
            }
            q.call = f[1]
            if f[2] != "-" { q.serialRcvd = Int(f[2]) }
            q.exchangeRcvd = f[3]
            q.deleted = f[4].contains("D")
            q.xqso = f[4].contains("X")
            q.freqHz = 14_025_000
            q.mode = .cw
            return q
        }
    }

    /// A QTC `S|R,partner,callsign,number` separated by `;` (the probe format).
    private static func qtcs(_ spec: String) -> [QtcRecord] {
        if spec.isEmpty { return [] }
        return spec.split(separator: ";", omittingEmptySubsequences: false).map { item in
            let f: [String] = item.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return QtcPlannerTests.rec(f[0] == "S", f[1], f[2], Int(f[3]) ?? 0)
        }
    }

    private static func check(_ id: String, expectedCount: Int, _ actual: ([String]) -> String) {
        let rows: [[String]] = Self.rows(id)
        #expect(rows.count == expectedCount, "\(id)")
        var mismatches = 0
        for row in rows {
            let got: String = actual(row)
            if got != row[row.count - 1] {
                mismatches += 1
                if mismatches <= 15 {
                    Issue.record("\(id) \(row): Swift \(got)")
                }
            }
        }
        #expect(mismatches == 0, "\(id): \(mismatches) mismatches")
    }

    @Test func serialMatchesJava() {
        Self.check("QTC.serial", expectedCount: 84) { row in
            var q = Qso()
            if row[0] != "-" { q.serialRcvd = Int(row[0]) }
            q.exchangeRcvd = Self.text(row[1]) ?? ""
            return String(QtcPlanner.serial(q))
        }
    }

    @Test func toLineMatchesJava() {
        Self.check("QTC.toLine", expectedCount: 6) { row in
            var q = Qso()
            q.timestampUtc = JavaInstant.parseIsoInstant(row[0])?.date
            q.call = Self.text(row[1]) ?? ""
            q.exchangeRcvd = Self.text(row[2]) ?? ""
            return QtcPlanner.toLine(q).map(\.description) ?? "nil"
        }
    }

    @Test func parseLineMatchesJava() {
        Self.check("QTC.parseLine", expectedCount: 34) { row in
            Self.line(QtcPlanner.parseLine(Self.text(row[0])))
        }
    }

    @Test func parseGroupMatchesJava() {
        Self.check("QTC.parseGroup", expectedCount: 20) { row in
            guard let group = QtcPlanner.parseGroup(Self.text(row[0])) else { return "Optional.empty" }
            return "Optional[\(group.groupNr)/\(group.count)]"
        }
    }

    @Test func cwTextMatchesJava() {
        Self.check("QTC.cwText", expectedCount: 3) { row in
            let lines: [QtcPlanner.Line] = row[1].isEmpty ? [] : row[1].split(separator: ";").map { item in
                let f: [String] = item.split(separator: ",").map(String.init)
                return QtcPlanner.Line(time: f[0], call: f[1], serial: Int(f[2]) ?? 0)
            }
            let text: [String] = QtcPlanner.cwText(Int(row[0]) ?? 0, lines)
            return "[" + text.joined(separator: ", ") + "]"
        }
    }

    @Test func remainingForMatchesJava() {
        Self.check("QTC.remaining", expectedCount: 240) { row in
            let list: [QtcRecord] = Self.qtcs(ProbeRows.unescape(row[0]))
            return String(QtcPlanner.remainingFor(Self.text(row[1]), list, Int(row[2]) ?? 0))
        }
    }

    @Test func candidatesMatchJava() {
        Self.check("QTC.candidates", expectedCount: 280) { row in
            let qsos: [Qso] = Self.log(ProbeRows.unescape(row[0]))
            let list: [QtcRecord] = Self.qtcs(ProbeRows.unescape(row[1]))
            let found: [Qso] = QtcPlanner.candidates(qsos, Self.text(row[2]), list, Int(row[3]) ?? 0, Int(row[4]) ?? 0)
            return "[" + found.map(\.call).joined(separator: ", ") + "]"
        }
    }
}
