import Darwin
import Foundation
import os

/// Actual UDP sending over **one long-lived socket** — port of `broadcast/UdpBroadcaster` (v1.1.1).
///
/// Like Java `new DatagramSocket()` (measured by `UdpIoProbe`, rows `UB.`): a dual-stack IPv6 socket on `::`
/// with a random port and **`SO_BROADCAST` enabled** (targets like `192.168.1.255` from the N1MM settings pass;
/// `UdpSender` does not have it and stays unchanged because of `N1mmRotorUdp`). The source port is the same for all
/// datagrams and both address families (`UB.sourcePortStable`). Each target is resolved again
/// (`InetAddress.getByName`, also `[::1]`), a port out of range → `IllegalArgumentException: Port out of range:<n>`,
/// port 0 → `Can't send to port 0`; **the error goes only to the log** `Broadcast na <host>:<port> selhal` and it
/// continues with the next target (`UB.errors`). After `close()` every send logs `Socket closed` (`UB.afterClose`).
///
/// Blocking (DNS) — call from your own thread, not from the shared pool.
public final class UdpBroadcaster: Broadcaster, @unchecked Sendable {

    private static let log = Logger(subsystem: "cz.ok1xoe.maccontestlogger", category: "UdpBroadcaster")

    private let lock = NSLock()
    private let fd: Int32
    private var closed = false
    private let failureSink: (@Sendable (String) -> Void)?

    public convenience init() throws {
        try self.init(failureSink: nil)
    }

    /// `failureSink` receives the text that would go to the log (tests).
    init(failureSink: (@Sendable (String) -> Void)?) throws(JavaSocketError) {
        let fd: Int32 = socket(AF_INET6, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw JavaSocketError.datagramFailure(errno)
        }
        // A subprocess (e.g. `rigctld` from CAT) does not inherit the socket (like the JDK and `LineSocket`).
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var zero: Int32 = 0
        var one: Int32 = 1
        var sendBuffer: Int32 = 65_535
        let intSize = socklen_t(MemoryLayout<Int32>.size)
        _ = setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &zero, intSize)
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, intSize)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sendBuffer, intSize)
        self.fd = fd
        self.failureSink = failureSink
    }

    deinit {
        close()
    }

    public func send(_ xml: String, _ targets: [Target]) {
        send(Array(xml.utf8), targets)
    }

    public func send(_ data: [UInt8], _ targets: [Target]) {
        for target in targets {
            do {
                try sendOne(data, target)
            } catch {
                report(target, error)
            }
        }
    }

    private func sendOne(_ data: [UInt8], _ target: Target) throws {
        let address: JavaInetAddress = try JavaInetAddress.byName(target.host)
        let port = Int(target.port)
        guard port >= 0 && port <= 65_535 else {
            throw JavaIllegalArgumentError(message: "Port out of range:" + String(port))
        }
        lock.lock()
        defer { lock.unlock() }
        if closed {
            throw JavaSocketError.socketClosed
        }
        try UdpReceiver.send(fd: fd, data, to: address, port: port)
    }

    private func report(_ target: Target, _ error: any Error) {
        let cause: String
        if let e = error as? JavaIllegalArgumentError {
            cause = "java.lang.IllegalArgumentException: " + e.message
        } else {
            cause = String(describing: error)
        }
        let text = "Broadcast na \(target.host):\(target.port) selhal | \(cause)"
        if let failureSink {
            failureSink(text)
        } else {
            Self.log.warning("\(text, privacy: .public)")
        }
    }

    /// Value of the socket's `SO_BROADCAST` (tests).
    var broadcastEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        var value: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(fd, SOL_SOCKET, SO_BROADCAST, &value, &size)
        return value != 0
    }

    /// Does the socket have `FD_CLOEXEC` (tests)?
    var closeOnExec: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed && fcntl(fd, F_GETFD) & FD_CLOEXEC != 0
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if closed { return }
        closed = true
        _ = Darwin.close(fd)
    }
}
