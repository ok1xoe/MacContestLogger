import Darwin
import Foundation
import os

/// Launches and supervises the local hamlib daemon process `rigctld` (Java `cat/RigctldProcessManager`).
///
/// Command as in Java: `<rigctld> -vvv -m <model> [-r <device> [-s <baud>] [--set-conf <serial parameters>]]
/// -t <port>`; binary from `/opt/homebrew/bin`, `/usr/local/bin`, otherwise `rigctld` from `PATH`. The line `spouštím: …`
/// and the process output (`-vvv`, stdout + stderr) go to `CatTrafficLog`.
///
/// Replacement for the JVM shutdown hook ("equivalent, not the same"): a running daemon is registered
/// in `ProcessShutdownHooks.shared`, whose `SIGTERM`/`SIGINT` handler kills it before the app exits;
/// a normal app exit calls `close()` (`applicationWillTerminate`). On a crash an orphan remains —
/// handled by adoption via `RigctldPort.isListening`.
///
/// Methods block (`close` up to 2 s while terminating the process) — call off Swift's shared pool.
public final class RigctldProcessManager: @unchecked Sendable {

    /// Hamlib dummy rig (`-m 1`) — for testing without hardware.
    public static let modelDummy = 1

    private let log: CatTrafficLog
    private let binary: String?
    private let hooks: ProcessShutdownHooks
    /// Reentrant: a CAT log listener (called synchronously from `start`) may touch `isAlive`.
    private let lock = NSRecursiveLock()
    private var process: ProcessRunner?
    private var mirror: OutputMirror?

    public convenience init(log: CatTrafficLog = .shared) {
        self.init(log: log, binary: nil, hooks: .shared)
    }

    /// `binary` replaces the `rigctld` lookup (tests: a harmless substitute), `hooks` is its own registry (tests without signals).
    init(log: CatTrafficLog, binary: String?, hooks: ProcessShutdownHooks) {
        self.log = log
        self.binary = binary
        self.hooks = hooks
    }

    /// Launches `rigctld`. `device` may be `nil`/empty (dummy rig); `baud` (only > 0) and `serial` are used only
    /// with a device.
    ///
    /// - Throws: `CatException("rigctld už běží")`, `CatException("Nelze spustit rigctld: <command>")` with cause
    ///   `ProcessRunnerError`; a CAT log error on the `spouštím:` line propagates (`UncheckedIOError`, the process is not started).
    public func start(model: Int, device: String?, baud: Int, port: Int, serial: SerialParams? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        if let process, process.isAlive {
            throw CatException("rigctld už běží")
        }
        var cmd: [String] = [binary ?? HamlibBinary.resolve("rigctld"), "-vvv", "-m", String(model)]
        if let device, !JavaText.isBlank(device), let normalized = Self.normalizeDevice(device) {
            cmd += ["-r", normalized]
            if baud > 0 {
                cmd += ["-s", String(baud)]
            }
            if let serial {
                cmd += ["--set-conf", serial.toSetConf()]
            }
        }
        cmd += ["-t", String(port)]
        let joined = cmd.joined(separator: " ")
        try log.info("spouštím: " + joined)
        let mirror = OutputMirror(log: log)
        let runner = ProcessRunner(executable: cmd[0], arguments: Array(cmd.dropFirst())) { line in
            mirror.forward(line)
        }
        do {
            try runner.start()
        } catch {
            throw CatException("Nelze spustit rigctld: " + joined, cause: error)
        }
        process = runner
        self.mirror = mirror
        hooks.register(self) { [self] in
            destroyProcess()
        }
    }

    /// Java `isAlive()`.
    public var isAlive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isAlive ?? false
    }

    /// Number of lines of the last launched process's output that mirroring has processed (including those skipped after a log
    /// error) — tests wait on it instead of a fixed pause.
    var outputLinesSeen: Int {
        lock.lock()
        defer { lock.unlock() }
        return mirror?.linesSeen ?? 0
    }

    /// Unregisters the shutdown-hook replacement and terminates the daemon (SIGTERM, SIGKILL after 1 s). Repeatable without error.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        hooks.unregister(self)
        destroyProcess()
        process = nil
    }

    private func destroyProcess() {
        lock.lock()
        defer { lock.unlock() }
        Self.terminate(process)
    }

    /// First politely, after a short wait forcefully — so no orphan is left behind (Java `terminate(Process)`).
    static func terminate(_ process: ProcessRunner?) {
        process?.terminate()
    }

    /// Full path to the serial port: `rigctld` without a slash treats the string as a network address.
    /// `nil`/empty/all whitespace (`isBlank`) unchanged, otherwise `trim` and `/dev/` only when there is no slash.
    static func normalizeDevice(_ device: String?) -> String? {
        guard let device, !JavaText.isBlank(device) else {
            return device
        }
        let d = JavaText.trim(device)
        return d.utf16.contains(0x2F) ? d : "/dev/" + d
    }
}

/// Mirroring daemon output into the CAT log. The Java reader thread dies on the first exception from `CatTrafficLog`
/// (uncaught `UncheckedIOException`) and mirrors nothing afterwards; here mirroring stops at the first error the same way
/// (but the output is still drained — in Java the pipe would fill up).
private final class OutputMirror: Sendable {
    private struct State {
        var stopped = false
        var seen = 0
    }

    private let log: CatTrafficLog
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(log: CatTrafficLog) {
        self.log = log
    }

    var linesSeen: Int {
        state.withLock { $0.seen }
    }

    func forward(_ line: String) {
        defer { state.withLock { $0.seen += 1 } }
        if state.withLock({ $0.stopped }) {
            return
        }
        do {
            try log.process(line)
        } catch {
            state.withLock { $0.stopped = true }
        }
    }
}

/// Replacement for Java `Runtime.addShutdownHook` for launched daemons. A registry of "hooks" by
/// owner; on first write `shared` installs a `SIGTERM` and `SIGINT` handler (only if the signal has the
/// default handler — it does not overwrite the host's foreign handler): it runs all hooks concurrently (like JVM hook
/// threads), then restores the signal's default handler and re-raises it, so the process ends as if there were no handler.
/// The signal list and the final action are parameters for tests (`SIGUSR1`/`SIGUSR2`, without terminating the process).
///
/// The app hands signal handling over to its own quit (`handOverSignalHandling()`, called by
/// `TerminationSignals.install` before any daemon registers): the hooks then never install a source, so they cannot
/// re-raise a signal and end the process before the quit released PTT; the app runs `runAll()` itself on every exit.
public final class ProcessShutdownHooks: @unchecked Sendable {

    /// Shared app registry (with signal handling).
    public static let shared = ProcessShutdownHooks(installSignalHandlers: true)

    private let installSignalHandlers: Bool
    private let signals: [Int32]
    private let finish: @Sendable (Int32) -> Void
    private let lock = NSLock()
    private var hooks: [ObjectIdentifier: @Sendable () -> Void] = [:]
    private var installed = false
    private var handedOver = false
    private var installedSignals: [Int32] = []
    private var sources: [any DispatchSourceSignal] = []
    private let queue = DispatchQueue(label: "rigctld-shutdown")

    /// - Parameters:
    ///   - signals: signals the handler is installed on (default `SIGTERM`, `SIGINT`)
    ///   - finish: action after the hooks finish (default: the default signal handler and re-raising it)
    init(installSignalHandlers: Bool, signals: [Int32] = [SIGTERM, SIGINT],
         finish: @escaping @Sendable (Int32) -> Void = ProcessShutdownHooks.reraise) {
        self.installSignalHandlers = installSignalHandlers
        self.signals = signals
        self.finish = finish
    }

    /// Default end of the handler: the process ends as if there were no handler.
    static func reraise(_ sig: Int32) {
        _ = signal(sig, SIG_DFL)
        _ = raise(sig)
    }

    /// Signals the handler was actually installed on (excluding those with a foreign handler).
    var handledSignals: [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return installedSignals
    }

    /// Writes (or replaces) the owner's hook.
    func register(_ owner: AnyObject, _ hook: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        hooks[ObjectIdentifier(owner)] = hook
        installIfNeeded()
    }

    func unregister(_ owner: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        hooks[ObjectIdentifier(owner)] = nil
    }

    /// Number of registered hooks.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return hooks.count
    }

    /// Runs all registered hooks concurrently and waits for them (Java shutdown-hook execution); the app also calls it
    /// from `applicationWillTerminate`, because a normal exit runs Java's shutdown hooks too.
    public func runAll() {
        lock.lock()
        let snapshot: [@Sendable () -> Void] = Array(hooks.values)
        lock.unlock()
        DispatchQueue.concurrentPerform(iterations: snapshot.count) { index in
            snapshot[index]()
        }
    }

    /// The host takes the signals over: no handler is installed from now on, and one installed already is
    /// cancelled (the host sets its own disposition right after). Returns the signals that had a handler of the hooks.
    @discardableResult
    public func handOverSignalHandling() -> [Int32] {
        lock.lock()
        defer { lock.unlock() }
        handedOver = true
        for source in sources {
            source.cancel()
        }
        sources = []
        let had: [Int32] = installedSignals
        installedSignals = []
        return had
    }

    private func installIfNeeded() {
        guard installSignalHandlers, !installed, !handedOver else {
            return
        }
        installed = true
        for sig in signals {
            let previous = signal(sig, SIG_IGN)
            if previous != nil {
                // The host has its own handler (or ignores the signal) — leave it alone.
                _ = signal(sig, previous)
                continue
            }
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            let finish = self.finish
            source.setEventHandler { [weak self] in
                self?.runAll()
                finish(sig)
            }
            source.resume()
            sources.append(source)
            installedSignals.append(sig)
        }
    }
}

/// Binary lookup for hamlib as in Java (`resolveBinary`): Homebrew on Apple Silicon, then Intel, otherwise the name
/// for `PATH`.
enum HamlibBinary {
    static func resolve(_ name: String) -> String {
        for candidate in ["/opt/homebrew/bin/" + name, "/usr/local/bin/" + name] where access(candidate, X_OK) == 0 {
            return candidate
        }
        return name
    }
}
