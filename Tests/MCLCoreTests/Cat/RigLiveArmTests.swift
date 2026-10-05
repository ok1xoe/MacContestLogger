import Darwin
import Foundation
import os
import Testing
@testable import MCLCore

/// The optional live arm of the radio gate: the production CAT path (`CatSession` → `RigctldProcessManager` →
/// `RigctldClient` → `RigController`) against a real hamlib dummy rig (`rigctld -m 1`), no hardware involved.
///
/// Safety (absolute): the daemon is the dummy model 1 without a device, on a free ephemeral loopback port that is never
/// 4532/4533 (the user's shared daemon); the test never signals any process but the one its own session started and
/// checks that every other `rigctld` that ran before it still runs after it. Skipped when `rigctld` is not installed
/// (CI runners have no hamlib). Waits are on session events, not on fixed pauses.
@Suite(.ioSafetyNet, .enabled(if: RigLiveArm.installed, "rigctld is not installed (the live arm needs hamlib)"))
struct RigLiveArmTests {

    @Test func dummyRigTunesChangesModeAndDisconnects() async throws {
        let port = RigLiveArm.freePort()
        let before: Set<Int32> = await RigLiveArm.rigctldPids()
        let ownPattern: String = RigLiveArm.pattern(port: port)
        let events = RigLiveArm.Events()
        let log = CatTrafficLog(maxLines: 500)
        let hooks = ProcessShutdownHooks(installSignalHandlers: false)
        let session = CatSession(
            transverters: { [] }, log: log,
            timing: CatSession.Timing(pollIntervalMs: 50, connectAttempts: 100, connectRetryMs: 50),
            translate: { $0 }, onChange: { events.add($0) }, onUnexpectedError: { events.fail($0) },
            makeProcessManager: { RigctldProcessManager(log: log, binary: nil, hooks: hooks) },
            connector: { host, port in try RigctldClient(host: host, port: port, log: log) },
            isListening: { host, port in RigctldPort.isListening(host: host, port: port) })
        var rc = RigConfig()
        rc.mode = .launchDaemon
        rc.model = RigctldProcessManager.modelDummy
        rc.modelLabel = "Dummy"
        rc.device = ""
        rc.host = "127.0.0.1"
        rc.port = port

        // Every path out of the test (a failed wait, a throw, cancellation) disconnects and kills the own daemon.
        defer {
            session.disconnect(nil)
            hooks.runAll()
        }
        session.connect(rc)
        try await events.wait("first state") { $0.last?.state != nil }
        #expect(events.last?.connected == true)
        #expect(events.errors.isEmpty, "\(events.errors)")
        let daemon: Set<Int32> = await RigLiveArm.pids(matching: ownPattern)
        #expect(daemon.count == 1, "the session started exactly one dummy daemon: \(daemon)")

        let hz: Int64 = 14_074_000
        try await onOwnThread { try session.tune(hz) }
        try await events.wait("frequency") { $0.last?.state?.freqHz == hz }

        try await onOwnThread { try session.setMode(.cw, freqHz: hz) }
        try await events.wait("CW") { $0.last?.state?.mode == .cw }
        #expect(events.last?.state?.rawMode == "CW")
        #expect(events.last?.state?.freqHz == hz)

        try await onOwnThread { try session.setMode(.ssb, freqHz: hz) }
        try await events.wait("USB") { $0.last?.state?.rawMode == "USB" }
        #expect(events.last?.state?.mode == .ssb)

        await onOwnThread { session.disconnect(nil) }
        #expect(events.last?.connected == false)
        #expect(events.last?.state == nil)
        let left: Set<Int32> = await RigLiveArm.pids(matching: ownPattern)
        #expect(left.isEmpty, "the session's own daemon is gone after the disconnect: \(left)")
        let after: Set<Int32> = await RigLiveArm.rigctldPids()
        #expect(before.isSubset(of: after), "a rigctld that ran before the test was left alone: \(before) vs \(after)")
    }
}

/// Helpers of the live arm: the `rigctld` lookup, a free port, the process list and the session event log.
enum RigLiveArm {

    /// `rigctld` in the places `HamlibBinary` looks (Homebrew) or on `PATH`.
    static let installed: Bool = {
        let resolved: String = HamlibBinary.resolve("rigctld")
        if resolved.hasPrefix("/") {
            return access(resolved, X_OK) == 0
        }
        let path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").contains { access(String($0) + "/rigctld", X_OK) == 0 }
    }()

    /// A free ephemeral port that is never the user's shared daemon.
    static func freePort() -> Int {
        let port: Int = FreeLoopbackPort.take()
        precondition(port != 4532 && port != 4533, "the live arm must not touch the shared daemon")
        return port
    }

    /// Command line of the dummy daemon on exactly this port (anchored: 5123 must not match 51234).
    static func pattern(port: Int) -> String {
        "rigctld.* -m 1 .*-t \(port)( |$)"
    }

    /// Pids of all running `rigctld` processes (`pgrep -x`).
    static func rigctldPids() async -> Set<Int32> {
        await pgrep(["-x", "rigctld"])
    }

    /// Pids whose command line matches the extended regular expression (`pgrep -f`).
    static func pids(matching pattern: String) async -> Set<Int32> {
        await pgrep(["-f", pattern])
    }

    private static func pgrep(_ arguments: [String]) async -> Set<Int32> {
        await onOwnThread { () -> Set<Int32> in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let data: Data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            let own: Int32 = getpid()
            return Set(text.split(separator: "\n").compactMap { Int32($0) }.filter { $0 != own })
        }
    }

    /// Session events shared between the session's own threads and the test.
    final class Events: Sendable {
        private let snapshots = OSAllocatedUnfairLock<[CatSession.Snapshot]>(initialState: [])
        private let failures = OSAllocatedUnfairLock<[String]>(initialState: [])

        func add(_ snapshot: CatSession.Snapshot) { snapshots.withLock { $0.append(snapshot) } }
        func fail(_ error: any Error) { failures.withLock { $0.append(String(describing: error)) } }

        var last: CatSession.Snapshot? { snapshots.withLock { $0.last } }
        var errors: [String] { failures.withLock { $0 } }

        struct TimedOut: Error {}

        /// Waits (off the pool) for the latest snapshot to satisfy the condition, at most 10 s; a miss records an issue
        /// and throws so the test's cleanup runs.
        func wait(_ what: String = "", sourceLocation: SourceLocation = #_sourceLocation,
                  _ condition: (Events) -> Bool) async throws {
            let deadline: UInt64 = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
            while !condition(self) {
                if DispatchTime.now().uptimeNanoseconds > deadline {
                    Issue.record("condition never held: \(what)", sourceLocation: sourceLocation)
                    throw TimedOut()
                }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }
}
