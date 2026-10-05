import Foundation
@testable import MCLCore

/// Swift side of the `wsjtx.*` sections of the network reference (maintainer-only probe, format documented with the probe):
/// for the input fields of an `in` row it produces the fields of an `out` row with the same notation as the generator. Called by the gate
/// `JavaNetParityTests`.
enum WsjtxParitySections {

    static let names: [String] = [
        "wsjtx.FT8", "wsjtx.DEC", "wsjtx.ENC", "wsjtx.EXCH", "wsjtx.IMP", "wsjtx.DEDUP", "wsjtx.SEND",
    ]

    enum Failure: Error, CustomStringConvertible {
        case malformed(String)
        var description: String {
            switch self {
            case .malformed(let why): "malformed reference input: \(why)"
            }
        }
    }

    /// Output fields for section `name` and input row `path` with fields `f`.
    static func output(_ name: String, _ path: String, _ f: [String]) throws -> [String] {
        switch name {
        case "wsjtx.FT8": return ft8(f)
        case "wsjtx.DEC": return try decode(f)
        case "wsjtx.ENC": return try encode(path, f)
        case "wsjtx.EXCH": return try exchange(f)
        case "wsjtx.IMP": return importer(f)
        case "wsjtx.DEDUP": return try dedup(f)
        case "wsjtx.SEND": return try sender(f)
        default: throw Failure.malformed("unknown section \(name)")
        }
    }

    // MARK: - Helpers

    static func tx(_ s: String?) -> String {
        JavaIoParityFixture.tx(s)
    }

    static func untx(_ s: String) -> String? {
        JavaIoParityFixture.untx(s)
    }

    static func flag(_ b: Bool) -> String {
        b ? "1" : "0"
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func unhex(_ text: String) throws -> [UInt8] {
        let units: [UInt8] = Array(text.utf8)
        guard units.count % 2 == 0 else { throw Failure.malformed("odd hex length") }
        var out: [UInt8] = []
        out.reserveCapacity(units.count / 2)
        var index = 0
        while index < units.count {
            let pair = String(decoding: units[index..<(index + 2)], as: UTF8.self)
            guard let byte = UInt8(pair, radix: 16) else { throw Failure.malformed("hex \(pair)") }
            out.append(byte)
            index += 2
        }
        return out
    }

    static func bits(_ d: Double) -> String {
        let raw = String(d.bitPattern, radix: 16)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }

    static func double(bits text: String) throws -> Double {
        guard let raw = UInt64(text, radix: 16) else { throw Failure.malformed("double \(text)") }
        return Double(bitPattern: raw)
    }

    static func int32(_ text: String) throws -> Int32 {
        guard let v = Int32(text) else { throw Failure.malformed("int \(text)") }
        return v
    }

    static func int64(_ text: String) throws -> Int64 {
        guard let v = Int64(text) else { throw Failure.malformed("long \(text)") }
        return v
    }

    /// An instant as `epochSeconds, nanoseconds` (`~, ~` = null) — milliseconds from `WsjtxCodec.epochMillis`.
    static func inst(_ date: Date?) -> [String] {
        guard let date else { return ["~", "~"] }
        let millis: Int64 = WsjtxCodec.epochMillis(date)
        let seconds: Int64 = JavaMath.floorDiv(millis, 1000)
        let nanos: Int64 = (millis - seconds * 1000) * 1_000_000
        return [String(seconds), String(nanos)]
    }

    static func date(_ seconds: String, _ nanos: String) throws -> Date? {
        if seconds == "~" { return nil }
        let s: Int64 = try int64(seconds)
        let n: Int64 = try int64(nanos)
        return Date(timeIntervalSince1970: Double(s) + Double(n) / 1_000_000_000)
    }

    /// Keys sorted like a Java `TreeMap<String, …>` (`compareTo` by UTF-16 units).
    static func sortedPairs(_ map: [String: String]) -> [String] {
        let keys: [String] = map.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        var out: [String] = [String(keys.count)]
        for key in keys {
            out.append(tx(key))
            out.append(tx(map[key]))
        }
        return out
    }

    // MARK: - FT8

    static func ft8(_ f: [String]) -> [String] {
        let m = Ft8Message.parse(untx(f[0]))
        return [tx(m.caller), tx(m.target), flag(m.cq), tx(m.grid)]
    }

    // MARK: - DEC

    static func decode(_ f: [String]) throws -> [String] {
        let data: [UInt8] = try unhex(f[0])
        do {
            return decoded(try WsjtxMessages.decode(data))
        } catch {
            switch error {
            case .endOfStream, .stringLengthOutOfRange:
                // `UncheckedIOException(cause)`: message = `cause.toString()`.
                return ["throws", "java.io.UncheckedIOException", tx(error.javaDescription(fromDecode: false))]
            case .badMagic, .epochDayOutOfRange:
                return ["throws", error.javaClass, tx(error.message)]
            }
        }
    }

    static func decoded(_ m: WsjtxMessages.Message?) -> [String] {
        guard let m else { return ["null"] }
        switch m {
        case .decode(let d):
            return ["decode", tx(d.id), flag(d.isNew), String(d.timeMs), String(d.snr), bits(d.deltaTime),
                    String(d.deltaFrequency), tx(d.mode), tx(d.message), flag(d.lowConfidence), flag(d.offAir)]
        case .status(let s):
            return ["status", tx(s.id), String(s.dialFrequencyHz), tx(s.mode), tx(s.dxCall), tx(s.report),
                    tx(s.txMode), flag(s.txEnabled), flag(s.transmitting)]
        case .clear(let c):
            return ["clear", tx(c.id)]
        case .loggedAdif(let a):
            return ["adif", tx(a.adif)]
        case .qsoLogged(let q):
            var out: [String] = ["qso"]
            out += inst(q.dateTimeOff)
            out += [tx(q.dxCall), tx(q.dxGrid), String(q.txFreqHz), tx(q.mode), tx(q.reportSent), tx(q.reportRcvd)]
            out += [tx(q.txPower), tx(q.comments), tx(q.name)]
            out += inst(q.dateTimeOn)
            out += [tx(q.opCall), tx(q.myCall), tx(q.myGrid), tx(q.exchangeSent), tx(q.exchangeRcvd), tx(q.propMode)]
            return out
        }
    }

    // MARK: - ENC

    static func encode(_ path: String, _ f: [String]) throws -> [String] {
        if path.hasPrefix("d/") {
            let d = WsjtxMessages.Decode(
                id: untx(f[0]), isNew: f[1] == "1", timeMs: try int32(f[2]), snr: try int32(f[3]),
                deltaTime: try double(bits: f[4]), deltaFrequency: try int32(f[5]), mode: untx(f[6]),
                message: untx(f[7]), lowConfidence: f[8] == "1", offAir: f[9] == "1")
            let modifiers: Int32 = try int32(f[10])
            return [hex(WsjtxMessages.encodeDecode(d)), hex(WsjtxMessages.encodeReply(d, modifiers: modifiers))]
        }
        if path.hasPrefix("q/") {
            let q = WsjtxMessages.QsoLogged(
                dateTimeOff: try date(f[0], f[1]), dxCall: untx(f[2]), dxGrid: untx(f[3]), txFreqHz: try int64(f[4]),
                mode: untx(f[5]), reportSent: untx(f[6]), reportRcvd: untx(f[7]), txPower: untx(f[8]),
                comments: untx(f[9]), name: untx(f[10]), dateTimeOn: try date(f[11], f[12]), opCall: untx(f[13]),
                myCall: untx(f[14]), myGrid: untx(f[15]), exchangeSent: untx(f[16]), exchangeRcvd: untx(f[17]),
                propMode: untx(f[18]))
            return [hex(WsjtxMessages.encodeQsoLogged(q))]
        }
        if path.hasPrefix("t/") {
            var out = WsjtxDataOutput()
            WsjtxCodec.writeDateTimeUtc(&out, try date(f[0], f[1]))
            return [hex(out.bytes)]
        }
        if path.hasPrefix("a/") {
            return [hex(WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: untx(f[0]))))]
        }
        throw Failure.malformed("ENC cesta \(path)")
    }

    // MARK: - EXCH

    static func exchange(_ f: [String]) throws -> [String] {
        var index = 0
        let fieldCount: Int = Int(f[index]) ?? -1
        index += 1
        var fields: [ContestDefinition.ExchangeField] = []
        for _ in 0..<max(0, fieldCount) {
            guard let type = ContestDefinition.FieldType(rawValue: f[index + 1]) else {
                throw Failure.malformed("typ \(f[index + 1])")
            }
            fields.append(ContestDefinition.ExchangeField(id: untx(f[index]), type: type, required: true, source: nil,
                                                          appliesWhen: nil, validation: nil))
            index += 2
        }
        let pairCount: Int = Int(f[index]) ?? -1
        index += 1
        var adif: [String: String] = [:]
        for _ in 0..<max(0, pairCount) {
            adif[f[index]] = untx(f[index + 1])
            index += 2
        }
        let raw = WsjtxExchangeMapper.toReceivedRaw(fields, adif)
        var out: [String] = []
        for key in raw.keys {
            out.append(tx(key))
            out.append(tx(raw[key]))
        }
        return out
    }

    // MARK: - IMP

    static func importer(_ f: [String]) -> [String] {
        do {
            guard let imp = try WsjtxImportMapper.map(untx(f[0]) ?? "") else { return ["null"] }
            let q: Qso = imp.qso
            var out: [String] = ["qso", tx(q.call), String(q.freqHz), q.band?.rawValue ?? "~", q.mode?.adif ?? "~"]
            out += [tx(q.rstSent), tx(q.rstRcvd)]
            out += inst(q.timestampUtc)
            out += sortedPairs(imp.adifFields)
            return out
        } catch {
            let (name, message) = JavaIoParityFixture.javaException(error)
            return ["throws", name, tx(message)]
        }
    }

    // MARK: - DEDUP

    static func dedupQso(_ f: [String], _ at: Int) throws -> Qso {
        var q = Qso()
        q.call = untx(f[at]) ?? ""
        if f[at + 1] != "~" {
            guard let band = Band(rawValue: f[at + 1]) else { throw Failure.malformed("band \(f[at + 1])") }
            q.band = band
        }
        q.timestampUtc = try date(f[at + 2], f[at + 3])
        return q
    }

    static func dedup(_ f: [String]) throws -> [String] {
        let count: Int = Int(f[0]) ?? -1
        var existing: [Qso] = []
        var at = 1
        for _ in 0..<max(0, count) {
            existing.append(try dedupQso(f, at))
            at += 4
        }
        let incoming: Qso = try dedupQso(f, at)
        let window: Int64 = try int64(f[at + 4])
        return [flag(WsjtxDedup.isDuplicate(existing, incoming, windowSeconds: window))]
    }

    // MARK: - SEND

    /// `Broadcaster` is `Sendable` (shared by threads) — a capture with a lock.
    final class Capture: Broadcaster, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [[UInt8]] = []
        private var xmlCount = 0
        var sent: [[UInt8]] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
        var xml: Int {
            lock.lock()
            defer { lock.unlock() }
            return xmlCount
        }
        func send(_ xml: String, _ targets: [Target]) {
            lock.lock()
            xmlCount += 1
            lock.unlock()
        }
        func send(_ data: [UInt8], _ targets: [Target]) {
            lock.lock()
            items.append(data)
            lock.unlock()
        }
        func close() {}
    }

    static func sender(_ f: [String]) throws -> [String] {
        var q = Qso()
        q.call = untx(f[0]) ?? ""
        q.freqHz = Int(try int64(f[1]))
        q.mode = f[2] == "~" ? nil : Mode(rawValue: f[2])
        q.timestampUtc = try date(f[3], f[4])
        q.rstSent = untx(f[5]) ?? ""
        q.rstRcvd = untx(f[6]) ?? ""
        q.comment = untx(f[7]) ?? ""
        q.exchangeSent = untx(f[8]) ?? ""
        q.exchangeRcvd = untx(f[9]) ?? ""
        var station: Station?
        if f[10] == "station" {
            station = Station(call: untx(f[11]) ?? "", operator: untx(f[12]) ?? "", gridSquare: untx(f[13]) ?? "",
                              name: untx(f[14]) ?? "")
        }
        let cap = Capture()
        WsjtxSender(cap, [Target(host: "127.0.0.1", port: 2237)]).send(q, station)
        var out: [String] = [String(cap.sent.count + cap.xml)]
        out += cap.sent.map(hex)
        return out
    }
}
