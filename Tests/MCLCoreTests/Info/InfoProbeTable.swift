import Foundation
@testable import MCLCore

/// The probe table a maintainer-only probe, read from the repository, and the seeded
/// logs and rules it carries. Inputs and results escape control characters, NBSP and the backslash as `\uXXXX`.
enum InfoProbeTable {

    struct Row {
        let area: String
        let input: String
        let result: String
    }

    static let rows: [Row] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/jvm-probes/info-probe.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Row(area: parts[0], input: SpotsCoreProbeTable.unescape(parts[1]),
                       result: parts.count > 2 ? SpotsCoreProbeTable.unescape(parts[2]) : "")
        }
    }()

    static func area(_ name: String) -> [Row] {
        rows.filter { $0.area == name }
    }

    /// The probe's base instant, 2026-10-03T12:00:00Z.
    static let baseMillis: Int64 = 1_791_028_800_000

    /// The probe's contest start (09:30Z), `CONTEST_START`.
    static let contestStart: JavaInstant = instant(millis: baseMillis - 150 * 60_000)

    static func instant(millis: Int64) -> JavaInstant {
        JavaInstant.ofEpochSecond(JavaMath.floorDiv(millis, 1000), (millis - JavaMath.floorDiv(millis, 1000) * 1000) * 1_000_000)!
    }

    // MARK: - Logs

    /// The seeded logs (`log` rows): `epochMilli|call|band|mode|freqHz|exchange|serial|deleted|xqso|operator|continent|dxcc|run`.
    static let logs: [String: [Qso]] = {
        var out: [String: [Qso]] = [:]
        for row in area("log") {
            out[row.input] = row.result.isEmpty ? [] : row.result.split(separator: ";", omittingEmptySubsequences: false)
                .map { qso(String($0)) }
        }
        return out
    }()

    static func qso(_ text: String) -> Qso {
        let f: [String] = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        var q = Qso()
        q.timestampUtc = f[0] == "~" ? nil : Date(timeIntervalSince1970: Double(f[0])! / 1000.0)
        q.call = f[1]
        q.freqHz = Int(f[4])!
        q.band = f[2] == "~" ? nil : Band.from(adif: f[2])
        q.mode = f[3] == "~" ? nil : Mode(rawValue: f[3])
        q.exchangeRcvd = f[5]
        q.serialRcvd = f[6] == "~" ? nil : Int(f[6])
        q.deleted = f[7] == "true"
        q.xqso = f[8] == "true"
        q.operator = f[9]
        q.continent = f[10]
        q.dxccName = f[11]
        q.runMode = RunMode(rawValue: f[12])!
        return q
    }

    // MARK: - Rules

    /// The synthetic operating rules (`rule` rows): `off=<min>/<required> band=<min>/<perHour>`, `~` = null.
    static let rules: [String: ContestDefinition.Operating?] = {
        var out: [String: ContestDefinition.Operating?] = [:]
        for row in area("rule") {
            if row.result == "none" {
                out[row.input] = .some(nil)
                continue
            }
            let parts = row.result.split(separator: " ").map(String.init)
            let off = pair(String(parts[0].dropFirst(4)))
            let band = pair(String(parts[1].dropFirst(5)))
            let offTime: ContestDefinition.OffTime? = off.0 == nil && off.1 == nil
                ? nil : ContestDefinition.OffTime(minimumMinutes: off.0, requiredMinutes: off.1)
            let bandChange: ContestDefinition.BandChange? = band.0 == nil && band.1 == nil
                ? nil : ContestDefinition.BandChange(minimumMinutes: band.0, perHour: band.1)
            out[row.input] = ContestDefinition.Operating(offTime: offTime, bandChange: bandChange)
        }
        return out
    }()

    private static func pair(_ text: String) -> (Int?, Int?) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return (parts[0] == "~" ? nil : Int(parts[0]), parts[1] == "~" ? nil : Int(parts[1]))
    }

    static func operating(_ name: String) -> ContestDefinition.Operating? {
        rules[name] ?? nil
    }

    // MARK: - Goal sets

    /// `goalSet(name)` of the probe.
    static func goalSet(_ name: String) -> GoalSet {
        switch name {
        case "a":
            return GoalSet.of([109: 10, 110: 15, 111: 25, 112: 30, 113: 12, 114: 60, 115: 0])
        case "big":
            var entries: [Int32: Int32] = [:]
            for key in 109...118 {
                entries[Int32(key)] = 2_000_000_000
            }
            return GoalSet.of(entries)
        default:
            return GoalSet.empty()
        }
    }

    /// Java `List.toString`.
    static func listText(_ items: [String]) -> String {
        "[" + items.joined(separator: ", ") + "]"
    }
}
