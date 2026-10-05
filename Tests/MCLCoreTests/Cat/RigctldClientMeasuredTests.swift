import Darwin
import Foundation
import os
import Testing
@testable import MCLCore

/// `RigctldClient` conversation with a fake server against the Java maintainer-only probe
/// (`out-en_US.tsv` → `RigctldProbeRows`): same server scripts, same client actions; the result of
/// each action is compared (`RigState[...]`, `ok`, `EXC class: message <- cause`), the commands the server received, and the rows of
/// the CAT log without time. The client timeout is generous (2,000 ms — in Java and here; the exception text does not depend on it):
/// it expires only at a deliberately silent server step, successful reads under load do not fail.
@Suite(.ioSafetyNet) struct RigctldClientMeasuredTests {

    typealias Action = @Sendable (RigctldClient) throws -> String

    // MARK: - Probe format

    static func esc(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            if unit >= 0x20 && unit < 0x7F && unit != 0x5C {
                out += String(UnicodeScalar(UInt8(unit)))
            } else {
                out += "\\u" + String(format: "%04X", Int(unit))
            }
        }
        return out
    }

    static func format(_ s: RigState) -> String {
        "RigState[freqHz=\(s.freqHz), mode=\(s.mode?.rawValue ?? "null"), rawMode=\(s.rawMode), "
            + "passband=\(s.passband), split=\(s.split), txFreqHz=\(s.txFreqHz)]"
    }

    static func exc(_ error: any Error) -> String {
        switch error {
        case let e as CatException:
            var text = "EXC CatException: " + e.message
            if let cause = e.cause {
                text += " <- " + String(describing: cause)
            }
            return text
        case let e as JavaIllegalArgumentError:
            return "EXC IllegalArgumentException: " + e.message
        case let e as UncheckedIOError:
            // The cause is the Java `FileAlreadyExistsException`, here a POSIX error — only the message is compared.
            return "EXC UncheckedIOException: " + e.message
        default:
            return "EXC " + String(describing: error)
        }
    }

    static func state(_ f: @escaping @Sendable (RigctldClient) throws -> RigState) -> Action {
        { client in format(try f(client)) }
    }

    static func ok(_ f: @escaping @Sendable (RigctldClient) throws -> Void) -> Action {
        { client in
            try f(client)
            return "ok"
        }
    }

    static func row(_ key: String) -> String? {
        RigctldProbeRows.rows[key]
    }

    // MARK: - Server script (Java `base()` + `with(...)`)

    static func base() -> [String: [String]] {
        var m: [String: [String]] = [
            "f": ["14074000\n"], "m": ["USB\n2400\n"], "s": ["0\nVFOA\n"], "i": ["14030000\n"],
        ]
        for k in ["F", "M", "S", "I", "V", "G", "J", "U", "Y", "T", "b", "\\stop_morse", "L"] {
            m[k] = ["RPRT 0\n"]
        }
        return m
    }

    /// Java `getBytes(ISO_8859_1)`: a unit above U+00FF → `?`.
    static func latin1(_ text: String) -> [UInt8] {
        text.utf16.map { $0 <= 0xFF ? UInt8($0) : 0x3F }
    }

    static func steps(_ answer: String) -> [FakeLineServer.Step] {
        if answer.hasSuffix("<CLOSE>") {
            return [.bytes(latin1(String(answer.dropLast(7)))), .close]
        }
        return answer.isEmpty ? [.silent] : [.bytes(latin1(answer))]
    }

    /// Replies per occurrence, the last one repeats (one-shot `enqueue` + permanent `respond`).
    static func server(_ overrides: [String: [String]]) throws -> FakeLineServer {
        let server = try FakeLineServer()
        for (key, answers) in base().merging(overrides, uniquingKeysWith: { $1 }) {
            for answer in answers.dropLast() {
                server.enqueue(key, steps(answer))
            }
            server.respond(key, steps(answers[answers.count - 1]))
        }
        return server
    }

    /// One probe scenario: actions `name.1…`, `name.sent`, `name.log`.
    static func scenario(_ name: String, _ overrides: [String: [String]], timeoutMs: Int,
                         modes: @escaping HamlibModeProvider = { .default },
                         _ actions: [Action]) async throws {
        try await scenario(name, overrides, timeoutMs: timeoutMs, modes: modes, actionsFor: { _ in actions })
    }

    /// The same with actions that know the server port.
    static func scenario(_ name: String, _ overrides: [String: [String]], timeoutMs: Int,
                         modes: @escaping HamlibModeProvider = { .default },
                         actionsFor: (Int) -> [Action]) async throws {
        let server = try server(overrides)
        defer { server.stop() }
        let port = server.port
        let actions: [Action] = actionsFor(port)
        let log = CatTrafficLog(maxLines: 1000)
        let results: [String] = try await onOwnThread {
            let client = try RigctldClient(host: "localhost", port: port, timeoutMs: timeoutMs, modes: modes, log: log)
            defer { client.close() }
            return actions.map { action in
                do {
                    return try action(client)
                } catch {
                    return exc(error)
                }
            }
        }
        for (i, result) in results.enumerated() {
            let key: String = "\(name).\(i + 1)"
            let got: String = esc(result)
            if let alternative = Self.racyAlternatives[key], got == alternative {
                continue
            }
            #expect(got == row(key), "\(key)")
        }
        // The server writes the command on receipt; the client could read the last reply from earlier bytes before the
        // server processed the next command (the Java probe waits 100 ms) — wait until the server catches up with the probe.
        let sent: String? = row("\(name).sent")
        var waits = 0
        while esc(server.allCommands.joined(separator: "|")) != sent && waits < 500 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waits += 1
        }
        #expect(esc(server.allCommands.joined(separator: "|")) == sent, "\(name).sent")
        let lines: [String] = log.snapshot().map { String($0.dropFirst(14)) }
        #expect(esc(lines.joined(separator: "|")) == row("\(name).log"), "\(name).log")
    }

    // MARK: - Scenarios

    @Test func basic() async throws {
        try await Self.scenario("basic", [:], timeoutMs: 2000, [
            Self.state { try $0.read() },
            Self.ok { try $0.setFrequencyHz(14_200_000) },
            Self.ok { try $0.setMode(.ssb, freqHz: 7_000_000) },
            Self.ok { try $0.setMode(.ssb, freqHz: 10_000_000) },
            Self.ok { try $0.setMode(nil, freqHz: 7_000_000) },
            Self.ok { try $0.setPtt(true); try $0.setPtt(false) },
            Self.ok { try $0.sendMorse("CQ TEST \u{017E}\u{1F600} 5NN") },
            Self.ok { try $0.stopMorse(); try $0.setCwSpeed(28); try $0.setAntenna(2) },
            Self.ok { try $0.selectVfo(true); try $0.selectVfo(false); try $0.swapVfo() },
            Self.ok { try $0.setRit(-50); try $0.setRit(0) },
            { client in String(client.isConnected()) },
            { client in
                client.close()
                return String(client.isConnected())
            },
            Self.state { try $0.read() },
            Self.ok { try $0.setFrequencyHz(1) },
        ])
    }

    @Test func numbers() async throws {
        try await Self.scenario("numbers", [
            "f": ["+14074000\n", " \t7012000 \n", "\u{0661}\u{0664}\n", "14.074e6\n", "9223372036854775808\n"],
            "m": [" pktusb \r\nabc\r", "\nRTTY\r\n+300\n"],
            "s": ["1\r\nVFOB\r\n", " 1 \nVFOB\n", "01\nVFOB\n"],
            "i": ["RPRT -9\n", "7015000\n", "x\n"],
        ], timeoutMs: 2000, Array(repeating: Self.state { try $0.read() }, count: 5))
    }

    /// The mode mapping is read on every call (Java `static volatile` state of `HamlibModes`).
    @Test func modes() async throws {
        let mapping = OSAllocatedUnfairLock(initialState: HamlibModeMapping.default)
        try await Self.scenario("modes", ["m": ["PKTUSB\n500\n"]], timeoutMs: 2000, modes: { mapping.withLock { $0 } }, [
            Self.state { client in
                mapping.withLock { $0 = HamlibModeMapping(dataMode: .ft8, rttyAfsk: true) }
                return try client.read()
            },
            Self.ok { try $0.setMode(.rtty, freqHz: 14_080_000); try $0.setMode(.ft4, freqHz: 14_080_000) },
            Self.state { client in
                mapping.withLock { $0 = HamlibModeMapping(dataMode: .ssb, rttyAfsk: false) }
                return try client.read()
            },
            Self.ok { try $0.setMode(.rtty, freqHz: 14_080_000) },
        ])
    }

    @Test func splitUnsupported() async throws {
        try await Self.scenario("splitUnsupported", ["s": ["RPRT -11\n", "RPRT -11\n", "0\nVFOA\n"]], timeoutMs: 2000, [
            Self.state { try $0.read() },
            Self.state { try $0.read() },
            Self.ok { try $0.setSplit(true, txFreqHz: 14_030_000) },
            Self.state { try $0.read() },
            Self.state { try $0.read() },
            Self.ok { try $0.setSplit(true, txFreqHz: 0); try $0.setSplit(false, txFreqHz: 0); try $0.setSplit(true, txFreqHz: -5) },
        ])
    }

    @Test func splitTx() async throws {
        try await Self.scenario("splitTx", ["s": ["RPRTX\n", "1\nVFOB\n"], "i": ["RPRT -1\n", "RPRT0\n"]], timeoutMs: 2000,
                                Array(repeating: Self.state { try $0.read() }, count: 3))
    }

    @Test func rprt() async throws {
        let answers = ["RPRT 0x\n", "  RPRT 0  \n", "RPRT 01\n", "rprt 0\n", "RPRT -1\n", "RPRT  0\n", "RPRT\n"]
        let actions: [Action] = (1...7).map { n in Self.ok { try $0.setFrequencyHz(Int64(n)) } }
        try await Self.scenario("rprt", ["F": answers], timeoutMs: 2000, actions)
    }

    @Test func setRejected() async throws {
        try await Self.scenario("setRejected", [
            "S": ["RPRT -1\n"], "I": ["RPRT -9\n"], "T": ["RPRT -1\n"], "b": ["RPRT -1\n"],
            "\\stop_morse": ["RPRT -11\n"], "L": ["RPRT -1\n"], "Y": ["RPRT -1\n"], "G": ["RPRT -1\n"],
            "M": ["RPRT -1\n"], "J": ["RPRT -1\n"],
        ], timeoutMs: 2000, [
            Self.ok { try $0.setSplit(true, txFreqHz: 1) }, Self.ok { try $0.setSplit(false, txFreqHz: 1) },
            Self.ok { try $0.setPtt(true) }, Self.ok { try $0.setPtt(false) },
            Self.ok { try $0.sendMorse("CQ") }, Self.ok { try $0.stopMorse() },
            Self.ok { try $0.setCwSpeed(30) }, Self.ok { try $0.setAntenna(9) },
            Self.ok { try $0.swapVfo() }, Self.ok { try $0.setMode(.cw, freqHz: 1) },
            Self.ok { try $0.setRit(10) }, Self.ok { try $0.selectVfo(true) },
        ])
    }

    @Test func splitTxRejected() async throws {
        try await Self.scenario("splitTxRejected", ["I": ["RPRT -9\n"]], timeoutMs: 2000, [
            Self.ok { try $0.setSplit(true, txFreqHz: 14_030_000) },
        ])
    }

    /// `finally` in `setOtherVfoFrequencyHz`: return to VFO A even after `F` is rejected; if the return fails too, its
    /// error comes out (Java `finally` overrides the exception from `try`).
    @Test func otherVfo() async throws {
        try await Self.scenario("otherVfo", [
            "V": ["RPRT 0\n", "RPRT 0\n", "RPRT -1\n", "RPRT 0\n", "RPRT -2\n", "RPRT -3\n"],
            "F": ["RPRT 0\n", "RPRT -1\n", "RPRT -4\n"],
        ], timeoutMs: 2000, [
            Self.ok { try $0.setOtherVfoFrequencyHz(7_012_000) },
            Self.ok { try $0.setOtherVfoFrequencyHz(7_013_000) },
            Self.ok { try $0.setOtherVfoFrequencyHz(7_014_000) },
            Self.ok { try $0.setOtherVfoFrequencyHz(7_015_000) },
        ])
    }

    @Test func otherVfoFirstRejected() async throws {
        try await Self.scenario("otherVfoFirstRejected", ["V": ["RPRT -1\n"]], timeoutMs: 2000, [
            Self.ok { try $0.setOtherVfoFrequencyHz(7_012_000) },
        ])
    }

    /// EOF in the middle of a reply = `CatException("rigctld ukončil spojení")`, not an empty string.
    @Test func eofMid() async throws {
        let socketFd = OSAllocatedUnfairLock<Int32?>(initialState: nil)
        try await Self.scenario("eofMid", ["m": ["USB\n<CLOSE>"]], timeoutMs: 2000) { port in [
            Self.state { try $0.read() },
            { client in String(client.isConnected()) },
            { client in
                // Find the client descriptor while it is connected (after RST `getpeername` fails); falsification
                // of the wait below: after FIN alone the state is `CLOSE_WAIT`, not `CLOSED`.
                let fd: Int32? = Self.clientFd(serverPort: port)
                socketFd.withLock { $0 = fd }
                guard let fd, Self.tcpState(fd) == Self.tcpsCloseWait else {
                    return "waiting for CLOSE_WAIT after FIN"
                }
                return Self.format(try client.read())
            },
            // The peer's RST for the write from `.3` arrives asynchronously (Java caught it thanks to its own overhead) — wait
            // until the client socket processes it (TCP state `CLOSED`), then `Broken pipe`.
            { client in
                guard let fd = socketFd.withLock({ $0 }), Self.waitForPeerReset(fd) else {
                    return "RST nedorazil do 10 s"
                }
                return Self.format(try client.read())
            },
            Self.ok { try $0.setFrequencyHz(1) },
        ] }
    }

    /// Steps whose result depends on TCP races, not on client code — besides the Java probe row,
    /// this second variant, which Java also yields under different timing, is valid too.
    ///
    /// `eofMid.3`: the client writes `f` into a connection the server has already closed and reads immediately. Whether the read sees the end
    /// of stream (probe: "rigctld ukončil spojení") or already the peer's RST for that write (`Connection reset`)
    /// depends only on whether the RST arrives before `read`. Under CI load (3 vCPU) it arrived earlier.
    static let racyAlternatives: [String: String] = [
        "eofMid.3": "EXC CatException: Chyba \\u010Dten\\u00ED odpov\\u011Bdi z rigctld <- java.net.SocketException: Connection reset",
    ]

    /// `TCPS_CLOSED` / `TCPS_CLOSE_WAIT` (`netinet/tcp_fsm.h`).
    static let tcpsClosed: UInt8 = 0
    static let tcpsCloseWait: UInt8 = 5

    /// Descriptor of this process's socket connected to `127.0.0.1:serverPort` (client `RigctldClient`; test only).
    static func clientFd(serverPort: Int) -> Int32? {
        for fd in Int32(0)..<Int32(getdtablesize()) {
            var addr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let rc: Int32 = withUnsafeMutablePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &len) }
            }
            if rc == 0 && addr.sin_family == sa_family_t(AF_INET) && Int(UInt16(bigEndian: addr.sin_port)) == serverPort {
                return fd
            }
        }
        return nil
    }

    /// TCP state of the socket (`TCP_CONNECTION_INFO`); on macOS `POLLHUP` comes already with FIN, hence the state.
    static func tcpState(_ fd: Int32) -> UInt8? {
        var info = tcp_connection_info()
        var len = socklen_t(MemoryLayout<tcp_connection_info>.size)
        guard getsockopt(fd, IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &len) == 0 else { return nil }
        return info.tcpi_state
    }

    static func waitForPeerReset(_ fd: Int32) -> Bool {
        for _ in 0..<1000 {
            if tcpState(fd) == tcpsClosed {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    @Test func eofSplit() async throws {
        try await Self.scenario("eofSplit", ["s": ["1\n<CLOSE>"]], timeoutMs: 2000, [Self.state { try $0.read() }])
    }

    /// After a timeout the client does not resynchronise: a late line is read as the reply to the next command (R7).
    @Test func desync() async throws {
        try await Self.scenario("desync", ["m": ["USB\n", "USB\n2400\n"], "f": ["14074000\n", "2400\n14074000\n"]],
                                timeoutMs: 2000, [
            Self.state { try $0.read() },
            Self.state { try $0.read() },
            Self.state { try $0.read() },
            { client in String(client.isConnected()) },
        ])
    }

    @Test func mRprt() async throws {
        try await Self.scenario("mRprt", ["m": ["RPRT -11\n"]], timeoutMs: 2000,
                                [Self.state { try $0.read() }, Self.state { try $0.read() }])
    }

    @Test func ritSilent() async throws {
        try await Self.scenario("ritSilent", ["U": [""]], timeoutMs: 2000,
                                [Self.ok { try $0.setRit(5) }, Self.state { try $0.read() }])
    }

    @Test func crSplit() async throws {
        try await Self.scenario("crSplit", ["f": ["14074000\r", "\n7000000\n"], "m": ["USB\r\n2400\r", "\nCW\n100\n"]],
                                timeoutMs: 2000, [Self.state { try $0.read() }, Self.state { try $0.read() }])
    }

    @Test func bytes() async throws {
        try await Self.scenario("bytes", ["f": ["\u{01}\u{E9}14074000\u{00}\n"], "m": ["\u{FC}SB\u{07}\n\u{0B}2400\u{1F}\n"]],
                                timeoutMs: 2000, [Self.state { try $0.read() }])
    }

    /// A CAT log file error propagates out (`UncheckedIOError`) — the command has already gone out, though, and further
    /// reads are desynchronised as in Java.
    @Test func logFails() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rigctld-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let server = try Self.server([:])
        defer { server.stop() }
        let port = server.port
        let log = CatTrafficLog(maxLines: 1000)
        let results: [String] = try await onOwnThread {
            let client = try RigctldClient(host: "localhost", port: port, timeoutMs: 2000, log: log)
            defer { client.close() }
            func run() -> String {
                do {
                    return Self.format(try client.read())
                } catch {
                    return Self.exc(error)
                }
            }
            log.setFile(blocker.appendingPathComponent("cat.log"))
            let first = run()
            log.setFile(nil)
            return [first, run(), run()]
        }
        let first = results[0].replacingOccurrences(of: dir.path, with: "<dir>")
        let expected = try #require(Self.row("logFails.1")?.components(separatedBy: " <- ").first)
        #expect(Self.esc(first) == expected)
        #expect(Self.esc(results[1]) == Self.row("logFails.2"))
        #expect(Self.esc(results[2]) == Self.row("logFails.3"))
        #expect(Self.esc(server.allCommands.joined(separator: "|")) == Self.row("logFails.sent"))
        let lines: [String] = log.snapshot().map { String($0.dropFirst(14)) }
        #expect(Self.esc(lines.joined(separator: "|")) == Self.row("logFails.log"))
    }

    /// Connection errors: refused and unknown host → `CatException` with a cause, `IllegalArgumentException`
    /// (port out of range, negative timeout, `nil` host) passes through unchanged.
    @Test func connect() async throws {
        let free = FreeLoopbackPort.take()
        let cases: [(String, String?, Int, Int)] = [
            ("refused", "localhost", free, 2000), ("range", "localhost", 70_000, 2000),
            ("rangeNeg", "localhost", -1, 2000), ("timeoutNeg", "localhost", free, -1),
            ("unknownHost", "rig.neexistuje.invalid", 4600, 2000), ("nullHost", nil, free, 2000),
        ]
        for (key, host, port, timeout) in cases {
            let result: String = await onOwnThread {
                do {
                    let client = try RigctldClient(host: host, port: port, timeoutMs: timeout, log: CatTrafficLog(maxLines: 10))
                    client.close()
                    return "ok"
                } catch {
                    return Self.exc(error)
                }
            }
            #expect(Self.esc(result.replacingOccurrences(of: ":\(free)", with: ":<port>")) == Self.row("connect.\(key)"), "\(key)")
        }
    }

    // MARK: - Concurrency (Java `synchronized`)

    /// A poll does not wedge in between `V VFOB` / `F` / `V VFOA` — the lock holds the whole sequence.
    @Test func otherVfoSequenceIsAtomicAgainstConcurrentRead() async throws {
        let server = try Self.server([:])
        defer { server.stop() }
        let client: RigctldClient = try await onOwnThread {
            try RigctldClient(host: "localhost", port: server.port, log: CatTrafficLog(maxLines: 10))
        }
        defer { client.close() }
        async let reads: Int = onOwnThread("poll") {
            for _ in 0..<40 { _ = try client.read() }
            return 40
        }
        async let sets: Int = onOwnThread("ui") {
            for n in 0..<40 { try client.setOtherVfoFrequencyHz(7_000_000 + Int64(n)) }
            return 40
        }
        let done: Int = try await reads + sets
        #expect(done == 80)
        let commands: [String] = server.allCommands
        let expectedCount: Int = 240 // 40 × (f, m, s) + 40 × (V VFOB, F, V VFOA)
        #expect(commands.count == expectedCount)
        for (i, command) in commands.enumerated() where command == "V VFOB" {
            let next: [String] = Array(commands[(i + 1)..<min(i + 3, commands.count)])
            #expect(next.count == 2 && next[0].hasPrefix("F ") && next[1] == "V VFOA", "\(commands)")
        }
    }

    /// `close` from another thread while waiting for a reply: the read ends with `CatException` with cause `Socket closed`
    /// (Java `SocketException` from `BufferedReader`), `isConnected` is `false`.
    @Test func closeFromAnotherThreadEndsBlockedRead() async throws {
        let server = try Self.server(["f": [""]])
        defer { server.stop() }
        let client: RigctldClient = try await onOwnThread {
            try RigctldClient(host: "localhost", port: server.port, timeoutMs: 0, log: CatTrafficLog(maxLines: 10))
        }
        async let result: String = onOwnThread("poll") {
            do {
                return Self.format(try client.read())
            } catch {
                return Self.exc(error)
            }
        }
        // Bounded: if the command never arrives, record an issue and close anyway (the close ends the blocked read).
        let deadline = ContinuousClock.now + .seconds(10)
        while server.allCommands.isEmpty {
            if ContinuousClock.now >= deadline {
                Issue.record("The poll command never reached the server within 10 s")
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        client.close()
        #expect(await result == "EXC CatException: Chyba čtení odpovědi z rigctld <- java.net.SocketException: Socket closed")
        #expect(client.isConnected() == false)
    }
}
