import Foundation
@testable import MCLCore

/// Swift side of the `hamqth.*` and `clublog.*` sections of the network reference (maintainer-only probe, format
/// documented with the probe): for an input row `in` it produces output rows `out` with the same notation as the generator. Some
/// items have several `in` rows in a row (`FLOW/…` + `/calls`, `PREFILL/…/rec` + `/fields`, `GRIDF/csv`) — the state
/// between them is held by `Ctx`. Called by the gate `JavaNetParityTests`.
enum CallbookParitySections {

    static let names: [String] = [
        "hamqth.HQ", "hamqth.QRZ", "hamqth.MASK", "hamqth.FLOW", "hamqth.PREFILL", "hamqth.GRIDDB", "hamqth.GRIDF",
        "clublog.FORM",
    ]

    typealias F = JavaIoParityFixture

    static func b(_ v: Bool) -> String { v ? "1" : "0" }

    static func record(_ r: HamQthRecord) -> [String] {
        [F.tx(r.grid), F.tx(r.name), F.tx(r.cqZone), F.tx(r.ituZone), b(r.isEmpty)]
    }

    static func unhex(_ s: String) -> Data {
        var bytes: [UInt8] = []
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            bytes.append(UInt8(s[index..<next], radix: 16) ?? 0)
            index = next
        }
        return Data(bytes)
    }

    /// State between the `in` rows of one item (order of rows in the reference).
    final class Ctx {
        let dxcc: DxccResolver
        var flowIn: [String] = []
        var rec: HamQthRecord?
        var fieldMap: GridFieldMap?

        /// - Parameter dxcc: resolver over `dxcc-test.json` (like the generator)
        init(dxcc: DxccResolver) {
            self.dxcc = dxcc
        }
    }

    static func compute(_ sec: String, _ path: String, _ inp: [String],
                        _ ctx: Ctx) throws -> [(String, [String])] {
        switch sec {
        case "hamqth.HQ":
            let xml = F.untx(inp[0])
            var out = record(HamQthClient.parseRecord(xml))
            out.append(F.tx(HamQthClient.parseSessionId(xml)))
            out.append(F.tx(HamQthClient.parseError(xml)))
            out.append(F.tx(HamQthClient.parseGrid(xml)))
            return [(path, out)]
        case "hamqth.QRZ":
            let xml = F.untx(inp[0])
            var out = record(QrzClient.parseRecord(xml))
            out.append(F.tx(QrzClient.parseKey(xml)))
            out.append(F.tx(QrzClient.parseError(xml)))
            return [(path, out)]
        case "hamqth.MASK":
            return [(path, [F.tx(HamQthLog.mask(F.untx(inp[0])))])]
        case "hamqth.FLOW":
            if !path.hasSuffix("/calls") {
                ctx.flowIn = inp
                return []
            }
            return try flow(String(path.dropLast(6)), ctx.flowIn, inp.map { F.untx($0) })
        case "hamqth.PREFILL":
            if path.hasSuffix("/rec") {
                ctx.rec = inp == ["~"] ? nil : HamQthRecord(grid: F.untx(inp[0]), name: F.untx(inp[1]),
                                                           cqZone: F.untx(inp[2]), ituZone: F.untx(inp[3]))
                return []
            }
            let base = String(path.dropLast(7))
            var fields: [ContestDefinition.ExchangeField]?
            if inp != ["~"] {
                var list: [ContestDefinition.ExchangeField] = []
                var i = 0
                while i < inp.count {
                    let type: ContestDefinition.FieldType? = inp[i + 1] == "~" ? nil
                        : ContestDefinition.FieldType(rawValue: inp[i + 1])
                    list.append(.init(id: F.untx(inp[i]), type: type, required: true, source: nil, appliesWhen: nil,
                                      validation: nil, estimate: nil))
                    i += 2
                }
                fields = list
            }
            let map = CallbookPrefill.prefill(ctx.rec, fields)
            var pairs: [String] = []
            for key in map.keys {
                pairs.append(F.tx(key))
                pairs.append(F.tx(map[key]))
            }
            var out: [(String, [String])] = [(base + "/map", pairs)]
            if let rec = ctx.rec {
                out.append((base + "/describe", [F.tx(CallbookPrefill.describe(rec))]))
            }
            return out
        case "hamqth.GRIDDB":
            let data = unhex(inp[0])
            let db = GridDatabase.fromCsv(data)
            var dbOut = [String(db.size)]
            for q in dbQuery { dbOut.append(F.tx(db.grid(q))) }
            // Files with KELVIN SIGN are omitted by the generator for fields (a divergence of the Swift DxccResolver, not of the map).
            if JavaUtf8.decode(data).unicodeScalars.contains("\u{212A}") {
                return [(path + "/db", dbOut)]
            }
            let map = GridFieldMap.build(data, ctx.dxcc)
            var fm: [String] = []
            for f in fieldQuery {
                var bits = b(map.known(f))
                for code in fieldCodes { bits += b(map.matches(f, entityCode: code)) }
                fm.append(bits)
            }
            return [(path + "/db", dbOut), (path + "/fields", fm)]
        case "hamqth.GRIDF":
            if path == "GRIDF/csv" {
                ctx.fieldMap = GridFieldMap.build(Data((F.untx(inp[0]) ?? "").utf8), ctx.dxcc)
                return []
            }
            let comment = F.untx(inp[0])
            let code = Int(inp[1]) ?? 0
            let prefix = F.untx(inp[2])
            let lat = Double(inp[3]) ?? .nan
            let lon = Double(inp[4]) ?? .nan
            let entity = DxccEntity(entityCode: code, name: "E", countryCode: prefix, continents: ["EU"], cq: [1],
                                    itu: [1], lat: lat, lon: lon, primaryPrefix: prefix)
            let box = LogBox()
            let g = GridComment.extractGrid(comment, entity, fieldMap: ctx.fieldMap, log: { box.lines.append($0) })
            return [(path, [F.tx(g)] + box.lines.map { F.tx($0) })]
        case "clublog.FORM":
            if path.hasPrefix("FORM/classify/") {
                return [(path, [ClubLogClient.classify(Int(inp[0]) ?? 0).rawValue])]
            }
            let v = inp.prefix(5).map { F.untx($0) }
            let status = Int(inp[5]) ?? 0
            let body = ClubLogClient.formBody(email: v[0], password: v[1], callsign: v[2], apiKey: v[3],
                                              adifRecord: v[4])
            let outcome: ClubLogClient.Outcome = status < 0 ? .RETRY : ClubLogClient.classify(status)
            return [(path, [F.tx(body), outcome.rawValue])]
        default:
            return []
        }
    }

    /// Collector of `GridComment` log rows (the callback is called synchronously).
    final class LogBox: @unchecked Sendable {
        var lines: [String] = []
    }

    static func flow(_ p: String, _ inp: [String], _ calls: [String?]) throws -> [(String, [String])] {
        let qrz = inp[0] == "qrz"
        let user = F.untx(inp[1])
        let pass = F.untx(inp[2])
        let logged = inp[3] == "1"
        var script: [FakeHttpGetter.Step] = []
        var i = 4
        while i < inp.count {
            if inp[i] == "x" {
                script.append(.failure(F.untx(inp[i + 1])))
            } else {
                script.append(.response(Int(inp[i]) ?? 0, unhex(inp[i + 1])))
            }
            i += 2
        }
        let fake = FakeHttpGetter(script)
        let log: HamQthLog? = logged ? HamQthLog() : nil
        let client: any CallbookClient = qrz
            ? QrzClient(username: user, password: pass, log: log, http: fake)
            : HamQthClient(username: user, password: pass, log: log, http: fake)
        var out: [(String, [String])] = []
        for (j, call) in calls.enumerated() {
            let rec = try client.lookup(call)
            out.append((p + "/" + String(j), [b(client.configured)] + record(rec)))
        }
        out.append((p + "/urls", fake.urls.map { F.tx($0) }))
        out.append((p + "/left", [String(fake.remaining)]))
        if let log {
            out.append((p + "/log", log.snapshot().map { F.tx(String($0.dropFirst(10))) }))
        }
        return out
    }

    static let dbQuery: [String?] = [nil, "", "  ", "OK1XOE", "ok1xoe", " OK1XOE ", "DL1ABC", "W1AW", "VE3XYZ", "XX1A",
        "O\u{212A}1XOE", "SS1A", "\u{00DF}1A", "OK1\u{00C5}", "OK1A\u{030A}", "W1AW/P", "K1\u{1F600}", "\u{00A0}OK1XOE",
        "OK1XOE\u{FFFD}", "\u{FFFD}"]
    static let fieldQuery: [String?] = [nil, "", "JO", "jo", " jo ", "JN", "FN", "fn", "XX", "\u{00C9}X", "\u{FFFD}",
        "J", "JO70", "\u{00A0}JO"]
    static let fieldCodes: [Int] = [503, 291, 1, 230, 999, 0]
}
