import Darwin
import Foundation
@testable import MCLCore

/// A byte proxy for MQTT on `127.0.0.1:0` in front of a local broker (like the Java `MqttTranscript`):
/// each connection on two dedicated threads, packets of both directions are recorded whole. `drop()` brings down all
/// live connections (shutdown of both sockets — the client sees an outage), `swallowFromClient` discards packets from the client
/// (recorded as swallowed), so that a QoS 1 publish stays unacknowledged.
final class MqttTestProxy: @unchecked Sendable {

    struct Captured: Sendable {
        let connection: Int
        let fromClient: Bool
        let bytes: [UInt8]
        let swallowed: Bool
    }

    private final class Pair: @unchecked Sendable {
        let clientFd: Int32
        let upstreamFd: Int32
        var finished = 0
        var closed = false

        init(clientFd: Int32, upstreamFd: Int32) {
            self.clientFd = clientFd
            self.upstreamFd = upstreamFd
        }
    }

    let port: Int
    private let upstreamPort: Int
    private let listenFd: Int32
    private let lock = NSLock()
    private var stopped = false
    private var pairs: [Pair] = []
    private var log: [Captured] = []
    private var accepted = 0
    private var swallow = false

    init(upstreamPort: Int) throws {
        self.upstreamPort = upstreamPort
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var sin = Self.loopback(port: 0)
        let bound: Int32 = withUnsafePointer(to: &sin) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            _ = Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        listenFd = fd
        port = Int(UInt16(bigEndian: actual.sin_port))
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "mqtt-proxy-accept"
        thread.start()
    }

    static func loopback(port: Int) -> sockaddr_in {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = in_addr_t(UInt32(0x7F00_0001).bigEndian)
        sin.sin_port = in_port_t(UInt16(port).bigEndian)
        return sin
    }

    var swallowFromClient: Bool {
        get { lock.withLock { swallow } }
        set { lock.withLock { swallow = newValue } }
    }

    var captured: [Captured] {
        lock.withLock { log }
    }

    var connectionCount: Int {
        lock.withLock { accepted }
    }

    /// Packets of one connection and direction.
    func packets(connection: Int, fromClient: Bool) -> [[UInt8]] {
        captured.filter { $0.connection == connection && $0.fromClient == fromClient }.map(\.bytes)
    }

    /// Brings down all live connections.
    func drop() {
        lock.lock()
        defer { lock.unlock() }
        for pair in pairs where !pair.closed {
            _ = shutdown(pair.clientFd, SHUT_RDWR)
            _ = shutdown(pair.upstreamFd, SHUT_RDWR)
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        drop()
    }

    private var isStopped: Bool {
        lock.withLock { stopped }
    }

    private func acceptLoop() {
        while !isStopped {
            var pfd = pollfd(fd: listenFd, events: Int16(POLLIN), revents: 0)
            if poll(&pfd, 1, 50) <= 0 { continue }
            let client: Int32 = accept(listenFd, nil, nil)
            if client < 0 { continue }
            let upstream: Int32 = socket(AF_INET, SOCK_STREAM, 0)
            var sin = Self.loopback(port: upstreamPort)
            let rc: Int32 = withUnsafePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(upstream, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if rc != 0 {
                _ = Darwin.close(upstream)
                _ = Darwin.close(client)
                continue
            }
            var one: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            _ = setsockopt(upstream, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let pair = Pair(clientFd: client, upstreamFd: upstream)
            lock.lock()
            let index = accepted
            accepted += 1
            pairs.append(pair)
            lock.unlock()
            let up = Thread { [self] in pump(pair, index: index, fromClient: true) }
            up.name = "mqtt-proxy-c2b"
            up.start()
            let down = Thread { [self] in pump(pair, index: index, fromClient: false) }
            down.name = "mqtt-proxy-b2c"
            down.start()
        }
        _ = Darwin.close(listenFd)
    }

    private func pump(_ pair: Pair, index: Int, fromClient: Bool) {
        let from: Int32 = fromClient ? pair.clientFd : pair.upstreamFd
        let to: Int32 = fromClient ? pair.upstreamFd : pair.clientFd
        var frames = MqttFrameReader()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        loop: while true {
            var pfd = pollfd(fd: from, events: Int16(POLLIN), revents: 0)
            let ready: Int32 = poll(&pfd, 1, 50)
            if ready == 0 {
                if isStopped { break }
                continue
            }
            let n: Int = chunk.withUnsafeMutableBytes { recv(from, $0.baseAddress, $0.count, 0) }
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                break
            }
            frames.append(Array(chunk[0..<n]))
            while true {
                guard let frame = try? frames.nextFrame() else { break }
                let swallowed = fromClient && swallowFromClient
                lock.withLock {
                    log.append(Captured(connection: index, fromClient: fromClient, bytes: frame, swallowed: swallowed))
                }
                if swallowed { continue }
                if !Self.sendAll(frame, to: to) { break loop }
            }
        }
        lock.lock()
        defer { lock.unlock() }
        if !pair.closed {
            _ = shutdown(pair.clientFd, SHUT_RDWR)
            _ = shutdown(pair.upstreamFd, SHUT_RDWR)
        }
        pair.finished += 1
        if pair.finished == 2 {
            pair.closed = true
            _ = Darwin.close(pair.clientFd)
            _ = Darwin.close(pair.upstreamFd)
        }
    }

    private static func sendAll(_ bytes: [UInt8], to fd: Int32) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let n: Int = bytes[offset...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return false }
            offset += n
        }
        return true
    }
}

/// Waits (on its own thread, not in the pool) for a condition to be met; the bound is a guard against hangs, not a measure.
func waitUntil(_ what: String, limitSeconds: Double = 60, _ condition: () -> Bool) throws {
    let end = Date(timeIntervalSinceNow: limitSeconds)
    while !condition() {
        if Date() > end {
            throw WaitTimeout(what: what)
        }
        usleep(20_000)
    }
}

struct WaitTimeout: Error, CustomStringConvertible {
    let what: String
    var description: String { "gave up waiting for: " + what }
}
