import Dispatch
import Foundation
import os
import Testing
@testable import MCLCore

/// Newly written tests of `CatSession` (the core of the Kotlin `ui/cat/CatConnection.kt`; neither Java nor Kotlin has tests).
///
/// Hardware safety: the daemon is always `FakeLineServer` on 127.0.0.1, the process always `FakeDaemon` (or
/// a non-existent binary) with its own `ProcessShutdownHooks` without signals; the connection and the listener check
/// in the tests refuse ports 4532/4533. No fixed time limits: it waits for a state from `onChange`.
@Suite(.ioSafetyNet) struct CatSessionTests {

    /// Recorded session events (shared between the session threads and the test).
    final class Recorder: Sendable {
        private let snapshots = OSAllocatedUnfairLock<[CatSession.Snapshot]>(initialState: [])
        private let connects = OSAllocatedUnfairLock<[String]>(initialState: [])
        private let errors = OSAllocatedUnfairLock<[String]>(initialState: [])
        private let managers = OSAllocatedUnfairLock<[RigctldProcessManager]>(initialState: [])

        func add(_ s: CatSession.Snapshot) { snapshots.withLock { $0.append(s) } }
        func connected(_ host: String, _ port: Int) { connects.withLock { $0.append(host + ":" + String(port)) } }
        func unexpected(_ e: any Error) { errors.withLock { $0.append(String(describing: e)) } }
        func manager(_ m: RigctldProcessManager) { managers.withLock { $0.append(m) } }

        var all: [CatSession.Snapshot] { snapshots.withLock { $0 } }
        var last: CatSession.Snapshot? { all.last }
        var connectCalls: [String] { connects.withLock { $0 } }
        var unexpectedErrors: [String] { errors.withLock { $0 } }
        var processManagers: [RigctldProcessManager] { managers.withLock { $0 } }

        /// Waits (off the pool, `Task.sleep`) until the list of events satisfies the condition; `timeLimit` is only a guard.
        func wait(_ condition: (Recorder) -> Bool) async throws {
            while !condition(self) {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    /// A port the tests must never touch (the user's shared `rigctld`/`rotctld`).
    static func guardPort(_ port: Int) {
        precondition(port != 4532 && port != 4533, "the test must not touch the shared daemon")
    }

    /// Default test timing: fast connection attempts and a poll so long that after the first state the poller sleeps
    /// (a disconnect stops it deterministically in its sleep, not in the middle of a read).
    static let testTiming = CatSession.Timing(pollIntervalMs: 600_000, connectAttempts: 12, connectRetryMs: 1)

    static func makeSession(_ rec: Recorder, log: CatTrafficLog, daemon: String? = nil,
                            timing: CatSession.Timing = testTiming,
                            transverters: [TransverterEntry] = [],
                            translate: @escaping @Sendable (String) -> String = { $0 },
                            connector: (@Sendable (String, Int) throws -> any RigController)? = nil) -> CatSession {
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let binary = daemon ?? "/nonexistent/fake-rigctld"
        let connect: @Sendable (String, Int) throws -> any RigController = connector ?? { host, port in
            try RigctldClient(host: host, port: port, log: log)
        }
        return CatSession(
            transverters: { transverters }, log: log, timing: timing, translate: translate,
            onChange: { rec.add($0) }, onUnexpectedError: { rec.unexpected($0) },
            makeProcessManager: {
                let m = RigctldProcessManager(log: log, binary: binary, hooks: hooks)
                rec.manager(m)
                return m
            },
            connector: { host, port in
                guardPort(port)
                rec.connected(host, port)
                return try connect(host, port)
            },
            isListening: { host, port in
                guardPort(port)
                return RigctldPort.isListening(host: host, port: port)
            })
    }

    static func rigConfig(_ mode: ConnectionMode, port: Int, host: String = "127.0.0.1",
                          label: String = "Test") -> RigConfig {
        var rc = RigConfig()
        rc.mode = mode
        rc.model = 1
        rc.modelLabel = label
        rc.device = ""
        rc.host = host
        rc.port = port
        return rc
    }

    static func server(freq: String = "14025050") throws -> FakeLineServer {
        var script: [String: [String]] = ["f": [freq], "m": ["USB", "2400"], "s": ["0", "VFOA"]]
        for command in ["F", "M", "T"] {
            script[command] = ["RPRT 0"]
        }
        return try FakeLineServer(lines: script)
    }

    static func hasState(_ rec: Recorder) -> Bool {
        rec.last?.state != nil
    }

    // MARK: - Helpers

    @Test func defaultTimingMatchesKotlin() {
        #expect(CatSession.Timing() == CatSession.Timing(pollIntervalMs: 500, connectAttempts: 12, connectRetryMs: 150))
    }

    /// `String.format(Locale.US, "TRX: %.1f kHz  %s", …)` — HALF_UP of the decimal expansion (printf would give 14025.0);
    /// without a mapped mode the raw hamlib mode.
    @Test func formatMatchesJavaStringFormat() {
        let ssb = RigState(freqHz: 14_025_050, mode: .ssb, rawMode: "USB", passband: 2400)
        #expect(CatSession.format(ssb) == "TRX: 14025.1 kHz  SSB")
        let raw = RigState(freqHz: 7_000_000, mode: nil, rawMode: "XYZ", passband: 0)
        #expect(CatSession.format(raw) == "TRX: 7000.0 kHz  XYZ")
    }

    @Test func serialParamsFromConfig() {
        var rc = RigConfig()
        rc.dataBits = 7
        rc.stopBits = 2
        rc.parity = .even
        rc.flowControl = .auto
        rc.rts = .on
        rc.dtr = .unset
        #expect(CatSession.serialParams(of: rc)
            == SerialParams(dataBits: 7, stopBits: 2, parity: "Even", handshake: "", rts: "ON", dtr: "Unset"))
    }

    // MARK: - Connecting

    /// `CONNECT_RUNNING` (a shared daemon under launchd): a single attempt at host:port, nothing is started or adopted;
    /// "Připojeno" comes before the first state; `disconnect(nil)` returns the default text.
    @Test func connectRunningConnectsDirectlyAndPolls() async throws {
        let fake = try Self.server()
        defer { fake.stop() }
        let rec = Recorder()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100))
        session.connect(Self.rigConfig(.connectRunning, port: fake.port))
        try await rec.wait(Self.hasState)
        let first = Array(rec.all.prefix(3))
        let state = RigState(freqHz: 14_025_050, mode: .ssb, rawMode: "USB", passband: 2400)
        #expect(first == [
            CatSession.Snapshot(state: nil, statusMessage: "Připojuji (Test)…", connected: false, connecting: true),
            CatSession.Snapshot(state: nil, statusMessage: "Připojeno (Test)…", connected: true),
            CatSession.Snapshot(state: state, statusMessage: "TRX: 14025.1 kHz  SSB", connected: true),
        ])
        #expect(rec.connectCalls == ["127.0.0.1:\(fake.port)"])
        #expect(rec.processManagers.isEmpty)
        #expect(session.rigOrNull() != nil)

        await onOwnThread { session.disconnect(nil) }
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: nil, connected: false))
        #expect(session.status == "TRX odpojen")
        #expect(session.rigOrNull() == nil)
    }

    /// `LAUNCH_DAEMON` and someone is already listening on the port: adoption — it connects to `localhost`, starts nothing, writes
    /// to the CAT log that the settings from the application do not apply; `toggle` then merely disconnects (the daemon lives on).
    @Test func launchDaemonAdoptsRunningDaemon() async throws {
        let fake = try Self.server()
        defer { fake.stop() }
        let rec = Recorder()
        let log = CatTrafficLog(maxLines: 100)
        let daemon = try FakeDaemon.sleeper()
        let session = Self.makeSession(rec, log: log, daemon: daemon.path)
        let rc = Self.rigConfig(.launchDaemon, port: fake.port)
        session.toggle(rc)
        try await rec.wait(Self.hasState)
        #expect(rec.processManagers.isEmpty, "a running daemon must not be started again")
        #expect(rec.connectCalls == ["localhost:\(fake.port)"])
        let info = "· na portu \(fake.port) už běžel rigctld — připojeno k němu, "
            + "nastavení rigu a sériové linky z aplikace se neuplatní"
        #expect(log.snapshot().contains { $0.hasSuffix(info) })

        await onOwnThread { session.toggle(rc) }
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: nil, connected: false))
        #expect(rec.processManagers.isEmpty)
        // The protection "an adopted daemon is neither started nor killed" is carried by `processManagers.isEmpty` above — the session
        // cannot shut down the `FakeLineServer` stand-in, this only verifies that it keeps listening.
        let port = fake.port
        #expect(await onOwnThread { RigctldPort.isListening(host: "127.0.0.1", port: port) },
                "the daemon stand-in keeps listening")
    }

    /// `LAUNCH_DAEMON` without a listener: starts the daemon (`-vvv -m 1 -t <port>`), tries to connect until
    /// it comes up; `toggle` disconnects and terminates its own daemon.
    @Test func launchDaemonStartsDaemonAndConnectsOnceUp() async throws {
        let fake = try Self.server()
        defer { fake.stop() }
        let port = FreeLoopbackPort.take()
        let rec = Recorder()
        let log = CatTrafficLog(maxLines: 100)
        let daemon = try FakeDaemon.sleeper()
        let failures = OSAllocatedUnfairLock(initialState: 2)
        let session = Self.makeSession(rec, log: log, daemon: daemon.path, connector: { _, _ in
            let fail: Bool = failures.withLock { left in
                defer { left -= 1 }
                return left > 0
            }
            if fail {
                throw CatException("ještě nenaběhl")
            }
            return try RigctldClient(host: "127.0.0.1", port: fake.port, log: log)
        })
        let rc = Self.rigConfig(.launchDaemon, port: port)
        session.toggle(rc)
        try await rec.wait(Self.hasState)
        #expect(rec.connectCalls == Array(repeating: "localhost:\(port)", count: 3))
        #expect(rec.processManagers.count == 1)
        #expect(rec.processManagers.first?.isAlive == true)
        #expect(log.snapshot().contains { $0.hasSuffix("spouštím: \(daemon.path) -vvv -m 1 -t \(port)") })

        await onOwnThread { session.toggle(rc) }
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: nil, connected: false))
        #expect(rec.processManagers.first?.isAlive == false, "its own daemon is terminated on disconnect")
    }

    /// A connection that waits at a barrier when called (the test knows when the connection thread got stuck in an attempt).
    final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private let entered = OSAllocatedUnfairLock(initialState: 0)

        var entries: Int { entered.withLock { $0 } }

        /// Called by the session's connection thread (its own `Thread`, not the pool).
        func pass() {
            entered.withLock { $0 += 1 }
            semaphore.wait()
        }

        /// Opens the barrier for `count` passes.
        func open(_ count: Int = 1) {
            for _ in 0..<count {
                semaphore.signal()
            }
        }
    }

    /// The `toggle` branch `connected || processManager.isAlive`: there is no connection yet, but its own daemon is already running
    /// (the connection thread hangs in an attempt) → `toggle` must disconnect and terminate the daemon, not start a second one.
    @Test func toggleWithRunningDaemonButNoConnectionDisconnectsAndTerminates() async throws {
        let port = FreeLoopbackPort.take()
        let rec = Recorder()
        let daemon = try FakeDaemon.sleeper()
        let gate = Gate()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), daemon: daemon.path,
                                       timing: CatSession.Timing(pollIntervalMs: 600_000, connectAttempts: 2,
                                                                 connectRetryMs: 1),
                                       connector: { _, _ in
                                           gate.pass()
                                           throw CatException("ještě nenaběhl")
                                       })
        let rc = Self.rigConfig(.launchDaemon, port: port)
        session.toggle(rc)
        try await rec.wait { _ in gate.entries == 1 }
        #expect(rec.processManagers.count == 1)
        #expect(rec.processManagers.first?.isAlive == true)
        #expect(rec.last?.connected == false)

        await onOwnThread { session.toggle(rc) }
        #expect(rec.processManagers.count == 1, "toggle while its own daemon is running must not start a second one")
        #expect(rec.processManagers.first?.isAlive == false, "toggle terminates its own daemon")
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: nil, connected: false))

        gate.open(2)
        try await rec.wait { $0.last?.statusMessage?.hasPrefix("Připojení selhalo") == true }
        #expect(rec.last?.statusMessage == "Připojení selhalo: ještě nenaběhl")
        #expect(rec.processManagers.count == 1)
    }

    /// A Kotlin quirk preserved deliberately: `disconnect` during a running `connect` does not cancel it — the attempt
    /// finishes and the session connects after it.
    @Test func disconnectDuringConnectDoesNotCancelItLikeInKotlin() async throws {
        let rec = Recorder()
        let gate = Gate()
        let rig = GatedRig()
        rig.open()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), connector: { _, _ in
            gate.pass()
            return rig
        })
        session.connect(Self.rigConfig(.connectRunning, port: 1))
        try await rec.wait { _ in gate.entries == 1 }
        await onOwnThread { session.disconnect("odpojeno uživatelem") }
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: "odpojeno uživatelem", connected: false))
        gate.open()
        try await rec.wait(Self.hasState)
        #expect(Array(rec.all.map(\.statusMessage).suffix(3)) == [
            "odpojeno uživatelem", "Připojeno (Test)…", "TRX: 7000.0 kHz  CW",
        ])
        #expect(rec.last?.connected == true)
        #expect(session.rigOrNull() != nil)
        await onOwnThread { session.disconnect(nil) }
    }

    /// Beyond Kotlin (quit, rig scan, the LED during „Připojuji…"): `disconnectCancellingConnect` cancels the connect
    /// in flight and returns only after it finished; the stale connect closes its rig and changes nothing.
    @Test func disconnectCancellingConnectCancelsAndWaits() async throws {
        let rec = Recorder()
        let gate = Gate()
        let rig = ClosingRig()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), connector: { _, _ in
            gate.pass()
            return rig
        })
        session.connect(Self.rigConfig(.connectRunning, port: 1))
        try await rec.wait { _ in gate.entries == 1 }
        #expect(session.isConnecting)
        let cancel = Task { await onOwnThread { session.disconnectCancellingConnect("ukončeno") } }
        try await rec.wait { $0.last?.statusMessage == "ukončeno" }
        gate.open()
        await cancel.value
        #expect(!session.isConnecting)
        #expect(rig.closed)
        #expect(session.rigOrNull() == nil)
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: "ukončeno", connected: false))
        #expect(!rec.all.contains { $0.connected })
    }

    /// The connect hook (a PTT release the app still owes the rig) runs with a fresh connection, but never for a
    /// connect cancelled meanwhile: a newer connection may already be up, and a late `T 0` would cut its transmission.
    @Test func theConnectHookSkipsACancelledConnect() async throws {
        let rec = Recorder()
        let gate = Gate()
        let rig = ClosingRig()
        let calls = OSAllocatedUnfairLock<Int>(initialState: 0)
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), connector: { _, _ in
            gate.pass()
            return rig
        })
        session.setOnConnected { _ in
            calls.withLock { $0 += 1 }
        }
        session.connect(Self.rigConfig(.connectRunning, port: 1))
        try await rec.wait { _ in gate.entries == 1 }
        let cancel = Task { await onOwnThread { session.disconnectCancellingConnect("ukončeno") } }
        try await rec.wait { $0.last?.statusMessage == "ukončeno" }
        gate.open()
        await cancel.value
        #expect(rig.closed)
        #expect(calls.withLock { $0 } == 0)
    }

    /// A cancel while the connect is about to start its daemon (held where `pm.start` begins): the stale connect
    /// never launches `rigctld` — no process, no „spouštím" line, the manager never alive.
    @Test func aCancelBeforeTheDaemonStartsLaunchesNothing() async throws {
        let rec = Recorder()
        let gate = Gate()
        let log = CatTrafficLog(maxLines: 100)
        let daemon = try FakeDaemon.sleeper()
        let port = FreeLoopbackPort.take()
        Self.guardPort(port)
        let session = CatSession(
            transverters: { [] }, log: log, timing: Self.testTiming, translate: { $0 },
            onChange: { rec.add($0) }, onUnexpectedError: { rec.unexpected($0) },
            makeProcessManager: {
                let manager = RigctldProcessManager(log: log, binary: daemon.path,
                                                    hooks: ProcessShutdownHooks(installSignalHandlers: false))
                rec.manager(manager)
                gate.pass()
                return manager
            },
            connector: { _, port in
                Self.guardPort(port)
                throw CatException("never reached")
            },
            isListening: { _, port in
                Self.guardPort(port)
                return false
            })
        session.connect(Self.rigConfig(.launchDaemon, port: port))
        try await rec.wait { _ in gate.entries == 1 }
        let cancel = Task { await onOwnThread { session.disconnectCancellingConnect("ukončeno") } }
        try await rec.wait { $0.last?.statusMessage == "ukončeno" }
        gate.open()
        await cancel.value
        #expect(!session.isConnecting)
        #expect(rec.processManagers.count == 1)
        #expect(rec.processManagers.first?.isAlive == false)
        #expect(!log.snapshot().contains { $0.contains("spouštím") })
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: "ukončeno", connected: false))
    }

    /// A rig that records `close()`.
    final class ClosingRig: RigController, @unchecked Sendable {
        private let flag = OSAllocatedUnfairLock(initialState: false)
        var closed: Bool { flag.withLock { $0 } }
        func read() throws -> RigState { RigState(freqHz: 7_000_000, mode: .cw, rawMode: "CW", passband: 500) }
        func setFrequencyHz(_ freqHz: Int64) throws {}
        func setMode(_ mode: Mode?, freqHz: Int64) throws {}
        func setPtt(_ on: Bool) throws {}
        func sendMorse(_ text: String) throws {}
        func stopMorse() throws {}
        func setCwSpeed(_ wpm: Int) throws {}
        func isConnected() -> Bool { !closed }
        func close() { flag.withLock { $0 = true } }
    }

    /// The daemon is started but never comes up: after attempts are exhausted the last connection error, the daemon is terminated.
    @Test func launchDaemonGivesUpAfterAttemptsAndTerminatesDaemon() async throws {
        let port = FreeLoopbackPort.take()
        let rec = Recorder()
        let daemon = try FakeDaemon.sleeper()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), daemon: daemon.path,
                                       timing: CatSession.Timing(pollIntervalMs: 600_000, connectAttempts: 3,
                                                                 connectRetryMs: 1))
        session.connect(Self.rigConfig(.launchDaemon, port: port))
        try await rec.wait { $0.all.count >= 2 }
        #expect(rec.last == CatSession.Snapshot(
            state: nil, statusMessage: "Připojení selhalo: Nelze se připojit k rigctld na localhost:\(port)",
            connected: false))
        #expect(rec.connectCalls == Array(repeating: "localhost:\(port)", count: 3))
        #expect(rec.processManagers.count == 1)
        #expect(rec.processManagers.first?.isAlive == false)
        #expect(session.rigOrNull() == nil)
    }

    /// Kotlin `throw last ?: CatException("Nelze se připojit k rigctld")` — with zero attempts.
    @Test func zeroAttemptsReportCannotConnect() async throws {
        let fake = try Self.server()
        defer { fake.stop() }
        let rec = Recorder()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100),
                                       timing: CatSession.Timing(pollIntervalMs: 600_000, connectAttempts: 0,
                                                                 connectRetryMs: 1))
        session.connect(Self.rigConfig(.launchDaemon, port: fake.port))
        try await rec.wait { $0.all.count >= 2 }
        #expect(rec.last?.statusMessage == "Připojení selhalo: Nelze se připojit k rigctld")
        #expect(rec.connectCalls.isEmpty)
    }

    /// Starting the daemon fails (`CatException` from `start`) → a message with the command line, no connection is made.
    @Test func daemonStartFailure() async throws {
        let port = FreeLoopbackPort.take()
        let rec = Recorder()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100))
        session.connect(Self.rigConfig(.launchDaemon, port: port))
        try await rec.wait { $0.all.count >= 2 }
        #expect(rec.last == CatSession.Snapshot(
            state: nil, statusMessage: "Připojení selhalo: Nelze spustit rigctld: /nonexistent/fake-rigctld -vvv -m 1 -t \(port)",
            connected: false))
        #expect(rec.connectCalls.isEmpty)
        #expect(rec.processManagers.count == 1)
    }

    /// The first poll error → "Spojení s rigem ztraceno", state gone, no reconnect.
    @Test func pollErrorDisconnectsWithoutReconnect() async throws {
        let fake = try FakeLineServer(lines: ["f": ["close"], "m": ["USB", "2400"], "s": ["0", "VFOA"]])
        defer { fake.stop() }
        fake.enqueue("f", [.line("14025050")])
        let rec = Recorder()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100),
                                       timing: CatSession.Timing(pollIntervalMs: 1, connectAttempts: 12, connectRetryMs: 1))
        session.connect(Self.rigConfig(.connectRunning, port: fake.port))
        try await rec.wait { $0.all.contains { $0.statusMessage == "Spojení s rigem ztraceno" } }
        #expect(rec.all.map(\.statusMessage) == [
            "Připojuji (Test)…", "Připojeno (Test)…", "TRX: 14025.1 kHz  SSB", "Spojení s rigem ztraceno",
        ])
        #expect(rec.last == CatSession.Snapshot(state: nil, statusMessage: "Spojení s rigem ztraceno", connected: false))
        #expect(rec.connectCalls.count == 1)
        #expect(session.rigOrNull() == nil)
    }

    /// The Configurer pattern (`ConfigurerDraft`): `disconnect("překonfigurováno")` + `connect` with new settings.
    @Test func reconfigurationDisconnectsAndConnectsWithNewSettings() async throws {
        let first = try Self.server(freq: "7010000")
        let second = try Self.server(freq: "3510000")
        defer {
            first.stop()
            second.stop()
        }
        let rec = Recorder()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100))
        session.connect(Self.rigConfig(.connectRunning, port: first.port, label: "A"))
        try await rec.wait(Self.hasState)
        await onOwnThread {
            session.disconnect("překonfigurováno")
            session.connect(Self.rigConfig(.connectRunning, port: second.port, label: "B"))
        }
        try await rec.wait { $0.last?.state?.freqHz == 3_510_000 }
        let messages = rec.all.map(\.statusMessage)
        let i = try #require(messages.firstIndex(of: "překonfigurováno"))
        #expect(Array(messages[i...].prefix(4)) == [
            "překonfigurováno", "Připojuji (B)…", "Připojeno (B)…", "TRX: 3510.0 kHz  SSB",
        ])
        #expect(rec.connectCalls == ["127.0.0.1:\(first.port)", "127.0.0.1:\(second.port)"])
        await onOwnThread { session.disconnect(nil) }
    }

    /// Without a connection `tune`/`setPtt`/`setMode` do nothing; with a connection they go through `TransverterRig`
    /// (frequency in the transverter band → IF, reading the IF → real frequency).
    @Test func rigControlDoesNothingWithoutConnectionAndUsesTransverterWithIt() async throws {
        let fake = try Self.server(freq: "28300000")
        defer { fake.stop() }
        let rec = Recorder()
        let xvtr = TransverterEntry(name: "2m", ifLowKHz: 28_000, ifHighKHz: 30_000, offsetKHz: 116_000, enabled: true)
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), transverters: [xvtr])
        try await onOwnThread {
            try session.tune(144_300_000)
            try session.setPtt(true)
            try session.setMode(.cw, freqHz: 144_300_000)
        }
        session.connect(Self.rigConfig(.connectRunning, port: fake.port))
        try await rec.wait(Self.hasState)
        #expect(rec.last?.statusMessage == "TRX: 144300.0 kHz  SSB")
        try await onOwnThread {
            try session.tune(144_300_000)
            try session.setMode(.ssb, freqHz: 144_300_000)
            try session.setPtt(true)
        }
        let commands = fake.allCommands
        #expect(commands.contains("F 28300000"))
        #expect(commands.contains("M USB 0"))
        #expect(commands.contains("T 1"))
        await onOwnThread { session.disconnect(nil) }
    }

    /// A rig whose first `read()` waits at a barrier (the test knows when the poller got stuck in a read).
    final class GatedRig: RigController, @unchecked Sendable {
        private let gate = DispatchSemaphore(value: 0)
        private let entered = OSAllocatedUnfairLock(initialState: false)

        var isReading: Bool { entered.withLock { $0 } }

        func open() { gate.signal() }

        func read() throws -> RigState {
            entered.withLock { $0 = true }
            gate.wait()
            return RigState(freqHz: 7_000_000, mode: .cw, rawMode: "CW", passband: 500)
        }

        func setFrequencyHz(_ freqHz: Int64) throws {}
        func setMode(_ mode: Mode?, freqHz: Int64) throws {}
        func setPtt(_ on: Bool) throws {}
        func sendMorse(_ text: String) throws {}
        func stopMorse() throws {}
        func setCwSpeed(_ wpm: Int) throws {}
        func isConnected() -> Bool { true }
        func close() {}
    }

    /// A Kotlin quirk preserved deliberately: a read that was running at `disconnect` is read to the end and its state
    /// is written (the poller stops, but the callback sets the state regardless of the disconnect).
    @Test func stateFromReadFinishedAfterDisconnectIsWrittenLikeInKotlin() async throws {
        let rig = GatedRig()
        let rec = Recorder()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), connector: { _, _ in rig })
        session.connect(Self.rigConfig(.connectRunning, port: 1))
        try await rec.wait { _ in rig.isReading }
        try await rec.wait { $0.last?.connected == true }
        await onOwnThread { session.disconnect(nil) }
        rig.open()
        try await rec.wait { $0.last?.state != nil }
        let state = RigState(freqHz: 7_000_000, mode: .cw, rawMode: "CW", passband: 500)
        #expect(rec.last == CatSession.Snapshot(state: state, statusMessage: "TRX: 7000.0 kHz  CW", connected: false))
        #expect(session.rigOrNull() == nil)
    }

    /// An error other than `CatException` (port out of range) is not caught by Kotlin: it goes to `onUnexpectedError` and the state
    /// stays "Připojuji…".
    @Test func unexpectedErrorIsNotCaughtLikeInKotlin() async throws {
        let rec = Recorder()
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100))
        session.connect(Self.rigConfig(.connectRunning, port: 70_000))
        try await rec.wait { !$0.unexpectedErrors.isEmpty }
        #expect(rec.unexpectedErrors.count == 1)
        #expect(rec.unexpectedErrors.first?.contains("port out of range:70000") == true)
        #expect(rec.all == [CatSession.Snapshot(state: nil, statusMessage: "Připojuji (Test)…", connected: false, connecting: true)])
    }

    /// Keys are translated (`tr`); a translation with an invalid pattern does not crash — the Czech key is used.
    @Test func statusTextTranslation() async throws {
        let fake = try Self.server()
        defer { fake.stop() }
        let rec = Recorder()
        let translations: [String: String] = ["Připojuji (%s)…": "Connecting (%s)…", "Připojeno (%s)…": "Connected (%d)"]
        let session = Self.makeSession(rec, log: CatTrafficLog(maxLines: 100), translate: { translations[$0] ?? $0 })
        session.connect(Self.rigConfig(.connectRunning, port: fake.port))
        try await rec.wait(Self.hasState)
        #expect(rec.all.prefix(2).map(\.statusMessage) == ["Connecting (Test)…", "Připojeno (Test)…"])
        await onOwnThread { session.disconnect(nil) }
    }
}
