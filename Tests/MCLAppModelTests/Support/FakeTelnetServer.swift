import Foundation
@testable import MCLAppModel
import MCLCore

/// A fake DX cluster node on `127.0.0.1` with a port the system picks — never a real cluster, RBN or any other host.
/// It accepts connections, records every line a client sends (without `\r\n`) and pushes the lines a test gives it.
/// Accepting and serving run on the server's own threads, never in Swift's shared pool.
final class FakeTelnetServer: @unchecked Sendable {

    static let host = "127.0.0.1"

    let port: Int
    private let socket: Int32
    private let lock = NSLock()
    private var stopped = false
    private var clients: [Int32] = []
    private var received: [[String]] = []
    private var accepted = 0

    init() throws {
        precondition(Self.host == "127.0.0.1", "a fake cluster listens on the loopback only")
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr(Self.host)
        let bound: Int32 = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        socket = fd
        port = Int(UInt16(bigEndian: actual.sin_port))
        guardTestPort(port)
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "fake-telnet"
        thread.start()
    }

    deinit {
        stop()
    }

    /// A favourite of this server (never a real host name).
    func favorite(name: String, login: String = "", password: String = "",
                  parallel: Bool = false) -> DxClusterFavorite {
        var fav = DxClusterFavorite(name: name, host: Self.host, port: port, login: login, password: password)
        fav.parallel = parallel
        return fav
    }

    var connectionCount: Int {
        lock.withLock { accepted }
    }

    var openConnections: Int {
        lock.withLock { clients.count }
    }

    /// The lines connection `index` (from 0) sent.
    func lines(_ index: Int) -> [String] {
        lock.withLock { index < received.count ? received[index] : [] }
    }

    /// Sends `line` + `\r\n` to every open connection.
    func push(_ line: String) {
        let open: [Int32] = lock.withLock { clients }
        let bytes: [UInt8] = Array((line + "\r\n").utf8)
        for client in open {
            _ = bytes.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
        }
    }

    /// Closes every open connection (the node ends the session).
    func dropAll() {
        let open: [Int32] = lock.withLock { clients }
        for client in open {
            shutdown(client, SHUT_RDWR)
        }
    }

    func stop() {
        let toClose: [Int32]? = lock.withLock { () -> [Int32]? in
            if stopped { return nil }
            stopped = true
            return clients
        }
        guard let toClose else { return }
        for client in toClose {
            shutdown(client, SHUT_RDWR)
        }
        wake()
    }

    /// A connection that unblocks `accept`, so the accept thread sees `stopped` and closes the socket.
    private func wake() {
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr(Self.host)
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private func acceptLoop() {
        while true {
            let client: Int32 = accept(socket, nil, nil)
            let isStopped: Bool = lock.withLock { stopped }
            if client < 0 || isStopped {
                if client >= 0 {
                    close(client)
                }
                close(socket)
                return
            }
            var on: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let index: Int = lock.withLock {
                accepted += 1
                clients.append(client)
                received.append([])
                return received.count - 1
            }
            let thread = Thread { [self] in serve(client, index) }
            thread.name = "fake-telnet-client"
            thread.start()
        }
    }

    private func serve(_ client: Int32, _ index: Int) {
        defer {
            lock.withLock { clients.removeAll { $0 == client } }
            close(client)
        }
        var pending: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count: Int = read(client, &buffer, buffer.count)
            if count <= 0 {
                return
            }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: 10) {
                var line: [UInt8] = Array(pending[..<newline])
                if line.last == 13 {
                    line.removeLast()
                }
                pending.removeSubrange(...newline)
                let text = String(decoding: line, as: UTF8.self)
                lock.withLock { received[index].append(text) }
            }
        }
    }
}

/// The session's `delay` in tests: records every wait and returns at once, or — while held — blocks the session's
/// own thread until `release()` (never a thread of Swift's pool).
final class TestSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Int] = []
    private var holding = false
    private var gates: [DispatchSemaphore] = []

    var requests: [Int] {
        lock.withLock { waits }
    }

    /// From now on a wait blocks until `release()`.
    func hold() {
        lock.withLock { holding = true }
    }

    /// Ends every blocked wait and stops holding.
    func release() {
        let open: [DispatchSemaphore] = lock.withLock {
            holding = false
            let current = gates
            gates = []
            return current
        }
        for gate in open {
            gate.signal()
        }
    }

    var sleep: @Sendable (Int) -> Void {
        { [self] ms in
            let gate: DispatchSemaphore? = lock.withLock {
                waits.append(ms)
                guard holding else { return nil }
                let semaphore = DispatchSemaphore(value: 0)
                gates.append(semaphore)
                return semaphore
            }
            gate?.wait()
        }
    }
}
