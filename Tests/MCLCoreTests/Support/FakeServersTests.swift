import Foundation
import Testing
@testable import MCLCore

/// The server stand-ins themselves: reply selection (whole line → first word → `fallback`, one-shot `enqueue`),
/// text directives and byte recording; the HTTP stand-in with request recording.
@Suite(.ioSafetyNet) struct FakeServersTests {

    @Test func directivesParse() {
        typealias Step = FakeLineServer.Step
        #expect(Step.parse("silent") == .silent)
        #expect(Step.parse("close") == .close)
        #expect(Step.parse("reset") == .reset)
        #expect(Step.parse("delay 250") == .delay(250))
        #expect(Step.parse("partial US") == .partial("US"))
        #expect(Step.parse("RPRT 0") == .line("RPRT 0"))
    }

    @Test func lineServerScriptSelection() async throws {
        let server = try FakeLineServer(lines: ["f": ["14074000"], "m": ["USB", "2400"], "V VFOB": ["RPRT 0"]])
        defer { server.stop() }
        server.enqueue("s", [.line("RPRT -11")])
        server.respond("s", [.line("0"), .line("VFOA")])
        let port = server.port
        let got: [String] = try await onOwnThread {
            let s = try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: 10_000)
            defer { s.close() }
            var out: [String] = []
            for cmd in ["f", "m", "s", "s", "V VFOB", "V VFOA", "X"] {
                try s.writeAscii(cmd + "\n")
                let lines = cmd == "m" || cmd == "s" && out.contains("RPRT -11") ? 2 : 1
                for _ in 0..<lines { out.append(try s.readLine() ?? "<null>") }
            }
            return out
        }
        #expect(got == ["14074000", "USB", "2400", "RPRT -11", "0", "VFOA", "RPRT 0", "RPRT -1", "RPRT -1"])
        #expect(server.commands(0) == ["f", "m", "s", "s", "V VFOB", "V VFOA", "X"])
        #expect(server.requestBytes(0) == Array("f\nm\ns\ns\nV VFOB\nV VFOA\nX\n".utf8))
        #expect(server.connectionCount == 1)
    }

    /// `silent` = no reply (the client gets a timeout), `close` = EOF; recording per connection.
    @Test func lineServerSilentAndClosePerConnection() async throws {
        let server = try FakeLineServer(lines: ["X": ["silent"], "q": ["close"]])
        defer { server.stop() }
        let port = server.port
        let got: [String] = try await onOwnThread {
            var out: [String] = []
            for cmd in ["X", "q"] {
                // `X` waits for a timeout (100 ms), `q` waits for EOF — a generous 10 s, so it does not depend on load.
                let timeout = cmd == "X" ? 100 : 10_000
                let s = try LineSocket.connect(host: "127.0.0.1", port: port, connectTimeoutMs: 2_000, readTimeoutMs: timeout)
                defer { s.close() }
                try s.writeAscii(cmd + "\n")
                do {
                    out.append(try s.readLine() ?? "<null>")
                } catch {
                    out.append(String(describing: error))
                }
            }
            return out
        }
        #expect(got == ["java.net.SocketTimeoutException: Read timed out", "<null>"])
        #expect(server.commands(0) == ["X"])
        #expect(server.commands(1) == ["q"])
    }

    @Test func httpServerRecordsRequestAndReplies() async throws {
        let server = try FakeHttpServer(response: .init(status: 200, body: "<methodResponse/>"))
        defer { server.stop() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/RPC2")!)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<methodCall/>".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "<methodResponse/>")
        #expect(server.requests.count == 1)
        #expect(server.head(0).hasPrefix("POST /RPC2 HTTP/1.1\r\n"))
        #expect(server.head(0).contains("Content-Type: text/xml\r\n"))
        #expect(server.body(0) == Array("<methodCall/>".utf8))

        server.respond(.init(status: 500, body: "oops"))
        let (_, second) = try await URLSession.shared.data(for: request)
        #expect((second as? HTTPURLResponse)?.statusCode == 500)
    }
}
