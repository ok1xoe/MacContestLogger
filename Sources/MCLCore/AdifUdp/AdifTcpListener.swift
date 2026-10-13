import Darwin
import Foundation

/// JTDX's „External logbook" over TCP (N1MM: port 52001): JTDX connects and writes the logged QSO as ADIF. Every
/// record up to `<eor>` (any case) that looks like ADIF (`AdifUdpFilter`) goes to the handler; the rest is dropped.
/// One accept/read thread (`adif-tcp-listener`), IPv4 bind; `close` ends it and the open connection. A Swift-only
/// addition (v1.1.1 receives JTDX only over WSJT-X's UDP).
public final class AdifTcpListener: @unchecked Sendable {

    /// A record larger than this is dropped (a stream without `<eor>` must not grow memory).
    static let maxRecordBytes = 64 * 1024

    private let lock = NSLock()
    private var socket: Int32
    private var client: Int32 = -1
    private var closed = false
    private var readerDone = false
    private var readerStarted = false
    private var doneWaiters: [CheckedContinuation<Void, Never>] = []
    private let handler: @Sendable (String) -> Void
    public let boundPort: Int

    /// Binds `host:port` (IPv4 literal or `localhost`; port 0 = an ephemeral one).
    public init(bindHost: String, bindPort: Int, handler: @escaping @Sendable (String) -> Void) throws {
        self.handler = handler
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(bindPort).bigEndian
        let host: String = bindHost == "localhost" ? "127.0.0.1" : bindHost
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            Darwin.close(fd)
            throw POSIXError(.EINVAL)
        }
        let bound: Int32 = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        socket = fd
        boundPort = Int(UInt16(bigEndian: actual.sin_port))
    }

    public func start() {
        lock.withLock { readerStarted = true }
        let thread = Thread { [self] in run() }
        thread.name = "adif-tcp-listener"
        thread.start()
    }

    public func close() {
        let (listening, connection): (Int32, Int32) = lock.withLock {
            guard !closed else { return (-1, -1) }
            closed = true
            return (socket, client)
        }
        if connection >= 0 {
            shutdown(connection, SHUT_RDWR)
        }
        if listening >= 0 {
            // A blocked `accept` is woken by a connection of our own (closing the descriptor does not wake it).
            wake()
            shutdown(listening, SHUT_RDWR)
            Darwin.close(listening)
        }
        if !lock.withLock({ readerStarted }) {
            finish()
        }
    }

    public func waitUntilStopped() async {
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

    private func wake() {
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(boundPort).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        Darwin.close(fd)
    }

    private func run() {
        defer { finish() }
        while true {
            let listening: Int32 = lock.withLock { closed ? -1 : socket }
            guard listening >= 0 else { return }
            let connection: Int32 = accept(listening, nil, nil)
            guard connection >= 0 else { return }
            var on: Int32 = 1
            _ = setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let accepted: Bool = lock.withLock {
                guard !closed else { return false }
                client = connection
                return true
            }
            guard accepted else {
                Darwin.close(connection)
                return
            }
            serve(connection)
            lock.withLock { client = -1 }
            Darwin.close(connection)
        }
    }

    /// Reads records until the peer closes the connection.
    private func serve(_ connection: Int32) {
        var pending: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count: Int = read(connection, &buffer, buffer.count)
            if count <= 0 {
                return
            }
            pending.append(contentsOf: buffer[0..<count])
            while let end = Self.recordEnd(pending) {
                let record: [UInt8] = Array(pending[0..<end])
                pending.removeFirst(end)
                if let adif = AdifUdpFilter.adif(from: record) {
                    handler(adif)
                }
            }
            if pending.count > Self.maxRecordBytes {
                pending.removeAll()
            }
        }
    }

    /// The end of the first record (just past `<eor>`, ASCII case-insensitive), `nil` when it is not complete.
    static func recordEnd(_ bytes: [UInt8]) -> Int? {
        let tag: [UInt8] = Array("<eor>".utf8)
        guard bytes.count >= tag.count else { return nil }
        for start in 0...(bytes.count - tag.count) {
            var match = true
            for offset in 0..<tag.count where bytes[start + offset] | 0x20 != tag[offset] | 0x20 {
                match = false
                break
            }
            if match {
                return start + tag.count
            }
        }
        return nil
    }

    private func finish() {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            readerDone = true
            let all = doneWaiters
            doneWaiters = []
            return all
        }
        for waiter in waiters {
            waiter.resume()
        }
    }
}
