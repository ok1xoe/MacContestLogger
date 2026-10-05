import Foundation
import Testing
@testable import MCLCore

/// `RotctldClient` conversation with a fake server against the Java maintainer-only probe
/// (rows `rot.*`): the same server scripts (`p` → azimuth + elevation, `P`/`S` → `RPRT 0`, overridden replies by
/// occurrence, the last one repeats, `<CLOSE>` = close), the same actions; the result of each action and the commands
/// the server received are compared. The client timeout is Java's (3,000 ms) — it expires only at a deliberately silent step (`silent`).
@Suite(.ioSafetyNet) struct RotctldClientMeasuredTests {

    typealias Action = @Sendable (RotctldClient) throws -> String

    static func value(_ f: @escaping @Sendable (RotctldClient) throws -> Double) -> Action {
        { client in JavaDouble.toString(try f(client)) }
    }

    static func ok(_ f: @escaping @Sendable (RotctldClient) throws -> Void) -> Action {
        { client in
            try f(client)
            return "ok"
        }
    }

    static let azimuth: Action = value { try $0.azimuth() }

    static func base() -> [String: [String]] {
        ["p": ["123.500000\n0.000000\n"], "P": ["RPRT 0\n"], "S": ["RPRT 0\n"]]
    }

    /// Java `getBytes(ISO_8859_1)`: a unit above U+00FF → `?`.
    static func latin1(_ text: String) -> [UInt8] {
        text.utf16.map { $0 <= 0xFF ? UInt8($0) : 0x3F }
    }

    static func steps(_ answer: String) -> [FakeLineServer.Step] {
        if answer.hasSuffix("<CLOSE>") {
            let head = String(answer.dropLast(7))
            return head.isEmpty ? [.close] : [.bytes(latin1(head)), .close]
        }
        return answer.isEmpty ? [.silent] : [.bytes(latin1(answer))]
    }

    static func scenario(_ name: String, _ overrides: [String: [String]], _ actions: [Action]) async throws {
        let server = try FakeLineServer()
        defer { server.stop() }
        for (key, answers) in base().merging(overrides, uniquingKeysWith: { $1 }) {
            for answer in answers.dropLast() {
                server.enqueue(key, steps(answer))
            }
            server.respond(key, steps(answers[answers.count - 1]))
        }
        let port = server.port
        let results: [String] = try await onOwnThread {
            let client = try RotctldClient(host: "localhost", port: port)
            defer { client.close() }
            return actions.map { action in RadioIoProbe.result { try action(client) } }
        }
        for (i, result) in results.enumerated() {
            #expect(RadioIoProbe.esc(result) == RadioIoProbe.row("rot.\(name).\(i + 1)"), "rot.\(name).\(i + 1)")
        }
        #expect(RadioIoProbe.row("rot.\(name).\(results.count + 1)") == nil, "rot.\(name): more actions in the probe")
        // The server writes the command on receipt; for the last command without a reply (EOF, closed) it may lag behind.
        let sent: String? = RadioIoProbe.row("rot.\(name).sent")
        var waits = 0
        while RadioIoProbe.esc(server.allCommands.joined(separator: "|")) != sent && waits < 500 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waits += 1
        }
        #expect(RadioIoProbe.esc(server.allCommands.joined(separator: "|")) == sent, "rot.\(name).sent")
    }

    @Test func basic() async throws {
        try await Self.scenario("basic", [:], [
            Self.azimuth,
            Self.ok { try $0.turnTo(-30) },
            Self.ok { try $0.stop() },
            Self.ok {
                try $0.turnTo(-0.0)
                try $0.turnTo(.nan)
                try $0.turnTo(359.95)
                try $0.turnTo(12.25)
            },
            Self.ok {
                $0.close()
                $0.close()
            },
            Self.azimuth,
            Self.ok { try $0.turnTo(1) },
        ])
    }

    @Test func numbers() async throws {
        try await Self.scenario("numbers", ["p": [
            " +12.5e1 \r\n0\r\n", "abc\n0\n", "\n0\n", "\u{0661}\u{0662}\n0\n", "NaN\n0\n", "12d\n0\n",
            "\u{E9}12\n0\n", "-0\n0\n", "0x1p3\n0\n", "1e400\n0\n",
        ]], Array(repeating: Self.azimuth, count: 10))
    }

    @Test func rprt() async throws {
        try await Self.scenario("rprt", [
            "p": ["RPRT -1\n", "  RPRT -8\n0\n", "rprt 0\n0\n"],
            "P": ["RPRT -8\n", "  RPRT 0  \n", "RPRT 01\n", "rprt 0\n", "RPRT0\n", "RPRT\n", "\n"],
            "S": ["RPRT -1\n", "RPRT 0 extra\n"],
        ], [
            Self.azimuth, Self.azimuth, Self.azimuth,
            Self.ok { try $0.turnTo(1) }, Self.ok { try $0.turnTo(2) }, Self.ok { try $0.turnTo(3) },
            Self.ok { try $0.turnTo(4) }, Self.ok { try $0.turnTo(5) }, Self.ok { try $0.turnTo(6) },
            Self.ok { try $0.turnTo(7) },
            Self.ok { try $0.stop() }, Self.ok { try $0.stop() },
        ])
    }

    /// `\r` as a terminator; a `\n` at the start of the next reply is skipped.
    @Test func carriageReturn() async throws {
        try await Self.scenario("cr", ["p": ["10.0\r0\r", "\n20.0\r\n0\r\n"]], [Self.azimuth, Self.azimuth])
    }

    @Test func endOfStream() async throws {
        try await Self.scenario("eofAz", ["p": ["<CLOSE>"]], [Self.azimuth])
        try await Self.scenario("eofEl", ["p": ["123\n<CLOSE>"]], [Self.azimuth])
        try await Self.scenario("eofTurn", ["P": ["<CLOSE>"]], [Self.ok { try $0.turnTo(10) }])
        try await Self.scenario("eofStop", ["S": ["<CLOSE>"]], [Self.ok { try $0.stop() }])
    }

    /// Java read timeout 3,000 ms (default, not shortened): a silent `p` → `Read timed out` after ~3 s at the earliest;
    /// a late reply is read as the reply to the next query (without resynchronisation).
    @Test func silentServerTimesOutAfterThreeSeconds() async throws {
        let start = DispatchTime.now()
        try await Self.scenario("silent", ["p": ["", "40\n0\n50\n0\n"]], [
            Self.azimuth,
            { _ in String(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds >= 2_900_000_000) },
            Self.azimuth, Self.azimuth,
        ])
        #expect(RotctldClient.timeoutMs == 3_000)
    }

    @Test func connectErrors() async throws {
        let free = FreeLoopbackPort.take()
        let cases: [(String, String?, Int)] = [
            ("refused", "localhost", free), ("range", "localhost", 70_000), ("rangeNeg", "localhost", -1),
            ("unknownHost", "rot.neexistuje.invalid", 4_600), ("nullHost", nil, free), ("emptyHost", "", free),
        ]
        for (key, host, port) in cases {
            let result: String = await onOwnThread {
                RadioIoProbe.result {
                    let client = try RotctldClient(host: host, port: port)
                    client.close()
                    return "ok"
                }
            }
            let shown = result.replacingOccurrences(of: ":" + String(free), with: ":<port>")
            #expect(RadioIoProbe.esc(shown) == RadioIoProbe.row("rot.connect." + key), "\(key)")
        }
    }
}
