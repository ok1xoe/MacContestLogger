import Darwin
import Foundation
import Testing
@testable import MCLCore

/// `UdpSender` against Java `DatagramSocket.send` (maintainer-only probe, rows `UDP.`). Only
/// 127.0.0.1; receiving via the test's own UDP socket.
@Suite(.ioSafetyNet) struct UdpSenderTests {

    /// A UDP socket on 127.0.0.1:0 with a receive timeout (guard).
    final class Receiver: @unchecked Sendable {
        let fd: Int32
        let port: Int

        init() {
            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            self.fd = fd
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            sin.sin_addr.s_addr = in_addr_t(UInt32(0x7F00_0001).bigEndian)
            _ = withUnsafePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
            }
            self.port = Int(UInt16(bigEndian: sin.sin_port))
            var tv = timeval(tv_sec: 30, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }

        deinit {
            _ = Darwin.close(fd)
        }

        func receive() -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: 65_536)
            let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            return n > 0 ? Array(buf[0..<n]) : []
        }
    }

    static func result(_ host: String?, _ port: Int, size: Int) async -> String {
        await onOwnThread {
            do {
                try UdpSender.send([UInt8](repeating: 0x41, count: size), host: host, port: port)
                return "ok"
            } catch let e as JavaSocketError {
                return "EXC " + e.description
            } catch let e as JavaIllegalArgumentError {
                return "EXC java.lang.IllegalArgumentException: " + e.message
            } catch {
                return "EXC " + String(describing: error)
            }
        }
    }

    /// The send socket has `FD_CLOEXEC` (the application's subprocess does not inherit it).
    @Test func socketIsCloseOnExec() throws {
        for family in [AF_INET, AF_INET6] {
            let fd: Int32 = try UdpSender.openSocket(family: family)
            defer { _ = close(fd) }
            #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0, "family \(family)")
        }
    }

    @Test func sendsDatagramBytes() async throws {
        let receiver = Receiver()
        let message = Array("<N1MMRotor><stop>A</stop></N1MMRotor>".utf8)
        let port = receiver.port
        try await onOwnThread { try UdpSender.send(message, host: "127.0.0.1", port: port) }
        #expect(await onOwnThread { receiver.receive() } == message)
    }

    /// `""` and `nil` = loopback (Java `InetAddress.getByName`).
    @Test func emptyAndNilHostAreLoopback() async throws {
        let receiver = Receiver()
        let port = receiver.port
        try await onOwnThread { try UdpSender.send([1], host: "", port: port) }
        #expect(await onOwnThread { receiver.receive() } == [1])
        try await onOwnThread { try UdpSender.send([2], host: nil, port: port) }
        #expect(await onOwnThread { receiver.receive() } == [2])
    }

    @Test func errorsMatchJava() async throws {
        let free = FreeLoopbackPort.take()
        let cases: [(String, String?, Int, Int, String)] = [
            ("ok", "127.0.0.1", free, 10, "ok"),
            ("port0", "127.0.0.1", 0, 10, "EXC java.net.SocketException: Can't send to port 0"),
            ("port65536", "127.0.0.1", 65_536, 10, "EXC java.lang.IllegalArgumentException: Port out of range:65536"),
            ("portNeg", "127.0.0.1", -1, 10, "EXC java.lang.IllegalArgumentException: Port out of range:-1"),
            ("unknownHost", "nonexistent-host.invalid", free, 10,
             "EXC java.net.UnknownHostException: nonexistent-host.invalid"),
            ("size9216", "127.0.0.1", free, 9_216, "ok"),
            ("size9217", "127.0.0.1", free, 9_217, "ok"),
            ("size65507", "127.0.0.1", free, 65_507, "ok"),
            ("size65508", "127.0.0.1", free, 65_508, "EXC java.net.SocketException: Message too long"),
        ]
        for (name, host, port, size, expected) in cases {
            #expect(await Self.result(host, port, size: size) == expected, "UDP.\(name)")
        }
    }
}
