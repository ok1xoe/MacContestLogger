import Darwin
import Foundation
import Testing
@testable import MCLCore

/// A scriptable MQTT 5 broker stand-in on `127.0.0.1:0` (without Mosquitto, runs on CI too): accepts on its own
/// thread, reads each connection on another dedicated thread (`poll` at 50 ms so that `stop` takes effect). All received
/// packets are recorded (with the connection number and bytes) and it replies automatically: CONNECT → `connectReply`, SUBSCRIBE →
/// SUBACK with the granted QoS, PUBLISH QoS 1 → PUBACK per `pubackFor` (or swallow), PINGREQ → PINGRESP
/// (`answerPings`). `send`/`sendRaw` sends the client anything, `drop` brings down the connection (`shutdown` → the client sees EOF).
/// A frame from the client that cannot be decoded is recorded and `stop()` (called in the test via `defer`) turns it into
/// a test failure — a broken client packet must not get lost as a "missing packet".
final class FakeBroker: @unchecked Sendable {

    enum ConnectReply: Sendable {
        case accept(MqttConnack)
        /// Close the connection without CONNACK (a refused attempt).
        case close
        /// Do not reply at all.
        case silent
    }

    enum PubackReply: Sendable {
        case ack(UInt8)
        case swallow
    }

    struct Received: Sendable {
        let connection: Int
        let packet: MqttPacket
        let bytes: [UInt8]
    }

    let port: Int
    private let listenFd: Int32
    private let lock = NSLock()
    private var stopped = false
    private var fds: [Int: Int32] = [:]
    private var log: [Received] = []
    private var undecodable: [[UInt8]] = []
    private var accepts: [UInt64] = []
    private var connectReplyRule: @Sendable (Int) -> ConnectReply
    private var pubackRule: @Sendable (MqttPublish, Int) -> PubackReply = { _, _ in .ack(0) }
    private var pings = true
    private var hook: (@Sendable (FakeBroker, Int, MqttPacket) -> Void)?

    static let ok = MqttConnack(sessionPresent: false, reasonCode: 0)

    init(connack: MqttConnack = FakeBroker.ok) throws {
        connectReplyRule = { _ in .accept(connack) }
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var sin = MqttTestProxy.loopback(port: 0)
        let bound: Int32 = withUnsafePointer(to: &sin) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
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
        thread.name = "fake-broker-accept"
        thread.start()
    }

    // MARK: - Script

    /// A reply to CONNECT by connection number (0, 1, …).
    func onConnect(_ rule: @escaping @Sendable (Int) -> ConnectReply) {
        lock.withLock { connectReplyRule = rule }
    }

    /// A reply to PUBLISH QoS 1 (message, connection number).
    func onPublish(_ rule: @escaping @Sendable (MqttPublish, Int) -> PubackReply) {
        lock.withLock { pubackRule = rule }
    }

    /// Called after the automatic reply to every packet (on the connection thread).
    func onPacket(_ body: @escaping @Sendable (FakeBroker, Int, MqttPacket) -> Void) {
        lock.withLock { hook = body }
    }

    var answerPings: Bool {
        get { lock.withLock { pings } }
        set { lock.withLock { pings = newValue } }
    }

    // MARK: - Recording

    var received: [Received] {
        lock.withLock { log }
    }

    func packets(connection: Int) -> [MqttPacket] {
        received.filter { $0.connection == connection }.map(\.packet)
    }

    var connectionCount: Int {
        lock.withLock { accepts.count }
    }

    /// Moments connections were accepted (monotonic ns).
    var acceptTimes: [UInt64] {
        lock.withLock { accepts }
    }

    // MARK: - Actions

    func send(_ packet: MqttPacket, connection: Int) {
        sendRaw((try? packet.encode()) ?? [], connection: connection)
    }

    /// Sends under a lock (the fd number cannot be reused in the meantime after the connection closes).
    func sendRaw(_ bytes: [UInt8], connection: Int) {
        lock.withLock {
            if let fd = fds[connection] {
                _ = Self.sendAll(bytes, to: fd)
            }
        }
    }

    /// Brings down the connection (the client gets EOF).
    func drop(connection: Int) {
        lock.withLock {
            if let fd = fds[connection] {
                _ = shutdown(fd, SHUT_RDWR)
            }
        }
    }

    func dropAll() {
        lock.withLock {
            for fd in fds.values {
                _ = shutdown(fd, SHUT_RDWR)
            }
        }
    }

    /// Stops the stand-in; undecodable frames from the client = a test failure.
    func stop(sourceLocation: SourceLocation = #_sourceLocation) {
        let bad: [[UInt8]] = lock.withLock {
            stopped = true
            return undecodable
        }
        dropAll()
        if !bad.isEmpty {
            Issue.record("FakeBroker: the client sent undecodable frames \(bad)", sourceLocation: sourceLocation)
        }
    }

    private var isStopped: Bool {
        lock.withLock { stopped }
    }

    // MARK: - Threads

    private func acceptLoop() {
        while !isStopped {
            var pfd = pollfd(fd: listenFd, events: Int16(POLLIN), revents: 0)
            if poll(&pfd, 1, 50) <= 0 { continue }
            let client: Int32 = accept(listenFd, nil, nil)
            if client < 0 { continue }
            var one: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let index: Int = lock.withLock {
                let i = accepts.count
                accepts.append(DispatchTime.now().uptimeNanoseconds)
                fds[i] = client
                return i
            }
            let thread = Thread { [self] in serve(client, index: index) }
            thread.name = "fake-broker-conn"
            thread.start()
        }
        _ = Darwin.close(listenFd)
    }

    private func serve(_ fd: Int32, index: Int) {
        var frames = MqttFrameReader()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        loop: while true {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready: Int32 = poll(&pfd, 1, 50)
            if ready == 0 {
                if isStopped { break }
                continue
            }
            let n: Int = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 {
                if n < 0 && errno == EINTR { continue }
                break
            }
            frames.append(Array(chunk[0..<n]))
            while true {
                guard let frame = try? frames.nextFrame() else { break }
                guard let packet = try? MqttPacket.decode(frame) else {
                    lock.withLock { undecodable.append(frame) }
                    continue
                }
                lock.withLock { log.append(Received(connection: index, packet: packet, bytes: frame)) }
                if !reply(to: packet, fd: fd, index: index) {
                    break loop
                }
                let after: (@Sendable (FakeBroker, Int, MqttPacket) -> Void)? = lock.withLock { hook }
                after?(self, index, packet)
            }
        }
        lock.withLock {
            _ = shutdown(fd, SHUT_RDWR)
            fds.removeValue(forKey: index)
        }
        _ = Darwin.close(fd)
    }

    /// An automatic reply; `false` = close the connection.
    private func reply(to packet: MqttPacket, fd: Int32, index: Int) -> Bool {
        switch packet {
        case .connect:
            let rule: @Sendable (Int) -> ConnectReply = lock.withLock { connectReplyRule }
            switch rule(index) {
            case .accept(let ack):
                _ = Self.sendAll((try? MqttPacket.connack(ack).encode()) ?? [], to: fd)
            case .close:
                return false
            case .silent:
                break
            }
        case .subscribe(let s):
            let codes: [UInt8] = s.subscriptions.map(\.qos)
            let ack = MqttPacket.suback(MqttSuback(packetId: s.packetId, reasonCodes: codes))
            _ = Self.sendAll((try? ack.encode()) ?? [], to: fd)
        case .publish(let p):
            guard p.qos == 1, let id = p.packetId else { break }
            let rule: @Sendable (MqttPublish, Int) -> PubackReply = lock.withLock { pubackRule }
            if case .ack(let reason) = rule(p, index) {
                _ = Self.sendAll((try? MqttPacket.puback(MqttPuback(packetId: id, reasonCode: reason)).encode()) ?? [], to: fd)
            }
        case .pingreq:
            if answerPings {
                _ = Self.sendAll([0xD0, 0x00], to: fd)
            }
        default:
            break
        }
        return true
    }

    private static func sendAll(_ bytes: [UInt8], to fd: Int32) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let n: Int = bytes[offset...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return false }
            offset += n
        }
        return true
    }
}

    /// A thread-safe record for MQTT tests.
final class MqttRecorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func add(_ item: T) {
        lock.withLock { items.append(item) }
    }

    var all: [T] {
        lock.withLock { items }
    }
}
