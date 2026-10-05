import Darwin
import Foundation
import Testing
@testable import MCLCore

/// `LineSocket` against Java `Socket` + `BufferedReader(InputStreamReader(…, US_ASCII))` — values from the probe
/// a maintainer-only probe (`out-en_US.tsv`, rows `RL.`, `CONN.`, `CLOSE.`, `WRITE.`, `RESET.`),
/// same result format (`"…"` with `\uXXXX`, `<null>` = EOF, `EXC class: message`).
///
/// The server is `FakeLineServer` on 127.0.0.1. The probe times the server with pauses; here the cases with a timeout are driven
/// by the `go` command from the client (the server stays silent until it gets it), so the result does not depend on machine load.
/// Blocking calls run on their own thread (`onOwnThread`).
@Suite(.ioSafetyNet) struct LineSocketTests {

    typealias Step = FakeLineServer.Step

    static func esc(_ line: String?) -> String {
        guard let line else { return "<null>" }
        var out = "\""
        for unit in line.utf16 {
            if unit >= 0x20 && unit < 0x7F && unit != 0x5C {
                out += String(UnicodeScalar(UInt8(unit)))
            } else {
                out += "\\u" + String(format: "%04X", Int(unit))
            }
        }
        return out + "\""
    }

    static func exc(_ error: any Error) -> String {
        if let e = error as? JavaSocketError {
            return "EXC " + e.description
        }
        if let e = error as? JavaIllegalArgumentError {
            return "EXC java.lang.IllegalArgumentException: " + e.message
        }
        return "EXC " + String(describing: error)
    }

    /// One `readLine` in the probe format.
    static func read(_ socket: LineSocket) -> String {
        do {
            return esc(try socket.readLine())
        } catch {
            return exc(error)
        }
    }

    /// Up to `reads` reads, after the first `<null>` the end (like the probe).
    static func readAll(_ socket: LineSocket, _ reads: Int) -> String {
        var out: [String] = []
        for _ in 0..<reads {
            let r = read(socket)
            out.append(r)
            if r == "<null>" { break }
        }
        return out.joined(separator: " | ")
    }

    static func bytes(_ text: String) -> Step {
        .bytes(Array(text.utf8))
    }

    /// Server with `onConnect` steps; the client reads `reads` lines.
    static func lines(_ steps: [Step], reads: Int, readTimeoutMs: Int = 10_000) async throws -> String {
        let server = try FakeLineServer(onConnect: steps)
        defer { server.stop() }
        let port = server.port
        return try await onOwnThread {
            let socket = try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: readTimeoutMs)
            defer { socket.close() }
            return readAll(socket, reads)
        }
    }

    static let timedOut = "EXC java.net.SocketTimeoutException: Read timed out"

    // MARK: - RL: terminators and EOF (Java rows RL.*)

    @Test func terminatorsMatchJavaReadLine() async throws {
        let cases: [(String, [Step], Int, String)] = [
            ("lf", [Self.bytes("a\nb\n"), .close], 3, "\"a\" | \"b\" | <null>"),
            ("crlf", [Self.bytes("a\r\nb\r\n"), .close], 3, "\"a\" | \"b\" | <null>"),
            ("cr", [Self.bytes("a\rb\r"), .close], 3, "\"a\" | \"b\" | <null>"),
            ("crcr", [Self.bytes("a\r\rb\n"), .close], 4, "\"a\" | \"\" | \"b\" | <null>"),
            ("lfcr", [Self.bytes("a\n\rb\n"), .close], 4, "\"a\" | \"\" | \"b\" | <null>"),
            ("crlflf", [Self.bytes("a\r\n\nb\n"), .close], 4, "\"a\" | \"\" | \"b\" | <null>"),
            ("empty", [Self.bytes("\n\r\n\r"), .close], 4, "\"\" | \"\" | \"\" | <null>"),
            ("trimNot", [Self.bytes("  a b \t\n"), .close], 2, "\"  a b \\u0009\" | <null>"),
            ("crSplitLf", [Self.bytes("a\r"), .delay(100), Self.bytes("\nb\n"), .close], 3, "\"a\" | \"b\" | <null>"),
            ("crSplitCrlf", [Self.bytes("a\r"), .delay(100), Self.bytes("\r\nb\n"), .close], 4,
             "\"a\" | \"\" | \"b\" | <null>"),
            ("crSplitText", [Self.bytes("a\r"), .delay(100), Self.bytes("b\n"), .close], 3, "\"a\" | \"b\" | <null>"),
            ("splitLine", [.partial("ab"), .delay(100), .line("cd"), .close], 2, "\"abcd\" | <null>"),
            ("highBytes", [.bytes([0x78, 0x80, 0xFF, 0xC3, 0xA9, 0x79, 0x0A]), .close], 2,
             "\"x\\uFFFD\\uFFFD\\uFFFD\\uFFFDy\" | <null>"),
            ("ctrl", [.bytes([0x00, 0x01, 0x7F, 0x09, 0x0B, 0x0C, 0x0A]), .close], 2,
             "\"\\u0000\\u0001\\u007F\\u0009\\u000B\\u000C\" | <null>"),
            ("eofTail", [.partial("abc"), .close], 3, "\"abc\" | <null>"),
            ("eofAfterCr", [Self.bytes("abc\r"), .close], 3, "\"abc\" | <null>"),
            ("eofOnlyCr", [Self.bytes("\r"), .close], 3, "\"\" | <null>"),
            ("eofOnlyLf", [Self.bytes("\n"), .close], 3, "\"\" | <null>"),
            ("eofImmediately", [.close], 2, "<null>"),
            ("eofThenAgain", [Self.bytes("a\n"), .close], 3, "\"a\" | <null>"),
        ]
        for (name, steps, reads, expected) in cases {
            let got = try await Self.lines(steps, reads: reads)
            #expect(got == expected, "RL.\(name)")
        }
    }

    /// After `<null>` the next read returns `nil` again (Java `readLine` after EOF).
    @Test func eofRepeats() async throws {
        let server = try FakeLineServer(onConnect: [.close])
        defer { server.stop() }
        let port = server.port
        let got: [String] = try await onOwnThread {
            let socket = try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: 10_000)
            defer { socket.close() }
            return [Self.read(socket), Self.read(socket), Self.read(socket)]
        }
        #expect(got == ["<null>", "<null>", "<null>"])
    }

    /// `RL.crReturnsAtOnce`: `\r` yields a line immediately, does not wait for another byte (otherwise a timeout would occur here).
    @Test func carriageReturnReturnsAtOnce() async throws {
        let got = try await Self.lines([Self.bytes("a\r")], reads: 1, readTimeoutMs: 5_000)
        #expect(got == "\"a\"")
    }

    // MARK: - Timeout (RL.timeout*, RL.lateAnswer)

    /// Client: reads and `go` commands according to `plan` ("r" = readLine that must return data, "t" = readLine that must
    /// time out, "go" = send `go\n`); the read results. The socket timeout is 100 ms. Only a "t" read may see it: an "r" read
    /// is repeated on `Read timed out` for up to 10 s, because the data it waits for comes from a server thread whose start
    /// (accept, first `send`) can lag by more than 100 ms under load and must not be mistaken for the timeout under test.
    /// The data of every "r" read arrives in one `send` (never a partially read line), so repeating cannot hide a discarded
    /// or kept remainder; a "t" read is deterministic because nothing arrives before `go`. The server's initial `lag`
    /// makes that start delay a fixed property of every run instead of a rare load accident.
    static func scripted(onConnect: [Step], go: [Step], plan: [String], lagMs: Int = 250) async throws -> String {
        let server = try FakeLineServer(script: ["go": go], onConnect: [.delay(lagMs)] + onConnect)
        defer { server.stop() }
        let port = server.port
        return try await onOwnThread {
            let socket = try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: 100)
            defer { socket.close() }
            var out: [String] = []
            for action in plan {
                switch action {
                case "go":
                    try socket.writeAscii("go\n")
                case "r":
                    var r = Self.read(socket)
                    for _ in 0..<100 where r == Self.timedOut {
                        r = Self.read(socket)
                    }
                    out.append(r)
                default:
                    out.append(Self.read(socket))
                }
            }
            return out.joined(separator: " | ")
        }
    }

    @Test func timeoutKeepsSocketUsable() async throws {
        // RL.timeoutNoData
        let got = try await Self.scripted(onConnect: [], go: [.line("x")], plan: ["t", "go", "r"])
        #expect(got == Self.timedOut + " | \"x\"")
    }

    /// RL.timeoutPartial: a partially read line (`AB`) is discarded by the timeout. The initial `ready` only ensures that `AB` arrived
    /// before the first wait (the probe solves that with a pause).
    @Test func timeoutDropsPartialLine() async throws {
        let got = try await Self.scripted(onConnect: [Self.bytes("ready\nAB")], go: [.line("CD")], plan: ["r", "t", "go", "r"])
        #expect(got == "\"ready\" | " + Self.timedOut + " | \"CD\"")
    }

    /// RL.timeoutAfterCr: skipping `\n` after `\r` survives a timeout.
    @Test func skipLineFeedSurvivesTimeout() async throws {
        let got = try await Self.scripted(onConnect: [Self.bytes("a\r")], go: [Self.bytes("\nX\n")], plan: ["r", "t", "go", "r"])
        #expect(got == "\"a\" | " + Self.timedOut + " | \"X\"")
    }

    /// RL.timeoutPartialThenEof: the discarded `AB` is not returned at the end of the stream.
    @Test func partialLineLostBeforeEof() async throws {
        let got = try await Self.scripted(onConnect: [Self.bytes("ready\nAB")], go: [.close], plan: ["r", "t", "go", "r"])
        #expect(got == "\"ready\" | " + Self.timedOut + " | <null>")
    }

    /// RL.timeoutBufferedSecond: `a\nB` — `a` is returned, `B` (a partially read next line) is discarded by the timeout.
    @Test func timeoutDropsBufferedRemainder() async throws {
        let got = try await Self.scripted(onConnect: [Self.bytes("a\nB")], go: [.line("C")], plan: ["r", "t", "go", "r"])
        #expect(got == "\"a\" | " + Self.timedOut + " | \"C\"")
    }

    /// RL.lateAnswer: a late answer is read as the answer to the next query.
    @Test func lateAnswerIsReadNext() async throws {
        let got = try await Self.scripted(onConnect: [.line("USB")], go: [Self.bytes("2400\nRPRT 0\n")],
                                          plan: ["r", "t", "go", "r", "r"])
        #expect(got == "\"USB\" | " + Self.timedOut + " | \"2400\" | \"RPRT 0\"")
    }

    // MARK: - CONN: connecting

    static func connectResult(_ host: String?, _ port: Int, connectTimeoutMs: Int = 2_000, readTimeoutMs: Int = 2_000) async -> String {
        await onOwnThread {
            do {
                let socket = try LineSocket.connect(host: host, port: port, connectTimeoutMs: connectTimeoutMs, readTimeoutMs: readTimeoutMs)
                socket.close()
                return "connected"
            } catch {
                return Self.exc(error)
            }
        }
    }

    @Test func connectErrorsMatchJava() async throws {
        let free = FreeLoopbackPort.take()
        #expect(await Self.connectResult("127.0.0.1", free) == "EXC java.net.ConnectException: Connection refused")
        #expect(await Self.connectResult("nonexistent-host.invalid", free)
            == "EXC java.net.UnknownHostException: nonexistent-host.invalid")
        #expect(await Self.connectResult(nil, free) == "EXC java.lang.IllegalArgumentException: hostname can't be null")
        #expect(await Self.connectResult("127.0.0.1", -1) == "EXC java.lang.IllegalArgumentException: port out of range:-1")
        #expect(await Self.connectResult("127.0.0.1", 65_536)
            == "EXC java.lang.IllegalArgumentException: port out of range:65536")
        #expect(await Self.connectResult("127.0.0.1", 0) == "EXC java.net.BindException: Can't assign requested address")
        #expect(await Self.connectResult("127.0.0.1", free, connectTimeoutMs: -1)
            == "EXC java.lang.IllegalArgumentException: connect: timeout can't be negative")
    }

    @Test func connectErrorKinds() async throws {
        let free = FreeLoopbackPort.take()
        let refused: JavaSocketError.Kind? = await onOwnThread {
            do {
                _ = try LineSocket.connect(host: "127.0.0.1", port: free, connectTimeoutMs: 2_000, readTimeoutMs: 0)
                return nil
            } catch {
                return (error as? JavaSocketError)?.kind
            }
        }
        #expect(refused == .refused)
    }

    /// CONN.emptyHost, CONN.localhost: `""` and `localhost` both lead to 127.0.0.1; a negative read timeout
    /// (Java `setSoTimeout(-1)` after connecting) throws only after connecting.
    @Test func emptyHostAndLocalhostReachLoopback() async throws {
        let server = try FakeLineServer()
        defer { server.stop() }
        #expect(await Self.connectResult("", server.port) == "connected")
        #expect(await Self.connectResult("localhost", server.port) == "connected")
        #expect(await Self.connectResult("127.0.0.1", server.port, readTimeoutMs: -1)
            == "EXC java.lang.IllegalArgumentException: timeout can't be negative")
    }

    /// Connect timeout: a listener with a full queue (`listen` 1, nobody accepts) drops the next SYN (measured on
    /// macOS: the second connection already waits) — no network, only 127.0.0.1.
    @Test func connectTimeoutMessage() async throws {
        let result: String? = await onOwnThread {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            defer { Darwin.close(fd) }
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            sin.sin_addr.s_addr = in_addr_t(UInt32(0x7F00_0001).bigEndian)
            _ = withUnsafePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            _ = listen(fd, 1)
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &sin) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
            }
            let port = Int(UInt16(bigEndian: sin.sin_port))
            var held: [LineSocket] = []
            defer { held.forEach { $0.close() } }
            for _ in 0..<8 {
                do {
                    held.append(try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 300, readTimeoutMs: 0))
                } catch let e as JavaSocketError {
                    return e.kind == .connectTimeout ? Self.exc(e) : "unexpected " + e.description
                } catch {
                    return "unexpected " + String(describing: error)
                }
            }
            return nil
        }
        #expect(result == "EXC java.net.SocketTimeoutException: Connect timed out")
    }

    // MARK: - CLOSE, WRITE, RESET

    /// CLOSE.duringRead/readAfter: `close` from another thread ends the waiting read with `Socket closed`, further calls
    /// throw the same; a second `close` does nothing. Close comes only once the reader is provably waiting inside `readLine`,
    /// and the descriptor must not be closed while it is being read (`fdClosedWhileInUse`).
    @Test func closeFromAnotherThreadUnblocksRead() async throws {
        let server = try FakeLineServer()
        defer { server.stop() }
        let port = server.port
        let socket: LineSocket = try await onOwnThread {
            try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: 0)
        }
        async let during: String = onOwnThread { Self.read(socket) }
        let entered: Bool = await onOwnThread {
            // The reader starts via `async let`, so only once it gets a thread of the shared pool — under CI load (3 vCPU)
            // that took over 10 s. The bound is only a guard against hangs, not a speed measure.
            let deadline: DispatchTime = .now() + .seconds(300)
            while socket.activeOperations == 0 && DispatchTime.now() < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
            let inside = socket.activeOperations == 1
            socket.close()
            socket.close()
            return inside
        }
        #expect(entered)
        #expect(await during == "EXC java.net.SocketException: Socket closed")
        #expect(!socket.fdClosedWhileInUse)
        #expect(Self.read(socket) == "EXC java.net.SocketException: Socket closed")
        #expect(throws: JavaSocketError.socketClosed) { try socket.writeAscii("f\n") }
        #expect(socket.isClosed)
    }

    /// WRITE.peerClosed: after the peer closes, the first write goes through, the next `Broken pipe` (without SIGPIPE).
    @Test func writeAfterPeerCloseIsBrokenPipe() async throws {
        let server = try FakeLineServer(script: ["quit": [.close]])
        defer { server.stop() }
        let port = server.port
        let got: [String] = try await onOwnThread {
            let socket = try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: 10_000)
            defer { socket.close() }
            try socket.writeAscii("quit\n")
            var out = [Self.read(socket)]
            for attempt in 0..<100 {
                do {
                    try socket.writeAscii("f\n")
                    if attempt == 0 { out.append("ok") }
                } catch {
                    out.append(Self.exc(error))
                    break
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return out
        }
        #expect(got == ["<null>", "ok", "EXC java.net.SocketException: Broken pipe"])
    }

    /// RESET.read: peer RST → `Connection reset`, also on a further read.
    @Test func resetByPeer() async throws {
        let got = try await Self.lines([.line("a"), .reset], reads: 3)
        #expect(got == "\"a\" | EXC java.net.SocketException: Connection reset | EXC java.net.SocketException: Connection reset")
    }

    // MARK: - Write

    /// Java `(command + "\n").getBytes(US_ASCII)`: every code point outside ASCII → one `?`; the server receives
    /// exactly these bytes.
    @Test func writesAsciiBytes() async throws {
        let server = try FakeLineServer(script: ["F": [.line("RPRT 0")]], fallback: [.line("RPRT 0")])
        defer { server.stop() }
        let port = server.port
        let replies: [String] = try await onOwnThread {
            let socket = try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: 10_000)
            defer { socket.close() }
            try socket.writeAscii("F 14074000\n")
            let first = Self.read(socket)
            try socket.writeAscii("b č😀é\n")
            return [first, Self.read(socket)]
        }
        #expect(replies == ["\"RPRT 0\"", "\"RPRT 0\""])
        #expect(server.requestBytes(0) == Array("F 14074000\nb ???\n".utf8))
        #expect(server.commands(0) == ["F 14074000", "b ???"])
    }

    @Test func asciiCodecs() {
        #expect(LineSocket.encodeAscii("a\u{7F}\u{80}ž😀") == [0x61, 0x7F, 0x3F, 0x3F, 0x3F])
        #expect(LineSocket.decodeAscii([0x41, 0x80, 0x00, 0xFF]) == "A\u{FFFD}\u{0}\u{FFFD}")
    }
}
