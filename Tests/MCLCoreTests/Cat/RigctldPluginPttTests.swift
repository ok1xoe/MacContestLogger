import Foundation
@testable import MCLCore
import Testing

/// Plugin PTT commands never go over a connection that may be out of step after a timeout, and a timeout of their own
/// closes the connection (a late reply is never read as the reply to a later command).
@Suite struct RigctldPluginPttTests {

    @Test func aPluginKeyRefusesAConnectionOutOfStep() async throws {
        let server = try FakeLineServer(script: ["T 0": [.delay(150), .line("RPRT 0")], "T 1": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        // The operator's own command times out (its reply comes late).
        #expect(throws: (any Error).self) { try client.setPtt(false) }
        #expect(client.isConnected())
        #expect(throws: (any Error).self) { _ = try client.keyPtt(unless: { false }) }
        #expect(!client.isConnected())
        #expect(!server.allCommands.contains("T 1"))
    }

    @Test func aPluginKeyThatTimesOutClosesTheConnection() async throws {
        let server = try FakeLineServer(script: ["T 1": [.delay(400), .line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        #expect(throws: (any Error).self) { _ = try client.keyPtt(unless: { false }) }
        #expect(!client.isConnected())
    }

    @Test func aRefusedKeyIsACatRefusal() async throws {
        let server = try FakeLineServer(script: ["T 1": [.line("RPRT -6")], "T 0": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 1_000)
        #expect(throws: CatRefusal.self) { _ = try client.keyPtt(unless: { false }) }
        try client.releasePtt()
        #expect(client.isConnected())
    }
}
