import Foundation

/// A minimal HTTP/1.1 server on `127.0.0.1` (an ephemeral port) for download tests — never a real server. Each
/// request gets the response of its path (`404` otherwise) and `Connection: close`. Accepting and answering run on
/// the server's own thread, never in Swift's shared pool.
final class LocalHttpServer: @unchecked Sendable {

    struct Response: Sendable {
        var status: Int
        var body: [UInt8]

        init(status: Int = 200, body: String) {
            self.status = status
            self.body = Array(body.utf8)
        }
    }

    let port: Int
    private let socket: Int32
    private let routes: [String: Response]
    private let lock = NSLock()
    private var stopped = false
    private var paths: [String] = []

    init(routes: [String: Response]) throws {
        self.routes = routes
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
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
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "local-http-server"
        thread.start()
    }

    deinit {
        stop()
    }

    /// The request paths served so far.
    var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func url(_ path: String) -> String {
        "http://127.0.0.1:\(port)" + path
    }

    /// Stops accepting: a wake-up connection unblocks `accept`, the accept thread then closes the socket.
    func stop() {
        lock.lock()
        let wasStopped: Bool = stopped
        stopped = true
        lock.unlock()
        if wasStopped {
            return
        }
        let wake: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard wake >= 0 else { return }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(wake, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        close(wake)
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func acceptLoop() {
        while true {
            let client: Int32 = accept(socket, nil, nil)
            if client < 0 || isStopped {
                if client >= 0 {
                    close(client)
                }
                close(socket)
                return
            }
            Self.configure(client)
            serve(client)
            close(client)
        }
    }

    /// No SIGPIPE when a client closes early (`write` fails with EPIPE instead), and a read timeout so a client that
    /// never sends a request cannot hold the accept thread (and `stop()`'s wake-up connection) forever.
    private static func configure(_ client: Int32) {
        var on: Int32 = 1
        _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func serve(_ client: Int32) {
        var request: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !Self.headersComplete(request) {
            let count: Int = read(client, &buffer, buffer.count)
            if count <= 0 {
                return
            }
            request.append(contentsOf: buffer[0..<count])
        }
        let head = String(decoding: request, as: UTF8.self)
        let path: String = head.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        lock.lock()
        paths.append(path)
        lock.unlock()
        let response: Response = routes[path] ?? Response(status: 404, body: "no")
        var reply: String = "HTTP/1.1 \(response.status) X\r\n"
        reply += "Content-Type: text/plain\r\n"
        reply += "Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        let bytes: [UInt8] = Array(reply.utf8) + response.body
        var offset = 0
        while offset < bytes.count {
            let written: Int = bytes[offset...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            if written <= 0 {
                return
            }
            offset += written
        }
    }

    private static func headersComplete(_ bytes: [UInt8]) -> Bool {
        let end: [UInt8] = [13, 10, 13, 10]
        guard bytes.count >= 4 else { return false }
        for start in 0...(bytes.count - 4) where Array(bytes[start..<(start + 4)]) == end {
            return true
        }
        return false
    }
}
