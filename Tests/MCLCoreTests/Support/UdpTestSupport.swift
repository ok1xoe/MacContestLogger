import Darwin
import Foundation

/// A wait guard of the UDP tests (s): a datagram over the loopback arrives in the order of ms; a longer wait = an error, not a slow machine.
let ioWait: TimeInterval = 20

/// A queue for handler outputs (Java `ArrayBlockingQueue`): the handler on the reader thread `offer`s, the test waits
/// in `take` — **only from its own thread** (`onOwnThread`), never in the shared pool. The guard `ioWait`
/// (20 s, not a measure of success): after it `take` returns `nil` and the test fails with a message instead of hanging.
final class Inbox<T: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private var items: [T] = []

    func offer(_ item: T) {
        condition.lock()
        items.append(item)
        condition.broadcast()
        condition.unlock()
    }

    /// Blocking: the first element of the queue; `nil` after the guard `ioWait`.
    func take() -> T? {
        let deadline = Date(timeIntervalSinceNow: ioWait)
        condition.lock()
        defer { condition.unlock() }
        while items.isEmpty {
            // Bounded explicitly: a spurious wake-up cannot extend the wait past the guard.
            if Date() >= deadline || (!condition.wait(until: deadline) && items.isEmpty) {
                return nil
            }
        }
        return items.removeFirst()
    }

    var count: Int {
        condition.lock()
        defer { condition.unlock() }
        return items.count
    }
}

/// A test UDP socket (Java `new DatagramSocket()` in tests): an IPv4 or IPv6 loopback, an OS-assigned port, receive
/// with the guard `SO_RCVTIMEO` = `ioWait` (not a measure of success).
final class UdpTestSocket: @unchecked Sendable {
    let fd: Int32
    let port: Int
    let family: Int32

    init(ipv6: Bool = false, wildcard: Bool = false) {
        family = ipv6 ? AF_INET6 : AF_INET
        let fd: Int32 = socket(family, SOCK_DGRAM, 0)
        precondition(fd >= 0, "socket")
        self.fd = fd
        var tv = timeval(tv_sec: Int(ioWait), tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        if ipv6 {
            var sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            sin6.sin6_addr = wildcard ? in6addr_any : in6addr_loopback
            let rc: Int32 = withUnsafePointer(to: &sin6) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
            precondition(rc == 0, "bind6")
            var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
            _ = withUnsafeMutablePointer(to: &sin6) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
            }
            port = Int(UInt16(bigEndian: sin6.sin6_port))
        } else {
            var sin = Self.ipv4(wildcard ? 0 : 0x7F00_0001, port: 0)
            let rc: Int32 = withUnsafePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            precondition(rc == 0, "bind4")
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
            }
            port = Int(UInt16(bigEndian: sin.sin_port))
        }
    }

    deinit {
        _ = Darwin.close(fd)
    }

    static func ipv4(_ address: UInt32, port: Int) -> sockaddr_in {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = in_addr_t(address.bigEndian)
        sin.sin_port = UInt16(port).bigEndian
        return sin
    }

    /// Sends a datagram to `127.0.0.1:port` (IPv4 socket) or `[::1]:port` (IPv6 socket).
    func send(_ bytes: [UInt8], toPort port: Int) {
        if family == AF_INET6 {
            var sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            sin6.sin6_addr = in6addr_loopback
            sin6.sin6_port = UInt16(port).bigEndian
            send(bytes, to: &sin6)
            return
        }
        var sin = Self.ipv4(0x7F00_0001, port: port)
        send(bytes, to: &sin)
    }

    func send<A>(_ bytes: [UInt8], to address: inout A) {
        let size = socklen_t(MemoryLayout<A>.size)
        let sent: Int = withUnsafePointer(to: &address) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bytes.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, 0, sa, size) }
            }
        }
        precondition(sent == bytes.count, "sendto")
    }

    /// Blocking receive (call from its own thread): bytes and the source port; `nil` after the guard.
    func receive() -> (bytes: [UInt8], port: Int)? {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var from = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let n: Int = buffer.withUnsafeMutableBytes { raw in
            withUnsafeMutablePointer(to: &from) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, raw.baseAddress, raw.count, 0, $0, &length) }
            }
        }
        guard n >= 0 else { return nil }
        var copy = from
        let port: Int
        if Int32(from.ss_family) == AF_INET6 {
            port = withUnsafeBytes(of: &copy) { Int(UInt16(bigEndian: $0.load(as: sockaddr_in6.self).sin6_port)) }
        } else {
            port = withUnsafeBytes(of: &copy) { Int(UInt16(bigEndian: $0.load(as: sockaddr_in.self).sin_port)) }
        }
        return (Array(buffer[0..<n]), port)
    }
}
