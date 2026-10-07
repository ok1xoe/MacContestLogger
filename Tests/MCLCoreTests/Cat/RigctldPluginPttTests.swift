import Foundation
@testable import MCLCore
import Testing

/// Plugin PTT commands never go over a connection that may be out of step (a reply unread or late), and an error of
/// their own reopens it: a late reply is never read as the reply to a later command, and the client stays connected.
@Suite struct RigctldPluginPttTests {

    @Test func aPluginKeyRefusesAConnectionOutOfStep() async throws {
        let server = try FakeLineServer(script: ["T 0": [.delay(150), .line("RPRT 0")], "T 1": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        // The operator's own command times out (its reply comes late).
        #expect(throws: (any Error).self) { try client.setPtt(false) }
        #expect(client.isConnected())
        // The plugin key reopens the connection first (transparently: the client stays connected) and never reads
        // the late reply as its own.
        #expect(try client.keyPtt(unless: { false }))
        #expect(client.isConnected())
        #expect(server.commands(0) == ["T 0"])
        #expect(server.commands(1) == ["T 1"])
    }

    @Test func aPluginKeyThatTimesOutReopensTheConnection() async throws {
        let server = try FakeLineServer(script: ["T 1": [.delay(400), .line("RPRT 0")], "T 0": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        #expect(throws: (any Error).self) { _ = try client.keyPtt(unless: { false }) }
        // Reopened at once: the late reply goes to the closed connection; the next command has a fresh one.
        #expect(client.isConnected())
        try client.releasePtt()
        #expect(server.commands(1) == ["T 0"])
    }

    @Test func aRefusedKeyIsACatRefusal() async throws {
        let server = try FakeLineServer(script: ["T 1": [.line("RPRT -6")], "T 0": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 1_000)
        #expect(throws: CatRefusal.self) { _ = try client.keyPtt(unless: { false }) }
        try client.releasePtt()
        #expect(client.isConnected())
    }

    /// The operator's command times out and its late `RPRT 0` arrives; the plugin release `T 0` that the rig refuses
    /// must not take that late reply as its own.
    @Test func aPluginReleaseNeverReadsALateReply() async throws {
        let server = try FakeLineServer(script: ["F": [.delay(150), .line("RPRT 0")], "T 0": [.line("RPRT -1")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        #expect(throws: (any Error).self) { try client.setFrequencyHz(7_000_000) }
        #expect(throws: (any Error).self) { try client.releasePtt() }
        #expect(server.commands(1) == ["T 0"])
    }

    /// A plugin release whose own reply times out reopens the connection at once: its late reply is never read later,
    /// not even by the operator's next command.
    @Test func aPluginReleaseThatTimesOutReopens() async throws {
        let server = try FakeLineServer(script: ["T 0": [.delay(150), .line("RPRT -9")], "F": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        #expect(throws: (any Error).self) { try client.releasePtt() }
        try client.setFrequencyHz(7_000_000)
        #expect(server.commands(1) == ["F 7000000"])
    }

    /// A CAT log error after a command was written leaves its reply unread: the next plugin release reopens the
    /// connection instead of reading that reply as its own (the rig refuses `T 0` here, so it must fail).
    @Test func aCatLogErrorPutsTheConnectionOutOfStep() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rigctld-step-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let server = try FakeLineServer(script: ["F": [.line("RPRT 0")], "T 0": [.line("RPRT -1")]])
        defer { server.stop() }
        let log = CatTrafficLog(maxLines: 100)
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 1_000, log: log)
        log.setFile(blocker.appendingPathComponent("cat.log"))
        #expect(throws: (any Error).self) { try client.setFrequencyHz(7_000_000) }
        log.setFile(nil)
        #expect(throws: (any Error).self) { try client.releasePtt() }
        #expect(server.commands(1) == ["T 0"])
        #expect(client.isConnected())
    }

    // MARK: - ninth security review

    /// The release check runs after a reopen, right before `T 1` is written: a release requested while the
    /// connection was being reopened still stops the key.
    @Test func theCancelCheckFollowsTheReopen() async throws {
        let server = try FakeLineServer(script: ["T 0": [.delay(150), .line("RPRT 0")], "T 1": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        #expect(throws: (any Error).self) { try client.setPtt(false) }
        #expect(try !client.keyPtt(unless: { client.reopenCount > 0 }))
        #expect(!server.allCommands.contains("T 1"))
    }

    private static func drained(_ outcome: CatUnknownOutcome) async -> PttKeyDrain.Result {
        await withCheckedContinuation { continuation in
            outcome.drain.onDone { continuation.resume(returning: $0) }
        }
    }

    /// An unanswered `T 1`: `T 0` goes right behind it on the same connection, which is read in the background; the
    /// client goes on over a fresh connection.
    @Test func anUnansweredKeyIsReleasedBehindItOnItsOwnConnection() async throws {
        let server = try FakeLineServer(script: ["T 1": [.delay(150), .line("RPRT 0")], "T 0": [.line("RPRT 0")],
                                                 "F": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 100)
        do {
            _ = try client.keyPtt(unless: { false })
            Issue.record("keyed although unanswered")
        } catch let unknown as CatUnknownOutcome {
            #expect(await Self.drained(unknown) == .released)
        }
        #expect(server.commands(0) == ["T 1", "T 0"])
        try client.setFrequencyHz(7_000_000)
        #expect(server.commands(1) == ["F 7000000"])
    }

    /// The drain tells a refused `T 0` behind an answered key, and a key that never answered.
    @Test func anUnansweredKeyDrainTellsHowItEnded() async throws {
        for (script, expected) in [(["T 1": [FakeLineServer.Step.delay(150), .line("RPRT 0")], "T 0": [.line("RPRT -1")]],
                                    PttKeyDrain.Result.keyRan),
                                   (["T 1": [.silent], "T 0": [.silent]], .unknown)] {
            let server = try FakeLineServer(script: script)
            defer { server.stop() }
            let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 50)
            do {
                _ = try client.keyPtt(unless: { false })
                Issue.record("keyed although unanswered")
            } catch let unknown as CatUnknownOutcome {
                #expect(await Self.drained(unknown) == expected)
            }
        }
    }

    /// The end of the stream mid-reply puts the connection out of step: the next plugin key goes over a fresh one.
    @Test func anEndOfStreamPutsTheConnectionOutOfStep() async throws {
        let server = try FakeLineServer(script: ["F": [.close], "T 1": [.line("RPRT 0")]])
        defer { server.stop() }
        let client = try RigctldClient(host: "127.0.0.1", port: server.port, timeoutMs: 1_000)
        #expect(throws: (any Error).self) { try client.setFrequencyHz(7_000_000) }
        #expect(try client.keyPtt(unless: { false }))
        #expect(server.commands(1) == ["T 1"])
    }
}
