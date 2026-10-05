import Foundation
import os
import Testing
@testable import MCLCore

/// Port of `cat/RigctldProcessManagerTest` (3 tests; processes only `/bin/sleep` and `/usr/bin/true`) + launch
/// over a harmless stand-in binary (`FakeDaemon`, never a real `rigctld`) and a shutdown-hook stand-in
/// over its own `ProcessShutdownHooks` instance without signal handling.
@Suite(.ioSafetyNet) struct RigctldProcessManagerTests {

    @Test func terminateStopsRunningProcess() async throws {
        let alive: Bool = try await onOwnThread {
            let p = ProcessRunner(executable: "/bin/sleep", arguments: ["30"]) { _ in }
            try p.start()
            RigctldProcessManager.terminate(p)
            return p.isAlive
        }
        #expect(alive == false, "no running daemon must be left behind")
    }

    @Test func terminateToleratesFinishedProcessAndNil() async throws {
        try await onOwnThread {
            let p = ProcessRunner(executable: "/usr/bin/true", arguments: []) { _ in }
            try p.start()
            p.waitForExit(timeoutMs: 10_000)
            RigctldProcessManager.terminate(p)
            RigctldProcessManager.terminate(nil)
        }
    }

    @Test func bareDeviceNameGetsDevPrefix() {
        // rigctld without a slash treats the string as a network address, not a serial port.
        #expect(RigctldProcessManager.normalizeDevice("cu.usbserial-X") == "/dev/cu.usbserial-X")
        #expect(RigctldProcessManager.normalizeDevice("/dev/cu.usbserial-X") == "/dev/cu.usbserial-X")
    }

    /// `null`/empty/only spaces unchanged (even without trimming), otherwise `trim` and `/dev/` only without a slash.
    @Test func measuredEdgeCases() {
        let cases: [(String?, String?)] = [
            (nil, nil), ("", ""), ("  ", "  "), (" cu.x ", "/dev/cu.x"), ("/dev/cu.x", "/dev/cu.x"),
            ("COM3", "/dev/COM3"), ("a/b", "a/b"), ("localhost:4532", "/dev/localhost:4532"),
        ]
        for (input, expected) in cases {
            #expect(RigctldProcessManager.normalizeDevice(input) == expected)
        }
    }

    /// Waits (off the pool, `Task.sleep`) until the CAT log contains the line.
    static func waitForLine(_ log: CatTrafficLog, _ line: String) async throws -> Bool {
        for _ in 0..<500 {
            if log.snapshot().contains(where: { $0.hasSuffix(line) }) {
                return true
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    /// Command line as in Java (`-vvv`, `-m`, `-r` with `/dev/`, `-s`, `--set-conf`, `-t`), the line
    /// `spouštím:` into the CAT log, process output as `rigctld: …`, the second start throws, `close` terminates the process
    /// and deregisters it from the shutdown-hook stand-in.
    @Test func startRunsDaemonAndCloseTerminatesIt() async throws {
        let daemon = try FakeDaemon.sleeper()
        let log = CatTrafficLog(maxLines: 100)
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let manager = RigctldProcessManager(log: log, binary: daemon.path, hooks: hooks)
        let serial = SerialParams(dataBits: 8, stopBits: 1, parity: "None", handshake: "None", rts: "Unset", dtr: "ON")
        let args = "-vvv -m 2011 -r /dev/cu.test-x -s 9600 --set-conf "
            + "data_bits=8,stop_bits=1,serial_parity=None,serial_handshake=None,dtr_state=ON -t 4600"
        let second: String = try await onOwnThread {
            try manager.start(model: 2011, device: " cu.test-x ", baud: 9600, port: 4600, serial: serial)
            do {
                try manager.start(model: 1, device: nil, baud: 0, port: 4600)
                return "ok"
            } catch let e as CatException {
                return e.message
            }
        }
        #expect(second == "rigctld už běží")
        #expect(manager.isAlive)
        #expect(hooks.count == 1)
        #expect(log.snapshot().first.map { String($0.dropFirst(14)) } == "\u{00B7} spouštím: " + daemon.path + " " + args)
        #expect(try await Self.waitForLine(log, "rigctld: fake " + args))
        await onOwnThread { manager.close() }
        #expect(manager.isAlive == false)
        #expect(hooks.count == 0)
        await onOwnThread { manager.close() } // repeatedly without error
    }

    /// Without a device (dummy rig) `-r`, `-s` and `--set-conf` are missing; baud is ignored without a device.
    @Test func startWithoutDeviceOmitsSerialOptions() async throws {
        let daemon = try FakeDaemon.sleeper()
        let log = CatTrafficLog(maxLines: 100)
        let manager = RigctldProcessManager(log: log, binary: daemon.path,
                                            hooks: ProcessShutdownHooks(installSignalHandlers: false))
        try await onOwnThread {
            try manager.start(model: RigctldProcessManager.modelDummy, device: "  ", baud: 9600, port: 4601,
                              serial: SerialParams(dataBits: 8, stopBits: 1, parity: nil, handshake: nil, rts: nil, dtr: nil))
        }
        #expect(log.snapshot().first.map { String($0.dropFirst(14)) } == "\u{00B7} spouštím: " + daemon.path + " -vvv -m 1 -t 4601")
        await onOwnThread { manager.close() }
        #expect(manager.isAlive == false)
    }

    /// Unrunnable binary → `CatException("Nelze spustit rigctld: <příkaz>")` with a Java cause.
    @Test func startFailureIsCatException() async throws {
        let log = CatTrafficLog(maxLines: 100)
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let manager = RigctldProcessManager(log: log, binary: "/nonexistent/rigctld", hooks: hooks)
        let error: CatException? = await onOwnThread {
            do {
                try manager.start(model: 1, device: nil, baud: 0, port: 4600)
                return nil
            } catch {
                return error as? CatException
            }
        }
        #expect(error?.message == "Nelze spustit rigctld: /nonexistent/rigctld -vvv -m 1 -t 4600")
        #expect(error?.cause as? ProcessRunnerError
            == ProcessRunnerError("Cannot run program \"/nonexistent/rigctld\": error=2, No such file or directory"))
        #expect(manager.isAlive == false)
        #expect(hooks.count == 0)
    }

    /// Stand-in for the JVM shutdown hook: the application-termination handler (SIGTERM/SIGINT) kills every still-running
    /// daemon; after `close` the manager is no longer in it.
    @Test func shutdownHooksTerminateRunningDaemon() async throws {
        let daemon = try FakeDaemon.sleeper()
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let manager = RigctldProcessManager(log: CatTrafficLog(maxLines: 100), binary: daemon.path, hooks: hooks)
        try await onOwnThread { try manager.start(model: 1, device: nil, baud: 0, port: 4602) }
        #expect(manager.isAlive)
        await onOwnThread { hooks.runAll() }
        #expect(manager.isAlive == false)
        await onOwnThread { manager.close() }
        #expect(hooks.count == 0)
    }

    /// A CAT log error while mirroring output ends the mirroring (the Java reader thread dies on the first
    /// exception) — the process keeps running. The daemon stand-in starts writing once the test creates the file `go`.
    @Test func outputMirroringStopsOnLogFailure() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let go = dir.appendingPathComponent("go")
        let daemon = try FakeDaemon("""
            while [ ! -f '\(go.path)' ]; do sleep 0.05; done
            echo one; echo two
            \(FakeDaemon.untilParentDies)
            """)
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let log = CatTrafficLog(maxLines: 100)
        let manager = RigctldProcessManager(log: log, binary: daemon.path,
                                            hooks: ProcessShutdownHooks(installSignalHandlers: false))
        try await onOwnThread { try manager.start(model: 1, device: nil, baud: 0, port: 4603) }
        log.setFile(blocker.appendingPathComponent("cat.log"))
        try Data().write(to: go)
        // The first output line is written to the buffer and thrown away, the second is no longer mirrored. Wait until mirroring
        // has processed both lines (counter), only then verify that the second is not in the log.
        var waits = 0
        while manager.outputLinesSeen < 2 && waits < 1000 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waits += 1
        }
        #expect(manager.outputLinesSeen == 2)
        #expect(log.snapshot().contains { $0.hasSuffix("rigctld: one") })
        #expect(!log.snapshot().contains { $0.hasSuffix("rigctld: two") })
        #expect(manager.isAlive)
        await onOwnThread { manager.close() }
    }

    /// A CAT log error on the `spouštím:` line propagates out (Java `UncheckedIOException`) and the process does not start.
    @Test func startLogFailurePropagates() async throws {
        let daemon = try FakeDaemon.sleeper()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let log = CatTrafficLog(maxLines: 100)
        log.setFile(blocker.appendingPathComponent("cat.log"))
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let manager = RigctldProcessManager(log: log, binary: daemon.path, hooks: hooks)
        let message: String? = await onOwnThread {
            do {
                try manager.start(model: 1, device: nil, baud: 0, port: 4604)
                return nil
            } catch {
                return (error as? UncheckedIOError)?.message
            }
        }
        #expect(message == "Nelze zapsat do CAT logu: " + blocker.appendingPathComponent("cat.log").path)
        #expect(manager.isAlive == false)
        #expect(hooks.count == 0)
    }

    // MARK: - Signal handling (shutdown-hook stand-in) on SIGUSR1/SIGUSR2 — does not touch the runner's SIGTERM/SIGINT

    /// A signal with the default handler: after it is delivered the hooks run, then a final action with the same signal.
    @Test func signalHandlerRunsHooksThenFinish() async throws {
        let ran = OSAllocatedUnfairLock(initialState: 0)
        let finished: Int32 = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let hooks = ProcessShutdownHooks(installSignalHandlers: true, signals: [SIGUSR1]) { sig in
                continuation.resume(returning: sig)
            }
            let owner = NSObject()
            hooks.register(owner) { ran.withLock { $0 += 1 } }
            #expect(hooks.handledSignals == [SIGUSR1])
            _ = kill(getpid(), SIGUSR1)
            _ = Unmanaged.passRetained(hooks) // the handler lives until the end of the process (like `shared`)
        }
        #expect(finished == SIGUSR1)
        #expect(ran.withLock { $0 } == 1)
    }

    /// A signal with a foreign host handler: left alone (the handler is not installed, the foreign one stays).
    @Test func foreignSignalHandlerIsKept() {
        let foreign: @convention(c) (Int32) -> Void = { _ in }
        let original = signal(SIGUSR2, foreign)
        defer { _ = signal(SIGUSR2, original) }
        let hooks = ProcessShutdownHooks(installSignalHandlers: true, signals: [SIGUSR2]) { _ in }
        hooks.register(NSObject()) {}
        #expect(hooks.handledSignals.isEmpty)
        let current = signal(SIGUSR2, foreign)
        #expect(current.map { unsafeBitCast($0, to: Int.self) } == unsafeBitCast(foreign, to: Int.self))
    }

    /// The app hands the signals over before any daemon registers: the hooks never install a handler (they could
    /// re-raise the signal before the quit released PTT), and still run on `runAll()`.
    @Test func handedOverSignalsGetNoHandler() {
        let hooks = ProcessShutdownHooks(installSignalHandlers: true, signals: [SIGUSR2]) { _ in }
        #expect(hooks.handOverSignalHandling().isEmpty)
        let ran = OSAllocatedUnfairLock(initialState: 0)
        hooks.register(NSObject()) { ran.withLock { $0 += 1 } }
        #expect(hooks.handledSignals.isEmpty)
        hooks.runAll()
        #expect(ran.withLock { $0 } == 1)
    }

    /// A hand-over after a handler was installed cancels it (SIGWINCH: ignored by default, nothing else uses it).
    @Test func aLateHandOverCancelsTheHandler() {
        defer { _ = signal(SIGWINCH, SIG_DFL) }
        let hooks = ProcessShutdownHooks(installSignalHandlers: true, signals: [SIGWINCH]) { _ in }
        hooks.register(NSObject()) {}
        #expect(hooks.handledSignals == [SIGWINCH])
        #expect(hooks.handOverSignalHandling() == [SIGWINCH])
        #expect(hooks.handledSignals.isEmpty)
        hooks.register(NSObject()) {}
        #expect(hooks.handledSignals.isEmpty)
    }
}
