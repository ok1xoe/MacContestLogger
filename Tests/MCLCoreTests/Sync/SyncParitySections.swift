import Foundation
@testable import MCLCore

/// Swift side of the `sync.*` and `mqtt.*` sections of the network reference (maintainer-only probe, format documented with the probe):
/// for an input row `in` it produces the fields of an output row `out` with the same notation as the generator. Called by the gate
/// `JavaNetParityTests`.
enum SyncParitySections {

    static let names: [String] = [
        "sync.TOPICS", "sync.INST", "sync.JSONW", "sync.JSONR", "sync.MAP", "sync.COORD", "sync.NET", "mqtt.UTF8",
        "mqtt.RC", "mqtt.ID",
    ]

    typealias F = JavaIoParityFixture

    static func b(_ v: Bool) -> String { v ? "1" : "0" }

    static func tx(_ s: String?) -> String { F.tx(s) }

    static func untx(_ s: String) -> String? { F.untx(s) }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func unhex(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            out.append(UInt8(s[index..<next], radix: 16) ?? 0)
            index = next
        }
        return out
    }

    static func inst(_ i: JavaInstant?) -> String {
        guard let i else { return "~" }
        return String(i.epochSecond) + ":" + String(i.nano)
    }

    static func uninst(_ s: String) -> JavaInstant? {
        guard s != "~", let colon = s.firstIndex(of: ":") else { return nil }
        let sec = Int64(s[..<colon]) ?? 0
        let nano = Int64(s[s.index(after: colon)...]) ?? 0
        return JavaInstant.ofEpochSecond(sec, nano)
    }

    static func instDate(_ d: Date?) -> String {
        inst(d.map(JavaInstant.init(date:)))
    }

    static func millis(_ d: Date?) -> String {
        guard let d else { return "~" }
        let i = JavaInstant(date: d)
        return String(i.epochSecond * 1_000 + Int64(i.nano / 1_000_000))
    }

    static func messageType(_ name: String) -> any WireMessage.Type {
        switch name {
        case "QsoWire": return QsoWire.self
        case "QsoState": return QsoState.self
        case "QsoCommand": return QsoCommand.self
        case "DeleteCommand": return DeleteCommand.self
        case "SpotWire": return SpotWire.self
        case "StationStatusWire": return StationStatusWire.self
        case "NetMessageWire": return NetMessageWire.self
        case "SerialRequest": return SerialRequest.self
        default: return SerialReply.self
        }
    }

    // MARK: - DTO values

    static func encode(_ fields: [WireField], _ values: [WireValue]) -> [String] {
        var out: [String] = []
        for (field, value) in zip(fields, values) {
            switch value {
            case .string(let v): out.append(tx(v))
            case .long(let v): out.append(String(v))
            case .int(let v): out.append(String(v))
            case .bool(let v): out.append(b(v))
            case .intBox(let v): out.append(v.map { String($0) } ?? "~")
            case .boolBox(let v): out.append(v.map(b) ?? "~")
            case .instant(let v): out.append(inst(v))
            case .record(let v):
                if let v, case .record(let nested) = field.kind {
                    out.append("{")
                    out += encode(nested, v)
                    out.append("}")
                } else {
                    out.append("~")
                }
            }
        }
        return out
    }

    static func decode(_ fields: [WireField], _ input: [String], _ pos: inout Int) -> [WireValue] {
        var values: [WireValue] = []
        for field in fields {
            let f: String = input[pos]
            pos += 1
            switch field.kind {
            case .string: values.append(.string(untx(f)))
            case .long: values.append(.long(Int64(f) ?? 0))
            case .int: values.append(.int(Int32(f) ?? 0))
            case .bool: values.append(.bool(f == "1"))
            case .intBox: values.append(.intBox(f == "~" ? nil : Int32(f)))
            case .boolBox: values.append(.boolBox(f == "~" ? nil : f == "1"))
            case .instant: values.append(.instant(uninst(f)))
            case .record(let nested):
                if f == "~" {
                    values.append(.record(nil))
                } else {
                    values.append(.record(decode(nested, input, &pos)))
                    pos += 1
                }
            }
        }
        return values
    }

    static func write<T: WireMessage>(_ type: T.Type, _ input: [String]) -> [String] {
        var pos = 1
        let value = T(wireValues: decode(T.wireFields, input, &pos))
        return [tx(WireJson.toJson(value)), tx(String(decoding: WireJson.toBytes(value), as: UTF8.self))]
    }

    static func read<T: WireMessage>(_ type: T.Type, _ bytes: [UInt8]) -> [String] {
        do {
            guard let value = try WireJson.fromBytes(bytes, as: T.self) else { return ["null"] }
            return ["value"] + encode(T.wireFields, value.wireValues)
        } catch {
            return ["error", tx(error.message)]
        }
    }

    // MARK: - output

    static func output(_ sec: String, _ path: String, _ inp: [String]) throws -> [String] {
        switch sec {
        case "sync.TOPICS":
            if path == "const" {
                return [Topics.cmdInsert, Topics.cmdUpdate, Topics.cmdDelete, Topics.spots, Topics.statusPrefix,
                        Topics.messages, Topics.serialRequest, Topics.serialReplyPrefix, Topics.statusWildcard,
                        Topics.statePrefix, Topics.stateWildcard]
            }
            let x: String? = untx(inp[0])
            return [tx(Topics.state(x)), tx(Topics.serialReply(x)), tx(Topics.status(x)), tx(Topics.uuidFromStateTopic(x))]
        case "sync.INST":
            return [uninst(inp[0])?.toString() ?? "?"]
        case "sync.JSONW":
            return write(messageType(inp[0]), inp)
        case "sync.JSONR":
            return read(messageType(inp[0]), unhex(inp[1]))
        case "sync.MAP":
            return path.hasPrefix("w") ? mapWire(inp) : mapQso(inp)
        case "sync.COORD":
            return try SyncScripts.coordinator(inp.map { untx($0) ?? "" })
        case "sync.NET":
            return try SyncScripts.network(inp.map { untx($0) ?? "" })
        case "mqtt.UTF8":
            return path.hasPrefix("d") ? mqttDecode(unhex(inp[0])) : mqttEncode(untx(inp[0]) ?? "")
        case "mqtt.RC":
            return [mqttReasonCodes(inp[0])]
        default:
            return mqttIds(inp)
        }
    }

    // MARK: - sync.MAP

    static func mapWire(_ f: [String]) -> [String] {
        var q = Qso()
        q.timestampUtc = uninst(f[0])?.date
        q.call = untx(f[1]) ?? ""
        q.freqHz = Int(f[2]) ?? 0
        if f[3] != "~" { q.band = Band(javaName: f[3]) }
        q.mode = f[4] == "~" ? nil : Mode(rawValue: f[4])
        q.rstSent = untx(f[5]) ?? ""
        q.rstRcvd = untx(f[6]) ?? ""
        q.exchangeSent = untx(f[7]) ?? ""
        q.exchangeRcvd = untx(f[8]) ?? ""
        q.serialSent = f[9] == "~" ? nil : Int(f[9])
        q.serialRcvd = f[10] == "~" ? nil : Int(f[10])
        q.operator = untx(f[11]) ?? ""
        q.comment = untx(f[12]) ?? ""
        q.dxccEntity = f[13] == "~" ? nil : Int(f[13])
        q.dxccName = untx(f[14]) ?? ""
        q.continent = untx(f[15]) ?? ""
        q.xqso = f[16] == "1"
        q.uuid = untx(f[17]) ?? ""
        q.updatedAtUtc = uninst(f[18])?.date
        return [tx(WireJson.toJson(WireMapper.toWire(q))), tx(WireJson.toJson(WireMapper.toInsertCommand("ST1", q))),
                tx(WireJson.toJson(WireMapper.toDeleteCommand("ST1", q)))]
    }

    static func mapQso(_ f: [String]) -> [String] {
        var pos = 0
        let state = QsoState(wireValues: decode(QsoState.wireFields, f, &pos))
        return qsoFields(WireMapper.toQso(state))
    }

    static func qsoFields(_ q: Qso) -> [String] {
        var o: [String] = [instDate(q.timestampUtc), tx(q.call), String(q.freqHz), q.band?.javaName ?? "~"]
        o += [q.mode?.rawValue ?? "~", tx(q.rstSent), tx(q.rstRcvd), tx(q.exchangeSent), tx(q.exchangeRcvd)]
        o += [q.serialSent.map { String($0) } ?? "~", q.serialRcvd.map { String($0) } ?? "~", tx(q.operator)]
        o += [tx(q.comment), q.dxccEntity.map { String($0) } ?? "~", tx(q.dxccName), tx(q.continent), b(q.xqso)]
        o += [tx(q.uuid), tx(q.stationId), String(q.version), instDate(q.updatedAtUtc), b(q.deleted)]
        return o
    }

    // MARK: - mqtt.*

    static func mqttDecode(_ data: [UInt8]) -> [String] {
        do {
            return ["ok", tx(try MqttReader.decodeUtf8(data))]
        } catch {
            return ["reject", tx(pahoMessage(error))]
        }
    }

    static func mqttEncode(_ text: String) -> [String] {
        var writer = MqttWriter()
        do {
            try writer.string(text)
            return ["ok", hex(writer.bytes)]
        } catch {
            return ["reject", tx(pahoMessage(error))]
        }
    }

    static func pahoMessage(_ error: MqttCodecError) -> String {
        guard case .invalidCharacter(let unit) = error else { return String(describing: error) }
        return "Invalid UTF-8 char: [" + String(format: "%04x", unit) + "]"
    }

    static func mqttReasonCodes(_ type: String) -> String {
        var out = ""
        for code in 0...255 {
            let c = UInt8(code)
            let packet: [UInt8]
            switch type {
            case "connack": packet = [0x20, 0x03, 0x00, c, 0x00]
            case "puback": packet = [0x40, 0x04, 0x00, 0x01, c, 0x00]
            case "suback": packet = [0x90, 0x04, 0x00, 0x01, 0x00, c]
            default: packet = [0xE0, 0x02, c, 0x00]
            }
            do {
                _ = try MqttPacket.decode(packet)
                out += "1"
            } catch {
                if case .invalidReasonCode = error {
                    out += "0"
                } else {
                    out += "E"
                }
            }
        }
        return out
    }

    static func mqttIds(_ f: [String]) -> [String] {
        var ids = MqttPacketIdAllocator(last: Int(f[0]) ?? 0)
        let ranges = Int(f[1]) ?? 0
        for index in 0..<ranges {
            let parts = f[2 + index].split(separator: "-")
            let lo = Int(parts[0]) ?? 1
            let hi = Int(parts[1]) ?? 0
            if lo <= hi {
                for id in lo...hi {
                    ids.markInUse(UInt16(id))
                }
            }
        }
        var out: [String] = []
        for op in f[(2 + ranges)...] {
            if op.hasPrefix("r") {
                ids.release(UInt16(op.dropFirst()) ?? 0)
                out.append("-")
            } else if let id = ids.next() {
                out.append(String(id))
            } else {
                out.append("x")
            }
        }
        return out
    }
}
