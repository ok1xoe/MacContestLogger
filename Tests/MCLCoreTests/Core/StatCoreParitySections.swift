import Foundation
import Testing
@testable import MCLCore

/// Swift side of the `stat.*` sections of the Java parity suite (maintainer-only probe): `ContestStats`,
/// `RateReports`, `LogStatistics.perHour` and `OperatingGuard.check` over logs from the reference.
enum StatCoreParitySections {

    typealias Ctx = JavaCoreParityFixture.Ctx
    typealias Rows = JavaCoreParityFixture.Rows
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["stat.LOG", "stat.GUARD"]

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let depth: Int = path.split(separator: "/").count
        if depth == 2 {
            ctx.qsos = try log(f[0])
            ctx.stats = ContestStats.of(ctx.qsos)
            return name == "stat.LOG" ? [(path, try summary(ctx))] : []
        }
        switch name {
        case "stat.LOG": return [(path, try query(f, ctx))]
        case "stat.GUARD": return [(path, try guardCheck(f, ctx))]
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    /// A log `epochMilli|band|freqHz|R/S|deleted` separated by `;` (`-` = null).
    static func log(_ spec: String) throws -> [Qso] {
        if spec.isEmpty {
            return []
        }
        var out: [Qso] = []
        for part in spec.components(separatedBy: ";") {
            let f: [String] = part.components(separatedBy: "|")
            guard f.count == 5 else { throw X.Malformed(text: part) }
            var q = Qso()
            q.call = "X"
            if f[0] != "-" {
                q.timestampUtc = try X.instant(millis: f[0]).date
            }
            q.freqHz = try X.int(f[2])
            q.band = try band(f[1])
            q.runMode = f[3] == "R" ? .run : .searchAndPounce
            q.deleted = f[4] == "1"
            out.append(q)
        }
        return out
    }

    static func band(_ field: String) throws -> Band? {
        if field == "-" {
            return nil
        }
        guard let band = Band.from(adif: field) else { throw X.Malformed(text: field) }
        return band
    }

    static func opt(_ value: JavaInstant?) -> String {
        value.map { $0.description } ?? "~"
    }

    static let bands: [String] = ["20m", "40m", "15m", "80m", "-"]

    static func summary(_ ctx: Ctx) throws -> [String] {
        let st: ContestStats = ctx.stats
        let rfl: [String] = [-1, 0, 1, 2, 3, 5, 10, 100].map { String(st.rateForLastQsos($0)) }
        var perBand: [String] = []
        for field in bands {
            let b: Band? = try band(field)
            perBand.append(opt(st.lastQsoOnOtherBandAt(b)))
            perBand.append(opt(st.currentBandRunStart(b)))
        }
        let map: JavaLinkedMap<Int> = LogStatistics.perHour(ctx.qsos)
        let pairs: [String] = map.entries.map { (e: (key: String?, value: Int?)) -> String in
            "\(e.key ?? "null")=\(e.value.map { String($0) } ?? "null")"
        }
        let perHour: String = "{" + pairs.joined(separator: ", ") + "}"
        return [opt(st.lastQsoAt()), opt(st.firstQsoAt()), st.lastQsoBand()?.adif ?? "~", opt(st.offTimeStart()),
                rfl.joined(separator: ","), perBand.joined(separator: ","), perHour]
    }

    static func duration(_ seconds: String, _ nanos: String) throws -> Duration {
        Duration.seconds(try X.int64(seconds)) + Duration.nanoseconds(try X.int64(nanos))
    }

    static func query(_ f: [String], _ ctx: Ctx) throws -> [String] {
        let st: ContestStats = ctx.stats
        let qsos: [Qso] = ctx.qsos
        switch f[0] {
        case "rch":
            let now: JavaInstant = try X.instant(f[1], f[2])
            return [String(st.rateThisClockHour(now)), String(st.bandChangesInClockHour(now))]
        case "rph":
            let now: JavaInstant = try X.instant(f[1], f[2])
            let window: Duration = try duration(f[3], f[4])
            return [try X.run { String(try st.ratePerHour(now, window)) }]
        case "trend":
            let now: JavaInstant = try X.instant(f[1], f[2])
            let interval: Duration = try duration(f[3], f[4])
            let count: Int = try X.int(f[5])
            return [try X.run { X.javaList(try st.trendRates(now, interval, count)) }]
        case "cum":
            let start: JavaInstant = try X.instant(f[1], f[2])
            let now: JavaInstant = try X.instant(f[3], f[4])
            return [String(st.cumulativeOffMinutes(start, now, try X.int(f[5])))]
        case "best":
            guard let best = RateReports.bestRate(qsos, try X.int(f[1])) else { return ["~"] }
            let perHour: String = try X.run { String(try best.perHour()) }
            return ["\(best.start) \(best.end) \(best.qsos) \(best.windowMinutes) \(perHour)"]
        case "off":
            let list: [RateReports.OffTime] = RateReports.offTimes(qsos, try X.int(f[1]))
            let parts: [String] = list.map { (o: RateReports.OffTime) -> String in "\(o.from) \(o.to) \(o.minutes())" }
            return [parts.joined(separator: ",")]
        case "runs":
            let list: [RateReports.Run] = RateReports.runs(qsos, try X.int(f[1]))
            let parts: [String] = list.map { (r: RateReports.Run) -> String in
                "\(r.start) \(r.end) \(r.band) \(r.freqHz) \(r.qsos) \(r.minutes()) \(r.perHour())"
            }
            return [parts.joined(separator: ",")]
        case "clock":
            let now: JavaInstant = try X.instant(f[1], f[2])
            let ten: String = try X.run { String(try st.ratePerHour(now, .seconds(600))) }
            let hour: String = try X.run { String(try st.ratePerHour(now, .seconds(3600))) }
            let trend: String = try X.run { X.javaList(try st.trendRates(now, .seconds(1200), 3)) }
            return [String(st.rateThisClockHour(now)), ten, hour, trend]
        default:
            throw X.Malformed(text: "unknown query \(f[0])")
        }
    }

    static let types: [OperatingGuard.StationType] = [.none, .run, .mult]

    static func guardCheck(_ f: [String], _ ctx: Ctx) throws -> [String] {
        let rules: ContestDefinition.BandChange? = try rule(f[0])
        let b: Band? = try band(f[1])
        let now: JavaInstant = try X.instant(f[2], f[3])
        var out: [String] = []
        for type in types {
            for mult in [false, true] {
                out.append(F.tx(OperatingGuard.check(ctx.stats, rules, b, now, type, mult) ?? "~"))
            }
        }
        return out
    }

    static func rule(_ spec: String) throws -> ContestDefinition.BandChange? {
        if spec == "-" {
            return nil
        }
        let p: [String] = spec.components(separatedBy: ":")
        guard p.count == 2 else { throw X.Malformed(text: spec) }
        let minimum: Int? = p[0] == "-" ? nil : try X.int(p[0])
        let perHour: Int? = p[1] == "-" ? nil : try X.int(p[1])
        return ContestDefinition.BandChange(minimumMinutes: minimum, perHour: perHour)
    }
}
