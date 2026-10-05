import Darwin
import Foundation
import Testing
@testable import MCLCore

/// `FldigiClient` over `FakeHttpServer` (and a raw server for response shapes) against the Java probe
/// a maintainer-only probe (rows `fl.*`): results of public methods, **exact bytes**
/// of requests (the header = Java's without the h2c upgrade and `User-Agent`, the body), HTTP states, response shapes, timeouts and address
/// errors. The Java cause (`<- …`) is not compared (Swift errors do not carry it, the status row shows only the message).
///
/// Timeouts: successful scenarios run with a generous 30 s (`generous` — success must not depend on wall-clock time); the Java
/// 2 s / 3 s are used only by the timeout tests (`silent`, `slowHeaders`, `slowBody`, connect timeout, addresses), which verify
/// a lower bound. The client and stand-ins run on their own threads (POSIX), nothing depends on GCD.
@Suite(.ioSafetyNet) struct FldigiClientMeasuredTests {

    typealias Action = @Sendable (FldigiClient) throws -> String

    /// A client with generous timeouts (the error text does not depend on them).
    static func generous(_ host: String, _ port: Int) throws -> FldigiClient {
        try FldigiClient(host: host, port: port, connectTimeoutMs: 30_000, requestTimeoutMs: 30_000)
    }

    static func response(_ value: String) -> String {
        FldigiClientTests.response(value)
    }

    /// `[B@<identity hash>` is random in Java — only the shape is compared.
    static func shape(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.replacingOccurrences(of: "\\[B@[0-9a-f]+", with: "[B@*", options: .regularExpression)
    }

    static func ok(_ f: @escaping @Sendable (FldigiClient) throws -> Void) -> Action {
        { client in
            try f(client)
            return "ok"
        }
    }

    static func method(_ body: [UInt8]) -> String {
        let text = String(decoding: body, as: UTF8.self)
        guard let a = text.range(of: "<methodName>"), let z = text.range(of: "</methodName>") else { return "" }
        return String(text[a.upperBound..<z.lowerBound])
    }

    /// One scenario: actions `fl.<name>.N`, bodies `fl.<name>.bodies`, headers of the first request `fl.<name>.head0`.
    static func scenario(_ name: String, _ reply: @escaping @Sendable (String) -> FakeHttpServer.Response,
                         javaTimeouts: Bool = false, _ actions: [Action]) async throws {
        let server = try FakeHttpServer()
        defer { server.stop() }
        server.respond { body in reply(method(body)) }
        let port = server.port
        let client = javaTimeouts ? try FldigiClient(host: "127.0.0.1", port: port) : try generous("127.0.0.1", port)
        let results: [String] = await onOwnThread {
            actions.map { action in RadioIoProbe.result { try action(client) } }
        }
        for (i, result) in results.enumerated() {
            let key = "fl.\(name).\(i + 1)"
            let expected: String? = RadioIoProbe.row(key).map { $0.replacingOccurrences(of: " [>=1.5s]", with: "") }
            #expect(shape(RadioIoProbe.esc(result)) == shape(RadioIoProbe.withoutCause(expected)), "\(key)")
        }
        #expect(RadioIoProbe.row("fl.\(name).\(results.count + 1)") == nil, "fl.\(name): more actions in the probe")
        let bodies: [String] = server.requests.indices.map { String(decoding: server.body($0), as: UTF8.self) }
        #expect(RadioIoProbe.esc(bodies.joined(separator: "|")) == RadioIoProbe.row("fl.\(name).bodies"), "fl.\(name).bodies")
        checkHead(server.head(0), port: port, javaRow: RadioIoProbe.row("fl.\(name).head0"), name)
    }

    /// The request header byte for byte like Java's without the h2c upgrade (`Connection`, `HTTP2-Settings`, `Upgrade`)
    /// and `User-Agent` (a deliberate divergence from Java v1.1.1): the request line, `Content-Length`, `Host`, `Content-Type`.
    static func checkHead(_ head: String, port: Int, javaRow: String?, _ name: String) {
        let lines: [String] = head.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: ":" + String(port), with: ":<port>") }
        let skipped = ["Connection:", "HTTP2-Settings:", "Upgrade:", "User-Agent:"]
        let java: [String] = (javaRow ?? "").components(separatedBy: "|")
            .filter { line in !skipped.contains { line.hasPrefix($0) } }
        #expect(lines == java, "fl.\(name).head0")
        #expect(head.hasSuffix("\r\n\r\n"), "fl.\(name).head0 end of header")
    }

    static let talkActions: [Action] = [
        { try $0.modemName() }, { try $0.trxState() }, { String(try $0.rxLength()) },
        { try $0.rxText(start: 0, length: 12) }, ok { try $0.transmit("CQ TEST OK1XOE") },
        { try $0.version() }, ok { try $0.setModem("BPSK31") }, ok { try $0.abort() }, { String(try $0.carrier()) },
        ok { try $0.transmit("\u{17E}\u{1F600} <&> \"'") }, { try $0.rxText(start: -1, length: .max) },
    ]

    @Test func talk() async throws {
        try await Self.scenario("talk", { method in
            switch method {
            case "main.get_trx_state": return .init(body: Self.response("<string>TX</string>"))
            case "text.get_rx_length": return .init(body: Self.response("<int>12</int>"))
            case "text.get_rx": return .init(body: Self.response("<base64>Q1EgREwxQUJD</base64>"))
            case "modem.get_name": return .init(body: Self.response("<string>RTTY</string>"))
            case "fldigi.version": return .init(body: Self.response("<string>4.2.05</string>"))
            case "modem.get_carrier": return .init(body: Self.response("<i4>1500</i4>"))
            default: return .init(body: Self.response("<string></string>"))
            }
        }, Self.talkActions)
    }

    /// A body with non-ASCII text byte for byte like Java `XmlRpc.call(...).getBytes(UTF_8)`.
    @Test func requestBodyBytesAreUtf8() async throws {
        let server = try FakeHttpServer(response: .init(body: Self.response("<string></string>")))
        defer { server.stop() }
        let client = try Self.generous("127.0.0.1", server.port)
        try await onOwnThread { try client.transmit("\u{17E}\u{1F600} <&>") }
        let expected = "<?xml version=\"1.0\"?><methodCall><methodName>text.add_tx</methodName><params><param><value>"
            + "<string>\u{17E}\u{1F600} &lt;&amp;&gt;^r</string></value></param></params></methodCall>"
        #expect(server.body(1) == Array(expected.utf8))
    }

    static let valueActions: [Action] = [
        { try $0.version() }, { String(try $0.rxLength()) }, { String(try $0.carrier()) },
        { try $0.rxText(start: 0, length: 1) },
    ]

    @Test(arguments: Array(["<int>-7</int>", "<string> 12 </string>", "<double>12.0</double>", "<boolean>1</boolean>",
                            "<base64>6WE=</base64>", "", "x<!-- c -->y", "<i8>2147483647</i8>"].enumerated()))
    func values(_ index: Int, _ value: String) async throws {
        try await Self.scenario("value\(index)", { _ in .init(body: Self.response(value)) }, Self.valueActions)
    }

    @Test func noValueAndFault() async throws {
        try await Self.scenario("noValue", { _ in
            .init(body: "<?xml version=\"1.0\"?><methodResponse><params/></methodResponse>")
        }, [{ try $0.version() }, { String(try $0.rxLength()) }, { try $0.rxText(start: 0, length: 1) }])
        try await Self.scenario("fault", { _ in
            .init(body: "<methodResponse><fault><value><struct><member><name>faultString</name><value>"
                + "<string>bad</string></value></member></struct></value></fault></methodResponse>")
        }, [{ try $0.version() }, Self.ok { try $0.transmit("x") }])
    }

    /// A status other than 200 → `fldigi: HTTP n`; a redirect is not followed (Java `Redirect.NEVER`).
    @Test(arguments: [500, 404, 201, 302])
    func statuses(_ status: Int) async throws {
        let headers: [String] = status == 302 ? ["Location: /RPC2"] : []
        try await Self.scenario("status\(status)", { _ in
            .init(status: status, body: Self.response("<string>X</string>"), headers: headers)
        }, [{ try $0.version() }, Self.ok { try $0.transmit("x") }])
    }

    @Test func connectionClosedWithoutReply() async throws {
        try await Self.scenario("closeNoReply", { _ in .init(closeWithoutReply: true) }, [{ try $0.version() }])
    }

    /// The Java request timeout of 3 s (default, not shortened): no response → `request timed out` after ~3 s at the earliest.
    @Test func silentServerTimesOutAfterThreeSeconds() async throws {
        let start = DispatchTime.now()
        try await Self.scenario("silent", { _ in .init(body: Self.response("<string>late</string>"), delayMs: 6_000) },
                                javaTimeouts: true, [{ try $0.version() }])
        #expect(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds >= 2_900_000_000)
        #expect(FldigiClient.requestTimeoutMs == 3_000 && FldigiClient.connectTimeoutMs == 2_000)
    }

    @Test func addressesAndConnectErrors() async throws {
        let free = FreeLoopbackPort.take()
        let cases: [(String, String, Int)] = [
            ("refused", "127.0.0.1", free), ("localhostRefused", "localhost", free), ("badHost", "bad host", 7_362),
            ("emptyHost", "", free), ("unknownHost", "fl.neexistuje.invalid", 7_362), ("range", "127.0.0.1", 70_000),
            ("negPort", "127.0.0.1", -1), ("port0", "127.0.0.1", 0), ("underscore", "my_host.invalid", 7_362),
            ("dashLabel", "-a.invalid", 7_362), ("emptyLabel", "a..b.invalid", 7_362),
            ("trailingDot", "fl.neexistuje.invalid.", 7_362), ("ipv6Bare", "::1", free), ("ipv6", "[::1]", free),
            ("nonAscii", "\u{17E}.invalid", 7_362), ("quote", "a\"b", 7_362), ("caret", "a^b", 7_362),
            ("pipe", "a|b", 7_362), ("percentBad", "a%zz", 7_362), ("tab", "a\tb", 7_362),
            ("bracketMid", "a[b", 7_362), ("bracketClose", "a]b", 7_362), ("ipv6Bad", "[zz]", 7_362),
            ("ipv6Open", "[::1", 7_362), ("ipv6Trailing", "[::1]x", 7_362), ("ipv6V4", "[::ffff:127.0.0.1]", free),
            ("ipv6Empty", "[]", 7_362),
        ]
        for (key, host, port) in cases {
            let result: String = await onOwnThread {
                RadioIoProbe.result {
                    let client = try FldigiClient(host: host, port: port)
                    return "created; " + RadioIoProbe.result { try client.version() }
                }
            }
            let shown = result.replacingOccurrences(of: ":" + String(free), with: ":<port>")
            #expect(RadioIoProbe.esc(shown) == RadioIoProbe.withoutCause(RadioIoProbe.row("fl.connect." + key)), "\(key)")
        }
    }

    /// Connect timeout 2 s (native, `LineSocket.connect`): a listener with a full queue accepts nobody and the kernel
    /// drops the SYN — as in the Java probe. `HTTP connect timed out` is reported, not a request timeout.
    @Test func connectTimeoutAfterTwoSeconds() async throws {
        let full: FullBacklogListener = try await onOwnThread { try FullBacklogListener() }
        defer { full.close() }
        #expect(String(full.blocked) == RadioIoProbe.row("fl.connectTimeout.blocked"))
        let port = full.port
        let client = try FldigiClient(host: "127.0.0.1", port: port)
        let start = DispatchTime.now()
        let result: String = await onOwnThread { RadioIoProbe.result { try client.version() } }
        let elapsed: UInt64 = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        #expect(RadioIoProbe.esc(result) == RadioIoProbe.withoutCause(RadioIoProbe.row("fl.connectTimeout.1")))
        #expect(elapsed >= 1_900_000_000)
    }

    /// A listening socket with a queue of 1 that never accepts; filling connections until the next `connect` expires.
    final class FullBacklogListener: @unchecked Sendable {
        let fd: Int32
        let port: Int
        private var fillers: [LineSocket] = []
        private(set) var blocked = false

        init() throws {
            let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
            self.fd = fd
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
            self.port = port
            for _ in 0..<64 {
                do {
                    fillers.append(try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 300, readTimeoutMs: 0))
                } catch {
                    blocked = true
                    break
                }
            }
        }

        func close() {
            for filler in fillers {
                filler.close()
            }
            _ = Darwin.close(fd)
        }
    }

    // MARK: - Response shapes (a raw server)

    /// A raw HTTP server: reads the request (header + `Content-Length`), sends parts of the response verbatim
    /// (ISO-8859-1) with a 4 s pause between them, then closes the connection, or with `resetAtEnd` resets (RST).
    final class RawHttpServer: @unchecked Sendable {
        private var listener: LoopbackListener!
        private let lock = NSLock()
        private var done = false

        /// The server sent all parts and closed the connection.
        var finished: Bool {
            lock.lock()
            defer { lock.unlock() }
            return done
        }

        init(parts: [String], resetAtEnd: Bool) throws {
            listener = try LoopbackListener(name: "raw-http") { connection in
                var bytes: [UInt8] = []
                while true {
                    guard let chunk = connection.receive() else { return }
                    bytes += chunk
                    if let end = FakeHttpServer.headerEnd(bytes) {
                        let head = String(decoding: bytes[..<end], as: UTF8.self)
                        let length = head.components(separatedBy: "\r\n").first { $0.hasPrefix("Content-Length: ") }
                            .flatMap { Int($0.dropFirst(16)) } ?? 0
                        if bytes.count >= end + length { break }
                    }
                }
                for (i, part) in parts.enumerated() {
                    if i > 0 {
                        Thread.sleep(forTimeInterval: 4)
                    }
                    connection.send(part.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
                }
                if resetAtEnd {
                    connection.reset()
                }
                self.lock.lock()
                self.done = true
                self.lock.unlock()
            }
        }

        var port: Int { listener.port }

        func stop() {
            listener.stop()
        }
    }

    /// The same responses as the probe (`raws` in `ProbeRadioIo.fldigi`).
    static func rawCases() -> [(String, String)] {
        let ok = response("<string>R</string>")
        let okUnits = Array(ok.utf16)
        let first16 = String(decoding: okUnits[..<16], as: UTF16.self)
        let rest = String(decoding: okUnits[16...], as: UTF16.self)
        let utf8 = response("<string>\u{C5}\u{BE}\u{FF}</string>")
        let n = String(okUnits.count)
        return [
            ("lenLower", "HTTP/1.1 200 OK\r\ncontent-length: " + n + "\r\n\r\n" + ok),
            ("http10NoLength", "HTTP/1.0 200 OK\r\nContent-Type: text/xml\r\n\r\n" + ok),
            ("noLengthClose", "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + ok),
            ("chunked", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10\r\n" + first16 + "\r\n"
                + String(okUnits.count - 16, radix: 16) + "\r\n" + rest + "\r\n0\r\n\r\n"),
            ("lfOnly", "HTTP/1.1 200 OK\nContent-Length: " + n + "\n\n" + ok),
            ("garbageStatus", "XYZ 200 OK\r\nContent-Length: 0\r\n\r\n"),
            ("noReason", "HTTP/1.1 200\r\nContent-Length: " + n + "\r\n\r\n" + ok),
            ("badCode", "HTTP/1.1 2x0 OK\r\nContent-Length: 0\r\n\r\n"),
            ("eofInHeaders", "HTTP/1.1 200 OK\r\nContent-Len"),
            ("eofInBody", "HTTP/1.1 200 OK\r\nContent-Length: 500\r\n\r\n" + ok),
            ("badLength", "HTTP/1.1 200 OK\r\nContent-Length: x\r\n\r\n" + ok),
            ("resetBeforeReply", "<RST>"),
            ("resetInBody", "HTTP/1.1 200 OK\r\nContent-Length: 500\r\n\r\n<string><RST>"),
            ("slowBody", "HTTP/1.1 200 OK\r\nContent-Length: " + n + "\r\n\r\n<SLEEP>" + ok),
            ("slowHeaders", "HTTP/1.1 200 OK\r\n<SLEEP>Content-Length: " + n + "\r\n\r\n" + ok),
            ("status500NoBody", "HTTP/1.1 500 Err\r\nContent-Length: 0\r\n\r\n"),
            ("chunkWrap", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + String(okUnits.count, radix: 16)
                + "\r\n" + ok + "\r\n100000000\r\n\r\n"),
            ("chunkExt", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + String(okUnits.count, radix: 16)
                + ";x=y\r\n" + ok + "\r\n0\r\n\r\n"),
            ("chunkBareCrlf", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + String(okUnits.count, radix: 16)
                + "\r\n" + ok + "\r\n\r\n\r\n"),
            ("chunkIllegal", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\ng\r\n"),
            ("chunkInvalidHeader", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10\rx"),
            ("chunkTooLong", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + String(repeating: "0", count: 2_100) + "\r\n"),
            ("chunkEofData", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10\r\n<str"),
            ("chunkEofLength", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1"),
            ("no204", "HTTP/1.1 204 No Content\r\n\r\n<SLEEP>"),
            ("len204", "HTTP/1.1 204 No Content\r\nContent-Length: 5\r\n\r\nabcde"),
            ("te204", "HTTP/1.1 204 No Content\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"),
            ("resetNoLength", "HTTP/1.1 200 OK\r\n\r\n<string><RST>"),
            ("utf8Body", "HTTP/1.1 200 OK\r\nContent-Length: " + String(utf8.utf16.count) + "\r\n\r\n" + utf8),
        ]
    }

    /// A state machine of headers, body length, chunked, RST as the end of stream and a timeout only up to the end of headers
    /// (`slowBody` passes after 4 s, `slowHeaders` ends with `request timed out`) — with the Java 2 s / 3 s.
    @Test(arguments: rawCases())
    func responseShapes(_ name: String, _ raw: String) async throws {
        var text = raw
        let reset = text.hasSuffix("<RST>")
        if reset {
            text = String(text.dropLast(5))
        }
        let server = try RawHttpServer(parts: text.components(separatedBy: "<SLEEP>"), resetAtEnd: reset)
        defer { server.stop() }
        // The Java 3 s only where the timeout is measured (headers after a pause expire, the body after a pause does not).
        let client = name == "slowHeaders" || name == "slowBody"
            ? try FldigiClient(host: "127.0.0.1", port: server.port) : try Self.generous("127.0.0.1", server.port)
        // `finished` is read on the client thread right after the call returns — after `await` a delay returning to the
        // shared pool (a loaded CI) could have it read only after the server's 4 s pause.
        let (result, finishedAtReturn): (String, Bool) = await onOwnThread {
            let result = RadioIoProbe.result { try client.version() }
            return (result, server.finished)
        }
        if name == "no204" {
            // Java does not read the body of a 204: the result must arrive while the server holds the connection (a 4 s pause).
            #expect(!finishedAtReturn, "a 204 without a length must not be read to the end of the stream")
        }
        let expected: String? = RadioIoProbe.row("fl.raw.\(name).1").map { $0.replacingOccurrences(of: " [>=1.5s]", with: "") }
        #expect(RadioIoProbe.esc(result) == RadioIoProbe.withoutCause(expected), "fl.raw.\(name)")
    }

    /// Java constants: connect timeout 2 s, request 3 s.
    @Test func timeoutsAreJavas() {
        #expect(FldigiClient.connectTimeoutMs == 2_000)
        #expect(FldigiClient.requestTimeoutMs == 3_000)
    }

    /// A negative `chunked` block length (32-bit overflow like a Java `int`): Java loops, Swift must neither crash
    /// (`0..<negative`) nor hang — it throws an error (a deliberate divergence from Java v1.1.1). Without a probe (Java does not finish).
    @Test(arguments: [("ffffffffffffffff", "-1"), ("80000000", "-2147483648"), ("1ffffffff", "-1")])
    func negativeChunkSizeThrows(_ size: String, _ shown: String) async throws {
        let server = try RawHttpServer(
            parts: ["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + size + "\r\nabc"], resetAtEnd: false)
        defer { server.stop() }
        let client = try Self.generous("127.0.0.1", server.port)
        let result: String = await onOwnThread { RadioIoProbe.result { try client.version() } }
        #expect(result == "EXC java.io.IOException: chunked transfer encoding, negative chunk size: " + shown)
    }
}
