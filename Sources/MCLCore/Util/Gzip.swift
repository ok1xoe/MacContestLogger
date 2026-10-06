import Foundation

/// A single-member gzip stream (RFC 1952) decoded with Apple's raw DEFLATE (`NSData.decompressed(using: .zlib)`).
/// The optional header fields (`FEXTRA`, `FNAME`, `FCOMMENT`, `FHCRC`) are skipped; the trailing CRC-32 and
/// length are verified.
public enum Gzip {

    public struct Error: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        public let reason: String
        public var description: String { "invalid gzip: \(reason)" }
    }

    /// `true` when `data` starts with the gzip magic bytes.
    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }

    public static func decompress(_ data: Data) throws(Gzip.Error) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B else {
            throw Error(reason: "header")
        }
        guard bytes[2] == 8 else { throw Error(reason: "compression method \(bytes[2])") }
        let flags: UInt8 = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw Error(reason: "header") }
            offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8)
        }
        for bit in [UInt8(0x08), 0x10] where flags & bit != 0 { // FNAME, FCOMMENT: zero-terminated
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        guard offset <= bytes.count - 8 else { throw Error(reason: "header") }
        let body = Data(bytes[offset..<(bytes.count - 8)])
        let out: Data
        do {
            out = try (body as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw Error(reason: "deflate")
        }
        let crc: UInt32 = bytes[(bytes.count - 8)..<(bytes.count - 4)].reversed()
            .reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let size: UInt32 = bytes[(bytes.count - 4)...].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard size == UInt32(truncatingIfNeeded: out.count) else { throw Error(reason: "length") }
        guard crc == crc32(out) else { throw Error(reason: "CRC32") }
        return out
    }

    /// CRC-32 (IEEE 802.3, reversed polynomial `0xEDB88320`), as gzip writes it.
    public static func crc32(_ data: Data) -> UInt32 {
        let table = crcTable
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for byte in raw { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0..<256).map { (n: Int) -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// A gzip stream of `data` (one member, no optional fields) — for tests and fixtures.
    public static func compress(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 0xFF])
        out.append(deflated)
        var crc = crc32(data).littleEndian
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }
}
