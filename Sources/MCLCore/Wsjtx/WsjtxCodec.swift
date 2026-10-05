import Foundation

/// (De)serialisation errors of WSJT-X — Java exceptions thrown by `WsjtxCodec`/`WsjtxMessages`.
///
/// `WsjtxMessages.decode` in Java wraps `IOException` into `UncheckedIOException` and lets others through:
/// `javaDescription(fromDecode:)` returns Java `Throwable.toString()` in both forms.
public enum WsjtxError: Error, Equatable, Sendable {
    /// `IllegalArgumentException("Neplatné WSJT-X magic: " + Integer.toHexString(magic))`.
    case badMagic(Int32)
    /// `java.io.EOFException` (no message) — the datagram ended in the middle of a field.
    case endOfStream
    /// `IOException("WSJT-X string length out of range: n")` — string length above 65 535.
    case stringLengthOutOfRange(Int32)
    /// `java.time.DateTimeException` from `LocalDate.ofEpochDay` — a Julian day outside the `LocalDate` range.
    case epochDayOutOfRange(Int64)

    /// Java exception class (before wrapping in `decode`).
    public var javaClass: String {
        switch self {
        case .badMagic: "java.lang.IllegalArgumentException"
        case .endOfStream: "java.io.EOFException"
        case .stringLengthOutOfRange: "java.io.IOException"
        case .epochDayOutOfRange: "java.time.DateTimeException"
        }
    }

    /// Java `getMessage()` (before wrapping in `decode`); `nil` = Java `null`.
    public var message: String? {
        switch self {
        case .badMagic(let magic):
            return "Neplatné WSJT-X magic: " + String(UInt32(bitPattern: magic), radix: 16)
        case .endOfStream:
            return nil
        case .stringLengthOutOfRange(let length):
            return "WSJT-X string length out of range: " + String(length)
        case .epochDayOutOfRange(let epochDay):
            let range: String = "(valid values -365243219162 - 365241780471): "
            return "Invalid value for EpochDay " + range + String(epochDay)
        }
    }

    /// Java `Throwable.toString()`; `fromDecode` = the exception as it escapes from `WsjtxMessages.decode`
    /// (`IOException` wrapped in `UncheckedIOException`, whose message is `cause.toString()`).
    public func javaDescription(fromDecode: Bool) -> String {
        let plain: String = message.map { javaClass + ": " + $0 } ?? javaClass
        switch self {
        case .endOfStream, .stringLengthOutOfRange:
            return fromDecode ? "java.io.UncheckedIOException: " + plain : plain
        case .badMagic, .epochDayOutOfRange:
            return plain
        }
    }
}

/// Reading big-endian primitives like Java `DataInputStream` over `ByteArrayInputStream`. Lack of bytes
/// is always `WsjtxError.endOfStream`, never a crash — the input comes from the network.
public struct WsjtxDataInput: Sendable {
    public let bytes: [UInt8]
    public private(set) var position: Int = 0

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Java `available()`.
    public var available: Int { bytes.count - position }

    /// Java `readFully(byte[count])`.
    public mutating func readFully(_ count: Int) throws(WsjtxError) -> [UInt8] {
        guard count >= 0, count <= available else { throw .endOfStream }
        let out: [UInt8] = Array(bytes[position..<(position + count)])
        position += count
        return out
    }

    public mutating func readUnsignedByte() throws(WsjtxError) -> UInt8 {
        guard available >= 1 else { throw .endOfStream }
        let value: UInt8 = bytes[position]
        position += 1
        return value
    }

    /// Java `readBoolean`: any non-zero byte is `true`.
    public mutating func readBoolean() throws(WsjtxError) -> Bool {
        try readUnsignedByte() != 0
    }

    public mutating func readInt() throws(WsjtxError) -> Int32 {
        Int32(truncatingIfNeeded: try readBigEndian(4))
    }

    public mutating func readLong() throws(WsjtxError) -> Int64 {
        Int64(bitPattern: try readBigEndian(8))
    }

    /// Java `readDouble` = `longBitsToDouble(readLong())`: the bit pattern unchanged (including the NaN payload).
    public mutating func readDouble() throws(WsjtxError) -> Double {
        Double(bitPattern: UInt64(bitPattern: try readLong()))
    }

    private mutating func readBigEndian(_ count: Int) throws(WsjtxError) -> UInt64 {
        guard available >= count else { throw .endOfStream }
        var value: UInt64 = 0
        for offset in 0..<count {
            value = value << 8 | UInt64(bytes[position + offset])
        }
        position += count
        return value
    }
}

/// Writing big-endian primitives like Java `DataOutputStream` over `ByteArrayOutputStream`.
public struct WsjtxDataOutput: Sendable {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func write(_ data: [UInt8]) {
        bytes += data
    }

    /// Java `writeByte(int)`: the low 8 bits (`0x1FF` → `FF`).
    public mutating func writeByte(_ value: Int32) {
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    public mutating func writeBoolean(_ value: Bool) {
        bytes.append(value ? 1 : 0)
    }

    public mutating func writeInt(_ value: Int32) {
        writeBigEndian(UInt64(UInt32(bitPattern: value)), 4)
    }

    public mutating func writeLong(_ value: Int64) {
        writeBigEndian(UInt64(bitPattern: value), 8)
    }

    /// Java `writeDouble` = `writeLong(doubleToLongBits(v))`: **every NaN is canonicalised** to
    /// `7FF8000000000000` (Swift `bitPattern` would keep the payload).
    public mutating func writeDouble(_ value: Double) {
        let bits: UInt64 = value.isNaN ? 0x7FF8_0000_0000_0000 : value.bitPattern
        writeBigEndian(bits, 8)
    }

    private mutating func writeBigEndian(_ value: UInt64, _ count: Int) {
        for index in stride(from: count - 1, through: 0, by: -1) {
            bytes.append(UInt8(truncatingIfNeeded: value >> (UInt64(index) * 8)))
        }
    }
}

/// Low-level (de)serialisation of Qt `QDataStream` primitives — port of `wsjtx/WsjtxCodec.java` (v1.1.1).
///
/// Instants are Swift `Date` (seconds in a `Double`): writing takes milliseconds truncated toward −∞ (Java
/// `getNano() / 1_000_000`) with a `Double` noise tolerance (`epochMillis`), reading assembles whole seconds and the remaining
/// milliseconds. For dates within ±20 000 years of 1970 it is byte-identical to Java (verified by the reference
/// `wsjtx.*`); `Double` carries milliseconds only up to roughly ±70 000 years, beyond that Java `Instant` does — a divergence of
/// precision only, without a crash (a deliberate divergence from Java v1.1.1).
public enum WsjtxCodec {

    /// Julian day number 1970-01-01 (`QDate::toJulianDay`).
    static let jdEpoch1970: Int64 = 2_440_588

    /// Range of `ChronoField.EPOCH_DAY` (`LocalDate.MIN`…`LocalDate.MAX`).
    static let minEpochDay: Int64 = -365_243_219_162
    static let maxEpochDay: Int64 = 365_241_780_471

    /// Qt string: `int` length + UTF-8 bytes; `nil` → length −1.
    public static func writeString(_ out: inout WsjtxDataOutput, _ s: String?) {
        guard let s else {
            out.writeInt(-1)
            return
        }
        let utf8: [UInt8] = Array(s.utf8)
        out.writeInt(Int32(truncatingIfNeeded: utf8.count))
        out.write(utf8)
    }

    /// Negative length (not only −1) → `nil`; above 65 535 → `stringLengthOutOfRange`; invalid UTF-8 is
    /// replaced by `U+FFFD` like Java `new String(b, UTF_8)` (`JavaUtf8`, not Swift's maximal subpart).
    public static func readString(_ input: inout WsjtxDataInput) throws(WsjtxError) -> String? {
        let length: Int32 = try input.readInt()
        if length < 0 {
            return nil
        }
        if length > 65_535 {
            throw .stringLengthOutOfRange(length)
        }
        let data: [UInt8] = try input.readFully(Int(length))
        return JavaUtf8.decode(data)
    }

    /// `QDate::toJulianDay` of a valid date (`LocalDate.toEpochDay() + 2440588`).
    public static func julianDay(year: Int64, month: Int64, day: Int64) -> Int64 {
        JavaLocalDate.epochDay(year: year, month: month, day: day) &+ jdEpoch1970
    }

    /// `LocalDate.ofEpochDay(jd - 2440588)` → (year, month, day); outside the `LocalDate` range it throws like Java
    /// `DateTimeException` (the difference overflows like a Java `long`).
    public static func dateFromJulianDay(_ jd: Int64) throws(WsjtxError) -> (year: Int64, month: Int64, day: Int64) {
        JavaLocalDate.civil(epochDay: try epochDay(fromJulianDay: jd))
    }

    /// Qt `QDateTime` in UTC: `long` Julian day + `int` ms since midnight + `byte` spec (1 = UTC).
    /// `nil` → `0, 0, 1`.
    public static func writeDateTimeUtc(_ out: inout WsjtxDataOutput, _ t: Date?) {
        guard let t else {
            out.writeLong(0)
            out.writeInt(0)
            out.writeByte(1)
            return
        }
        let millis: Int64 = epochMillis(t)
        let day: Int64 = JavaMath.floorDiv(millis, 86_400_000)
        out.writeLong(day &+ jdEpoch1970)
        out.writeInt(Int32(truncatingIfNeeded: millis - day * 86_400_000))
        out.writeByte(1)
    }

    /// Spec 2 additionally reads an `int` offset (unused); Julian day 0 → `nil`; milliseconds are
    /// not checked (`0x7FFFFFFF` = +24.8 days, negative ones go before midnight).
    public static func readDateTimeUtc(_ input: inout WsjtxDataInput) throws(WsjtxError) -> Date? {
        let jd: Int64 = try input.readLong()
        let ms: Int32 = try input.readInt()
        let spec: UInt8 = try input.readUnsignedByte()
        if spec == 2 {
            _ = try input.readInt() // offset (unused)
        }
        if jd == 0 {
            return nil
        }
        let day: Int64 = try epochDay(fromJulianDay: jd)
        let msWide: Int64 = Int64(ms)
        let seconds: Int64 = day * 86_400 + JavaMath.floorDiv(msWide, 1000)
        let fraction: Int64 = msWide - JavaMath.floorDiv(msWide, 1000) * 1000
        return Date(timeIntervalSince1970: Double(seconds) + Double(fraction) / 1000)
    }

    /// Epoch day from a Julian day with a `LocalDate.ofEpochDay` range check.
    static func epochDay(fromJulianDay jd: Int64) throws(WsjtxError) -> Int64 {
        let day: Int64 = jd &- jdEpoch1970
        guard day >= minEpochDay, day <= maxEpochDay else {
            throw .epochDayOutOfRange(day)
        }
        return day
    }

    /// Epoch milliseconds truncated toward −∞ (Java `getNano() / 1_000_000` over `Instant`). `Date` carries
    /// seconds in a `Double` with a few ULP of noise, so a value closer than `max(0.5 µs, 2 ULP)` to a whole
    /// millisecond is taken as that millisecond, otherwise it is truncated. Outside `Int64` saturated to half the range
    /// (Java has no such `Instant`), NaN as positive saturation.
    static func epochMillis(_ date: Date) -> Int64 {
        saturated(floorIgnoringNoise(date.timeIntervalSince1970 * 1000, minimumTolerance: 0.000_5))
    }

    /// `floor(x)`, except values within the `Double` noise tolerance below an integer (those give that integer).
    static func floorIgnoringNoise(_ x: Double, minimumTolerance: Double) -> Double {
        let nearest: Double = x.rounded()
        let tolerance: Double = Swift.max(minimumTolerance, 2 * nearest.ulp)
        return Swift.abs(x - nearest) <= tolerance ? nearest : x.rounded(.down)
    }

    static func saturated(_ value: Double) -> Int64 {
        if let exact = Int64(exactly: value), exact > Int64.min / 2, exact < Int64.max / 2 {
            return exact
        }
        return value < 0 ? Int64.min / 2 : Int64.max / 2
    }
}
