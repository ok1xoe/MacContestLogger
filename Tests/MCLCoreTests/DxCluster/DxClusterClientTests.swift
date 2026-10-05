import Foundation
import os
import Testing
@testable import MCLCore

/// Port of the Java `DxClusterClientTest` (2 tests): a telnet client against a local server stand-in — receiving rows,
/// the format of a sent command (CRLF) and an error when the server ends the connection. The server is always `FakeLineServer`
/// on 127.0.0.1 (never a real DX cluster); the blocking connection runs on its own thread (`onOwnThread`)
/// and rows are awaited without time bounds (`ioSafetyNet` is only a guard).
@Suite(.ioSafetyNet) struct DxClusterClientTests {

    /// Rows and errors from the client's reader thread.
    final class Received: Sendable {
        private let lines = OSAllocatedUnfairLock<[String]>(initialState: [])
        private let errors = OSAllocatedUnfairLock<[any Error]>(initialState: [])

        func line(_ text: String) { lines.withLock { $0.append(text) } }
        func error(_ e: any Error) { errors.withLock { $0.append(e) } }

        var allLines: [String] { lines.withLock { $0 } }
        var allErrors: [any Error] { errors.withLock { $0 } }

        func wait(_ condition: (Received) -> Bool) async throws {
            while !condition(self) {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    static func ascii(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    @Test func receivesLinesSendsCommandAndReportsEof() async throws {
        let echo: [FakeLineServer.Step] = [.bytes(Self.ascii("echo: SH/DX\r\n")), .close]
        // The client sends CRLF, the stand-in splits by `\n` — the command therefore arrives as `SH/DX\r`.
        let server = try FakeLineServer(script: ["SH/DX\r": echo], fallback: [.close],
                                        onConnect: [.bytes(Self.ascii("Welcome to cluster\r\n"))])
        defer { server.stop() }
        let port: Int = server.port
        let received = Received()
        let client: DxClusterClient = try await onOwnThread {
            try DxClusterClient(host: "localhost", port: port,
                                onLine: { received.line($0) }, onError: { received.error($0) })
        }
        try await received.wait { $0.allLines.contains { $0.contains("Welcome") } }
        try await onOwnThread { try client.send("SH/DX") }
        try await received.wait { $0.allLines.contains { $0.hasPrefix("echo:") } }

        #expect(server.commands(0) == ["SH/DX\r"])
        #expect(server.requestBytes(0) == Self.ascii("SH/DX\r\n"))
        #expect(received.allLines.contains("Welcome to cluster"))
        #expect(received.allLines.contains("echo: SH/DX"))

        try await received.wait { !$0.allErrors.isEmpty }
        let error = try #require(received.allErrors.first as? DxClusterException)
        #expect(error.message == "DX cluster ukončil spojení")
        #expect(error.cause == nil)
        // After EOF the client is still "connected" (Java `running` is brought down only by `close`).
        #expect(client.isConnected)

        client.close()
        #expect(!client.isConnected)
    }

    @Test func connectFailureThrows() async throws {
        // A port on which nobody listens (a fast error, not a timeout).
        let freePort: Int = FreeLoopbackPort.take()
        let outcome: Result<DxClusterClient, any Error> = await onOwnThread {
            Result { try DxClusterClient(host: "localhost", port: freePort, timeoutMs: 1000,
                                         onLine: { _ in }, onError: { _ in }) }
        }
        guard case .failure(let failure) = outcome else {
            Issue.record("connecting to a free port should not have succeeded")
            return
        }
        let error = try #require(failure as? DxClusterException)
        #expect(error.message == "Nelze se připojit k DX clusteru na localhost:" + String(freePort))
        let cause = try #require(error.cause as? JavaSocketError)
        #expect(cause.kind == .refused)
    }
}

/// New client tests (Java has none): texts of write and read errors, an error from `onLine`, the encoding of the sent text.
@Suite(.ioSafetyNet) struct DxClusterClientExtraTests {

    typealias Received = DxClusterClientTests.Received

    static func connect(_ server: FakeLineServer, _ received: Received,
                        onLine: (@Sendable (String) throws -> Void)? = nil) async throws -> DxClusterClient {
        let port: Int = server.port
        precondition(port != 4532 && port != 4533, "the test must not touch the shared daemon")
        let handler: @Sendable (String) throws -> Void = onLine ?? { received.line($0) }
        return try await onOwnThread {
            try DxClusterClient(host: "127.0.0.1", port: port, onLine: handler, onError: { received.error($0) })
        }
    }

    @Test func nonAsciiIsSentAsQuestionMarkWithCrlf() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let client = try await Self.connect(server, Received())
        defer { client.close() }
        try await onOwnThread { try client.send("OK1É 😀") }
        while server.requestBytes(0).count < 8 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(server.requestBytes(0) == Array("OK1? ?\r\n".utf8))
    }

    @Test func sendAfterCloseThrowsJavaText() async throws {
        let server = try FakeLineServer(fallback: [.silent])
        defer { server.stop() }
        let client = try await Self.connect(server, Received())
        client.close()
        #expect(!client.isConnected)
        let outcome: Result<Void, any Error> = await onOwnThread { Result { try client.send("SH/DX") } }
        guard case .failure(let failure) = outcome else {
            Issue.record("a write after close should have failed")
            return
        }
        let error = try #require(failure as? DxClusterException)
        #expect(error.message == "Chyba zápisu příkazu 'SH/DX' do DX clusteru")
        #expect((error.cause as? JavaSocketError)?.kind == .closed)
    }

    @Test func errorFromOnLineEndsLoopAndIsReportedAsIs() async throws {
        let server = try FakeLineServer(fallback: [.silent], onConnect: [.line("first"), .line("second")])
        defer { server.stop() }
        let received = Received()
        let client = try await Self.connect(server, received) { line in
            received.line(line)
            throw JavaNumberFormatError(message: "For input string: \"99999999999\"")
        }
        defer { client.close() }
        try await received.wait { !$0.allErrors.isEmpty }
        #expect(received.allLines == ["first"])
        let error = try #require(received.allErrors.first as? JavaNumberFormatError)
        #expect(error.message == "For input string: \"99999999999\"")
        #expect(client.isConnected)
    }

    @Test func connectionResetIsReadError() async throws {
        let server = try FakeLineServer(fallback: [.silent], onConnect: [.reset])
        defer { server.stop() }
        let received = Received()
        let client = try await Self.connect(server, received)
        defer { client.close() }
        try await received.wait { !$0.allErrors.isEmpty }
        let error = try #require(received.allErrors.first as? DxClusterException)
        #expect(error.message == "Chyba čtení z DX clusteru")
        #expect((error.cause as? JavaSocketError)?.kind == .reset)
    }

    @Test func portOutOfRangeIsNotWrapped() async throws {
        let outcome: Result<DxClusterClient, any Error> = await onOwnThread {
            Result { try DxClusterClient(host: "127.0.0.1", port: 70_000, onLine: { _ in }, onError: { _ in }) }
        }
        guard case .failure(let failure) = outcome else {
            Issue.record("a port out of range should have failed")
            return
        }
        #expect((failure as? JavaIllegalArgumentError)?.message == "port out of range:70000")
    }
}
