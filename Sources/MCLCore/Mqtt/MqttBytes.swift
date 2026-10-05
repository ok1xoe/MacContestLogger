/// MQTT 5 data types (§1.5): Two/Four Byte Integer, Variable Byte Integer, UTF-8 string, binary data.
public enum MqttVarInt {

    /// Largest Variable Byte Integer value (4 bytes).
    public static let max = 268_435_455

    /// Encodes a value 0…268 435 455 in the shortest form (§1.5.5).
    public static func encode(_ value: Int) throws(MqttCodecError) -> [UInt8] {
        guard value >= 0 && value <= max else {
            throw .variableByteIntegerOutOfRange(value)
        }
        var out: [UInt8] = []
        var x = value
        repeat {
            var byte = UInt8(x % 128)
            x /= 128
            if x > 0 {
                byte |= 0x80
            }
            out.append(byte)
        } while x > 0
        return out
    }

    /// Decodes from `start`; returns the value and byte count, `nil` = not enough bytes yet (the stream is still filling).
    /// Accepts an over-long form (e.g. `80 00`) like Paho (`MqttDataTypes.readVariableByteInteger`);
    /// a fifth byte is an error.
    public static func decode(_ bytes: ArraySlice<UInt8>, at start: Int) throws(MqttCodecError) -> (value: Int, count: Int)? {
        var value = 0
        var multiplier = 1
        var index = start
        while true {
            guard index < bytes.endIndex else {
                return nil
            }
            let byte = bytes[index]
            value += Int(byte & 0x7F) * multiplier
            index += 1
            if byte & 0x80 == 0 {
                return (value, index - start)
            }
            if index - start >= 4 {
                throw .variableByteIntegerTooLong
            }
            multiplier *= 128
        }
    }
}

/// Packet field writer.
struct MqttWriter {
    var bytes: [UInt8] = []

    mutating func byte(_ value: UInt8) {
        bytes.append(value)
    }

    mutating func u16(_ value: UInt16) {
        bytes.append(UInt8(value >> 8))
        bytes.append(UInt8(value & 0xFF))
    }

    mutating func u32(_ value: UInt32) {
        bytes.append(UInt8(value >> 24))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    mutating func varInt(_ value: Int) throws(MqttCodecError) {
        bytes += try MqttVarInt.encode(value)
    }

    /// UTF-8 string with a two-byte length (§1.5.4). Characters Paho rejects (`MqttDataTypes.encodeUTF8`
    /// → `validateUTF8String`) are an error — see `MqttUtf8.validate`.
    mutating func string(_ text: String) throws(MqttCodecError) {
        try MqttUtf8.validate(text)
        try binary(Array(text.utf8))
    }

    /// Binary data with a two-byte length (§1.5.6).
    mutating func binary(_ data: [UInt8]) throws(MqttCodecError) {
        guard data.count <= 65_535 else {
            throw .fieldTooLong(data.count)
        }
        u16(UInt16(data.count))
        bytes += data
    }

    mutating func raw(_ data: [UInt8]) {
        bytes += data
    }
}

/// Packet field reader over the body (without the fixed header); every read past the end is `truncated`.
struct MqttReader {
    private let bytes: [UInt8]
    private(set) var index: Int
    private var end: Int

    init(_ bytes: [UInt8], start: Int = 0) {
        self.bytes = bytes
        self.index = start
        self.end = bytes.count
    }

    var remaining: Int { end - index }

    mutating func byte() throws(MqttCodecError) -> UInt8 {
        guard index < end else {
            throw .truncated
        }
        let value = bytes[index]
        index += 1
        return value
    }

    mutating func u16() throws(MqttCodecError) -> UInt16 {
        let high: UInt8 = try byte()
        let low: UInt8 = try byte()
        return UInt16(high) << 8 | UInt16(low)
    }

    mutating func u32() throws(MqttCodecError) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            value = value << 8 | UInt32(try byte())
        }
        return value
    }

    mutating func varInt() throws(MqttCodecError) -> Int {
        let slice: ArraySlice<UInt8> = bytes[index..<end]
        guard let (value, count) = try MqttVarInt.decode(slice, at: index) else {
            throw .truncated
        }
        index += count
        return value
    }

    mutating func take(_ count: Int) throws(MqttCodecError) -> [UInt8] {
        guard count >= 0 && count <= remaining else {
            throw .truncated
        }
        let out = Array(bytes[index..<(index + count)])
        index += count
        return out
    }

    mutating func rest() -> [UInt8] {
        let out = Array(bytes[index..<end])
        index = end
        return out
    }

    mutating func binary() throws(MqttCodecError) -> [UInt8] {
        let count = Int(try u16())
        return try take(count)
    }

    /// UTF-8 string (§1.5.4) like Paho `MqttDataTypes.decodeUTF8`: the bytes are decoded the Java way by
    /// `new String(bytes, UTF_8)` (invalid sequences → U+FFFD, `JavaUtf8`) and the result goes through
    /// `MqttUtf8.validate` (control characters and noncharacters are an error).
    mutating func string() throws(MqttCodecError) -> String {
        let data: [UInt8] = try binary()
        return try Self.decodeUtf8(data)
    }

    static func decodeUtf8(_ data: [UInt8]) throws(MqttCodecError) -> String {
        let text: String = JavaUtf8.decode(data)
        try MqttUtf8.validate(text)
        return text
    }

    /// Limits reading to the next `count` bytes (property block); returns the original end for `restoreLimit`.
    mutating func limit(_ count: Int) throws(MqttCodecError) -> Int {
        guard count >= 0 && count <= remaining else {
            throw .propertyLengthMismatch
        }
        let saved = end
        end = index + count
        return saved
    }

    mutating func restoreLimit(_ saved: Int) {
        end = saved
    }
}

/// MQTT string check like Paho 1.2.5 (`MqttDataTypes.validateUTF8String`, called on both encode and decode):
/// rejects Java `Character.isISOControl` (U+0000–U+001F, U+007F–U+009F), noncharacters U+FDD0–U+FDDF
/// and `xxFFFE`/`xxFFFF` in all planes (and lone surrogates, which a Swift `String` cannot hold). Invalid
/// UTF-8 on input is **not an error** for Paho — `new String(bytes, UTF_8)` replaces it with U+FFFD (MQTT 5 §1.5.4
/// would reject it; we follow Paho). The error carries the UTF-16 unit reported by Paho
/// (`Invalid UTF-8 char: [%04x]`; for an astral character the high half of the pair).
enum MqttUtf8 {

    static func validate(_ text: String) throws(MqttCodecError) {
        for scalar in text.unicodeScalars {
            let v: UInt32 = scalar.value
            let control: Bool = v <= 0x1F || (v >= 0x7F && v <= 0x9F)
            let nonBase: Bool = v >= 0xFDD0 && v <= 0xFDDF
            let planeEnd: Bool = v & 0xFFFE == 0xFFFE
            guard control || nonBase || planeEnd else { continue }
            let unit: UInt16 = v > 0xFFFF ? UInt16(0xD800 + ((v - 0x10000) >> 10)) : UInt16(v)
            throw .invalidCharacter(unit)
        }
    }
}
