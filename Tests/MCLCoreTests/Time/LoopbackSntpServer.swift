import Darwin
import Foundation
@testable import MCLCore

/// A hermetic "NTP" server on the loopback — for `SNTPClientTests.queriesFakeServer`,
/// a port of Java `SntpClientTest.queriesFakeServer`, which creates a real
/// `DatagramSocket` na `InetAddress.getLoopbackAddress()`.
///
/// A plain POSIX UDP socket, not `NWListener`: for a single request/response pair on
/// the loopback it is simpler and deterministic — no listener state machine,
/// just `bind` (port 0 = the system assigns a free one), `recvfrom`, `sendto`.
final class LoopbackSntpServer: @unchecked Sendable {
    /// The port the system assigned at `bind`.
    let port: UInt16
    private let fd: Int32

    enum ServerError: Error {
        case socketCreationFailed
        case bindFailed
        case getsocknameFailed
    }

    init() throws {
        let newFd = socket(AF_INET, SOCK_DGRAM, 0)
        guard newFd >= 0 else { throw ServerError.socketCreationFailed }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0 // ephemeral port

        let bindResult = withUnsafePointer(to: &addr) { addrPtr -> Int32 in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(newFd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(newFd)
            throw ServerError.bindFailed
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { addrPtr -> Int32 in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.getsockname(newFd, sa, &boundLen)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(newFd)
            throw ServerError.getsocknameFailed
        }

        // A safety net: if the query never arrived for some reason, let
        // the server thread end by itself after a while instead of hanging forever.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(newFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        self.fd = newFd
        self.port = UInt16(bigEndian: boundAddr.sin_port)
    }

    /// Receives one query and replies with a timestamp `aheadMs` ahead — like Java
    /// `queriesFakeServer` (`resp[0] = 0x1C`, timestamp at offsets 32 and 40).
    /// Blocking — call from its own thread, not from the main/test task.
    func respondOnce(aheadMs: Int64) {
        var buffer = [UInt8](repeating: 0, count: 48)
        var fromAddr = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &fromAddr) { addrPtr -> Int in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &buffer, buffer.count, 0, sa, &fromLen)
            }
        }
        guard received > 0 else { return } // safety-net timeout or an error

        var response = [UInt8](repeating: 0, count: 48)
        response[0] = 0x1C
        let now = Int64(Date().timeIntervalSince1970 * 1000) + aheadMs
        SNTPClient.writeTimestamp(into: &response, at: 32, millis: now)
        SNTPClient.writeTimestamp(into: &response, at: 40, millis: now)

        _ = withUnsafePointer(to: &fromAddr) { addrPtr -> Int in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(fd, &response, response.count, 0, sa, fromLen)
            }
        }
    }

    /// Receives one query and replies with a deliberately shorter packet than `query` expects
    /// (48 bytes) — for `SNTPClientTests.shortResponseThrowsInsteadOfCrashing`
    /// (F3): verifies that a corrupt/forged reply from a configured host
    /// leads to an error, not to a process crash when indexing `bytes[32...47]`.
    func respondOnceWithShortResponse(byteCount: Int) {
        var buffer = [UInt8](repeating: 0, count: 48)
        var fromAddr = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &fromAddr) { addrPtr -> Int in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &buffer, buffer.count, 0, sa, &fromLen)
            }
        }
        guard received > 0 else { return } // safety-net timeout or an error

        var response = [UInt8](repeating: 0xFF, count: byteCount)
        _ = withUnsafePointer(to: &fromAddr) { addrPtr -> Int in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(fd, &response, response.count, 0, sa, fromLen)
            }
        }
    }

    func close() {
        Darwin.close(fd)
    }
}
