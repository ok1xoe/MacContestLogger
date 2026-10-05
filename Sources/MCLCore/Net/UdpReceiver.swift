import Darwin
import Foundation

/// Listener UDP socket (Java `DatagramSocket`/`MulticastSocket` from `WsjtxListener`, `AdifUdpListener`,
/// `N1mmListener`): receives on **its own thread**, replies from the **same socket** (a WSJT-X Reply must go out
/// from the listener's source port) and `close` from another thread reliably ends the read loop.
///
/// Like the JDK, the socket is **dual-stack IPv6** (`IPV6_V6ONLY=0`, measured `UdpIoProbe`): a bind to an IPv4 address
/// goes through `::ffff:a.b.c.d`, `0.0.0.0` as `::` (receives IPv4 and IPv6), `SO_BROADCAST` on
/// (`BIND.*`: `broadcast=true`), `SO_SNDBUF` 65 535 (the JDK on macOS enlarges it for 65 507 B datagrams).
/// Unicast **without** `SO_REUSEADDR` — a second listener on the same port gets `BindException: Address already
/// in use` (`BIND.inUse`). Multicast (`MulticastSocket(port)` + `joinGroup`): `SO_REUSEADDR` and
/// `SO_REUSEPORT` (`N1MM.mcastOpts`), bind to wildcard `::`, group via `IPV6_JOIN_GROUP` (an IPv4 group
/// as a mapped address; `IP_ADD_MEMBERSHIP` on an IPv6 socket is rejected by macOS with `EINVAL`) on the interface
/// `DefaultMulticastInterface`.
///
/// Shutdown: `close()` sets a flag and wakes the reader thread through a pipe (the read waits in `poll` on the socket
/// and the pipe, without periodic wake-ups); the reader thread closes the socket once it is running — so the descriptor cannot
/// be reassigned under `recvfrom`. Without a running read, `close()` closes it directly.
final class UdpReceiver: @unchecked Sendable {

    /// Datagram (bytes, sender) — called synchronously on the reader thread.
    typealias DatagramHandler = @Sendable ([UInt8], UdpEndpoint) -> Void
    /// `recvfrom` error (Java logs it and keeps reading).
    typealias ErrorHandler = @Sendable (JavaSocketError) -> Void

    private let lock = NSLock()
    private let fd: Int32
    private let wakeRead: Int32
    private let wakeWrite: Int32
    private let port: Int
    private var closed = false
    private var readerRunning = false
    private var readerStarted = false
    private var readerDone = false
    private var doneWaiters: [CheckedContinuation<Void, Never>] = []

    /// Java `InetSocketAddress(port)`/`InetSocketAddress(addr, port)`: `IllegalArgumentException: port out of
    /// range:<n>` (`BIND.port70000`, `BIND.portNeg`).
    static func checkPort(_ port: Int) throws(JavaIllegalArgumentError) {
        guard port >= 0 && port <= 65_535 else {
            throw JavaIllegalArgumentError(message: "port out of range:" + String(port))
        }
    }

    /// Java `new DatagramSocket(new InetSocketAddress(host, port))`: the port is checked before the name,
    /// an unresolvable name (even a bad IPv6 literal) → `SocketException: Unresolved address`
    /// (`BIND.unresolved`), `""` → loopback (`BIND.empty`). Blocking (DNS).
    static func unicast(host: String, port: Int) throws -> UdpReceiver {
        try checkPort(port)
        let address: JavaInetAddress
        do {
            address = try JavaInetAddress.byName(host)
        } catch {
            throw JavaSocketError.unresolvedAddress
        }
        return try UdpReceiver(bind: address, port: port, multicast: false)
    }

    /// Java `new DatagramSocket(new InetSocketAddress(address, port))` over a resolved address.
    static func unicast(address: JavaInetAddress, port: Int) throws -> UdpReceiver {
        try checkPort(port)
        return try UdpReceiver(bind: address, port: port, multicast: false)
    }

    /// Java `new MulticastSocket(port)` + `joinGroup(group)`. `interfaceIndex` only for tests (loopback `lo0`);
    /// the default is the Java default interface.
    static func multicast(group: JavaInetAddress, port: Int,
                          interfaceIndex: UInt32 = DefaultMulticastInterface.index) throws -> UdpReceiver {
        try checkPort(port)
        let receiver = try UdpReceiver(bind: nil, port: port, multicast: true)
        do {
            try receiver.join(group, interfaceIndex: interfaceIndex)
        } catch {
            receiver.close()
            throw error
        }
        return receiver
    }

    private init(bind address: JavaInetAddress?, port: Int, multicast: Bool) throws(JavaSocketError) {
        let fd: Int32 = socket(AF_INET6, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw JavaSocketError.datagramFailure(errno)
        }
        // Like the JDK (and `LineSocket`): a child process (e.g. `rigctld` from CAT) does not inherit the socket, the port is freed after `close`.
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var zero: Int32 = 0
        var one: Int32 = 1
        var sendBuffer: Int32 = 65_535
        let intSize = socklen_t(MemoryLayout<Int32>.size)
        _ = setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &zero, intSize)
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, intSize)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sendBuffer, intSize)
        if multicast {
            _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, intSize)
            _ = setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, intSize)
        }
        var sin6: sockaddr_in6
        if let address {
            sin6 = address.dualStackSockAddr(port: UInt16(port))
        } else {
            sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            sin6.sin6_port = UInt16(port).bigEndian
        }
        let bound: Int32 = withUnsafePointer(to: &sin6) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        if bound != 0 {
            let code = errno
            _ = Darwin.close(fd)
            throw JavaSocketError.datagramFailure(code)
        }
        var pipeFds: [Int32] = [-1, -1]
        guard pipe(&pipeFds) == 0 else {
            let code = errno
            _ = Darwin.close(fd)
            throw JavaSocketError.datagramFailure(code)
        }
        _ = fcntl(pipeFds[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(pipeFds[1], F_SETFD, FD_CLOEXEC)
        var actual = sockaddr_in6()
        var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        _ = withUnsafeMutablePointer(to: &actual) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        self.fd = fd
        self.wakeRead = pipeFds[0]
        self.wakeWrite = pipeFds[1]
        self.port = Int(UInt16(bigEndian: actual.sin6_port))
    }

    deinit {
        close()
    }

    private func join(_ group: JavaInetAddress, interfaceIndex: UInt32) throws(JavaSocketError) {
        var request = ipv6_mreq()
        request.ipv6mr_multiaddr = group.dualStackSockAddr(port: 0).sin6_addr
        request.ipv6mr_interface = interfaceIndex
        let rc: Int32 = setsockopt(fd, IPPROTO_IPV6, IPV6_JOIN_GROUP, &request, socklen_t(MemoryLayout<ipv6_mreq>.size))
        if rc != 0 {
            throw JavaSocketError.datagramFailure(errno)
        }
    }

    /// Java `getLocalPort()`: `-1` after closing (`WSJ.fromAndAfterClose`).
    var boundPort: Int {
        lock.lock()
        defer { lock.unlock() }
        return closed ? -1 : port
    }

    /// Integer socket option (tests: `SO_REUSEADDR`, `SO_REUSEPORT`, `SO_BROADCAST`); `nil` after closing.
    func intOption(_ level: Int32, _ name: Int32) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        if closed { return nil }
        var value: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, level, name, &value, &size) == 0 else { return nil }
        return value
    }

    /// Do the socket and the wake-up pipe have `FD_CLOEXEC` (tests)? `false` after closing.
    var closeOnExec: Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        return [fd, wakeRead, wakeWrite].allSatisfy { fcntl($0, F_GETFD) & FD_CLOEXEC != 0 }
    }

    /// Java `getLocalAddress()` (mapped IPv4 as IPv4, `::` for wildcard); `nil` after closing.
    var localAddress: JavaInetAddress? {
        lock.lock()
        defer { lock.unlock() }
        if closed { return nil }
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let rc: Int32 = withUnsafeMutablePointer(to: &storage) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return rc == 0 ? JavaInetAddress(socketAddress: storage) : nil
    }

    /// Starts reading on its own thread `name`. Does nothing after `close()` or the second time.
    func start(name: String, onDatagram: @escaping DatagramHandler, onError: @escaping ErrorHandler) {
        lock.lock()
        if closed || readerStarted {
            lock.unlock()
            return
        }
        readerStarted = true
        readerRunning = true
        lock.unlock()
        let thread = Thread { [self] in
            readLoop(onDatagram: onDatagram, onError: onError)
        }
        thread.name = name
        thread.start()
    }

    private func readLoop(onDatagram: DatagramHandler, onError: ErrorHandler) {
        var buffer = [UInt8](repeating: 0, count: 65_535)
        while true {
            var fds: [pollfd] = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                                 pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0)]
            let ready: Int32 = poll(&fds, 2, -1)
            if isClosed {
                break
            }
            if ready <= 0 || fds[0].revents == 0 {
                continue
            }
            var from = sockaddr_storage()
            var fromLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count: Int = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &from) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, raw.baseAddress, raw.count, MSG_DONTWAIT, $0, &fromLength)
                    }
                }
            }
            if count < 0 {
                let code = errno
                if code == EAGAIN || code == EINTR { continue }
                if !isClosed { onError(JavaSocketError.datagramFailure(code)) }
                continue
            }
            if isClosed {
                break
            }
            let address = JavaInetAddress(socketAddress: from)
            let sender = UdpEndpoint(address: address, port: Self.port(of: from))
            onDatagram(Array(buffer[0..<count]), sender)
        }
        finishReader()
    }

    private static func port(of storage: sockaddr_storage) -> Int {
        var copy = storage
        if Int32(storage.ss_family) == AF_INET6 {
            return withUnsafeBytes(of: &copy) { Int(UInt16(bigEndian: $0.load(as: sockaddr_in6.self).sin6_port)) }
        }
        return withUnsafeBytes(of: &copy) { Int(UInt16(bigEndian: $0.load(as: sockaddr_in.self).sin_port)) }
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    private func finishReader() {
        lock.lock()
        readerRunning = false
        readerDone = true
        closeDescriptors()
        let waiters = doneWaiters
        doneWaiters = []
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Called under the lock.
    private func closeDescriptors() {
        _ = Darwin.close(fd)
        _ = Darwin.close(wakeRead)
        _ = Darwin.close(wakeWrite)
    }

    /// Java `socket.send(new DatagramPacket(data, data.length, to))`: after closing `SocketException: Socket
    /// closed`, port 0 → `Can't send to port 0`, otherwise a `sendto` error (`WSJ.send*`).
    func send(_ data: [UInt8], to target: UdpEndpoint) throws(JavaSocketError) {
        lock.lock()
        defer { lock.unlock() }
        if closed {
            throw JavaSocketError.socketClosed
        }
        try Self.send(fd: fd, data, to: target.address, port: target.port)
    }

    /// `sendto` from a dual-stack socket (shared with `UdpBroadcaster`).
    static func send(fd: Int32, _ data: [UInt8], to address: JavaInetAddress, port: Int) throws(JavaSocketError) {
        if port == 0 {
            throw JavaSocketError(kind: .other, javaClass: "java.net.SocketException", message: "Can't send to port 0")
        }
        var sin6: sockaddr_in6 = address.dualStackSockAddr(port: UInt16(port))
        let sent: Int = withUnsafePointer(to: &sin6) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                data.withUnsafeBytes { raw in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
        if sent < 0 {
            throw JavaSocketError.datagramFailure(errno)
        }
    }

    /// Java `close()`: idempotent, from any thread; the read loop ends without further delivery.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        if closed { return }
        closed = true
        if readerRunning {
            var byte: UInt8 = 1
            _ = write(wakeWrite, &byte, 1)
        } else {
            closeDescriptors()
        }
    }

    /// Waits until the reader thread ends (tests; immediately without a running read).
    func waitUntilReaderExits() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if readerDone || !readerStarted {
                lock.unlock()
                continuation.resume()
                return
            }
            doneWaiters.append(continuation)
            lock.unlock()
        }
    }
}
