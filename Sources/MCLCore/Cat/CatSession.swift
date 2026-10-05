import Foundation

/// Non-UI core of the CAT connection to the rig — Kotlin `ui/cat/CatConnection.kt` without Compose.
/// The UI wraps it: it receives state via the `onChange` callback and hops to the main thread itself
/// (`Task { @MainActor in … }`, Kotlin `scope.launch(Dispatchers.Main)`).
///
/// State machine as in Kotlin:
/// - `connect` immediately sets „Připojuji (<model>)…" and does the rest on **its own thread** (Kotlin `scope.launch`
///   + `Dispatchers.IO`; each connection has its own thread, concurrent connections are not queued behind each other):
///   - `LAUNCH_DAEMON`: when something already listens on `localhost:<port>` (an orphaned daemon after an app crash,
///     or one started by the user), it **adopts it** — connects (`connectWithRetry`) and neither starts nor
///     later kills anything; it writes to the CAT log that the rig and serial-line settings from the app do not apply;
///   - `LAUNCH_DAEMON` with no listener: starts `rigctld` (`RigctldProcessManager.start`), remembers it
///     and connects via `connectWithRetry` (12 attempts, 150 ms apart, while the daemon boots);
///   - `CONNECT_RUNNING`: a single `RigctldClient(host, port)` attempt (a shared daemon under launchd on the
///     user's machine — never started or terminated by us);
///   - `CatException` anywhere in that → `disconnect("Připojení selhalo: <message>")` (also closes an already started daemon);
///   - success: the rig is wrapped in `TransverterRig`, `RigPoller` starts (500 ms), `connected = true`,
///     „Připojeno (<model>)…" — only then may the first state arrive (Kotlin: the callback waits for the main thread).
/// - poller state → `state` + status text `TRX: %.1f kHz  <mode>` (Java `String.format`, HALF_UP);
/// - **first poll error** → `disconnect("Spojení s rigem ztraceno")`; no reconnect;
/// - `disconnect(message)`: stop the poller, close the rig, terminate **only our own** daemon, `connected = false`,
///   `state = nil`, status message (`nil` = the default „TRX odpojen", translated only on read);
/// - `toggle`: connected or own daemon running → `disconnect(nil)`, otherwise `connect`.
///
/// `disconnectCancellingConnect` (beyond Kotlin, for the quit, a rig scan and the LED during „Připojuji…") cancels a
/// connect in flight and waits for it: the stale connect closes what it opened and changes nothing.
///
/// Kotlin quirks deliberately preserved: `disconnect` during an in-flight `connect` does not cancel it (on success
/// it connects, on error it overwrites the message); state from a read that was running during `disconnect` may still arrive
/// and set `state`/text (the poller stops but finishes reading); an error other than `CatException` (port out of range,
/// CAT log error) is not caught — Kotlin lets it escape the coroutine, here it goes to `onUnexpectedError` and the state stays
/// as it was at the moment of the error („Připojuji…", possibly with a running daemon).
///
/// Threads: all state under a recursive lock (replacing Kotlin's main thread); `onChange` is called
/// **under the lock** from the thread that made the change (the caller of `connect`/`disconnect`, the connection thread, the
/// poller thread) — this guarantees event order. `onChange` therefore must not synchronously wait for another thread that
/// would touch the session (wrapping it in `Task { @MainActor in … }` is enough). `disconnect` blocks up to ~2 s
/// (terminating the own daemon), `tune`/`setPtt`/`setMode` block on rig I/O — call off the main thread
/// and off Swift's shared pool.
public final class CatSession: @unchecked Sendable {

    /// Immediate state for the UI (Kotlin `state`, `status`, `connected`).
    public struct Snapshot: Equatable, Sendable {
        /// Last rig state (`nil` = disconnected / nothing yet).
        public var state: RigState?
        /// Status message; `nil` = the default „TRX odpojen" (the UI translates it only on display).
        public var statusMessage: String?
        public var connected: Bool
        /// A connect is in progress (set with „Připojuji (…)…", cleared when it ends either way).
        public var connecting: Bool

        public init(state: RigState? = nil, statusMessage: String? = nil, connected: Bool = false,
                    connecting: Bool = false) {
            self.state = state
            self.statusMessage = statusMessage
            self.connected = connected
            self.connecting = connecting
        }

        /// Kotlin `status` (without translating the default text).
        public var status: String {
            statusMessage ?? CatSession.disconnectedText
        }
    }

    /// Timing (Kotlin: `pollIntervalMs`, `connectAttempts`, `connectRetryMs`); tests shorten it.
    public struct Timing: Equatable, Sendable {
        public var pollIntervalMs: Int64
        public var connectAttempts: Int
        public var connectRetryMs: Int

        public init(pollIntervalMs: Int64 = 500, connectAttempts: Int = 12, connectRetryMs: Int = 150) {
            self.pollIntervalMs = pollIntervalMs
            self.connectAttempts = connectAttempts
            self.connectRetryMs = connectRetryMs
        }
    }

    /// Connection to `rigctld` at `host:port` (default `RigctldClient`).
    typealias Connector = @Sendable (_ host: String, _ port: Int) throws -> any RigController

    /// Default status text (Kotlin `tr("TRX odpojen")`).
    public static let disconnectedText = "TRX odpojen"

    private let transverters: @Sendable () -> [TransverterEntry]
    private let log: CatTrafficLog
    private let timing: Timing
    private let translate: @Sendable (String) -> String
    private let onChange: @Sendable (Snapshot) -> Void
    private let onUnexpectedError: @Sendable (any Error) -> Void
    private let makeProcessManager: @Sendable () -> RigctldProcessManager
    private let connector: Connector
    private let isListening: @Sendable (String, Int) -> Bool
    /// Runs on the connect thread with a freshly connected rig, before the poller's first read (Swift addition:
    /// the app sends a PTT release it still owes the rig as the first command of the new connection).
    private var onConnected: (@Sendable (any RigController) -> Void)?

    /// Replacement for Kotlin's main thread (reentrant — `onChange` may read the session).
    private let lock = NSRecursiveLock()
    private var current = Snapshot()
    private var rig: (any RigController)?
    private var poller: RigPoller?
    private var processManager: RigctldProcessManager?
    /// Raised by `disconnectCancellingConnect`: a connect started under an older generation is stale — it closes
    /// what it opened (its daemon, its rig) and changes nothing.
    private var generation: UInt64 = 0
    /// Connect threads still running (guarded by `connects`).
    private var inFlight = 0
    private let connects = NSCondition()

    /// - Parameters:
    ///   - transverters: transverters — the rig is wrapped in `TransverterRig` (read on every call)
    ///   - modes: hamlib mode mapping for `RigctldClient` (shared live configuration provider)
    ///   - translate: translation of the Czech key (`tr`); the session fills in the `%s` placeholder
    ///   - onChange: new state after every change (from its own threads, under the session lock)
    ///   - onUnexpectedError: error that Kotlin does not catch (see the type description)
    public convenience init(transverters: @escaping @Sendable () -> [TransverterEntry] = { [] },
                            modes: @escaping HamlibModeProvider = { HamlibModeMapping.default },
                            log: CatTrafficLog = .shared,
                            timing: Timing = Timing(),
                            translate: @escaping @Sendable (String) -> String = { $0 },
                            onChange: @escaping @Sendable (Snapshot) -> Void,
                            onUnexpectedError: @escaping @Sendable (any Error) -> Void = { _ in }) {
        self.init(transverters: transverters, log: log, timing: timing, translate: translate, onChange: onChange,
                  onUnexpectedError: onUnexpectedError,
                  makeProcessManager: { RigctldProcessManager(log: log) },
                  connector: { host, port in try RigctldClient(host: host, port: port, modes: modes, log: log) },
                  isListening: { host, port in RigctldPort.isListening(host: host, port: port) })
    }

    /// Tests: replacement for daemon launching (`FakeDaemon`), connecting and listener detection.
    init(transverters: @escaping @Sendable () -> [TransverterEntry], log: CatTrafficLog, timing: Timing,
         translate: @escaping @Sendable (String) -> String, onChange: @escaping @Sendable (Snapshot) -> Void,
         onUnexpectedError: @escaping @Sendable (any Error) -> Void,
         makeProcessManager: @escaping @Sendable () -> RigctldProcessManager, connector: @escaping Connector,
         isListening: @escaping @Sendable (String, Int) -> Bool) {
        self.transverters = transverters
        self.log = log
        self.timing = timing
        self.translate = translate
        self.onChange = onChange
        self.onUnexpectedError = onUnexpectedError
        self.makeProcessManager = makeProcessManager
        self.connector = connector
        self.isListening = isListening
    }

    /// Sets the hook run with every freshly connected rig before its first poll (on the connect thread).
    public func setOnConnected(_ hook: @escaping @Sendable (any RigController) -> Void) {
        locked { onConnected = hook }
    }

    // MARK: - State

    public var snapshot: Snapshot {
        locked { current }
    }

    public var state: RigState? {
        snapshot.state
    }

    public var status: String {
        snapshot.status
    }

    public var connected: Bool {
        snapshot.connected
    }

    /// Connected rig for CW over CAT and VFO B / split operations; `nil` when CAT is not running.
    public func rigOrNull() -> (any RigController)? {
        locked { rig }
    }

    // MARK: - Connection

    public func toggle(_ rc: RigConfig) {
        lock.lock()
        defer { lock.unlock() }
        if current.connected || processManager?.isAlive == true {
            disconnect(nil) // nil = default „disconnected", so it follows the UI language
        } else {
            connect(rc)
        }
    }

    public func connect(_ rc: RigConfig) {
        lock.lock()
        current.statusMessage = tr("Připojuji (%s)…", rc.modelLabel)
        current.connecting = true
        onChange(current)
        // Captured together: a cancel either sees this connect in flight or makes it stale.
        let started: UInt64 = generation
        connects.lock()
        inFlight += 1
        connects.unlock()
        lock.unlock()
        let thread = Thread { [self] in
            runConnect(rc, generation: started)
            connects.lock()
            inFlight -= 1
            connects.broadcast()
            connects.unlock()
        }
        thread.name = "cat-connect"
        thread.start()
    }

    /// A connect is still running (its thread has not finished).
    public var isConnecting: Bool {
        connects.lock()
        defer { connects.unlock() }
        return inFlight > 0
    }

    /// `disconnect(message)` that also cancels a connect in flight and **blocks** until every connect thread has
    /// finished (a stale connect closes the daemon and the rig it opened; nothing survives). Beyond Kotlin, whose
    /// `disconnect` lets a running connect complete (kept in `disconnect`): the app uses this at quit, before a rig
    /// scan and when the LED is pressed during „Připojuji…". Call off the main thread and off Swift's pool.
    public func disconnectCancellingConnect(_ message: String?) {
        lock.lock()
        generation &+= 1
        disconnect(message)
        lock.unlock()
        connects.lock()
        while inFlight > 0 {
            connects.wait()
        }
        connects.unlock()
    }

    /// `message` `nil` = return to the default „disconnected".
    public func disconnect(_ message: String?) {
        lock.lock()
        defer { lock.unlock() }
        poller?.stop()
        poller = nil
        rig?.close()
        rig = nil
        processManager?.close()
        processManager = nil
        current.connected = false
        current.connecting = false
        current.state = nil
        current.statusMessage = message
        onChange(current)
    }

    // MARK: - Rig control (no-op without a connection; blocks on I/O)

    /// Tunes the rig to the given frequency.
    public func tune(_ freqHz: Int64) throws {
        try rigOrNull()?.setFrequencyHz(freqHz)
    }

    /// Rig PTT (voice keyer); a CAT error propagates so we do not transmit blindly.
    public func setPtt(_ on: Bool) throws {
        try rigOrNull()?.setPtt(on)
    }

    /// Sets the operating mode on the rig.
    public func setMode(_ mode: Mode?, freqHz: Int64) throws {
        try rigOrNull()?.setMode(mode, freqHz: freqHz)
    }

    // MARK: - Helpers (Kotlin `format`, `serialParamsOf`)

    /// `String.format(Locale.US, "TRX: %.1f kHz  %s", freqKHz, mode?.name ?: rawMode)`.
    static func format(_ s: RigState) -> String {
        let mode: String = s.mode?.rawValue ?? s.rawMode
        return JavaFormat.format("TRX: %.1f kHz  %s", .double(s.freqKHz), .string(mode))
    }

    static func serialParams(of rc: RigConfig) -> SerialParams {
        SerialParams(dataBits: rc.dataBits, stopBits: rc.stopBits, parity: rc.parity.hamlib,
                     handshake: rc.flowControl.hamlib, rts: rc.rts.hamlib, dtr: rc.dtr.hamlib)
    }

    // MARK: - Internals

    /// Kotlin coroutine `connect` (part on `Dispatchers.IO` without the lock, parts on the main thread under the lock).
    private func runConnect(_ rc: RigConfig, generation started: UInt64) {
        let adopted: Bool = rc.mode == .launchDaemon && isListening("localhost", rc.port)
        let newRig: any RigController
        do {
            if rc.mode == .launchDaemon && !adopted {
                let pm = makeProcessManager()
                // A cancelled connect never launches `rigctld`.
                if isStale(started) {
                    return
                }
                try pm.start(model: rc.model, device: rc.device, baud: rc.baud, port: rc.port,
                             serial: Self.serialParams(of: rc))
                let stale: Bool = locked { () -> Bool in
                    if generation != started {
                        return true
                    }
                    processManager = pm
                    return false
                }
                if stale {
                    pm.close()
                    return
                }
                newRig = try connectWithRetry("localhost", rc.port, generation: started)
            } else if adopted {
                newRig = try connectWithRetry("localhost", rc.port, generation: started)
            } else {
                newRig = try connector(rc.host, rc.port)
            }
        } catch is ConnectCancelled {
            return
        } catch let e as CatException {
            lock.lock()
            defer { lock.unlock() }
            if generation == started {
                disconnect(tr("Připojení selhalo: %s", e.message))
            }
            return
        } catch {
            if !isStale(started) {
                onUnexpectedError(error)
            }
            return
        }
        // Outside the lock (it may block on I/O): the first command on the new connection, before the poller's read.
        // Not for a connect cancelled meanwhile: a newer connection may already be up.
        if !isStale(started), let hook = locked({ onConnected }) {
            hook(newRig)
        }
        lock.lock()
        defer { lock.unlock() }
        if generation != started {
            // Cancelled meanwhile: the daemon (if any) was closed by the cancelling disconnect.
            newRig.close()
            return
        }
        if adopted {
            do {
                try log.info(tr("na portu %s už běžel rigctld — připojeno k němu, ", String(rc.port))
                    + tr("nastavení rigu a sériové linky z aplikace se neuplatní"))
            } catch {
                onUnexpectedError(error)
                return
            }
        }
        let wrapped = TransverterRig(inner: newRig, transverters: transverters)
        rig = wrapped
        let newPoller = RigPoller(rig: wrapped, intervalMs: timing.pollIntervalMs, onState: { [weak self] st in
            self?.applyState(st)
        }, onError: { [weak self] _ in
            self?.pollFailed()
        })
        poller = newPoller
        newPoller.start()
        current.connected = true
        current.connecting = false
        current.statusMessage = tr("Připojeno (%s)…", rc.modelLabel)
        onChange(current)
    }

    /// After starting the daemon, tries to establish a connection for a while until rigctld boots.
    private func connectWithRetry(_ host: String, _ port: Int, generation started: UInt64) throws -> any RigController {
        var last: CatException?
        for _ in 0..<max(timing.connectAttempts, 0) {
            if isStale(started) {
                throw ConnectCancelled()
            }
            do {
                return try connector(host, port)
            } catch let e as CatException {
                last = e
                Thread.sleep(forTimeInterval: Double(timing.connectRetryMs) / 1_000)
            }
        }
        throw last ?? CatException(tr("Nelze se připojit k rigctld"))
    }

    /// Kotlin `{ st -> scope.launch(Main) { state = st; status = format(st) } }` — regardless of whether the
    /// poller is still current (state from a drained read after `disconnect` is written, as in Kotlin).
    private func applyState(_ st: RigState) {
        lock.lock()
        defer { lock.unlock() }
        current.state = st
        current.statusMessage = Self.format(st)
        onChange(current)
    }

    private func pollFailed() {
        disconnect(tr("Spojení s rigem ztraceno"))
    }

    /// Kotlin `tr(cs)` (without arguments translation only, no `format`) and `tr(cs, args…)` = `tr(cs).format(args)`.
    /// A translation with an invalid pattern (Kotlin would throw from `format`) is replaced by the original Czech key —
    /// `JavaFormat` fails on an invalid pattern.
    private func tr(_ cs: String, _ args: String...) -> String {
        let translated = translate(cs)
        if args.isEmpty {
            return translated
        }
        let jargs: [JavaFormat.Arg] = args.map { .string($0) }
        if JavaFormat.failure(translated, arguments: jargs) == nil {
            return JavaFormat.format(translated, arguments: jargs)
        }
        return JavaFormat.format(cs, arguments: jargs)
    }

    /// A connect thread of an older generation (cancelled by `disconnectCancellingConnect`).
    private struct ConnectCancelled: Error {}

    private func isStale(_ started: UInt64) -> Bool {
        locked { generation != started }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
