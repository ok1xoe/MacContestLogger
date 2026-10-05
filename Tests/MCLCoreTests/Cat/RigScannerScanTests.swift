import Foundation
import os
import Testing
@testable import MCLCore

/// `RigScanner.scan` over stand-ins: the daemon is `FakeDaemon` (with `-m 9` it ends at once, otherwise it sleeps), the "rig" is
/// `FakeLineServer` on the port that the scan environment assigns to the candidate index. Never a real `rigctld`
/// nor ports 4600+ (Java: `4600 + idx % 50`).
@Suite(.ioSafetyNet) struct RigScannerScanTests {

    final class Recorder: RigScanner.Listener, @unchecked Sendable {
        private let lock = NSLock()
        private var probed: [RigScanner.Candidate] = []
        private let cancelAfter: Int

        init(cancelAfter: Int = Int.max) {
            self.cancelAfter = cancelAfter
        }

        func onProbe(_ candidate: RigScanner.Candidate) {
            lock.lock()
            probed.append(candidate)
            lock.unlock()
        }

        func isCancelled() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return probed.count >= cancelAfter
        }

        var probes: [RigScanner.Candidate] {
            lock.lock()
            defer { lock.unlock() }
            return probed
        }
    }

    static func rig(freq: String) throws -> FakeLineServer {
        try FakeLineServer(lines: ["f": [freq], "m": ["USB", "2400"], "s": ["0", "VFOA"]])
    }

    let dying = RigScanner.Candidate(model: 9, label: "Dying", baud: 4800)
    let low = RigScanner.Candidate(model: 2, label: "Low", baud: 9600)
    let good = RigScanner.Candidate(model: 3, label: "Good", baud: 38400)

    @Test func firstAnsweringCandidateWins() async throws {
        let daemon = try FakeDaemon.sleeper()
        let closedPort = FreeLoopbackPort.take()
        let lowRig = try Self.rig(freq: "1699999")
        let goodRig = try Self.rig(freq: "14074000")
        defer {
            lowRig.stop()
            goodRig.stop()
        }
        let ports = [closedPort, lowRig.port, goodRig.port, closedPort]
        let log = CatTrafficLog(maxLines: 1000)
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let env = RigScanner.Environment(
            makeManager: { RigctldProcessManager(log: log, binary: daemon.path, hooks: hooks) },
            port: { ports[$0] }, log: log, clientTimeoutMs: 10_000)
        let recorder = Recorder()
        let candidates = [dying, low, good, RigScanner.Candidate(model: 4, label: "Never", baud: 1200)]
        let outcome: RigScanner.Outcome? = await onOwnThread {
            RigScanner.scan(device: "/dev/cu.test-scan", candidates: candidates, listener: recorder, environment: env)
        }
        #expect(outcome == RigScanner.Outcome(candidate: good, freqHz: 14_074_000))
        #expect(recorder.probes == [dying, low, good])
        #expect(lowRig.allCommands == ["f", "m", "s"])
        #expect(goodRig.allCommands == ["f", "m", "s"])
        #expect(hooks.count == 0, "no daemon may be running after the scan")
        let lines: [String] = log.snapshot().map { String($0.dropFirst(14)) }
        #expect(lines.contains("\u{00B7} scan: Good @ 38400 baud (port \(goodRig.port))"))
        #expect(lines.contains("\u{00B7} scan: ODPOVĚĎ Good @ 38400 \u{2192} 14074.0 kHz"))
        #expect(lines.contains { $0.hasPrefix("\u{00B7} spouštím: \(daemon.path) -vvv -m 3 -r /dev/cu.test-scan -s 38400 "
            + "--set-conf data_bits=8,stop_bits=1,serial_parity=None,serial_handshake=None -t \(goodRig.port)") })
    }

    @Test func cancelledScanStops() async throws {
        let daemon = try FakeDaemon.sleeper()
        let lowRig = try Self.rig(freq: "470000001")
        defer { lowRig.stop() }
        let port = lowRig.port
        let log = CatTrafficLog(maxLines: 1000)
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let env = RigScanner.Environment(
            makeManager: { RigctldProcessManager(log: log, binary: daemon.path, hooks: hooks) },
            port: { _ in port }, log: log, clientTimeoutMs: 10_000)
        let recorder = Recorder(cancelAfter: 1)
        let candidates = [low, good]
        let outcome: RigScanner.Outcome? = await onOwnThread {
            RigScanner.scan(device: "/dev/cu.test-scan", candidates: candidates, listener: recorder, environment: env)
        }
        #expect(outcome == nil)
        #expect(recorder.probes == [low])
        #expect(hooks.count == 0)
    }

    /// Java scan ports: `4600 + idx % 50`.
    @Test func livePortsMatchJava() {
        #expect(RigScanner.Environment.livePort(0) == 4600)
        #expect(RigScanner.Environment.livePort(49) == 4649)
        #expect(RigScanner.Environment.livePort(50) == 4600)
        #expect(RigScanner.Environment.live.clientTimeoutMs == 600)
    }
}
