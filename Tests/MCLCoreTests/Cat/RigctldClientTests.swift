import Foundation
import os
import Testing
@testable import MCLCore

/// Port of `cat/RigctldClientTest` (10 tests) — the mock server is `FakeLineServer` with the same script as the Java
/// mock (`f`, `m`, set commands `RPRT 0`, `s` per test, `i`, otherwise `RPRT -1`). Blocking client calls run
/// on their own thread (`onOwnThread`).
@Suite(.ioSafetyNet) struct RigctldClientTests {

    /// Java rig mock; `split` = reply to `s`.
    static func mockServer(split: [String] = ["0", "VFOA"]) throws -> FakeLineServer {
        var script: [String: [String]] = [
            "f": ["14074000"],
            "m": ["USB", "2400"],
            "s": split,
            "i": ["14030000"],
        ]
        for command in ["F", "M", "S", "I", "V", "G", "J"] {
            script[command] = ["RPRT 0"]
        }
        return try FakeLineServer(lines: script)
    }

    /// Java `connect()` + `try-with-resources`.
    static func withClient<T: Sendable>(_ server: FakeLineServer,
                                        _ body: @escaping @Sendable (RigctldClient) throws -> T) async throws -> T {
        let port = server.port
        return try await onOwnThread {
            let client = try RigctldClient(host: "localhost", port: port, log: CatTrafficLog(maxLines: 1000))
            defer { client.close() }
            return try body(client)
        }
    }

    @Test func readReturnsFrequencyAndMappedMode() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        let state = try await Self.withClient(server) { try $0.read() }
        #expect(state.freqHz == 14_074_000)
        #expect(state.mode == .ssb)
        #expect(state.rawMode == "USB")
        #expect(state.passband == 2400)
    }

    @Test func setFrequencySendsCorrectCommand() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        try await Self.withClient(server) { try $0.setFrequencyHz(14_200_000) }
        #expect(server.allCommands.contains("F 14200000"), "sent commands: \(server.allCommands)")
    }

    @Test func setModeChoosesUsbAboveTenMHz() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        try await Self.withClient(server) { try $0.setMode(.ssb, freqHz: 14_200_000) }
        #expect(server.allCommands.contains("M USB 0"), "sent commands: \(server.allCommands)")
    }

    @Test func setRitSendsOffsetAndToleratesMissingFunction() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        try await Self.withClient(server) { client in
            try client.setRit(120) // the mock rejects "U RIT 1" (RPRT -1) — must not bring it down
            try client.setRit(0)
        }
        let received = server.allCommands
        #expect(["J 120", "U RIT 1", "J 0", "U RIT 0"].allSatisfy(received.contains), "sent: \(received)")
    }

    @Test func selectVfoForSo2v() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        try await Self.withClient(server) { client in
            try client.selectVfo(true)
            try client.selectVfo(false)
        }
        #expect(server.allCommands == ["V VFOB", "V VFOA"])
    }

    @Test func readWithoutSplit() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        let state = try await Self.withClient(server) { try $0.read() }
        #expect(state.split == false)
        #expect(state.txFreqHz == 0)
        #expect(server.allCommands == ["f", "m", "s"])
    }

    @Test func readWithSplitReportsTxFrequency() async throws {
        let server = try Self.mockServer(split: ["1", "VFOB"])
        defer { server.stop() }
        let state = try await Self.withClient(server) { try $0.read() }
        #expect(state.split)
        #expect(state.txFreqHz == 14_030_000)
    }

    @Test func rigWithoutSplitIsAskedOnlyOnce() async throws {
        let server = try Self.mockServer(split: ["RPRT -11"])
        defer { server.stop() }
        let freqs = try await Self.withClient(server) { client in
            [try client.read().freqHz, try client.read().freqHz]
        }
        #expect(freqs == [14_074_000, 14_074_000])
        #expect(server.allCommands.filter { $0 == "s" }.count == 1)
    }

    @Test func splitOnSetsTxFrequencyAndOffReturnsToVfoA() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        try await Self.withClient(server) { client in
            try client.setSplit(true, txFreqHz: 14_030_000)
            try client.setSplit(true, txFreqHz: 0)
            try client.setSplit(false, txFreqHz: 0)
        }
        #expect(server.allCommands == ["S 1 VFOB", "I 14030000", "S 1 VFOB", "S 0 VFOA"])
    }

    @Test func otherVfoFrequencyIsSetAndVfoARestored() async throws {
        let server = try Self.mockServer()
        defer { server.stop() }
        try await Self.withClient(server) { client in
            try client.setOtherVfoFrequencyHz(7_012_000)
            try client.swapVfo()
        }
        #expect(server.allCommands == ["V VFOB", "F 7012000", "V VFOA", "G XCHG"])
    }
}
