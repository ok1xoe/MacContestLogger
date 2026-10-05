/// Value of one MQTT 5 property (§2.2.2.2) according to its data type.
public enum MqttPropertyValue: Equatable, Sendable {
    case byte(UInt8)
    case u16(UInt16)
    case u32(UInt32)
    case varInt(Int)
    case string(String)
    case binary([UInt8])
    case pair(String, String)
}

/// One property (identifier + value).
public struct MqttProperty: Equatable, Sendable {
    public let id: UInt8
    public let value: MqttPropertyValue

    public init(_ id: UInt8, _ value: MqttPropertyValue) {
        self.id = id
        self.value = value
    }
}

/// List of properties in wire order. The codec decodes them all (an unknown identifier = Malformed Packet),
/// the client reads only those Paho uses. A repeated property (except Subscription Identifier
/// and User Property) is an error as in Paho; properties allowed per packet type are not checked.
public struct MqttProperties: Equatable, Sendable {

    public enum Id {
        public static let payloadFormatIndicator: UInt8 = 0x01
        public static let messageExpiryInterval: UInt8 = 0x02
        public static let contentType: UInt8 = 0x03
        public static let responseTopic: UInt8 = 0x08
        public static let correlationData: UInt8 = 0x09
        public static let subscriptionIdentifier: UInt8 = 0x0B
        public static let sessionExpiryInterval: UInt8 = 0x11
        public static let assignedClientIdentifier: UInt8 = 0x12
        public static let serverKeepAlive: UInt8 = 0x13
        public static let authenticationMethod: UInt8 = 0x15
        public static let authenticationData: UInt8 = 0x16
        public static let requestProblemInformation: UInt8 = 0x17
        public static let willDelayInterval: UInt8 = 0x18
        public static let requestResponseInformation: UInt8 = 0x19
        public static let responseInformation: UInt8 = 0x1A
        public static let serverReference: UInt8 = 0x1C
        public static let reasonString: UInt8 = 0x1F
        public static let receiveMaximum: UInt8 = 0x21
        public static let topicAliasMaximum: UInt8 = 0x22
        public static let topicAlias: UInt8 = 0x23
        public static let maximumQos: UInt8 = 0x24
        public static let retainAvailable: UInt8 = 0x25
        public static let userProperty: UInt8 = 0x26
        public static let maximumPacketSize: UInt8 = 0x27
        public static let wildcardSubscriptionAvailable: UInt8 = 0x28
        public static let subscriptionIdentifierAvailable: UInt8 = 0x29
        public static let sharedSubscriptionAvailable: UInt8 = 0x2A
    }

    enum Kind {
        case byte, u16, u32, varInt, string, binary, pair
    }

    static func kind(of id: UInt8) -> Kind? {
        switch id {
        case 0x01, 0x17, 0x19, 0x24, 0x25, 0x28, 0x29, 0x2A:
            return .byte
        case 0x13, 0x21, 0x22, 0x23:
            return .u16
        case 0x02, 0x11, 0x18, 0x27:
            return .u32
        case 0x0B:
            return .varInt
        case 0x03, 0x08, 0x12, 0x15, 0x1A, 0x1C, 0x1F:
            return .string
        case 0x09, 0x16:
            return .binary
        case 0x26:
            return .pair
        default:
            return nil
        }
    }

    public var items: [MqttProperty]

    public init(_ items: [MqttProperty] = []) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }

    /// First value with the given identifier.
    public func first(_ id: UInt8) -> MqttPropertyValue? {
        items.first { $0.id == id }?.value
    }

    public func u16(_ id: UInt8) -> UInt16? {
        if case .u16(let v)? = first(id) { return v }
        return nil
    }

    public func u32(_ id: UInt8) -> UInt32? {
        if case .u32(let v)? = first(id) { return v }
        return nil
    }

    public func string(_ id: UInt8) -> String? {
        if case .string(let v)? = first(id) { return v }
        return nil
    }

    /// Without properties with the given identifier (e.g. Topic Alias).
    public func removing(_ id: UInt8) -> MqttProperties {
        MqttProperties(items.filter { $0.id != id })
    }

    /// Block length (Variable Byte Integer) + properties.
    func encode(into writer: inout MqttWriter) throws(MqttCodecError) {
        var body = MqttWriter()
        for item in items {
            try Self.encode(item, into: &body)
        }
        try writer.varInt(body.bytes.count)
        writer.raw(body.bytes)
    }

    private static func encode(_ item: MqttProperty, into w: inout MqttWriter) throws(MqttCodecError) {
        // The value type must match the identifier — otherwise the peer would read a different shape.
        guard let kind = kind(of: item.id) else {
            throw .unknownProperty(item.id)
        }
        try w.varInt(Int(item.id))
        switch (kind, item.value) {
        case (.byte, .byte(let v)):
            w.byte(v)
        case (.u16, .u16(let v)):
            w.u16(v)
        case (.u32, .u32(let v)):
            w.u32(v)
        case (.varInt, .varInt(let v)):
            try w.varInt(v)
        case (.string, .string(let v)):
            try w.string(v)
        case (.binary, .binary(let v)):
            try w.binary(v)
        case (.pair, .pair(let k, let v)):
            try w.string(k)
            try w.string(v)
        default:
            throw .unknownProperty(item.id)
        }
    }

    /// Reads a property block (length + properties); a property overflowing the block is an error.
    static func decode(from reader: inout MqttReader) throws(MqttCodecError) -> MqttProperties {
        let length: Int = try reader.varInt()
        let saved: Int = try reader.limit(length)
        var items: [MqttProperty] = []
        do throws(MqttCodecError) {
            while reader.remaining > 0 {
                let item: MqttProperty = try decodeOne(from: &reader)
                // Paho `MqttProperties.decodeProperties`: only Subscription Identifier and User Property may repeat.
                if item.id != Id.subscriptionIdentifier && item.id != Id.userProperty && items.contains(where: { $0.id == item.id }) {
                    throw .duplicateProperty(item.id)
                }
                items.append(item)
            }
        } catch {
            throw error == .truncated ? .propertyLengthMismatch : error
        }
        reader.restoreLimit(saved)
        return MqttProperties(items)
    }

    private static func decodeOne(from r: inout MqttReader) throws(MqttCodecError) -> MqttProperty {
        // The identifier is formally a Variable Byte Integer; all known ones fit in one byte.
        let rawId: Int = try r.varInt()
        guard rawId <= 0x7F, let kind = kind(of: UInt8(rawId)) else {
            throw .unknownProperty(UInt8(truncatingIfNeeded: rawId))
        }
        let id = UInt8(rawId)
        let value: MqttPropertyValue
        switch kind {
        case .byte:
            value = .byte(try r.byte())
        case .u16:
            value = .u16(try r.u16())
        case .u32:
            value = .u32(try r.u32())
        case .varInt:
            value = .varInt(try r.varInt())
        case .string:
            value = .string(try r.string())
        case .binary:
            value = .binary(try r.binary())
        case .pair:
            let key: String = try r.string()
            value = .pair(key, try r.string())
        }
        return MqttProperty(id, value)
    }
}
