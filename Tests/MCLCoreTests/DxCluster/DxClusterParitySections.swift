import CryptoKit
import Foundation
@testable import MCLCore

/// Swift side of the `dxcluster.*` sections of the network reference (maintainer-only probe, format
/// documented with the probe): for an input row `in` it produces output rows `out` with the same notation as the generator.
/// Multi-row items (`PLAN` favourites/open/primary, `LAYOUT` rows/area, `BLK` and `BUF` scripts)
/// hold state between rows in `Ctx`; `BUF` writes the scenario's `ages` row only at its end (`before`, `finish`).
/// Called by the gate `JavaNetParityTests`.
enum DxClusterParitySections {

    static let names: [String] = [
        "dxcluster.DSP", "dxcluster.WWV", "dxcluster.SELF", "dxcluster.SMP", "dxcluster.SKIM", "dxcluster.GRID",
        "dxcluster.URLENC", "dxcluster.PLAN", "dxcluster.LAYOUT", "dxcluster.COLOR", "dxcluster.BLK",
        "dxcluster.BEACON", "dxcluster.DIGI", "dxcluster.BUF",
    ]

    typealias F = JavaIoParityFixture
    typealias V = JavaNetParityValues
    typealias Rows = [(String, [String])]

    /// State between the rows of one item.
    final class Ctx {
        var buf: SpotBuffer?
        var clock: DxTestClock?
        var hits = NotifyBox()
        var bufPath: String?
        var blk: [BlacklistEntry] = []
        var blkScript = ""
        var dir: URL?
        var planFavs: [DxClusterFavorite] = []
        var planOpen: [String] = []
        var rows: [SpotLabelLayout.Row] = []

        deinit {
            if let dir { try? FileManager.default.removeItem(at: dir) }
        }
    }

    /// A call counter of the `SpotBuffer` listener (called synchronously from `add`/`remove`…).
    final class NotifyBox: @unchecked Sendable {
        var n = 0
    }

    // MARK: - Helpers

    static func u(_ s: String) -> String? { F.untx(s) }
    static func uu(_ s: String) -> String { F.untx(s) ?? "" }
    static func b(_ v: Bool) -> String { v ? "1" : "0" }

    static func spotFields(_ s: DxSpot) -> [String] {
        [F.tx(s.spotter), String(s.freqHz), F.tx(s.dxCall), F.tx(s.comment), b(s.selfSpotted)]
    }

    static func nfe(_ e: JavaNumberFormatError) -> [String] {
        ["throws", "java.lang.NumberFormatException", F.tx(e.message)]
    }

    static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `Integer.toHexString(Float.floatToIntBits(f))` in uppercase, 8 places (NaN canonically).
    static func fbits(_ f: Float) -> String {
        let bits: UInt32 = f.isNaN ? 0x7FC0_0000 : f.bitPattern
        return String(format: "%08X", bits)
    }

    static func readList(_ f: [String], _ i: inout Int) throws -> [String]? {
        if f[i] == "~" {
            i += 1
            return nil
        }
        let n: Int = try V.int(f[i])
        i += 1
        var out: [String] = []
        for _ in 0..<n {
            out.append(uu(f[i]))
            i += 1
        }
        return out
    }

    static let bufCalls: [String] = ["OH2AS", "oh2as", "DL1ABC", "W1AW", "OK1XOE", "\u{0131}x", "IX", "\u{212A}1A", "k1a",
                                     "OZ7IGY/B"]
    static let digiProbes: [Int] = [14_074_000, 14_075_300, 7_047_500, 50_313_000, 14_202_000, 1, 0,
                                    14_073_500, 14_077_000, 14_077_001, 1_000_000, 1_838_000]
    static let ageOffsets: [Double] = [-121, -61, -60, -59, -1, 0, 59, 60, 61, 3599, 3600]

    static func digiModes(_ d: DigiFrequencies) -> [String] {
        digiProbes.map { F.tx(d.modeAt($0)) }
    }

    static func digiTable(_ t: DigiFreqFile.Table) -> [String] {
        var out: [String] = [String(t.channels.count)]
        for c in t.channels {
            out.append(F.tx(c.mode))
            out.append(JavaDouble.toString(c.fromKhz))
            out.append(JavaDouble.toString(c.toKhz))
        }
        return out
    }

    static func blkState(_ list: [BlacklistEntry]) -> [String] {
        var out: [String] = []
        for entry in list {
            out.append(F.tx(entry.value))
            out.append(F.tx(entry.addedAtUtc))
            out.append(F.tx(entry.note))
        }
        return out
    }

    /// `Spotted.ageMinutes` across edges around the instant `t0`.
    static func ages(_ t0: Date) -> [String] {
        let spotted = SpotBuffer.Spotted(spot: DxSpot(spotter: "A", freqHz: 1, dxCall: "B", comment: ""), spottedAt: t0)
        return ageOffsets.map { String(spotted.ageMinutes(t0.addingTimeInterval($0))) }
    }

    // MARK: - Sections

    static func compute(_ sec: String, _ p: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch sec {
        case "dxcluster.DSP":
            guard let s = DxSpotParser.parse(u(f[0])) else { return [(p, ["empty"])] }
            return [(p, ["spot"] + spotFields(s))]
        case "dxcluster.WWV": return [(p, wwv(f))]
        case "dxcluster.SELF": return [(p, try selfSpot(f))]
        case "dxcluster.SMP":
            return [(p, [F.tx(SpotModeParser.fromComment(u(f[0])))])]
        case "dxcluster.SKIM":
            let spot = DxSpot(spotter: uu(f[0]), freqHz: 1, dxCall: "X", comment: uu(f[1]), selfSpotted: f[2] == "1")
            return [(p, [b(SkimmerSpot.isSkimmer(spot))])]
        case "dxcluster.GRID": return [(p, try grid(f))]
        case "dxcluster.URLENC": return [(p, try urlEncode(p, f))]
        case "dxcluster.PLAN": return try plan(p, f, ctx)
        case "dxcluster.LAYOUT": return try layout(p, f, ctx)
        case "dxcluster.COLOR":
            let key = SpotColorClassifier.classify(dupe: f[0] == "1", newMultCount: try V.int(f[1]))
            return [(p, [key.rawValue])]
        case "dxcluster.BLK": return [(p, try blacklist(p, f, ctx))]
        case "dxcluster.BEACON": return [(p, beacon(f))]
        case "dxcluster.DIGI": return try digi(p, f, ctx)
        case "dxcluster.BUF": return try buffer(p, f, ctx)
        default: throw JavaNetParityValues.Malformed(text: "unknown section \(sec)")
        }
    }

    /// Rows before the input row `path`: Java writes the `ages` of the `BUF` scenario at its end, i.e. before the row
    /// of the next scenario (`BUF/NN`).
    static func before(_ sec: String, _ path: String, _ ctx: Ctx) -> Rows {
        guard sec == "dxcluster.BUF", path.split(separator: "/").count == 2 else { return [] }
        return finish(sec, ctx)
    }

    /// Rows at the end of an item: the `ages` of the last `BUF` scenario.
    static func finish(_ sec: String, _ ctx: Ctx) -> Rows {
        guard sec == "dxcluster.BUF", let prev = ctx.bufPath, let clock = ctx.clock else { return [] }
        ctx.bufPath = nil
        return [(prev + "/ages", ages(clock.now))]
    }

    static func wwv(_ f: [String]) -> [String] {
        do throws(JavaNumberFormatError) {
            guard let m = try WwvMessage.parse(u(f[0])) else { return ["empty"] }
            let numbers: [String] = [String(m.hourUtc), String(m.sfi), String(m.aIndex), String(m.kIndex)]
            var out: [String] = ["wwv", F.tx(m.spotter)]
            out += numbers
            out.append(F.tx(m.conditions))
            return out
        } catch {
            return nfe(error)
        }
    }

    static func selfSpot(_ f: [String]) throws -> [String] {
        let spot = DxSpot(spotter: uu(f[0]), freqHz: try V.int(f[1]), dxCall: uu(f[2]), comment: uu(f[3]))
        let at = Date(timeIntervalSince1970: Double(try V.int(f[5])))
        do throws(JavaNumberFormatError) {
            guard let v = try SelfSpot.detect(spot, myCall: u(f[4]), at: at) else { return ["empty"] }
            let snr: String = v.snrDb.map { String($0) } ?? "~"
            let wpm: String = v.wpm.map { String($0) } ?? "~"
            var out: [String] = ["self", F.tx(v.spotter), String(v.freqHz), b(v.rbn)]
            out += [snr, wpm, String(Int(v.at.timeIntervalSince1970))]
            return out
        } catch {
            return nfe(error)
        }
    }

    static func grid(_ f: [String]) throws -> [String] {
        let prefix: String? = u(f[2])
        let entity = DxccEntity(entityCode: try V.int(f[1]), name: "E", countryCode: prefix, continents: ["EU"],
                                cq: [1], itu: [1], lat: try V.double(f[3]), lon: try V.double(f[4]),
                                primaryPrefix: prefix)
        var log: [String] = []
        let g: String? = GridComment.extractGrid(u(f[0]), entity, fieldMap: nil, log: { log.append($0) })
        return [F.tx(g)] + log.map { F.tx($0) }
    }

    static func urlEncode(_ p: String, _ f: [String]) throws -> [String] {
        if p.hasPrefix("URLENC/bmp/") {
            guard let start = Int(f[0], radix: 16) else { throw V.Malformed(text: f[0]) }
            var s = ""
            for cp in start..<(start + 0x400) {
                guard let scalar = Unicode.Scalar(UInt32(cp)) else { throw V.Malformed(text: f[0]) }
                s.unicodeScalars.append(scalar)
            }
            let enc: String = JavaUrlEncoder.encode(s)
            return [sha(enc), String(enc.utf16.count)]
        }
        if p.hasPrefix("URLENC/rbn/") { return [F.tx(RbnLink.spotsOfStation(u(f[0])))] }
        return [JavaUrlEncoder.encode(uu(f[0]))]
    }

    static func plan(_ p: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if p.hasSuffix("/favorites") {
            var favs: [DxClusterFavorite] = []
            var i = 0
            while i + 2 < f.count {
                var fav = DxClusterFavorite(name: "f\(favs.count)", host: uu(f[i]), port: try V.int(f[i + 1]),
                                            login: "OK1XOE", password: "")
                fav.parallel = f[i + 2] == "1"
                favs.append(fav)
                i += 3
            }
            ctx.planFavs = favs
            return []
        }
        if p.hasSuffix("/open") {
            ctx.planOpen = f.map(uu)
            return []
        }
        let base = String(p.dropLast("/primary".count))
        let plan = ParallelClusterPlan.plan(ctx.planFavs, open: ctx.planOpen, primary: u(f[0]))
        return [(base + "/keys", ctx.planFavs.map { F.tx($0.connectionKey) }),
                (base + "/connect", plan.toConnect.map(\.name)),
                (base + "/disconnect", plan.toDisconnect.map { F.tx($0) })]
    }

    static func layout(_ p: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if p.hasSuffix("/rows") {
            ctx.rows = try f.map { s in
                let parts = s.split(separator: ":")
                guard parts.count == 2 else { throw V.Malformed(text: s) }
                return SpotLabelLayout.Row(index: try V.int(String(parts[0])), trueY: try V.float(String(parts[1])))
            }
            return []
        }
        let out = SpotLabelLayout.place(ctx.rows, rowH: try V.float(f[0]), minY: try V.float(f[1]),
                                        maxY: try V.float(f[2]))
        let fields: [String] = out.map { "\($0.index):\(fbits($0.trueY)):\(fbits($0.labelY))" }
        return [(String(p.dropLast("/area".count)), fields)]
    }

    static func blacklist(_ p: String, _ f: [String], _ ctx: Ctx) throws -> [String] {
        let script = String(p.prefix(8))
        if ctx.blkScript != script {
            ctx.blkScript = script
            ctx.blk = []
        }
        var result = ""
        switch f[0] {
        case "add": result = b(BlacklistService.add(&ctx.blk, u(f[1]), note: u(f[2]), nowUtc: u(f[3])))
        case "remove": result = b(BlacklistService.remove(&ctx.blk, u(f[1])))
        case "updateValue": result = b(BlacklistService.updateValue(&ctx.blk, u(f[1]), u(f[2])))
        case "setNote": result = b(BlacklistService.setNote(&ctx.blk, u(f[1]), u(f[2])))
        case "values": result = BlacklistService.values(ctx.blk).map { F.tx($0) }.joined(separator: ",")
        case "migrate":
            var i = 3
            let legacy: [String]? = try readList(f, &i)
            let merged = BlacklistService.migrate(legacy, f[1] == "1" ? nil : ctx.blk, nowUtc: u(f[2]))
            result = String(merged.count)
            ctx.blk = merged
        default:
            var i = 2
            let wanted: [String]? = try readList(f, &i)
            result = b(BlacklistService.sync(&ctx.blk, wanted, nowUtc: u(f[1])))
        }
        return [result] + blkState(ctx.blk)
    }

    static func beacon(_ f: [String]) -> [String] {
        let parsed = BeaconFile.parse(u(f[0]))
        var out: [String] = [String(parsed.hours), String(parsed.beacons.count)]
        for s in parsed.beacons { out += spotFields(s) }
        out.append(String(parsed.skipped.count))
        out += parsed.skipped.map { F.tx($0) }
        return out
    }

    static func digi(_ p: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        let dir: URL
        if let existing = ctx.dir {
            dir = existing
        } else {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-net-digi-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            ctx.dir = dir
        }
        let file = dir.appendingPathComponent("digi_frequencies.yaml")
        if p.hasPrefix("DIGI/write/") {
            var channels: [DigiFreqFile.Channel] = []
            var i = 0
            while i + 2 < f.count {
                let from: Double = try V.double(bits: f[i + 1])
                let to: Double = try V.double(bits: f[i + 2])
                channels.append(DigiFreqFile.Channel(mode: uu(f[i]), fromKhz: from, toKhz: to))
                i += 3
            }
            try DigiFreqFile.write(dir, DigiFreqFile.Table(channels: channels))
            let written = try String(contentsOf: file, encoding: .utf8)
            return [(p + "/bytes", [F.tx(written)]), (p + "/read", digiTable(DigiFreqFile.read(dir))),
                    (p + "/modes", digiModes(DigiFrequencies.fromDir(dir)))]
        }
        if p.hasPrefix("DIGI/read/") {
            try uu(f[0]).write(to: file, atomically: false, encoding: .utf8)
            return [(p + "/read", digiTable(DigiFreqFile.read(dir))), (p + "/modes", digiModes(DigiFrequencies.fromDir(dir)))]
        }
        if p == "DIGI/missing" {
            try? FileManager.default.removeItem(at: file)
            return [("DIGI/missing/read", digiTable(DigiFreqFile.read(dir))),
                    ("DIGI/missing/modes", digiModes(DigiFrequencies.fromDir(dir))),
                    ("DIGI/missing/null", digiModes(DigiFrequencies.fromDir(nil)))]
        }
        var sweep: [String] = []
        let table = DigiFrequencies.defaultTable()
        var fr = 1_830_000
        while fr <= 147_000_000 {
            if let m = table.modeAt(fr) { sweep.append("\(fr)=\(m)") }
            fr += fr < 30_000_000 ? 250 : 2_500
        }
        return [("DIGI/default", [sha(sweep.joined(separator: "\n")), String(sweep.count)])]
    }

    static func buffer(_ p: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        if p.split(separator: "/").count == 2 {
            // a new scenario (the `ages` row of the previous one was already written by `before`)
            let clock = DxTestClock("2026-07-09T10:00:00Z")
            let buf = SpotBuffer(maxAgeMinutes: try V.int(f[0]), clock: clock.source)
            let box = NotifyBox()
            _ = buf.addListener { box.n += 1 }
            ctx.clock = clock
            ctx.hits = box
            ctx.buf = buf
            ctx.bufPath = p
            return []
        }
        guard let buf = ctx.buf, let clock = ctx.clock else { throw V.Malformed(text: "BUF without a scenario: \(p)") }
        if p.hasSuffix("/near") {
            let near: DxSpot? = buf.nearestWithin(try V.int(f[0]), toleranceHz: try V.int(f[1]))
            return [(p, [near.map { F.tx($0.dxCall) + "@" + String($0.freqHz) } ?? "~"])]
        }
        try step(buf, clock, f)
        let snap: [String] = buf.snapshot().map { F.tx($0.dxCall) + "@" + String($0.freqHz) + "@" + F.tx($0.spotter) }
        var counts: [String] = []
        var found: [String] = []
        for call in bufCalls {
            counts.append(String(buf.skimmerCount(call)))
            if let s = buf.find(call) {
                let at = Int(s.spottedAt.timeIntervalSince1970)
                found.append("\(s.spot.freqHz)@\(at)@\(s.ageMinutes(clock.now))")
            } else {
                found.append("~")
            }
        }
        return [(p + "/notify", [String(ctx.hits.n)]), (p + "/snap", snap), (p + "/skim", counts), (p + "/find", found)]
    }

    static func step(_ buf: SpotBuffer, _ clock: DxTestClock, _ f: [String]) throws {
        switch f[0] {
        case "add":
            buf.add(DxSpot(spotter: uu(f[1]), freqHz: try V.int(f[2]), dxCall: uu(f[3]), comment: uu(f[4]),
                           selfSpotted: f[5] == "1"))
        case "addUntil":
            let until: Date? = f[2] == "~" ? nil : clock.now.addingTimeInterval(Double(try V.int(f[2])))
            buf.addUntil(DxSpot(spotter: "BEACONS", freqHz: 144_471_100, dxCall: uu(f[1]), comment: ""), until: until)
        case "remove": buf.remove(u(f[1]))
        case "clear": buf.clear()
        case "setBlacklist":
            var i = 2
            let calls: [String]? = try readList(f, &i)
            let spotters: [String]? = try readList(f, &i)
            buf.setBlacklist(calls: f[1] == "1" ? nil : calls, spotters: spotters)
        case "setMinSkimmers": buf.setMinSkimmers(try V.int(f[1]))
        case "setMaxAgeMinutes": buf.setMaxAgeMinutes(try V.int(f[1]))
        case "touch": buf.touch()
        default: clock.set(clock.now.addingTimeInterval(Double(try V.int(f[1]))))
        }
    }
}
