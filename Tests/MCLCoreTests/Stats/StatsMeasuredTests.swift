import Foundation
import Testing
@testable import MCLCore

/// `stats/` and `OperatingGuard.check` against Java v1.1.1 (maintainer-only probe,
/// table `StatsMeasured`): 13 synthetic logs (empty, one QSO, equal times, window and hour boundaries,
/// milliseconds, deleted and without time/band, before 1970, runs at the tolerance limits and gaps,
/// a tie of the best window, two random ones) × a grid of "now", windows (zero, half-second, negative, extreme
/// `long`), intervals, column counts and band-change rules; exceptions as `throws <class>: <message>`.
@Suite struct StatsMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(StatsMeasured.rows, id)
    }

    private static func grid(_ name: String) -> [String] {
        let row: [String] = rows("grid").first { $0[0] == name } ?? []
        return row.count > 1 ? row[1].components(separatedBy: "|") : []
    }

    private static let logs: [String: [Qso]] = {
        var out: [String: [Qso]] = [:]
        for row in rows("log") {
            out[row[0]] = parseLog(row[1])
        }
        return out
    }()

    private static let stats: [String: ContestStats] = logs.mapValues { ContestStats.of($0) }

    private static func parseLog(_ spec: String) -> [Qso] {
        if spec.isEmpty {
            return []
        }
        var out: [Qso] = []
        for part in spec.components(separatedBy: ";") {
            let f: [String] = part.components(separatedBy: "|")
            var q = Qso()
            q.call = "X"
            if f[0] != "-" {
                let ms = Int64(f[0])!
                let second: Int64 = JavaMath.floorDiv(ms, 1000)
                let nanos: Int64 = (ms - second * 1000) * 1_000_000
                q.timestampUtc = JavaInstant.ofEpochSecond(second, nanos)!.date
            }
            q.freqHz = Int(f[2])!
            q.band = f[1] == "-" ? nil : Band.from(adif: f[1])!
            q.runMode = f[3] == "R" ? .run : .searchAndPounce
            q.deleted = f[4] == "1"
            out.append(q)
        }
        return out
    }

    private static func instant(_ text: String) -> JavaInstant {
        JavaInstant.parseIsoInstant(text)!
    }

    private static func band(_ text: String) -> Band? {
        text == "-" ? nil : Band.from(adif: text)!
    }

    private static func duration(_ spec: String) -> Duration {
        let p: [String] = spec.components(separatedBy: ":")
        return Duration.seconds(Int64(p[0])!) + Duration.nanoseconds(Int64(p[1])!)
    }

    private static func opt(_ value: CustomStringConvertible?) -> String {
        value.map { $0.description } ?? "-"
    }

    private static func javaList(_ values: [Int]) -> String {
        let body: String = values.map { (v: Int) -> String in String(v) }.joined(separator: ", ")
        return "[\(body)]"
    }

    /// `throws <class>: <message>` like the probe's `run`.
    private static func run(_ body: () throws -> String) -> String {
        do {
            return try body()
        } catch let error as JavaArithmeticError {
            return "throws java.lang.ArithmeticException: " + error.message
        } catch let error as JavaIllegalArgumentError {
            return "throws java.lang.IllegalArgumentException: " + error.message
        } catch {
            return "throws ?: \(error)"
        }
    }

    /// Compares rows of one kind; `actual` gets the row and returns the expected number of trailing columns.
    private static func check(_ id: String, expectedCount: Int, _ actual: ([String]) -> [String]) {
        let rows: [[String]] = Self.rows(id)
        #expect(rows.count == expectedCount, "\(id)")
        var mismatches = 0
        for row in rows {
            let got: [String] = actual(row)
            let want: [String] = Array(row.suffix(got.count))
            if got != want {
                mismatches += 1
                if mismatches <= 15 {
                    Issue.record("\(id) \(row.prefix(row.count - got.count)): Java \(want), Swift \(got)")
                }
            }
        }
        #expect(mismatches == 0, "\(id)")
    }

    @Test func logsParsed() {
        #expect(Self.logs.count == 13)
        #expect(Self.grid("windows").count == 10)
    }

    @Test func rateForLastQsos() {
        Self.check("rfl", expectedCount: 91) { row in
            [String(Self.stats[row[0]]!.rateForLastQsos(Int(row[1])!))]
        }
    }

    @Test func timers() {
        Self.check("last", expectedCount: 13) { row in
            let s: ContestStats = Self.stats[row[0]]!
            return [Self.opt(s.lastQsoAt()), Self.opt(s.firstQsoAt()), s.lastQsoBand()?.adif ?? "-",
                    Self.opt(s.offTimeStart())]
        }
        Self.check("band", expectedCount: 52) { row in
            let s: ContestStats = Self.stats[row[0]]!
            let b: Band? = Self.band(row[1])
            return [Self.opt(s.lastQsoOnOtherBandAt(b)), Self.opt(s.currentBandRunStart(b))]
        }
    }

    @Test func clockHour() {
        Self.check("rch", expectedCount: 130) { row in
            let s: ContestStats = Self.stats[row[0]]!
            let now: JavaInstant = Self.instant(row[1])
            return [String(s.rateThisClockHour(now)), String(s.bandChangesInClockHour(now))]
        }
    }

    @Test func ratePerHour() {
        let windows: [Duration] = Self.grid("windows").map(Self.duration)
        Self.check("rph", expectedCount: 130) { row in
            let s: ContestStats = Self.stats[row[0]]!
            let now: JavaInstant = Self.instant(row[1])
            let results: [String] = windows.map { w in
                Self.run { String(try s.ratePerHour(now, w)) }
            }
            return [results.joined(separator: "|")]
        }
    }

    @Test func trendRates() {
        let counts: [Int] = Self.grid("counts").map { Int($0)! }
        Self.check("trend", expectedCount: 780) { row in
            let s: ContestStats = Self.stats[row[0]]!
            let now: JavaInstant = Self.instant(row[1])
            let interval: Duration = Self.duration(row[2])
            let results: [String] = counts.map { c in
                Self.run { Self.javaList(try s.trendRates(now, interval, c)) }
            }
            return [results.joined(separator: "|")]
        }
    }

    @Test func cumulativeOffMinutes() {
        let mins: [Int] = Self.grid("cumMins").map { Int($0)! }
        Self.check("cum", expectedCount: 390) { row in
            let s: ContestStats = Self.stats[row[0]]!
            let start: JavaInstant = Self.instant(row[1])
            let now: JavaInstant = Self.instant(row[2])
            let results: [String] = mins.map { String(s.cumulativeOffMinutes(start, now, $0)) }
            return [results.joined(separator: "|")]
        }
    }

    @Test func bestRate() {
        Self.check("best", expectedCount: 78) { row in
            guard let b = RateReports.bestRate(Self.logs[row[0]]!, Int(row[1])!) else { return ["-"] }
            let perHour: String = Self.run { String(try b.perHour()) }
            return ["\(b.start) \(b.end) \(b.qsos) \(b.windowMinutes) \(perHour)"]
        }
    }

    @Test func offTimes() {
        Self.check("off", expectedCount: 78) { row in
            let list: [RateReports.OffTime] = RateReports.offTimes(Self.logs[row[0]]!, Int(row[1])!)
            let parts: [String] = list.map { (o: RateReports.OffTime) -> String in
                "\(o.from) \(o.to) \(o.minutes())"
            }
            return [parts.joined(separator: ",")]
        }
    }

    @Test func runs() {
        Self.check("runs", expectedCount: 65) { row in
            let list: [RateReports.Run] = RateReports.runs(Self.logs[row[0]]!, Int(row[1])!)
            let parts: [String] = list.map { (r: RateReports.Run) -> String in
                "\(r.start) \(r.end) \(r.band) \(r.freqHz) \(r.qsos) \(r.minutes()) \(r.perHour())"
            }
            return [parts.joined(separator: ",")]
        }
    }

    @Test func perHour() {
        Self.check("perhour", expectedCount: 13) { row in
            let map: JavaLinkedMap<Int> = LogStatistics.perHour(Self.logs[row[0]]!)
            let parts: [String] = map.entries.map { (e: (key: String?, value: Int?)) -> String in
                "\(e.key ?? "null")=\(e.value ?? 0)"
            }
            let body: String = parts.joined(separator: ", ")
            return ["{\(body)}"]
        }
    }

    @Test func operatingGuard() {
        let types: [OperatingGuard.StationType] = [.none, .run, .mult]
        Self.check("guard", expectedCount: 1372) { row in
            let s: ContestStats = Self.stats[row[0]]!
            let rules: ContestDefinition.BandChange? = Self.rules(row[1])
            let b: Band? = Self.band(row[2])
            let now: JavaInstant = Self.instant(row[3])
            var results: [String] = []
            for type in types {
                for mult in [false, true] {
                    results.append(OperatingGuard.check(s, rules, b, now, type, mult) ?? "-")
                }
            }
            return [results.joined(separator: "|")]
        }
    }

    private static func rules(_ spec: String) -> ContestDefinition.BandChange? {
        if spec == "-" {
            return nil
        }
        let p: [String] = spec.components(separatedBy: ":")
        return ContestDefinition.BandChange(minimumMinutes: p[0] == "-" ? nil : Int(p[0]),
                                            perHour: p[1] == "-" ? nil : Int(p[1]))
    }
}
