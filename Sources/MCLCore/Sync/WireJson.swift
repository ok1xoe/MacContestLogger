/// (De)serialisation error of a wire message (Java `SyncSerializationException`). `message` literally as Java
/// (`"Nelze deserializovat " + type.getSimpleName()`); Swift does not carry the cause (a Jackson exception) — all that matters is
/// whether the read succeeded.
public struct SyncSerializationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// (De)serialisation of cluster sync wire messages — counterpart of Java `sync.WireJson` (Jackson 2.22,
/// `JavaTimeModule`, `WRITE_DATES_AS_TIMESTAMPS` off, `FAIL_ON_UNKNOWN_PROPERTIES` off).
///
/// **Writing** (`WireJsonWriter`): components in Java record order, `null` is written, no spaces, numbers bare,
/// the instant as `Instant.toString()`; in strings `\"`, `\\`, `\b \t \n \f \r`, others < U+0020 as upper-case `\u00XX`,
/// everything else (also `/`, DEL, U+2028) raw in UTF-8 — except characters above U+FFFF in `toBytes` (the wire), which
/// Jackson writes as an escaped surrogate pair. Swift `JSONEncoder` cannot be used: it escapes `/` and does not keep key
/// order.
///
/// **Reading** (`WireJsonReader`): the Java parser `UTF8StreamJsonParser` and the `StdDeserializer`/
/// `InstantDeserializer` coercions — see there. A read error is always `SyncSerializationError("Nelze deserializovat <Typ>")`;
/// a root `null` returns `nil` (Java `null`).
public enum WireJson {

    /// `WireJson.toJson` — JSON as text (Jackson `WriterBasedJsonGenerator`: astral characters raw).
    public static func toJson<T: WireMessage>(_ value: T) -> String {
        var writer = WireJsonWriter(escapeAstral: false)
        writer.record(T.wireFields, value.wireValues)
        return String(decoding: writer.bytes, as: UTF8.self)
    }

    /// `WireJson.toBytes` — JSON as UTF-8 bytes, as it goes over the MQTT wire (Jackson `UTF8JsonGenerator`:
    /// a character above U+FFFF as a pair of escapes `😀` in upper case, others as `toJson`).
    public static func toBytes<T: WireMessage>(_ value: T) -> [UInt8] {
        var writer = WireJsonWriter(escapeAstral: true)
        writer.record(T.wireFields, value.wireValues)
        return writer.bytes
    }

    /// `WireJson.fromBytes(json, type)`; `nil` = Java `null` (the root literal `null`).
    public static func fromBytes<T: WireMessage>(_ json: [UInt8], as type: T.Type) throws(SyncSerializationError) -> T? {
        let values: [WireValue]?
        do {
            values = try WireJsonReader.decodeRoot(json, fields: T.wireFields)
        } catch {
            throw SyncSerializationError(message: "Nelze deserializovat " + T.wireTypeName)
        }
        return values.map(T.init(wireValues:))
    }
}

/// JSON writer in Java form (Jackson with default escapes). `escapeAstral` = `UTF8JsonGenerator`
/// (`toBytes`), otherwise `WriterBasedJsonGenerator` (`toJson`).
struct WireJsonWriter {
    var bytes: [UInt8] = []
    let escapeAstral: Bool

    init(escapeAstral: Bool) {
        self.escapeAstral = escapeAstral
    }

    mutating func record(_ fields: [WireField], _ values: [WireValue]) {
        bytes.append(0x7B)
        for (index, field) in fields.enumerated() {
            if index > 0 {
                bytes.append(0x2C)
            }
            string(field.name)
            bytes.append(0x3A)
            value(field.kind, values[index])
        }
        bytes.append(0x7D)
    }

    mutating func value(_ kind: WireKind, _ value: WireValue) {
        switch value {
        case .string(let v):
            if let v { string(v) } else { null() }
        case .long(let v):
            ascii(String(v))
        case .int(let v):
            ascii(String(v))
        case .bool(let v):
            ascii(v ? "true" : "false")
        case .intBox(let v):
            if let v { ascii(String(v)) } else { null() }
        case .boolBox(let v):
            if let v { ascii(v ? "true" : "false") } else { null() }
        case .instant(let v):
            if let v { string(v.toString()) } else { null() }
        case .record(let v):
            if let v, case .record(let fields) = kind { record(fields, v) } else { null() }
        }
    }

    mutating func null() {
        ascii("null")
    }

    mutating func ascii(_ text: String) {
        bytes += Array(text.utf8)
    }

    private static let hex: [UInt8] = Array("0123456789ABCDEF".utf8)

    mutating func string(_ text: String) {
        bytes.append(0x22)
        for scalar in text.unicodeScalars {
            let v: UInt32 = scalar.value
            switch v {
            case 0x22: bytes += [0x5C, 0x22]
            case 0x5C: bytes += [0x5C, 0x5C]
            case 0x08: bytes += [0x5C, 0x62]
            case 0x09: bytes += [0x5C, 0x74]
            case 0x0A: bytes += [0x5C, 0x6E]
            case 0x0C: bytes += [0x5C, 0x66]
            case 0x0D: bytes += [0x5C, 0x72]
            case 0x00..<0x20:
                unicodeEscape(UInt16(v))
            case 0x10000... where escapeAstral:
                let offset: UInt32 = v - 0x10000
                unicodeEscape(UInt16(0xD800 + (offset >> 10)))
                unicodeEscape(UInt16(0xDC00 + (offset & 0x3FF)))
            default:
                bytes += Array(String(scalar).utf8)
            }
        }
        bytes.append(0x22)
    }

    /// `\uXXXX` with upper-case hex digits.
    mutating func unicodeEscape(_ unit: UInt16) {
        bytes += [0x5C, 0x75, Self.hex[Int(unit >> 12)], Self.hex[Int((unit >> 8) & 0x0F)]]
        bytes += [Self.hex[Int((unit >> 4) & 0x0F)], Self.hex[Int(unit & 0x0F)]]
    }
}
