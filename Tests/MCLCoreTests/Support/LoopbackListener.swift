import Darwin
import Foundation

/// A POSIX listener on `127.0.0.1:0` for server stand-ins (`FakeLineServer`, `FakeHttpServer`): accepts
/// on its own thread and serves each connection on another dedicated thread. Waits in `poll` at 50 ms so that
/// `stop()` took effect without relying on `close` unblocking `accept`/`recv`.
final class LoopbackListener: @unchecked Sendable {

    let port: Int
    private let fd: Int32
    private let lock = NSLock()
    private var stopped = false
    private var connections: [Int32] = []
    private var acceptThreadDone = false

    /// `handler(fd, index)` runs on its own thread; after it returns the connection is closed.
    init(name: String, handler: @escaping @Sendable (Connection) -> Void) throws {
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_addr.s_addr = in_addr_t(UInt32(0x7F00_0001).bigEndian)
        sin.sin_port = 0
        let bound: Int32 = withUnsafePointer(to: &sin) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            let code = errno
            _ = Darwin.close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        self.fd = fd
        self.port = Int(UInt16(bigEndian: actual.sin_port))
        let thread = Thread { [self] in acceptLoop(name: name, handler: handler) }
        thread.name = name + "-accept"
        thread.start()
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Stops accepting and closes all connections (from the stand-in's side).
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if stopped { return }
        stopped = true
        for c in connections {
            _ = shutdown(c, SHUT_RDWR)
        }
    }

    private func acceptLoop(name: String, handler: @escaping @Sendable (Connection) -> Void) {
        var index = 0
        while !isStopped {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&pfd, 1, 50) <= 0 { continue }
            let c: Int32 = accept(fd, nil, nil)
            if c < 0 { continue }
            var one: Int32 = 1
            _ = setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            lock.lock()
            if stopped {
                lock.unlock()
                _ = Darwin.close(c)
                break
            }
            connections.append(c)
            lock.unlock()
            let connection = Connection(fd: c, index: index, listener: self)
            index += 1
            let thread = Thread {
                handler(connection)
                connection.close()
            }
            thread.name = name + "-conn"
            thread.start()
        }
        _ = Darwin.close(fd)
    }

    fileprivate func forget(_ c: Int32) {
        lock.lock()
        connections.removeAll { $0 == c }
        lock.unlock()
    }

    /// One accepted connection (used only by its thread).
    final class Connection: @unchecked Sendable {
        let index: Int
        private let fd: Int32
        private weak var listener: LoopbackListener?
        private var closed = false

        fileprivate init(fd: Int32, index: Int, listener: LoopbackListener) {
            self.fd = fd
            self.index = index
            self.listener = listener
        }

        /// Reads what arrived (at most `max` bytes); `nil` = end of stream or the stand-in stopped.
        func receive(max: Int = 4_096) -> [UInt8]? {
            while !closed && !(listener?.isStopped ?? true) {
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                if poll(&pfd, 1, 50) <= 0 { continue }
                var chunk = [UInt8](repeating: 0, count: max)
                let n: Int = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
                if n > 0 { return Array(chunk[0..<n]) }
                if n == 0 { return nil }
                if errno == EINTR || errno == EAGAIN { continue }
                return nil
            }
            return nil
        }

        /// Sends the bytes with one `send` (until all have gone out); ignores errors (the client may already be gone).
        func send(_ bytes: [UInt8]) {
            var offset = 0
            while offset < bytes.count && !closed {
                let n: Int = bytes[offset...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
                if n <= 0 {
                    if n < 0 && errno == EINTR { continue }
                    return
                }
                offset += n
            }
        }

        /// Closes the connection with RST (`SO_LINGER` 0) instead of FIN.
        func reset() {
            var linger = Darwin.linger(l_onoff: 1, l_linger: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_LINGER, &linger, socklen_t(MemoryLayout<Darwin.linger>.size))
            close()
        }

        func close() {
            if closed { return }
            closed = true
            listener?.forget(fd)
            _ = Darwin.close(fd)
        }
    }
}
