import Darwin
import Foundation
import MCLCore
import os
import Testing
@testable import MCLAppModel

/// Ports no test may ever send to or bind: the user's own software lives there (N1MM 12060/12061, WSJT-X 2237, the
/// ADIF feed 2333, `rigctld` 4532/4533, MQTT 1883/8883).
let forbiddenTestPorts: Set<Int> = [12060, 12061, 2237, 2333, 4532, 4533, 1883, 8883]

/// A UDP socket on `127.0.0.1` with an OS-assigned port (never a well-known one): collects what arrives on its own
/// reader thread and can send from the same socket, so the peer's reply comes back to it. Every wait is bounded.
final class UdpSink: @unchecked Sendable {
    private let fd: Int32
    let port: Int
    private let lock = NSLock()
    private var datagrams: [[UInt8]] = []
    private var stopped = false
    private var readerDone = false

    init() {
        let descriptor: Int32 = socket(AF_INET, SOCK_DGRAM, 0)
        precondition(descriptor >= 0, "socket")
        var timeout = timeval(tv_sec: 0, tv_usec: 50_000)
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)
        address.sin_port = 0
        let bound: Int32 = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        precondition(bound == 0, "bind")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        let assigned = Int(UInt16(bigEndian: address.sin_port))
        precondition(!forbiddenTestPorts.contains(assigned), "ephemeral port collides with a well-known one")
        fd = descriptor
        port = assigned
        let thread = Thread { [self] in readLoop() }
        thread.name = "test-udp-sink"
        thread.start()
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            lock.lock()
            let done: Bool = stopped
            lock.unlock()
            if done { break }
            let count: Int = recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                lock.lock()
                datagrams.append(Array(buffer[0..<count]))
                lock.unlock()
            }
        }
        lock.lock()
        readerDone = true
        lock.unlock()
        _ = Darwin.close(fd)
    }

    /// Stops the reader and closes the socket (after its last receive timeout).
    func close() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    deinit {
        close()
    }

    /// What arrived so far, as texts.
    var texts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return datagrams.map { String(decoding: $0, as: UTF8.self) }
    }

    var bytes: [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        return datagrams
    }

    /// Sends from this socket to `127.0.0.1:<port>` (never a forbidden port).
    func send(_ data: [UInt8], toPort target: Int) {
        precondition(!forbiddenTestPorts.contains(target), "never send to a well-known port")
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)
        address.sin_port = UInt16(target).bigEndian
        _ = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                data.withUnsafeBytes { raw in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    func send(_ text: String, toPort target: Int) {
        send(Array(text.utf8), toPort: target)
    }

    /// Waits (letting the main queue run) until `count` datagrams contain `fragment`; the bound only ends a failing test.
    @MainActor
    func waitFor(_ fragment: String, count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async {
        await eventually("\(count) datagram(s) with \(fragment)", {
            self.texts.filter { $0.contains(fragment) }.count >= count
        }, sourceLocation: sourceLocation)
    }

    func count(containing fragment: String) -> Int {
        texts.filter { $0.contains(fragment) }.count
    }
}

/// A broadcaster over the real `UdpBroadcaster` that refuses (a crash, never a send) any target but `127.0.0.1` with
/// a non-well-known port, and counts its creations.
final class LoopbackBroadcaster: Broadcaster, @unchecked Sendable {
    private let inner: UdpBroadcaster

    init() throws {
        inner = try UdpBroadcaster()
    }

    private func check(_ targets: [Target]) {
        for target in targets {
            precondition(target.host == "127.0.0.1", "tests send to 127.0.0.1 only")
            precondition(!forbiddenTestPorts.contains(Int(target.port)), "tests never send to a well-known port")
        }
    }

    func send(_ xml: String, _ targets: [Target]) {
        check(targets)
        inner.send(xml, targets)
    }

    func send(_ data: [UInt8], _ targets: [Target]) {
        check(targets)
        inner.send(data, targets)
    }

    func close() {
        inner.close()
    }
}

/// Counts what the integrations ask the UDP ports for.
final class UdpFactoryCounts: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (listeners: 0, broadcasters: 0))

    var listeners: Int { state.withLock { $0.listeners } }
    var broadcasters: Int { state.withLock { $0.broadcasters } }

    func listener() { state.withLock { $0.listeners += 1 } }
    func broadcaster() { state.withLock { $0.broadcasters += 1 } }
}

/// A receiver is only ever asked to bind loopback.
@Sendable func checkLoopbackHost(_ host: String) {
    precondition(host == "127.0.0.1", "tests bind 127.0.0.1 only")
}

/// UDP ports whose receivers bind `127.0.0.1:0` whatever the configured address says (the configured port is never
/// bound), and whose broadcaster sends to loopback only.
func loopbackUdpPorts(_ counts: UdpFactoryCounts = UdpFactoryCounts()) -> UdpPorts {
    return UdpPorts(
        makeWsjtxListener: { host, _, handler in
            checkLoopbackHost(host)
            counts.listener()
            return try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0, handler: handler)
        },
        makeN1mmListener: { host, _, handler in
            checkLoopbackHost(host)
            counts.listener()
            return try N1mmListener(bindHost: "127.0.0.1", bindPort: 0, handler: handler)
        },
        makeAdifListener: { host, _, handler in
            checkLoopbackHost(host)
            counts.listener()
            return try AdifUdpListener(bindHost: "127.0.0.1", bindPort: 0, handler: handler)
        },
        makeBroadcaster: {
            counts.broadcaster()
            return try LoopbackBroadcaster()
        })
}

/// WSJT-X packets the listener understands that the core does not encode.
enum WsjtxPackets {
    static func status(dialHz: Int64, mode: String, transmitting: Bool = false) -> [UInt8] {
        var out = WsjtxDataOutput()
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(WsjtxProtocol.schema)
        out.writeInt(WsjtxProtocol.status)
        WsjtxCodec.writeString(&out, "WSJT-X")
        out.writeLong(dialHz)
        WsjtxCodec.writeString(&out, mode)
        WsjtxCodec.writeString(&out, "")
        WsjtxCodec.writeString(&out, "")
        WsjtxCodec.writeString(&out, mode)
        out.writeBoolean(false)
        out.writeBoolean(transmitting)
        return out.bytes
    }

    static func clear() -> [UInt8] {
        var out = WsjtxDataOutput()
        out.writeInt(WsjtxProtocol.magic)
        out.writeInt(WsjtxProtocol.schema)
        out.writeInt(WsjtxProtocol.clear)
        WsjtxCodec.writeString(&out, "WSJT-X")
        return out.bytes
    }

    static func decode(_ message: String, deltaFrequency: Int32 = 1_000) -> [UInt8] {
        WsjtxMessages.encodeDecode(WsjtxMessages.Decode(
            id: "WSJT-X", isNew: true, timeMs: 12 * 3_600_000, snr: -10, deltaTime: 0.1,
            deltaFrequency: deltaFrequency, mode: "~", message: message, lowConfidence: false, offAir: false))
    }

    static func loggedAdif(_ record: String) -> [UInt8] {
        WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: record))
    }
}
