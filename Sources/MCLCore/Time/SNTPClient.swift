import Foundation
import Network

/// Simple SNTP client (RFC 4330) — finds the offset of the computer clock from an NTP server.
/// Corresponds to the "Sync time" function in DXLog and time synchronisation in N1MM.
public enum SNTPClient {

    /// Offset of the NTP epoch (1900) from the Unix one (1970) in seconds.
    static let ntpEpochOffset: Int64 = 2_208_988_800

    /// Offset (ms, positive = the computer is behind) and path delay (ms).
    public struct Result: Equatable, Sendable {
        public let offsetMs: Int64
        public let roundTripMs: Int64
    }

    /// RFC 4330: offset = ((t2 − t1) + (t3 − t4)) / 2, delay = (t4 − t1) − (t3 − t2).
    static func compute(t1: Int64, t2: Int64, t3: Int64, t4: Int64) -> Result {
        Result(offsetMs: ((t2 - t1) + (t3 - t4)) / 2,
               roundTripMs: (t4 - t1) - (t3 - t2))
    }

    static func readTimestamp(_ bytes: [UInt8], at offset: Int) -> Int64 {
        func uint32(_ start: Int) -> Int64 {
            Int64(bytes[start]) << 24 | Int64(bytes[start + 1]) << 16
                | Int64(bytes[start + 2]) << 8 | Int64(bytes[start + 3])
        }
        let seconds = uint32(offset)
        let fraction = uint32(offset + 4)
        return (seconds - ntpEpochOffset) * 1000 + ((fraction * 1000) >> 32)
    }

    static func writeTimestamp(into bytes: inout [UInt8], at offset: Int, millis: Int64) {
        let seconds = millis / 1000 + ntpEpochOffset
        let fraction = ((millis % 1000) << 32) / 1000
        for i in 0..<4 { bytes[offset + i] = UInt8((seconds >> (24 - 8 * i)) & 0xFF) }
        for i in 0..<4 { bytes[offset + 4 + i] = UInt8((fraction >> (24 - 8 * i)) & 0xFF) }
    }
}

public extension SNTPClient {
    /// Errors of `query` that have no counterpart in the Java original (which works with an `int`
    /// port without validation).
    enum QueryError: Error, Equatable, Sendable {
        /// `port` is `0` — a reserved/"wildcard" value, not a valid UDP packet destination.
        ///
        /// Note on `NWEndpoint.Port(rawValue:)`: verified experimentally that for
        /// `UInt16` it never returns `nil` (even `rawValue: 0` succeeds) — so the original
        /// `NWEndpoint.Port(rawValue: port) ?? 123` was never a really
        /// reachable fallback, more like dead code. We therefore validate port 0
        /// explicitly ourselves, instead of relying on that initializer failing.
        case invalidPort(UInt16)
        /// The response from the NTP server is shorter than 48 bytes — a corrupted or
        /// untrustworthy packet from the configured host. The Java original reads
        /// into a fixed 48-byte `DatagramPacket` buffer, so a short
        /// response can never break parsing; `readTimestamp` in Swift
        /// on the contrary indexes `bytes[32...47]` without a length check, so a short
        /// response must be rejected before it ever reaches parsing.
        case responseTooShort(Int)
    }

    /// Asks the NTP server for the time. Called from the `Dispatchers.IO` equivalent, never from the UI.
    /// Public (member of a `public extension`) for the app layer (`ClockWatch`).
    static func query(host: String, port: UInt16, timeoutMs: Int) async throws -> Result {
        guard port != 0, let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw QueryError.invalidPort(port)
        }
        var request = [UInt8](repeating: 0, count: 48)
        request[0] = 0x1B // LI=0, VN=3, Mode=3 (client)
        let t1 = Int64(Date().timeIntervalSince1970 * 1000)
        writeTimestamp(into: &request, at: 40, millis: t1)

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .udp)
        defer { connection.cancel() }

        let response = try await connection.exchange(
            request: Data(request), expecting: 48, timeoutMs: timeoutMs)
        let t4 = Int64(Date().timeIntervalSince1970 * 1000)
        let bytes = [UInt8](response)
        guard bytes.count >= 48 else {
            throw QueryError.responseTooShort(bytes.count)
        }
        return compute(t1: t1,
                       t2: readTimestamp(bytes, at: 32),
                       t3: readTimestamp(bytes, at: 40),
                       t4: t4)
    }
}
