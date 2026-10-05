/// Will (last will) in CONNECT (§3.1.3.2–3.1.3.4).
public struct MqttWill: Equatable, Sendable {
    public var topic: String
    public var payload: [UInt8]
    public var qos: UInt8
    public var retain: Bool
    public var properties: MqttProperties

    public init(topic: String, payload: [UInt8], qos: UInt8, retain: Bool, properties: MqttProperties = MqttProperties()) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.retain = retain
        self.properties = properties
    }
}

/// CONNECT (§3.1) — field order like Paho `MqttConnect`: properties, Client ID, Will properties, Will topic,
/// Will payload, username, password.
public struct MqttConnect: Equatable, Sendable {
    public var clientId: String
    public var cleanStart: Bool
    public var keepAliveSeconds: UInt16
    public var properties: MqttProperties
    public var will: MqttWill?
    public var username: String?
    public var password: [UInt8]?

    public init(
        clientId: String, cleanStart: Bool, keepAliveSeconds: UInt16, properties: MqttProperties = MqttProperties(),
        will: MqttWill? = nil, username: String? = nil, password: [UInt8]? = nil
    ) {
        self.clientId = clientId
        self.cleanStart = cleanStart
        self.keepAliveSeconds = keepAliveSeconds
        self.properties = properties
        self.will = will
        self.username = username
        self.password = password
    }
}

/// CONNACK (§3.2).
public struct MqttConnack: Equatable, Sendable {
    public var sessionPresent: Bool
    public var reasonCode: UInt8
    public var properties: MqttProperties

    public init(sessionPresent: Bool, reasonCode: UInt8, properties: MqttProperties = MqttProperties()) {
        self.sessionPresent = sessionPresent
        self.reasonCode = reasonCode
        self.properties = properties
    }
}

/// PUBLISH (§3.3); `packetId` only for QoS > 0.
public struct MqttPublish: Equatable, Sendable {
    public var topic: String
    public var packetId: UInt16?
    public var qos: UInt8
    public var retain: Bool
    public var dup: Bool
    public var properties: MqttProperties
    public var payload: [UInt8]

    public init(
        topic: String, packetId: UInt16?, qos: UInt8, retain: Bool, dup: Bool = false,
        properties: MqttProperties = MqttProperties(), payload: [UInt8]
    ) {
        self.topic = topic
        self.packetId = packetId
        self.qos = qos
        self.retain = retain
        self.dup = dup
        self.properties = properties
        self.payload = payload
    }
}

/// PUBACK (§3.4): short form (`40 02 id`) = reason 0 without properties.
public struct MqttPuback: Equatable, Sendable {
    public var packetId: UInt16
    public var reasonCode: UInt8
    public var properties: MqttProperties

    public init(packetId: UInt16, reasonCode: UInt8 = 0, properties: MqttProperties = MqttProperties()) {
        self.packetId = packetId
        self.reasonCode = reasonCode
        self.properties = properties
    }
}

/// One subscription in SUBSCRIBE (§3.8.3.1): QoS + No Local, Retain As Published, Retain Handling.
public struct MqttSubscription: Equatable, Sendable {
    public var topicFilter: String
    public var qos: UInt8
    public var noLocal: Bool
    public var retainAsPublished: Bool
    public var retainHandling: UInt8

    public init(topicFilter: String, qos: UInt8, noLocal: Bool = false, retainAsPublished: Bool = false, retainHandling: UInt8 = 0) {
        self.topicFilter = topicFilter
        self.qos = qos
        self.noLocal = noLocal
        self.retainAsPublished = retainAsPublished
        self.retainHandling = retainHandling
    }
}

/// SUBSCRIBE (§3.8).
public struct MqttSubscribe: Equatable, Sendable {
    public var packetId: UInt16
    public var properties: MqttProperties
    public var subscriptions: [MqttSubscription]

    public init(packetId: UInt16, properties: MqttProperties = MqttProperties(), subscriptions: [MqttSubscription]) {
        self.packetId = packetId
        self.properties = properties
        self.subscriptions = subscriptions
    }
}

/// SUBACK (§3.9): a reason code per subscription (0x00–0x02 = granted QoS, ≥ 0x80 = error, ACL → 0x87).
public struct MqttSuback: Equatable, Sendable {
    public var packetId: UInt16
    public var properties: MqttProperties
    public var reasonCodes: [UInt8]

    public init(packetId: UInt16, properties: MqttProperties = MqttProperties(), reasonCodes: [UInt8]) {
        self.packetId = packetId
        self.properties = properties
        self.reasonCodes = reasonCodes
    }
}

/// DISCONNECT (§3.14).
public struct MqttDisconnect: Equatable, Sendable {
    public var reasonCode: UInt8
    public var properties: MqttProperties

    public init(reasonCode: UInt8 = 0, properties: MqttProperties = MqttProperties()) {
        self.reasonCode = reasonCode
        self.properties = properties
    }
}

/// MQTT 5 packets the client sends or receives as measured on Java v1.1.1 (without QoS 2, UNSUBSCRIBE and AUTH).
public enum MqttPacket: Equatable, Sendable {
    case connect(MqttConnect)
    case connack(MqttConnack)
    case publish(MqttPublish)
    case puback(MqttPuback)
    case subscribe(MqttSubscribe)
    case suback(MqttSuback)
    case pingreq
    case pingresp
    case disconnect(MqttDisconnect)

    static let protocolName: [UInt8] = [0x00, 0x04, 0x4D, 0x51, 0x54, 0x54]
}

// MARK: - Encoding

extension MqttPacket {

    /// The whole packet (fixed header + remaining length + body).
    public func encode() throws(MqttCodecError) -> [UInt8] {
        var body = MqttWriter()
        let header: UInt8
        switch self {
        case .connect(let p):
            header = 0x10
            try Self.encodeConnect(p, into: &body)
        case .connack(let p):
            header = 0x20
            body.byte(p.sessionPresent ? 1 : 0)
            body.byte(p.reasonCode)
            try p.properties.encode(into: &body)
        case .publish(let p):
            header = try Self.publishHeader(p)
            try Self.encodePublish(p, into: &body)
        case .puback(let p):
            header = 0x40
            body.u16(p.packetId)
            // Short form like Paho and Mosquitto: without reason code and properties when the reason is 0 and there are no properties.
            if p.reasonCode != 0 || !p.properties.isEmpty {
                body.byte(p.reasonCode)
                if !p.properties.isEmpty {
                    try p.properties.encode(into: &body)
                }
            }
        case .subscribe(let p):
            header = 0x82
            try Self.encodeSubscribe(p, into: &body)
        case .suback(let p):
            header = 0x90
            body.u16(p.packetId)
            try p.properties.encode(into: &body)
            body.raw(p.reasonCodes)
        case .pingreq:
            header = 0xC0
        case .pingresp:
            header = 0xD0
        case .disconnect(let p):
            header = 0xE0
            // Paho always sends the reason code and (empty) properties: `e0 02 00 00`; a broker (Mosquitto) with a non-zero
            // code and no properties sends the short form `e0 01 <code>` (§3.14.2.2.1) — we write it the same way.
            body.byte(p.reasonCode)
            if p.reasonCode == 0 || !p.properties.isEmpty {
                try p.properties.encode(into: &body)
            }
        }
        var out = MqttWriter()
        out.byte(header)
        try out.varInt(body.bytes.count)
        out.raw(body.bytes)
        return out.bytes
    }

    private static func encodeConnect(_ p: MqttConnect, into w: inout MqttWriter) throws(MqttCodecError) {
        w.raw(protocolName)
        w.byte(5)
        var flags: UInt8 = 0
        if p.username != nil {
            flags |= 0x80
        }
        if p.password != nil {
            flags |= 0x40
        }
        if let will = p.will {
            guard will.qos <= 2 else {
                throw .invalidQos(will.qos)
            }
            flags |= 0x04 | will.qos << 3
            if will.retain {
                flags |= 0x20
            }
        }
        if p.cleanStart {
            flags |= 0x02
        }
        w.byte(flags)
        w.u16(p.keepAliveSeconds)
        try p.properties.encode(into: &w)
        try w.string(p.clientId)
        if let will = p.will {
            try will.properties.encode(into: &w)
            try w.string(will.topic)
            try w.binary(will.payload)
        }
        if let username = p.username {
            try w.string(username)
        }
        if let password = p.password {
            try w.binary(password)
        }
    }

    private static func publishHeader(_ p: MqttPublish) throws(MqttCodecError) -> UInt8 {
        guard p.qos <= 2 else {
            throw .invalidQos(p.qos)
        }
        if p.dup && p.qos == 0 {
            throw .dupWithQos0
        }
        var header: UInt8 = 0x30 | p.qos << 1
        if p.dup {
            header |= 0x08
        }
        if p.retain {
            header |= 0x01
        }
        return header
    }

    private static func encodePublish(_ p: MqttPublish, into w: inout MqttWriter) throws(MqttCodecError) {
        try w.string(p.topic)
        if p.qos > 0 {
            guard let id = p.packetId, id != 0 else {
                throw .zeroPacketIdentifier
            }
            w.u16(id)
        }
        try p.properties.encode(into: &w)
        w.raw(p.payload)
    }

    private static func encodeSubscribe(_ p: MqttSubscribe, into w: inout MqttWriter) throws(MqttCodecError) {
        guard p.packetId != 0 else {
            throw .zeroPacketIdentifier
        }
        guard !p.subscriptions.isEmpty else {
            throw .emptyPayload
        }
        w.u16(p.packetId)
        try p.properties.encode(into: &w)
        for s in p.subscriptions {
            guard s.qos <= 2 else {
                throw .invalidQos(s.qos)
            }
            guard s.retainHandling <= 2 else {
                throw .invalidSubscriptionOptions(s.retainHandling << 4)
            }
            try w.string(s.topicFilter)
            var options: UInt8 = s.qos | s.retainHandling << 4
            if s.noLocal {
                options |= 0x04
            }
            if s.retainAsPublished {
                options |= 0x08
            }
            w.byte(options)
        }
    }
}

// MARK: - Decoding

extension MqttPacket {

    /// Decodes one whole packet (exactly as many bytes as the remaining length says). It never crashes on arbitrary
    /// bytes: everything malformed is a `MqttCodecError`.
    public static func decode(_ bytes: [UInt8]) throws(MqttCodecError) -> MqttPacket {
        guard let first = bytes.first else {
            throw .truncated
        }
        guard let (length, count) = try MqttVarInt.decode(bytes[1...], at: 1) else {
            throw .truncated
        }
        let start = 1 + count
        guard bytes.count - start == length else {
            throw .remainingLengthMismatch(declared: length, actual: bytes.count - start)
        }
        let type: UInt8 = first >> 4
        let flags: UInt8 = first & 0x0F
        var r = MqttReader(bytes, start: start)
        let packet: MqttPacket = try decodeBody(type: type, flags: flags, reader: &r)
        guard r.remaining == 0 else {
            throw .trailingBytes(r.remaining)
        }
        return packet
    }

    private static func expectFlags(_ type: UInt8, _ flags: UInt8, _ expected: UInt8) throws(MqttCodecError) {
        guard flags == expected else {
            throw .invalidFixedHeaderFlags(type: type, flags: flags)
        }
    }

    private static func decodeBody(type: UInt8, flags: UInt8, reader r: inout MqttReader) throws(MqttCodecError) -> MqttPacket {
        switch type {
        case 0:
            throw .reservedPacketType
        case 1:
            try expectFlags(type, flags, 0)
            return .connect(try decodeConnect(&r))
        case 2:
            try expectFlags(type, flags, 0)
            return .connack(try decodeConnack(&r))
        case 3:
            return .publish(try decodePublish(flags: flags, &r))
        case 4:
            try expectFlags(type, flags, 0)
            return .puback(try decodePuback(&r))
        case 8:
            try expectFlags(type, flags, 2)
            return .subscribe(try decodeSubscribe(&r))
        case 9:
            try expectFlags(type, flags, 0)
            return .suback(try decodeSuback(&r))
        case 12:
            try expectFlags(type, flags, 0)
            return .pingreq
        case 13:
            try expectFlags(type, flags, 0)
            return .pingresp
        case 14:
            try expectFlags(type, flags, 0)
            return .disconnect(try decodeDisconnect(&r))
        default:
            throw .unsupportedPacketType(type)
        }
    }

    private static func packetId(_ r: inout MqttReader) throws(MqttCodecError) -> UInt16 {
        let id: UInt16 = try r.u16()
        guard id != 0 else {
            throw .zeroPacketIdentifier
        }
        return id
    }

    private static func decodeConnect(_ r: inout MqttReader) throws(MqttCodecError) -> MqttConnect {
        let name: [UInt8] = try r.take(protocolName.count)
        let version: UInt8 = try r.byte()
        guard name == protocolName && version == 5 else {
            throw .unsupportedProtocol
        }
        let flags: UInt8 = try r.byte()
        guard flags & 0x01 == 0 else {
            throw .reservedFlagSet
        }
        let hasWill = flags & 0x04 != 0
        let willQos: UInt8 = (flags >> 3) & 0x03
        let willRetain = flags & 0x20 != 0
        guard willQos != 3 else {
            throw .invalidQos(3)
        }
        if !hasWill && (willQos != 0 || willRetain) {
            throw .inconsistentConnectFlags
        }
        let keepAlive: UInt16 = try r.u16()
        let properties: MqttProperties = try MqttProperties.decode(from: &r)
        let clientId: String = try r.string()
        var will: MqttWill?
        if hasWill {
            let willProps: MqttProperties = try MqttProperties.decode(from: &r)
            let topic: String = try r.string()
            let payload: [UInt8] = try r.binary()
            will = MqttWill(topic: topic, payload: payload, qos: willQos, retain: willRetain, properties: willProps)
        }
        let username: String? = if flags & 0x80 != 0 { try r.string() } else { nil }
        let password: [UInt8]? = if flags & 0x40 != 0 { try r.binary() } else { nil }
        return MqttConnect(
            clientId: clientId, cleanStart: flags & 0x02 != 0, keepAliveSeconds: keepAlive, properties: properties,
            will: will, username: username, password: password)
    }

    private static func decodeConnack(_ r: inout MqttReader) throws(MqttCodecError) -> MqttConnack {
        let ack: UInt8 = try r.byte()
        guard ack & 0xFE == 0 else {
            throw .reservedFlagSet
        }
        let reason: UInt8 = try r.byte()
        try MqttReasonCodes.validate(reason, type: 2)
        let properties: MqttProperties = try MqttProperties.decode(from: &r)
        return MqttConnack(sessionPresent: ack == 1, reasonCode: reason, properties: properties)
    }

    private static func decodePublish(flags: UInt8, _ r: inout MqttReader) throws(MqttCodecError) -> MqttPublish {
        let qos: UInt8 = (flags >> 1) & 0x03
        let dup = flags & 0x08 != 0
        guard qos != 3 else {
            throw .invalidQos(3)
        }
        if dup && qos == 0 {
            throw .dupWithQos0
        }
        let topic: String = try r.string()
        let id: UInt16? = if qos > 0 { try packetId(&r) } else { nil }
        let properties: MqttProperties = try MqttProperties.decode(from: &r)
        let payload: [UInt8] = r.rest()
        return MqttPublish(
            topic: topic, packetId: id, qos: qos, retain: flags & 0x01 != 0, dup: dup, properties: properties,
            payload: payload)
    }

    private static func decodePuback(_ r: inout MqttReader) throws(MqttCodecError) -> MqttPuback {
        let id: UInt16 = try packetId(&r)
        // §3.4.2.1: remaining length 2 = reason 0; 3 = reason only; more = reason + properties.
        let reason: UInt8 = if r.remaining > 0 { try r.byte() } else { 0 }
        try MqttReasonCodes.validate(reason, type: 4)
        let properties: MqttProperties = if r.remaining > 0 { try MqttProperties.decode(from: &r) } else { MqttProperties() }
        return MqttPuback(packetId: id, reasonCode: reason, properties: properties)
    }

    private static func decodeSubscribe(_ r: inout MqttReader) throws(MqttCodecError) -> MqttSubscribe {
        let id: UInt16 = try packetId(&r)
        let properties: MqttProperties = try MqttProperties.decode(from: &r)
        var subscriptions: [MqttSubscription] = []
        while r.remaining > 0 {
            let filter: String = try r.string()
            let options: UInt8 = try r.byte()
            guard options & 0xC0 == 0, (options >> 4) & 0x03 != 3 else {
                throw .invalidSubscriptionOptions(options)
            }
            guard options & 0x03 != 3 else {
                throw .invalidQos(3)
            }
            subscriptions.append(MqttSubscription(
                topicFilter: filter, qos: options & 0x03, noLocal: options & 0x04 != 0,
                retainAsPublished: options & 0x08 != 0, retainHandling: (options >> 4) & 0x03))
        }
        guard !subscriptions.isEmpty else {
            throw .emptyPayload
        }
        return MqttSubscribe(packetId: id, properties: properties, subscriptions: subscriptions)
    }

    private static func decodeSuback(_ r: inout MqttReader) throws(MqttCodecError) -> MqttSuback {
        let id: UInt16 = try packetId(&r)
        let properties: MqttProperties = try MqttProperties.decode(from: &r)
        let codes: [UInt8] = r.rest()
        guard !codes.isEmpty else {
            throw .emptyPayload
        }
        for code in codes {
            try MqttReasonCodes.validate(code, type: 9)
        }
        return MqttSuback(packetId: id, properties: properties, reasonCodes: codes)
    }

    private static func decodeDisconnect(_ r: inout MqttReader) throws(MqttCodecError) -> MqttDisconnect {
        // §3.14.2.1: remaining length 0 = reason 0 (Normal disconnection); 1 = reason only.
        let reason: UInt8 = if r.remaining > 0 { try r.byte() } else { 0 }
        try MqttReasonCodes.validate(reason, type: 14)
        let properties: MqttProperties = if r.remaining > 0 { try MqttProperties.decode(from: &r) } else { MqttProperties() }
        return MqttDisconnect(reasonCode: reason, properties: properties)
    }
}

/// Reason codes Paho 1.2.5 accepts when reading (`validateReturnCode` with the `validReturnCodes` array of the classes
/// `MqttConnAck`, `MqttPubAck`, `MqttSubAck`, `MqttDisconnect`); any other code is `REASON_CODE_INVALID_RETURN_CODE`
/// and the connection drops. Only decoding is checked (writing packets with an unknown code needs broker stand-ins).
enum MqttReasonCodes {

    static let connack: Set<UInt8> = [
        0x00, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8C, 0x90, 0x95, 0x97, 0x9A, 0x9C,
        0x9D, 0x9F,
    ]
    static let puback: Set<UInt8> = [0x00, 0x10, 0x80, 0x83, 0x87, 0x90, 0x97, 0x99]
    static let suback: Set<UInt8> = [0x00, 0x01, 0x02, 0x80, 0x83, 0x87, 0x8F, 0x91, 0x9E]
    static let disconnect: Set<UInt8> = [
        0x00, 0x04, 0x80, 0x81, 0x82, 0x83, 0x87, 0x89, 0x8B, 0x8D, 0x8E, 0x8F, 0x90, 0x93, 0x94, 0x95, 0x96, 0x97,
        0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xA0, 0xA1, 0xA2,
    ]

    /// - Parameter type: packet type (2 CONNACK, 4 PUBACK, 9 SUBACK, 14 DISCONNECT)
    static func validate(_ code: UInt8, type: UInt8) throws(MqttCodecError) {
        let valid: Set<UInt8>
        switch type {
        case 2: valid = connack
        case 4: valid = puback
        case 9: valid = suback
        default: valid = disconnect
        }
        guard valid.contains(code) else {
            throw .invalidReasonCode(type: type, code: code)
        }
    }
}
