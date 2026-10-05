import Foundation
import Testing
@testable import MCLCore

/// Swift side of the sections `qtc.*`, `info.*`, `sim.*` of the Java parity suite (maintainer-only probe):
/// `QtcPlanner`, `CallsignInfo.forEntity` and `PileupSimulator`/`CwSynth` (the randomness `JavaPileupRandom` bit by bit
/// like `java.util.Random`; nothing plays to a device).
enum ToolCoreParitySections {

    typealias Ctx = JavaCoreParityFixture.Ctx
    typealias Rows = JavaCoreParityFixture.Rows
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = [
        "qtc.SERIAL", "qtc.PARSE", "qtc.CAND", "qtc.CAB", "info.FOR", "sim.RUN", "sim.SRC", "sim.ED", "sim.CW",
    ]

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "qtc.SERIAL": return [(path, path.hasPrefix("s/") ? try serial(f) : try toLine(f))]
        case "qtc.PARSE": return [(path, path.hasPrefix("cw/") ? try cwText(f) : parse(f))]
        case "qtc.CAND": return [(path, try candidates(f))]
        case "qtc.CAB": return [(path, try cabrillo(f))]
        case "info.FOR": return [(path, try info(f))]
        case "sim.RUN": return try simRun(path, f, ctx)
        case "sim.SRC": return [(path, try source(f))]
        case "sim.ED": return [(path, [String(PileupSimulator.editDistance(X.text(f[0]) ?? "", X.text(f[1]) ?? ""))])]
        case "sim.CW": return [(path, try cw(path, f))]
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    // MARK: - qtc

    static func line(_ l: QtcPlanner.Line) -> String {
        F.tx(l.time) + " " + F.tx(l.call) + " " + String(l.serial)
    }

    static func optionalInt(_ field: String) throws -> Int? {
        field == "~" ? nil : try X.int(field)
    }

    static func serial(_ f: [String]) throws -> [String] {
        var q = Qso()
        q.serialRcvd = try optionalInt(f[0])
        q.exchangeRcvd = X.text(f[1]) ?? "" // Swift `Qso.exchangeRcvd` is non-optional; Java reads `null` as ""
        return [String(QtcPlanner.serial(q))]
    }

    static func toLine(_ f: [String]) throws -> [String] {
        var q = Qso()
        q.timestampUtc = try X.instant(millis: f[0]).date
        q.call = X.text(f[1]) ?? ""
        q.serialRcvd = try optionalInt(f[2])
        q.exchangeRcvd = X.text(f[3]) ?? ""
        guard let l = QtcPlanner.toLine(q) else { throw X.Malformed(text: "toLine without a time") }
        return [line(l)]
    }

    static func parse(_ f: [String]) -> [String] {
        let text: String? = X.text(f[0])
        let group: String = QtcPlanner.parseGroup(text).map { "\($0.groupNr)/\($0.count)" } ?? "~"
        return [QtcPlanner.parseLine(text).map(line) ?? "~", group]
    }

    static func cwText(_ f: [String]) throws -> [String] {
        let group: Int = try X.int(f[0])
        let count: Int = try X.int(f[1])
        guard 2 + 3 * count == f.count else { throw X.Malformed(text: "QTC rows") }
        var lines: [QtcPlanner.Line] = []
        for index in 0..<count {
            let base: Int = 2 + 3 * index
            lines.append(QtcPlanner.Line(time: X.text(f[base]) ?? "", call: X.text(f[base + 1]) ?? "",
                                         serial: try X.int(f[base + 2])))
        }
        return QtcPlanner.cwText(group, lines).map { F.tx($0) }
    }

    static let qtcBase: JavaInstant = JavaInstant.ofEpochSecond(1_786_190_400, 0)! // 2026-08-08T12:00:00Z
    static let qtcAt: JavaInstant = JavaInstant.ofEpochSecond(1_786_194_000, 0)! // 2026-08-08T13:00:00Z

    static func candidates(_ f: [String]) throws -> [String] {
        var index = 0
        func next() throws -> String {
            guard index < f.count else { throw X.Malformed(text: "QTC candidates past the end of the row") }
            index += 1
            return f[index - 1]
        }
        var qsos: [Qso] = []
        let n: Int = try X.int(try next())
        for _ in 0..<n {
            let minute: String = try next()
            var q = Qso()
            if minute != "~" {
                q.timestampUtc = qtcBase.date.addingTimeInterval(60 * Double(try X.int(minute)))
            }
            q.call = X.text(try next()) ?? ""
            q.serialRcvd = try optionalInt(try next())
            q.exchangeRcvd = X.text(try next()) ?? ""
            let flags: String = try next()
            q.deleted = flags.contains("D")
            q.xqso = flags.contains("X")
            q.freqHz = 14_025_000
            q.mode = .cw
            qsos.append(q)
        }
        var qtcs: [QtcRecord] = []
        let m: Int = try X.int(try next())
        for _ in 0..<m {
            let sent: Bool = X.bool(try next())
            let partner: String = X.text(try next()) ?? ""
            let call: String = X.text(try next()) ?? ""
            let number: Int = try X.int(try next())
            qtcs.append(QtcRecord(contestId: "wae", sent: sent, partnerCall: partner, groupNr: 1, groupSize: 10,
                                  qsoTime: "1200", qsoCall: call, qsoSerial: number, at: qtcAt.date,
                                  freqHz: 14_025_000, mode: "CW"))
        }
        let partner: String? = X.text(try next())
        let max: Int = try X.int(try next())
        let group: Int = try X.int(try next())
        let picked: [Qso] = QtcPlanner.candidates(qsos, partner, qtcs, max, group)
        return [String(QtcPlanner.remainingFor(partner, qtcs, max))] + picked.map { F.tx($0.call) }
    }

    static func cabrillo(_ f: [String]) throws -> [String] {
        let record = QtcRecord(contestId: "wae", sent: X.bool(f[0]), partnerCall: X.text(f[1]) ?? "",
                               groupNr: try X.int(f[2]), groupSize: try X.int(f[3]), qsoTime: X.text(f[4]) ?? "",
                               qsoCall: X.text(f[5]) ?? "", qsoSerial: try X.int(f[6]),
                               at: try X.instant(millis: f[7]).date, freqHz: try X.int64(f[8]), mode: X.text(f[9]))
        return [F.tx(QtcPlanner.cabrilloLine(record, X.text(f[10]) ?? ""))]
    }

    // MARK: - info

    static func s<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "null"
    }

    static func info(_ f: [String]) throws -> [String] {
        var index = 2
        var continents: [String?]?
        if f[index] != "~" {
            let count: Int = try X.int(f[index])
            continents = (0..<count).map { X.text(f[index + 1 + $0]) }
            index += count
        }
        index += 1
        var zones: [Int?]?
        if f[index] != "~" {
            let count: Int = try X.int(f[index])
            zones = try (0..<count).map { try optionalInt(f[index + 1 + $0]) }
            index += count
        }
        index += 1
        guard index + 6 == f.count else { throw X.Malformed(text: "entita") }
        let entity = DxccEntity(entityCode: 1, name: X.text(f[1]), countryCode: X.text(f[0]), continents: continents,
                                cq: zones, itu: [28], lat: try X.double(bits: f[index]),
                                lon: try X.double(bits: f[index + 1]), primaryPrefix: X.text(f[0]))
        let myLat: Double = try X.double(bits: f[index + 2])
        let myLon: Double = try X.double(bits: f[index + 3])
        let now: JavaInstant = try X.instant(f[index + 4], f[index + 5])
        do throws(JavaDateTimeException) {
            let i: CallsignInfo = try CallsignInfo.forEntity(entity, myLat: myLat, myLon: myLon, now: now)
            let cols: [String] = [
                s(i.prefix), s(i.entityName), s(i.continent), s(i.cqZone), s(i.shortPathDeg), s(i.longPathDeg),
                s(i.distanceKm), s(i.distanceMiles), s(i.sunrise), s(i.sunset), s(i.dxLocalTime),
                s(i.dxDayOfWeek?.javaName),
            ]
            return [F.tx(cols.joined(separator: "|"))]
        } catch {
            return ["THROW DateTimeException"]
        }
    }

    // MARK: - sim

    static let testPool: [String] = ["DL1ABC", "OK2XYZ", "SP9AAA", "G4BBB", "K1ZZ"]
    static let oddPool: [String] = ["ok1abc", "OK1ABC", " ", "DL1X", "dl1x", "", "\u{DF}1A", "OK2XYZ"]

    static func source(_ kind: String, _ random: any PileupRandom) throws -> () -> String? {
        switch kind {
        case "made": return PileupSimulator.callSource(pool: [], random: random)
        case "pool": return PileupSimulator.callSource(pool: testPool, random: random)
        case "odd": return PileupSimulator.callSource(pool: oddPool, random: random)
        case "null": return PileupSimulator.callSource(pool: nil, random: random)
        case "nothing": return { nil }
        default: throw X.Malformed(text: "callsign source \(kind)")
        }
    }

    static func caller(_ c: PileupSimulator.Caller?) -> String {
        guard let c else { return "null" }
        let cols: [String] = [c.call, String(c.serial), String(c.wpm), String(c.pitchOffsetHz), String(c.patience)]
        return cols.joined(separator: "/")
    }

    static func sent(_ out: [PileupSimulator.Transmission]) -> String {
        out.map { (t: PileupSimulator.Transmission) -> String in
            caller(t.from) + ">" + String(t.delayMs) + ">" + t.text
        }.joined(separator: ";")
    }

    static func simRun(_ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if path.split(separator: "/").count == 2 {
            let settings = PileupSimulator.Settings(activity: try X.int32(f[0]), minWpm: try X.int32(f[1]),
                                                    maxWpm: try X.int32(f[2]), pitchSpreadHz: try X.int32(f[3]))
            let seed: Int64 = try X.int64(f[4])
            let random = JavaPileupRandom(seed: seed)
            let callRandom: any PileupRandom = X.bool(f[6]) ? random : JavaPileupRandom(seed: seed ^ 0x5EED)
            ctx.simulator = PileupSimulator(settings: settings, callSource: try source(f[5], callRandom), random: random)
            return []
        }
        guard let sim = ctx.simulator else { throw X.Malformed(text: "step without a simulator") }
        let result: String
        switch f[0] {
        case "S":
            let text: String? = X.text(f[1])
            result = try X.run { sent(try sim.onSent(text)) }
        case "N":
            result = try X.run { sent(try sim.onSent(nil)) }
        case "L":
            let k: PileupSimulator.Check = sim.onLogged(call: X.text(f[1]), exchange: X.text(f[2]))
            let cols: [String] = [k.loggedCall, k.expectedCall, String(k.callOk), String(k.exchangeOk),
                                  k.expectedExchange]
            result = cols.joined(separator: "|")
        default:
            throw X.Malformed(text: "simulator step \(f[0])")
        }
        let callers: String = sim.callers.map { caller($0) }.joined(separator: ",")
        return [(path, [F.tx(result), F.tx(callers), F.tx(caller(sim.current)), String(sim.qsos), String(sim.errors)])]
    }

    static func source(_ f: [String]) throws -> [String] {
        let next: () -> String? = try source(f[0], JavaPileupRandom(seed: try X.int64(f[1])))
        return (0..<30).map { _ in F.tx(next()) }
    }

    static func runs(_ v: [Bool]) -> String {
        var parts: [String] = []
        var i = 0
        while i < v.count {
            var j = i
            while j < v.count && v[j] == v[i] { j += 1 }
            parts.append((v[i] ? "+" : "-") + String(j - i))
            i = j
        }
        return parts.joined(separator: ",")
    }

    static let wpms: [Int32] = [-1] + Array(5...70) + [100]

    static func cw(_ path: String, _ f: [String]) throws -> [String] {
        if path.hasPrefix("d/") {
            let rate: Float = try X.float(bits: f[0])
            let dits: [String] = wpms.map { String(CwSynth.keying("E", wpm: $0, sampleRate: rate).count / 4) }
            return [dits.joined(separator: ",")]
        }
        let text: String = X.text(f[0]) ?? ""
        let wpm: Int32 = try X.int32(f[1])
        if path.hasPrefix("k/") {
            let key: [Bool] = CwSynth.keying(text, wpm: wpm, sampleRate: try X.float(bits: f[2]))
            return [String(key.count), runs(key)]
        }
        let out: [Float] = CwSynth.render(text, wpm: wpm, pitchHz: try X.double(bits: f[2]),
                                          amplitude: try X.double(bits: f[3]), sampleRate: try X.float(bits: f[4]))
        return [String(out.count), runs(out.map { $0 != 0 })]
    }
}
