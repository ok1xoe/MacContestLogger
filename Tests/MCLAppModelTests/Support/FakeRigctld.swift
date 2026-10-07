import Foundation

/// The shared `rigctld`/`rotctld` daemons of the user listen on 4532/4533; a test never touches them.
func guardTestPort(_ port: Int) {
    precondition(port != 4532 && port != 4533, "the test must not touch the shared daemon")
}

/// A fake hamlib daemon (`rigctld`, and the few `rotctld` commands) on `127.0.0.1` with a port the system picks —
/// never a real rig. It keeps a rig state (frequency, mode, split), answers the line protocol of `RigctldClient`
/// and `RotctldClient`, and records every command line. Accepting and serving run on the server's own threads,
/// never in Swift's shared pool.
final class FakeRigctld: @unchecked Sendable {

    let port: Int
    private let socket: Int32
    private let lock = NSLock()
    private var stopped = false
    private var clients: [Int32] = []
    private var lines: [String] = []
    private var accepted = 0
    private var freqHz: Int64
    private var mode: String
    private var split = false
    private var txHz: Int64 = 0
    private var azimuthText = "123.0"
    /// The next `f` closes the connection instead of answering (a lost rig).
    private var dropOnRead = false
    /// Command words answered with `RPRT -1`.
    private var rejected: Set<String> = []
    /// The command line whose answer is held back (a late answer) until `releaseAnswer()`.
    private var heldLine: String?
    private var answerHeld = false
    private let answerGate = NSCondition()

    init(freqHz: Int64 = 14_025_000, mode: String = "CW") throws {
        self.freqHz = freqHz
        self.mode = mode
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
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
        guardTestPort(port)
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "fake-rigctld"
        thread.start()
    }

    deinit {
        stop()
    }

    // MARK: - what the test sees and sets

    /// Every command line received, in order.
    var commands: [String] {
        lock.withLock { lines }
    }

    /// The command lines that change the rig (not the poll's `f`, `m`, `s`, `i`, `p`).
    var writes: [String] {
        commands.filter { !["f", "m", "s", "i", "p"].contains($0) }
    }

    /// Connections still open (a client that disconnected is gone).
    var openConnections: Int {
        lock.withLock { clients.count }
    }

    var connectionCount: Int {
        lock.withLock { accepted }
    }

    var frequency: Int64 {
        lock.withLock { freqHz }
    }

    func setFrequency(_ hz: Int64) {
        lock.withLock { freqHz = hz }
    }

    func setSplit(_ on: Bool, txHz: Int64) {
        lock.withLock {
            split = on
            self.txHz = txHz
        }
    }

    func dropNextRead() {
        lock.withLock { dropOnRead = true }
    }

    /// The next `line` is recorded at once but answered only after `releaseAnswer()` — the client's read times out
    /// first (a late answer), and the lines it sends meanwhile wait in the socket.
    func holdAnswer(to line: String) {
        answerGate.lock()
        heldLine = line
        answerGate.unlock()
    }

    func releaseAnswer() {
        answerGate.lock()
        heldLine = nil
        answerHeld = false
        answerGate.broadcast()
        answerGate.unlock()
    }

    /// The held answer is waiting (its line was received).
    var isHoldingAnswer: Bool {
        answerGate.lock()
        defer { answerGate.unlock() }
        return answerHeld
    }

    /// Waits while the answer to `line` is held (bounded at two minutes, so a failing test does not keep the thread).
    private func waitIfHeld(_ line: String) {
        answerGate.lock()
        defer { answerGate.unlock() }
        guard heldLine == line else { return }
        heldLine = nil
        answerHeld = true
        let deadline = Date(timeIntervalSinceNow: 120)
        while answerHeld && Date() < deadline {
            _ = answerGate.wait(until: deadline)
        }
    }

    /// Answers `word` normally again.
    func unreject(_ word: String) {
        lock.withLock { _ = rejected.remove(word) }
    }

    func reject(_ word: String) {
        lock.withLock { _ = rejected.insert(word) }
    }

    func setAzimuth(_ text: String) {
        lock.withLock { azimuthText = text }
    }

    /// The server still accepts a connection (a new client gets an answer to `f`).
    func stillListening() -> Bool {
        let fd: Int32 = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected: Int32 = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }

    func stop() {
        let toClose: [Int32]? = lock.withLock { () -> [Int32]? in
            if stopped { return nil }
            stopped = true
            let open: [Int32] = clients
            clients = []
            return open
        }
        guard let toClose else { return }
        releaseAnswer()
        for client in toClose {
            shutdown(client, SHUT_RDWR)
        }
        // A wake-up connection unblocks `accept`; the accept thread then closes the socket.
        _ = stillListening()
    }

    // MARK: - serving

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
            lock.withLock {
                accepted += 1
                clients.append(client)
            }
            let thread = Thread { [self] in serve(client) }
            thread.name = "fake-rigctld-client"
            thread.start()
        }
    }

    private func serve(_ client: Int32) {
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
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                pending.removeSubrange(...newline)
                guard let reply = answer(line) else { return }
                waitIfHeld(line)
                let bytes: [UInt8] = Array(reply.map { $0 + "\n" }.joined().utf8)
                var offset = 0
                while offset < bytes.count {
                    let written: Int = bytes[offset...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                    if written <= 0 {
                        return
                    }
                    offset += written
                }
            }
        }
    }

    /// The reply lines; `nil` = close the connection.
    private func answer(_ line: String) -> [String]? {
        lock.withLock { () -> [String]? in
            lines.append(line)
            let words: [Substring] = line.split(separator: " ")
            let word: String = words.first.map(String.init) ?? ""
            if rejected.contains(word) {
                return ["RPRT -1"]
            }
            switch word {
            case "f":
                if dropOnRead {
                    dropOnRead = false
                    return nil
                }
                return [String(freqHz)]
            case "m":
                return [mode, "500"]
            case "s":
                return words.count == 1 ? [split ? "1" : "0", split ? "VFOB" : "VFOA"] : ["RPRT 0"]
            case "i":
                return [String(txHz)]
            case "p":
                return [azimuthText, "0.0"]
            case "F":
                if words.count > 1, let hz = Int64(words[1]) {
                    freqHz = hz
                }
                return ["RPRT 0"]
            case "M":
                if words.count > 1 {
                    mode = String(words[1])
                }
                return ["RPRT 0"]
            case "S":
                if words.count > 1 {
                    split = words[1] == "1"
                }
                return ["RPRT 0"]
            default:
                return ["RPRT 0"]
            }
        }
    }
}
