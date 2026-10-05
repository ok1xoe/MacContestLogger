import Foundation
@testable import MCLCore

/// Swift side of the sections `broadcast.*`, `n1mmrecv.*` and `scoreboard.*` of the network reference
/// (maintainer-only probe, format documented with the probe): for an input row `in` it produces output
/// rows `out` with the same notation as the generator. The breakdowns `scoreboard.SXML/bdNNNN` are held by `Ctx` for later
/// rows `xNNNN`. A Java `null` in `rstSent`/`rstRcvd` is an empty string in the Swift `Qso` (`""` ↔ `~`).
/// Called by the gate `JavaNetParityTests`.
enum BroadcastParitySections {

    static let names: [String] = ["broadcast.TGT", "broadcast.BXML", "n1mmrecv.N1MM", "scoreboard.SXML"]

    typealias F = JavaIoParityFixture
    typealias V = JavaNetParityValues
    typealias Rows = [(String, [String])]

    final class Ctx {
        var breakdowns: [ScoreBreakdown] = []
    }

    static func s(_ v: String) -> String? { F.untx(v) }
    static func b(_ v: Bool) -> String { v ? "1" : "0" }

    static func date(_ sec: String, _ nanos: String) throws -> Date? {
        guard sec != "~" else { return nil }
        let seconds: Double = Double(try V.int64(sec))
        let fraction: Double = Double(try V.int64(nanos)) / 1e9
        return Date(timeIntervalSince1970: seconds + fraction)
    }

    static func i32(_ v: String) throws -> Int32? {
        v == "~" ? nil : try V.int32(v)
    }

    static func instantFields(_ d: Date?) -> [String] {
        guard let d else { return ["~", "~"] }
        let floor: Double = d.timeIntervalSince1970.rounded(.down)
        let nanos = Int64(((d.timeIntervalSince1970 - floor) * 1e9).rounded())
        return [String(Int64(floor)), String(nanos)]
    }

    static func compute(_ sec: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch sec {
        case "broadcast.TGT":
            var out: [String] = []
            for t in Target.parseAll(s(f[0])) {
                out.append(F.tx(t.host))
                out.append(String(t.port))
            }
            return [(path, out)]
        case "broadcast.BXML": return try xml(path, f)
        case "n1mmrecv.N1MM": return [(path, n1mm(f))]
        case "scoreboard.SXML": return try score(path, f, ctx)
        default: throw V.Malformed(text: "unknown section \(sec)")
        }
    }

    static func xml(_ path: String, _ f: [String]) throws -> Rows {
        if path.hasPrefix("contact") {
            let c = BroadcastXml.ContactData(
                contestName: s(f[0]), contestNr: try V.int32(f[1]), timestamp: try date(f[2], f[3]),
                myCall: s(f[4]), rxFreqHz: try V.int64(f[5]), txFreqHz: try V.int64(f[6]), mode: s(f[7]),
                call: s(f[8]), continent: s(f[9]), snt: s(f[10]), sntNr: try i32(f[11]),
                rcv: s(f[12]), rcvNr: try i32(f[13]), points: try V.int32(f[14]), isMultiplier: f[15] == "1",
                id: s(f[16]), stationName: s(f[17]))
            let oldTs: Date? = try date(f[19], f[20])
            let replace: String = BroadcastXml.contactReplace(c, oldCall: s(f[18]), oldTs: oldTs)
            return [(path + "/info", [F.tx(BroadcastXml.contactInfo(c))]), (path + "/replace", [F.tx(replace)]),
                    (path + "/delete", [F.tx(BroadcastXml.contactDelete(c))])]
        }
        if path.hasPrefix("radio") {
            let d = BroadcastXml.RadioData(stationName: s(f[0]), freqHz: try V.int64(f[1]), mode: s(f[2]),
                                           opCall: s(f[3]), isRunning: f[4] == "1")
            return [(path, [F.tx(BroadcastXml.radioInfo(d))])]
        }
        if path.hasPrefix("score") {
            let d = BroadcastXml.ScoreData(contest: s(f[0]), call: s(f[1]), ops: s(f[2]), score: try V.int64(f[3]),
                                           timestamp: try date(f[4], f[5]))
            return [(path, [F.tx(BroadcastXml.dynamicResults(d))])]
        }
        let d = BroadcastXml.AppInfoData(dbName: s(f[0]), contestNr: try V.int32(f[1]), contestName: s(f[2]),
                                         stationName: s(f[3]), myCall: s(f[4]))
        return [(path, [F.tx(BroadcastXml.appInfo(d))])]
    }

    static func n1mm(_ f: [String]) -> [String] {
        guard let pc = N1mmContactParser.parse(s(f[0])) else { return ["null"] }
        let q = pc.qso
        var out: [String] = ["contact", F.tx(q.call)]
        out += instantFields(q.timestampUtc)
        out += [String(q.freqHz), q.band?.rawValue ?? "~", q.mode?.adif ?? "~"]
        out.append(q.rstSent.isEmpty ? "~" : F.tx(q.rstSent))
        out.append(q.rstRcvd.isEmpty ? "~" : F.tx(q.rstRcvd))
        out.append(q.serialSent.map { String($0) } ?? "~")
        out.append(q.serialRcvd.map { String($0) } ?? "~")
        out.append(F.tx(pc.app))
        out.append(F.tx(pc.stationName))
        for e in pc.fields.entries {
            out.append(F.tx(e.key))
            out.append(F.tx(e.value))
        }
        return out
    }

    static func score(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.hasPrefix("bd") {
            let session = try SessionFixture.session("@" + f[0] + ".yaml")
            var qsos: [Qso] = []
            var k = 1
            while k + 4 < f.count {
                var q = Qso()
                let minute: Int = try V.int(f[k])
                q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(1_795_867_200 + 60 * minute))
                q.call = f[k + 1]
                q.freqHz = try V.int(f[k + 2])
                q.mode = f[k + 3] == "~" ? nil : Mode.from(adif: f[k + 3])
                q.exchangeRcvd = f[k + 4]
                qsos.append(q)
                k += 5
            }
            ctx.breakdowns.append(try ScoreBreakdown.compute(session, qsos))
            return []
        }
        var k = 0
        func next() -> String {
            defer { k += 1 }
            return k < f.count ? f[k] : "~"
        }
        let contest = s(next())
        let call = s(next())
        let ops = s(next())
        let club = s(next())
        let cq = s(next())
        let itu = s(next())
        let grid = s(next())
        let catCount = next()
        var cat: [String: String]?
        if catCount != "~" {
            var m: [String: String] = [:]
            for _ in 0..<(try V.int(catCount)) {
                let key: String = s(next()) ?? ""
                m[key] = s(next()) ?? ""
            }
            cat = m
        }
        let qc: Int32 = try V.int32(next())
        let qp: Int64 = try V.int64(next())
        let mt: Int32 = try V.int32(next())
        let total: Int64 = try V.int64(next())
        let bdIndex: Int = try V.int(next())
        let withBreakdown = next() == "1"
        let version = s(next())
        let nowSeconds = next()
        guard let now = try date(nowSeconds, next()) else { throw V.Malformed(text: "SXML bez now") }
        let station = ScoreXml.Station(call: call, ops: ops, club: club, cqZone: cq, ituZone: itu, grid: grid,
                                       category: cat)
        let state = ScoreState(qsoCount: qc, qsoPoints: qp, multTotal: mt, multByGroup: JavaLinkedMap(),
                               bonusPoints: 0, qtcPoints: 0, total: total)
        let breakdown: ScoreBreakdown? = bdIndex < 0 || bdIndex >= ctx.breakdowns.count ? nil : ctx.breakdowns[bdIndex]
        let xml = ScoreXml.build(contestName: contest, station: station, score: state, breakdown: breakdown,
                                 withBreakdown: withBreakdown, version: version, now: now)
        return [(path, [F.tx(xml)])]
    }
}
