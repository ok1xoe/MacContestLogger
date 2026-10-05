import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Hardware ports for the rig tests: real `CatSession`s that only ever reach a `FakeRigctld` on a loopback port
/// (the connector refuses 4532/4533; a daemon would be `/nonexistent/fake-rigctld`), OTRSP and the footswitch as
/// recorders, the rotator over a fake `rotctld`, the UDP message recorded. Nothing real is opened or keyed.
final class FakeHardware: @unchecked Sendable {

    private let lock = NSLock()
    private var log: [String] = []
    private var footswitchChange: (@Sendable (Bool) -> Void)?
    private var daemons = 0
    /// Ports where "something already listens" (the adoption path of `LAUNCH_DAEMON`).
    private var listening: Set<Int> = []
    private var otrspFailure: String?
    /// The connector throws an error that is not a `CatException` (Kotlin lets it escape the coroutine).
    private var unexpectedConnectError: String?
    /// Every process manager a session made (a daemon is a harmless sleeping script, or the nonexistent binary).
    private var managers: [RigctldProcessManager] = []
    private var daemonBinary = "/nonexistent/fake-rigctld"
    private var rigReadTimeoutMs: Int = FakeHardware.readTimeoutMs
    /// The CAT timing of the sessions this hardware makes (a test of a poll error polls often).
    private let catTiming: CatSession.Timing

    init(pollIntervalMs: Int64? = nil) {
        var timing: CatSession.Timing = Self.timing
        if let pollIntervalMs {
            timing.pollIntervalMs = pollIntervalMs
        }
        catTiming = timing
    }
    private var daemonDir: URL?
    /// Connect attempts wait here while held (the connect thread is the session's own thread).
    private let connectGate = NSCondition()
    private var connectsHeld = false
    private var connectsEntered = 0

    deinit {
        if let daemonDir {
            try? FileManager.default.removeItem(at: daemonDir)
        }
    }

    /// The process managers made so far.
    var processManagers: [RigctldProcessManager] {
        lock.withLock { managers }
    }

    /// Sessions start a harmless script instead of `rigctld`: it prints its arguments and sleeps while the test
    /// process lives (never hamlib, never a serial port).
    func useSleeperDaemon() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fake-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: URL = dir.appendingPathComponent("fake-rigctld")
        let body = "#!/bin/sh\necho \"fake $*\"\nwhile kill -0 $PPID 2>/dev/null; do sleep 0.2; done\n"
        try Data(body.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        lock.withLock {
            daemonDir = dir
            daemonBinary = file.path
        }
    }

    /// Connect attempts block until `releaseConnects()`.
    func holdConnects() {
        connectGate.lock()
        connectsHeld = true
        connectGate.unlock()
    }

    func releaseConnects() {
        connectGate.lock()
        connectsHeld = false
        connectGate.broadcast()
        connectGate.unlock()
    }

    /// Connect attempts that reached the connector.
    var connectAttempts: Int {
        connectGate.lock()
        defer { connectGate.unlock() }
        return connectsEntered
    }

    private func passConnectGate() {
        connectGate.lock()
        connectsEntered += 1
        while connectsHeld {
            connectGate.wait()
        }
        connectGate.unlock()
    }

    /// The OTRSP commands, footswitch opens/closes and UDP messages, in order.
    var events: [String] {
        lock.withLock { log }
    }

    /// How many `rigctld` processes a session tried to start (always the nonexistent binary).
    var daemonStarts: Int {
        lock.withLock { daemons }
    }

    func listen(on port: Int) {
        guardTestPort(port)
        lock.withLock { _ = listening.insert(port) }
    }

    func failConnectUnexpectedly(_ message: String) {
        lock.withLock { unexpectedConnectError = message }
    }

    /// The read timeout of the rig clients connected from now on (a test of a late answer shortens it; the fake then
    /// holds the answer until the test releases it, so the timeout always expires first).
    func setRigReadTimeout(_ milliseconds: Int) {
        lock.withLock { rigReadTimeoutMs = milliseconds }
    }

    func failOtrsp(_ message: String?) {
        lock.withLock { otrspFailure = message }
    }

    /// The footswitch's line changed (as its polling thread would report it).
    func press(_ pressed: Bool) {
        let change: (@Sendable (Bool) -> Void)? = lock.withLock { footswitchChange }
        change?(pressed)
    }

    var footswitchOpen: Bool {
        lock.withLock { footswitchChange != nil }
    }

    private func record(_ event: String) {
        lock.withLock { log.append(event) }
    }

    /// Fast connection attempts; a poll so long that after the first state the poller sleeps (a disconnect stops it
    /// in its sleep).
    static let timing = CatSession.Timing(pollIntervalMs: 600_000, connectAttempts: 3, connectRetryMs: 1)
    /// The rig client's connect and read timeout against `FakeRigctld` (the app's 2 s is a wall-clock bound a loaded
    /// runner can exceed; a fake that stops closes its sockets, so no test waits for this).
    static let readTimeoutMs = 120_000

    var ports: HardwarePorts {
        HardwarePorts(
            makeCat: { [self] hooks in makeCat(hooks) },
            openOtrsp: { [self] path in
                if let failure = lock.withLock({ otrspFailure }) {
                    throw JavaIOError(failure)
                }
                record("otrsp open " + path)
                return Otrsp(sink: { [self] command in record("otrsp " + command) },
                             closer: { [self] in record("otrsp close") })
            },
            openFootswitch: { [self] path, pin, onChange in
                record("footswitch open " + path + " " + pin.rawValue)
                lock.withLock { footswitchChange = onChange }
                return Footswitch(input: { false }, onChange: { _ in }, onClose: { [self] in
                    record("footswitch close")
                    lock.withLock { footswitchChange = nil }
                }, periodMs: 600_000)
            },
            makeRotctld: { _, port in
                // Whatever host the configuration names, only the loopback fake is reached.
                guardTestPort(port)
                return try RotctldClient(host: "127.0.0.1", port: port, timeoutMs: 2_000)
            },
            rotorUdp: { [self] host, port, message in
                guardTestPort(port)
                record("udp \(host):\(port) " + message)
            },
            playPcm: { _, _, _, _ throws(AudioIOError) in throw AudioIOError("fake") })
    }

    private func makeCat(_ hooks: CatHooks) -> CatSession {
        let log: CatTrafficLog = hooks.log
        let modes: HamlibModeProvider = hooks.modes
        return CatSession(
            transverters: hooks.transverters, log: log, timing: catTiming, translate: hooks.translate,
            onChange: hooks.onChange, onUnexpectedError: hooks.onUnexpectedError,
            makeProcessManager: { [self] in
                let binary: String = lock.withLock { daemonBinary }
                let manager = RigctldProcessManager(log: log, binary: binary,
                                                    hooks: ProcessShutdownHooks(installSignalHandlers: false))
                lock.withLock {
                    daemons += 1
                    managers.append(manager)
                }
                return manager
            },
            connector: { [self] _, port in
                guardTestPort(port)
                passConnectGate()
                if let message = lock.withLock({ unexpectedConnectError }) {
                    throw JavaIOError(message)
                }
                // The fake always answers: a read deadline only turns a starved runner into a lost answer (a failed
                // key or a desynchronised client), so the tests wait for the answer as long as it takes.
                let timeoutMs: Int = lock.withLock { rigReadTimeoutMs }
                return try RigctldClient(host: "127.0.0.1", port: port, timeoutMs: timeoutMs, modes: modes, log: log)
            },
            isListening: { [self] _, port in
                guardTestPort(port)
                return lock.withLock { listening.contains(port) }
            })
    }
}

/// A rig configuration that connects to a fake daemon (never a serial port).
func fakeRigConfig(_ port: Int, mode: ConnectionMode = .connectRunning, label: String = "Fake") -> RigConfig {
    guardTestPort(port)
    var rc = RigConfig()
    rc.mode = mode
    rc.model = 1
    rc.modelLabel = label
    rc.device = ""
    rc.host = "127.0.0.1"
    rc.port = port
    return rc
}

/// Waits until `condition` holds, letting the main queue run (the rig's results hop there). The bound only ends a
/// failing test; a passing one never waits for it.
@MainActor
func eventually(_ what: String = "", _ condition: @MainActor () -> Bool,
                sourceLocation: SourceLocation = #_sourceLocation) async {
    for _ in 0..<20_000 {
        if condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    Issue.record("condition never held: \(what)", sourceLocation: sourceLocation)
}

/// An app over a temporary data directory with fake hardware.
@MainActor
struct RigApp {
    let app: TestApp
    let hardware: FakeHardware
    let rotatorClock: ManualClock
    let keyer: RecordingKeyer

    var model: AppModel { app.model }
    var rig: MCLAppModel.RigModel { app.model.rig }
    var entry: EntryModel { app.model.entry }
    var status: String { app.model.status.message }

    static func make(configure: @escaping (inout AppConfig, URL) throws -> Void = { _, _ in },
                     adjust: @escaping (inout AppModel.Environment) -> Void = { _ in }) async throws -> RigApp {
        let hardware = FakeHardware()
        let clock = ManualClock()
        let keyer = RecordingKeyer()
        let app = try await TestApp.make(configure: configure, adjust: { environment in
            environment.hardware = hardware.ports
            environment.rotatorClock = clock
            environment.ports = EntryPorts(keyer: keyer)
            adjust(&environment)
        })
        return RigApp(app: app, hardware: hardware, rotatorClock: clock, keyer: keyer)
    }

    /// Connects rig 1 (the main window's rig) and waits for the first state.
    func connect(vfo: Int = 0) async {
        rig.toggle(vfo: vfo)
        await eventually("rig connected") { rig.snapshot(vfo: vfo).state != nil }
    }

    /// Waits for both lanes and the peripherals, then lets the posted results run.
    func settle() async {
        await rig.settle()
        await model.peripherals.settle()
        await rig.rotator.settle()
        await runMainQueue()
    }
}

/// Lets the work posted to the main queue run.
@MainActor
func runMainQueue() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
