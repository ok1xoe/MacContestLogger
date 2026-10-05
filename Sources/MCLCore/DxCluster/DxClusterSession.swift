import Foundation

/// Non-UI core of the telnet connection to a DX cluster — Kotlin `ui/dxcluster/DxClusterConnection.kt` without Compose.
/// The UI wraps it: it receives state via `onChange` and hops to the main
/// thread itself (`Task { @MainActor in … }`, Kotlin `scope.launch(Dispatchers.Main)`).
///
/// State machine as in Kotlin:
/// - `connect(fav, autoLogin:)`: an empty host (Kotlin `isBlank`) → „Chybí adresa clusteru" and nothing more; otherwise
///   `connecting`, „Připojuji k <name|host>…", to the traffic log `· Připojuji k <host>:<port>…` and on **its own thread**
///   `DxClusterClient(host, port)` (8 s). `DxClusterException` → `disconnect("Připojení selhalo: <message>")`;
///   success → `connected`, „Připojeno k <name|host>", and if `autoLogin` is set and the login is non-empty, after
///   `autoLoginDelayMs` (1,500 ms) `login(fav)` — only if the client is still the same one (not disconnected in the meantime).
/// - Lines are processed by the **client's reader thread** (as in Kotlin): `log.rx` (`[tag] ` for concurrent connections), spot
///   (`DxSpotParser`) → `spots.add` → `onSpot` (errors swallowed like `runCatching`) → `SelfSpot.detect`
///   (with `myCall`, time from `clock`) → `onSelfSpot`; WWV → `lastWwv`; login confirmation. An error from any
///   step (`JavaNumberFormatError` from `SelfSpot`/`WwvMessage`, a traffic-log error) ends the read loop → disconnect.
/// - `login(fav)`: without a client nothing; an empty login → „Favorit nemá vyplněné přihlašovací jméno"; otherwise it waits for
///   confirmation (token = Kotlin `login.trim()`), „Přihlašuji jako <login>…" and on its own thread sends the login,
///   writes `» <login>`, and if the password is non-empty, after `passwordDelayMs` (400 ms) sends the password and writes
///   `· (heslo odesláno)`. **Logged in** = the first incoming line that contains the token, case-insensitively
///   (Kotlin `contains(ignoreCase = true)`), → `loggedIn`, „Přihlášeno jako <token>".
/// - `logout()`: `BYE` (sent on its own thread, `» BYE` immediately), „Odhlašuji…", `loggedIn = false`.
/// - `send(cmd)`: Kotlin `trim()`, empty does nothing; sent on its own thread, `» <cmd>` immediately.
/// - A read-loop error → `disconnect("Spojení ztraceno: <message>")` (message `null` when the Java exception
///   has none — `NoSuchElementException` from a traffic log with negative capacity).
/// - `disconnect(message)`: closes the client, clears `connected`/`connecting`/`loggedIn`/the login wait,
///   `currentFavorite = nil`, status = `message` (not translated), `· <message>` to the traffic log. `lastWwv` stays.
/// - `toggle`: connected → `disconnect("Odpojeno")` (verbatim, untranslated as in Kotlin), otherwise `connect`.
///
/// Errors that Kotlin does not catch: synchronous calls (`connect`, `logout`, `send`, `disconnect`, `toggle`)
/// throw the traffic-log error (`JavaNoSuchElementError` with negative capacity) to the caller — the state is already changed,
/// as in Kotlin. Errors from coroutines (sending login/password/`BYE`/a command, `disconnect` after a connection error,
/// an argument error on connect such as `port out of range`) go to `onUnexpectedError`; the state stays as it was
/// (so for an argument error „Připojuji…" with `connecting == true`).
///
/// Kotlin quirks deliberately preserved: `connect` while a connection is running opens a second one and lets the first keep running
/// (it keeps feeding the log and buffer); a connection error disconnects the **current** client, whichever it is; if the connection ends
/// before the connect thread writes success, the result depends on ordering (the same in Kotlin — two tasks on Main).
/// Not preserved (technique): a connect that finishes **after** a `disconnect` (any — the user's, the quit's, the
/// parallel plan's, a lost connection's) closes its new client instead of adopting it, so it never shows as connected
/// and never auto-logs in; Kotlin would adopt it.
///
/// Threads: state under a recursive lock (replacing Kotlin's main thread); `onChange` is called **under the lock**
/// from the thread that made the change (the caller, the connect thread, the client's reader thread). Writes to the
/// traffic log from `connect`, `disconnect`, `logout`, `send` and `login` (`log.info`/`tx`) also run under the same lock, so **the listeners of
/// `DxClusterTrafficLog`** (the log window) are called **sometimes under the session lock, sometimes without it** — an incoming line
/// is written by the reader thread (`handleLine` → `log.rx`) outside the lock. `onChange` and the log listener must therefore not synchronously
/// wait for another thread that would touch the session (e.g. `DispatchQueue.main.sync`), nor assume the lock is held;
/// and they **must not call mutating session methods** (`connect`, `disconnect`, `login`, `logout`, `send`, `toggle`):
/// `onChange` is called in the middle of methods (e.g. in `connect` before the connect thread starts) and a reentrant
/// `disconnect` would not stop the connection anyway. Every `onChange` carries a whole snapshot; on the main thread the UI layer should
/// re-read `snapshot` rather than rely on the delivery order of snapshots from different threads. `onSelfSpot` and `onSpot` are
/// called from the reader thread outside the lock (Kotlin `onSelfSpot` hops to Main — that is the UI layer's business).
public final class DxClusterSession: @unchecked Sendable {

    /// Immediate state for the UI (Kotlin `connected`, `connecting`, `status`, `loggedIn`, `lastWwv`,
    /// `currentFavorite`).
    public struct Snapshot: Equatable, Sendable {
        public var connected = false
        public var connecting = false
        /// Status message (already translated; the default „Odpojeno" is not translated in Kotlin).
        public var status = DxClusterSession.disconnectedText
        public var loggedIn = false
        /// Last WWV message from the node (solar and geomagnetic indices for the Info window).
        public var lastWwv: WwvMessage?
        public var currentFavorite: DxClusterFavorite?

        public init() {}
    }

    /// Timing (Kotlin: `delay(400)` before the password, `delay(1500)` before auto-login, Java connect timeout).
    public struct Timing: Equatable, Sendable {
        public var passwordDelayMs: Int
        public var autoLoginDelayMs: Int
        public var connectTimeoutMs: Int

        public init(passwordDelayMs: Int = 400, autoLoginDelayMs: Int = 1_500,
                    connectTimeoutMs: Int = DxClusterClient.defaultTimeoutMs) {
            self.passwordDelayMs = passwordDelayMs
            self.autoLoginDelayMs = autoLoginDelayMs
            self.connectTimeoutMs = connectTimeoutMs
        }
    }

    /// Default state (Kotlin `mutableStateOf("Odpojeno")`, without `tr`).
    public static let disconnectedText = "Odpojeno"
    /// Cluster logout command (on DXSpider/AR-Cluster it typically also ends the connection).
    public static let logoutCommand = "BYE"

    /// Spot buffer — concurrent connections share the main one's buffer, so everything goes into one bandmap.
    public let spots: SpotBuffer
    /// Traffic log — concurrent connections write to the main one's log with the prefix `tag`.
    public let log: DxClusterTrafficLog
    /// Line prefix in the log (name of the concurrent cluster); empty for the main connection.
    private let tag: String
    private let timing: Timing
    private let clock: @Sendable () -> Date
    private let translate: @Sendable (String) -> String
    private let onChange: @Sendable (Snapshot) -> Void
    private let onUnexpectedError: @Sendable (any Error) -> Void
    /// Kotlin `delay` (tests replace it with a controlled wait).
    private let sleep: @Sendable (Int) -> Void

    /// Replacement for Kotlin's main thread (reentrant — `onChange` may read the session).
    private let lock = NSRecursiveLock()
    private var current = Snapshot()
    private var client: DxClusterClient?
    private var awaitingLogin = false
    /// Raised by every `disconnect`: a connect started before it closes its client instead of adopting it.
    private var epoch: UInt64 = 0
    private var loginToken = ""
    private var callsign = ""
    private var selfSpotHandler: (@Sendable (SelfSpot) -> Void)?
    private var spotHandler: (@Sendable (DxSpot) throws -> Void)?
    /// Running session threads (connect, send) — tests wait for their end (`idle`).
    private var running = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var clientCreatedHook: (@Sendable () -> Void)?

    /// - Parameters:
    ///   - spots: spot buffer (Kotlin `SpotBuffer(90) { Instant.now() }`)
    ///   - log: traffic log (new for the main connection, shared for concurrent ones)
    ///   - tag: line prefix `[tag] ` in the log
    ///   - clock: time for `SelfSpot.detect` (Kotlin `Instant.now()`)
    ///   - translate: translation of the Czech key (`tr`); the session fills in the `%s` placeholder
    ///   - onChange: new state after every change (under the session lock)
    ///   - onUnexpectedError: error that Kotlin does not catch (see the type description)
    public convenience init(spots: SpotBuffer = SpotBuffer(maxAgeMinutes: 90, clock: { Date() }),
                            log: DxClusterTrafficLog = DxClusterTrafficLog(),
                            tag: String = "",
                            timing: Timing = Timing(),
                            clock: @escaping @Sendable () -> Date = { Date() },
                            translate: @escaping @Sendable (String) -> String = { $0 },
                            onChange: @escaping @Sendable (Snapshot) -> Void = { _ in },
                            onUnexpectedError: @escaping @Sendable (any Error) -> Void = { _ in }) {
        self.init(spots: spots, log: log, tag: tag, timing: timing, clock: clock, translate: translate,
                  onChange: onChange, onUnexpectedError: onUnexpectedError,
                  sleep: { ms in Thread.sleep(forTimeInterval: Double(max(ms, 0)) / 1_000) })
    }

    /// With a replacement for `delay` (tests: recording and controlled release of the wait; it runs on the session's
    /// own threads, never on the caller's).
    public init(spots: SpotBuffer, log: DxClusterTrafficLog, tag: String, timing: Timing,
                clock: @escaping @Sendable () -> Date, translate: @escaping @Sendable (String) -> String,
                onChange: @escaping @Sendable (Snapshot) -> Void,
                onUnexpectedError: @escaping @Sendable (any Error) -> Void,
                sleep: @escaping @Sendable (Int) -> Void) {
        self.spots = spots
        self.log = log
        self.tag = tag
        self.timing = timing
        self.clock = clock
        self.translate = translate
        self.onChange = onChange
        self.onUnexpectedError = onUnexpectedError
        self.sleep = sleep
    }

    // MARK: - State and settings

    public var snapshot: Snapshot {
        locked { current }
    }

    public var connected: Bool { snapshot.connected }
    public var connecting: Bool { snapshot.connecting }
    public var status: String { snapshot.status }
    public var loggedIn: Bool { snapshot.loggedIn }
    public var lastWwv: WwvMessage? { snapshot.lastWwv }
    public var currentFavorite: DxClusterFavorite? { snapshot.currentFavorite }

    /// The station's own callsign for the „you were spotted" report; empty = the report is not issued.
    public var myCall: String {
        get { locked { callsign } }
        set { locked { callsign = newValue } }
    }

    /// Spot of the own callsign (from the reader thread).
    public var onSelfSpot: (@Sendable (SelfSpot) -> Void)? {
        get { locked { selfSpotHandler } }
        set { locked { selfSpotHandler = newValue } }
    }

    /// Every spot received from the cluster (from the reader thread; errors are swallowed) — sharing the telnet over the network.
    public var onSpot: (@Sendable (DxSpot) throws -> Void)? {
        get { locked { spotHandler } }
        set { locked { spotHandler = newValue } }
    }

    public func setBufferMinutes(_ minutes: Int) {
        spots.setMaxAgeMinutes(minutes)
    }

    /// Sets the application blacklist (callsigns + spotters) into the buffer.
    public func setBlacklist(calls: [String], spotters: [String]) {
        spots.setBlacklist(calls: calls, spotters: spotters)
    }

    // MARK: - Connection

    public func toggle(_ fav: DxClusterFavorite) throws {
        lock.lock()
        defer { lock.unlock() }
        if current.connected {
            try disconnect(Self.disconnectedText)
        } else {
            try connect(fav)
        }
    }

    public func connect(_ fav: DxClusterFavorite, autoLogin: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        if KotlinText.isBlank(fav.host) {
            current.status = tr("Chybí adresa clusteru")
            onChange(current)
            return
        }
        let started: UInt64 = epoch
        current.connecting = true
        current.status = tr("Připojuji k %s…", Self.displayName(fav))
        onChange(current)
        try log.info(tr("Připojuji k %s:%s…", fav.host, String(fav.port)))
        background("dxcluster-connect") { [self] in
            runConnect(fav, autoLogin: autoLogin, epoch: started)
        }
    }

    /// Sends the saved login name and (if any) password — manually from the „Přihlásit" button.
    public func login(_ fav: DxClusterFavorite) {
        lock.lock()
        defer { lock.unlock() }
        guard let c = client else { return }
        if KotlinText.isBlank(fav.login) {
            current.status = tr("Favorit nemá vyplněné přihlašovací jméno")
            onChange(current)
            return
        }
        // Waiting for confirmation: the first incoming line with our callsign → logged in.
        loginToken = KotlinText.trim(fav.login)
        awaitingLogin = true
        current.status = tr("Přihlašuji jako %s…", fav.login)
        onChange(current)
        background("dxcluster-login") { [self] in
            reportingUnexpected {
                try c.send(fav.login)
                try log.tx(fav.login)
                if !KotlinText.isBlank(fav.password) {
                    sleep(timing.passwordDelayMs)
                    try c.send(fav.password)
                    try log.info(tr("(heslo odesláno)"))
                }
            }
        }
    }

    /// Sends the logout command and switches the state — manually from the „Odhlásit" button.
    public func logout() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let c = client else { return }
        awaitingLogin = false
        current.loggedIn = false
        current.status = tr("Odhlašuji…")
        onChange(current)
        sendInBackground(c, Self.logoutCommand)
        try log.tx(Self.logoutCommand)
    }

    /// Sends an arbitrary command (no-op when not connected).
    public func send(_ command: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let c = client else { return }
        let cmd = KotlinText.trim(command)
        if cmd.isEmpty { return }
        sendInBackground(c, cmd)
        try log.tx(cmd)
    }

    public func disconnect(_ message: String) throws {
        lock.lock()
        defer { lock.unlock() }
        client?.close()
        client = nil
        epoch &+= 1
        current.connected = false
        current.connecting = false
        current.loggedIn = false
        awaitingLogin = false
        current.currentFavorite = nil
        current.status = message
        onChange(current)
        try log.info(message)
    }

    // MARK: - Waiting

    /// Waits until all session threads finish (connect including auto-login, sending) — tests, and the quit that
    /// closes every connection.
    public func idle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if running == 0 {
                lock.unlock()
                continuation.resume()
                return
            }
            idleWaiters.append(continuation)
            lock.unlock()
        }
    }

    /// Test seam: runs on the connect thread after the new client exists and before it is adopted or dropped
    /// (tests hold it to order a `disconnect` deterministically against the connect).
    var onClientCreated: (@Sendable () -> Void)? {
        get { locked { clientCreatedHook } }
        set { locked { clientCreatedHook = newValue } }
    }

    // MARK: - Internals

    /// Kotlin coroutine `connect` (`withContext(IO)` without the lock, the rest on the main thread under the lock).
    private func runConnect(_ fav: DxClusterFavorite, autoLogin: Bool, epoch started: UInt64) {
        let newClient: DxClusterClient
        do {
            newClient = try DxClusterClient(
                host: fav.host, port: fav.port, timeoutMs: timing.connectTimeoutMs,
                onLine: { [self] line in try handleLine(line) },
                onError: { [self] err in connectionLost(err) })
        } catch let e as DxClusterException {
            reportingUnexpected { try disconnect(tr("Připojení selhalo: %s", e.message)) }
            return
        } catch {
            onUnexpectedError(error)
            return
        }
        if let hook = onClientCreated {
            hook()
        }
        lock.lock()
        if epoch != started {
            // Disconnected while connecting (the quit, the parallel plan): never adopted, never logged in.
            lock.unlock()
            newClient.close()
            return
        }
        client = newClient
        current.currentFavorite = fav
        current.connected = true
        current.connecting = false
        current.status = tr("Připojeno k %s", Self.displayName(fav))
        onChange(current)
        lock.unlock()
        // Concurrent connections (skimmers, RBN) log in by themselves — they have no window of their own.
        guard autoLogin && !KotlinText.isBlank(fav.login) else { return }
        sleep(timing.autoLoginDelayMs)
        lock.lock()
        defer { lock.unlock() }
        if client === newClient {
            login(fav)
        }
    }

    /// Kotlin line callback (client reader thread).
    private func handleLine(_ line: String) throws {
        try log.rx(tag.isEmpty ? line : "[\(tag)] \(line)")
        if let spot = DxSpotParser.parse(line) {
            spots.add(spot)
            if let callback = onSpot {
                try? callback(spot)
            }
            // Spot of the own callsign — report to the messages window.
            if let own = try SelfSpot.detect(spot, myCall: myCall, at: clock()), let callback = onSelfSpot {
                callback(own)
            }
        }
        // WWV — solar and geomagnetic indices for the Info window.
        if let wwv = try WwvMessage.parse(line) {
            lock.lock()
            current.lastWwv = wwv
            onChange(current)
            lock.unlock()
        }
        maybeConfirmLogin(line)
    }

    /// Detection of a successful login: the cluster repeats our callsign in its response (greeting/prompt).
    private func maybeConfirmLogin(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard awaitingLogin else { return }
        let token = loginToken
        if !KotlinText.isBlank(token) && KotlinText.containsIgnoreCase(line, token) {
            awaitingLogin = false
            current.loggedIn = true
            current.status = tr("Přihlášeno jako %s", token)
            onChange(current)
        }
    }

    private func connectionLost(_ err: any Error) {
        reportingUnexpected { try disconnect(tr("Spojení ztraceno: %s", Self.javaMessage(err))) }
    }

    private func sendInBackground(_ c: DxClusterClient, _ line: String) {
        background("dxcluster-send") { [self] in
            reportingUnexpected { try c.send(line) }
        }
    }

    /// Kotlin `scope.launch(Dispatchers.IO)` — its own thread, not the shared pool.
    private func background(_ name: String, _ body: @escaping @Sendable () -> Void) {
        locked { running += 1 }
        let thread = Thread { [self] in
            body()
            finishBackground()
        }
        thread.name = name
        thread.start()
    }

    private func finishBackground() {
        lock.lock()
        running -= 1
        var waiters: [CheckedContinuation<Void, Never>] = []
        if running == 0 {
            waiters = idleWaiters
            idleWaiters = []
        }
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func reportingUnexpected(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            onUnexpectedError(error)
        }
    }

    /// Kotlin `fav.name.ifBlank { fav.host }`.
    private static func displayName(_ fav: DxClusterFavorite) -> String {
        KotlinText.isBlank(fav.name) ? fav.host : fav.name
    }

    /// Java `Throwable.getMessage()` formatted `%s` (`null` without a message).
    static func javaMessage(_ error: any Error) -> String {
        switch error {
        case let e as DxClusterException:
            return e.message
        case let e as JavaNumberFormatError:
            return e.message
        case let e as JavaIllegalArgumentError:
            return e.message
        case let e as JavaIOError:
            return e.message ?? "null"
        case let e as JavaSocketError:
            return e.message ?? "null"
        case is JavaNoSuchElementError:
            return "null"
        default:
            return String(describing: error)
        }
    }

    /// Kotlin `tr(cs)` and `tr(cs, args…)` = `tr(cs).format(args)`. A translation with an invalid pattern (Kotlin would throw
    /// an exception from `format`) is replaced by the original Czech key.
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

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Kotlin text functions (JVM stdlib 2.1) that differ from Java's (measured by a probe over
/// `kotlin-stdlib-2.1.20`): `Char.isWhitespace()` = `Character.isWhitespace || Character.isSpaceChar`, so
/// `isBlank` and `trim` treat U+00A0, U+2007, U+202F as white too (Java `isBlank` does not) and `trim` keeps control
/// characters (U+0001) and U+0085 (Java `trim` drops U+0001). All by UTF-16 units.
enum KotlinText {

    /// `Char.isWhitespace()` on the JVM.
    static func isWhitespace(_ unit: UInt16) -> Bool {
        if JavaChar.isWhitespace(unit) {
            return true
        }
        guard let scalar = Unicode.Scalar(unit) else {
            return false
        }
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
    }

    /// `CharSequence.isBlank()`.
    static func isBlank(_ text: String) -> Bool {
        text.utf16.allSatisfy { isWhitespace($0) }
    }

    /// `String.trim()`.
    static func trim(_ text: String) -> String {
        let units: [UInt16] = Array(text.utf16)
        var start = 0
        var end: Int = units.count
        while start < end && isWhitespace(units[start]) { start += 1 }
        while end > start && isWhitespace(units[end - 1]) { end -= 1 }
        if start == 0 && end == units.count { return text }
        return JavaChar.string(Array(units[start..<end]))
    }

    /// `CharSequence.contains(other, ignoreCase = true)`: by UTF-16 units `Char.equals(ignoreCase)` =
    /// match of upper case, or lower case of upper case (like Java `regionMatches(true, …)`).
    static func containsIgnoreCase(_ text: String, _ other: String) -> Bool {
        let a: [UInt16] = Array(text.utf16)
        let b: [UInt16] = Array(other.utf16)
        if b.isEmpty { return true }
        if b.count > a.count { return false }
        for start in 0...(a.count - b.count) where regionMatches(a, start, b) {
            return true
        }
        return false
    }

    private static func regionMatches(_ a: [UInt16], _ start: Int, _ b: [UInt16]) -> Bool {
        for k in 0..<b.count where !charEqualsIgnoreCase(a[start + k], b[k]) {
            return false
        }
        return true
    }

    private static func charEqualsIgnoreCase(_ x: UInt16, _ y: UInt16) -> Bool {
        if x == y { return true }
        let ux: UInt16 = JavaChar.toUpperCase(x)
        let uy: UInt16 = JavaChar.toUpperCase(y)
        return ux == uy || JavaChar.toLowerCase(ux) == JavaChar.toLowerCase(uy)
    }
}
