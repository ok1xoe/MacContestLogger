import Foundation
import MCLCore
import Observation

/// Window plugins (protocol 1): `plugins/<name>/plugin.json` with an executable. A plugin's process starts when one
/// of its windows opens (menu Window → Custom, or restored from `config.openWindows` as `plugin:<name>/<window>`) and
/// stops when the user closes the last of them; a contest switch keeps it running (it hears `contest-closed` and
/// `contest-opened` when subscribed). The quit stops every plugin within the plugins' quit deadline.
///
/// The process talks JSON lines (`PluginWireProtocol`): the app sends `hello`, the subscribed events, the window
/// interactions and the answers to requests; the plugin replaces window contents, asks read-only requests
/// (`PluginRpc`) and writes lines for the messages window. A crash keeps the last content with a banner and Restart;
/// a plugin that does not answer `hello` within `helloTimeoutMs`, or does not read its input, is stopped as hung.
@Observable @MainActor
public final class PluginWindowsModel {

    /// The answer to `hello` must come this soon.
    public static let helloTimeoutMs = 10_000
    /// A window renders at most once per this interval (5 per second).
    public static let renderIntervalMs = 200
    /// Lines of stderr and `log` shown per run (then one notice).
    public static let outputLinesPerRun = 500
    /// The longest `log` text shown.
    static let maxLogText = 500

    /// The window plugins found by the last scan.
    public private(set) var catalog = PluginCatalog.Scan()
    /// `true` once the first scan finished.
    public private(set) var scanned = false
    /// The sessions of the plugins started at least once (by plugin id).
    public private(set) var sessions: [String: PluginSession] = [:]

    @ObservationIgnored let router = PluginEventRouter()
    @ObservationIgnored public var context = PluginHostContext()
    /// The quit's grace between `SIGTERM` and `SIGKILL`, and how long the quit waits for the exits; a test seam.
    @ObservationIgnored var quitGraceMs: Int = 1_000
    /// A test seam: told inside every database read of a request whether it runs on the main thread.
    @ObservationIgnored var readProbe: (@Sendable (Bool) -> Void)?

    @ObservationIgnored private let root: String
    @ObservationIgnored private let launcher: PluginLauncher?
    @ObservationIgnored private let windows: WindowsModel
    @ObservationIgnored private let messages: MessagesModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let appVersion: String?
    /// Window keys shown on screen (a view appeared and was not closed by the user).
    @ObservationIgnored private var shown: Set<String> = []
    @ObservationIgnored private var reportedProblems: Set<String> = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var quitting = false

    init(launcher: PluginLauncher?, dataDir: URL, windows: WindowsModel, messages: MessagesModel,
         language: LanguageModel, clock: any RescoreClock, now: @escaping @Sendable () -> Date, appVersion: String?) {
        self.launcher = launcher
        self.root = dataDir.appendingPathComponent("plugins").path
        self.windows = windows
        self.messages = messages
        self.language = language
        self.clock = clock
        self.now = now
        self.appVersion = appVersion
        router.onBackpressure.withLock { report in
            report = { [weak self] plugin, generation in
                self?.backpressure(plugin: plugin, generation: generation)
            }
        }
    }

    /// Window plugins can start at all (not under `MCL_INERT_*`).
    public var isActive: Bool {
        launcher != nil
    }

    // MARK: - catalog

    /// Reads the plugins directory again (off the main actor). New problems go to the messages window; the windows
    /// already shown start once their plugin is known.
    public func rescan() async {
        let root: String = self.root
        scanGeneration += 1
        let generation: Int = scanGeneration
        let scan: PluginCatalog.Scan = (try? await BlockingQueue.run { PluginCatalog.scan(root: root) })
            ?? PluginCatalog.Scan()
        // A later scan started meanwhile: its result is the current one.
        guard generation == scanGeneration else { return }
        catalog = scan
        scanned = true
        var texts: [String] = []
        for problem in scan.problems {
            let text: String = "[" + problem.plugin + "] " + language.text(problem.message)
            if reportedProblems.insert(text).inserted {
                texts.append(text)
            }
        }
        for package in scan.packages where !package.manifest.unsupportedPermissions.isEmpty {
            let text: String = refusalText(package)
            if reportedProblems.insert(text).inserted {
                texts.append(text)
            }
        }
        if !texts.isEmpty {
            messages.add(texts, at: now())
        }
        for key in shown.sorted() {
            if let parsed = PluginCatalog.parseWindowKey(key) {
                ensureRunning(parsed.plugin)
            }
        }
    }

    /// A rescan in the background (the menu opening); coalesced.
    public func refreshCatalog() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            await self?.rescan()
            self?.scanTask = nil
        }
    }

    /// The menu entries: every window of every plugin, by plugin then window order.
    public var menuWindows: [(key: String, title: String)] {
        catalog.packages.flatMap { package in
            package.manifest.windows.map { window in
                (PluginCatalog.windowKey(plugin: package.id, window: window.id), window.title)
            }
        }
    }

    public func session(_ plugin: String) -> PluginSession? {
        sessions[plugin]
    }

    /// The window's manifest entry (`nil` while unknown).
    public func window(_ key: String) -> PluginManifest.Window? {
        guard let parsed = PluginCatalog.parseWindowKey(key) else { return nil }
        return catalog.package(parsed.plugin)?.manifest.window(parsed.window)
    }

    /// The window title (the manifest's, else the key's plugin name).
    public func title(_ key: String) -> String {
        if let window = window(key) {
            return window.title
        }
        return PluginCatalog.parseWindowKey(key)?.plugin ?? key
    }

    // MARK: - windows

    /// Opens a plugin window (the menu): the app layer shows it and the process starts.
    public func open(_ key: String) {
        guard PluginCatalog.parseWindowKey(key) != nil else { return }
        windows.setOpen(key, true)
        windowAppeared(key)
    }

    /// A plugin window is on screen (also a restored one): its plugin runs.
    public func windowAppeared(_ key: String) {
        guard let parsed = PluginCatalog.parseWindowKey(key) else { return }
        shown.insert(key)
        ensureRunning(parsed.plugin)
    }

    /// The user closed a plugin window: its id leaves `openWindows`; the last window of a plugin stops it.
    public func windowClosed(_ key: String) {
        windows.setOpen(key, false)
        shown.remove(key)
        guard let parsed = PluginCatalog.parseWindowKey(key) else { return }
        let stillShown: Bool = shown.contains { PluginCatalog.parseWindowKey($0)?.plugin == parsed.plugin }
        if !stillShown {
            stop(parsed.plugin)
        }
    }

    /// The banner of a window (`nil` = none): why the plugin is not running.
    public func banner(_ key: String) -> String? {
        guard let parsed = PluginCatalog.parseWindowKey(key) else { return nil }
        guard let session = sessions[parsed.plugin] else {
            if scanned && catalog.package(parsed.plugin) == nil {
                return language.tr("Plugin %s nebyl nalezen", .string(parsed.plugin))
            }
            return nil
        }
        switch session.phase {
        case .exited(let code):
            return language.tr("Plugin skončil (kód %s)", .int(Int(code)))
        case .hung:
            return language.tr("Plugin neodpovídá — byl zastaven")
        case .failed(let reason):
            return language.tr("Plugin nelze spustit: %s", .string(reason))
        case .refused(let permissions):
            return language.tr("Plugin vyžaduje oprávnění, které tato verze neumí: %s",
                               .string(permissions.joined(separator: ", ")))
        case .disabled:
            return language.tr("Pluginy jsou v tomto režimu vypnuté")
        case .stopped, .starting, .running:
            return nil
        }
    }

    /// Restart after a crash or a hang.
    public func restart(_ plugin: String) {
        guard let session = sessions[plugin], session.canRestart else { return }
        session.phase = .stopped
        ensureRunning(plugin)
    }

    // MARK: - interactions

    /// A click (`double` = a double click) on a button, a table row or a list item.
    public func click(_ key: String, target: String, row: Int? = nil, rowId: String? = nil, double: Bool = false) {
        sendUi(key, action: double ? "double-click" : "click", target: target, row: row, rowId: rowId, value: nil)
    }

    /// A toggle changed: shown at once and sent as `change`.
    public func toggle(_ key: String, target: String, value: Bool) {
        guard let parsed = PluginCatalog.parseWindowKey(key) else { return }
        sessions[parsed.plugin]?.setToggle(window: parsed.window, id: target, value: value)
        sendUi(key, action: "change", target: target, row: nil, rowId: nil, value: .bool(value))
    }

    /// A tab was chosen (`select`, `value` = the tab id).
    public func selectTab(_ key: String, target: String, tab: String) {
        sendUi(key, action: "select", target: target, row: nil, rowId: nil, value: .string(tab))
    }

    private func sendUi(_ key: String, action: String, target: String, row: Int?, rowId: String?, value: PluginJSON?) {
        guard let parsed = PluginCatalog.parseWindowKey(key), let session = sessions[parsed.plugin],
              session.phase == .running || session.phase == .starting else { return }
        send(session, PluginOutbound.ui(window: parsed.window, action: action, target: target, row: row,
                                         rowId: rowId, value: value))
    }

    // MARK: - lifecycle

    private func ensureRunning(_ plugin: String) {
        guard !quitting, scanned, let package = catalog.package(plugin) else { return }
        let session: PluginSession = sessions[plugin] ?? PluginSession(package: package)
        sessions[plugin] = session
        switch session.phase {
        case .starting, .running, .exited, .hung, .failed:
            return
        case .stopped, .refused, .disabled:
            break
        }
        let refused: [String] = package.manifest.unsupportedPermissions
        guard refused.isEmpty else {
            session.phase = .refused(refused)
            return
        }
        guard let launcher else {
            session.phase = .disabled
            return
        }
        start(session, launcher: launcher)
    }

    private func start(_ session: PluginSession, launcher: PluginLauncher) {
        session.resetForRun()
        session.generation += 1
        let generation: Int = session.generation
        let plugin: String = session.package.id
        let handlers = PluginProcess.Handlers(
            message: { [weak self] message in
                MainHop.post { self?.received(message, plugin: plugin, generation: generation) }
            },
            protocolError: { [weak self] text in
                MainHop.post { self?.protocolError(text, plugin: plugin, generation: generation) }
            },
            stderr: { [weak self] line in
                MainHop.post { self?.output(line, plugin: plugin, generation: generation) }
            },
            exited: { [weak self] code in
                MainHop.post { self?.exited(code, plugin: plugin, generation: generation) }
            })
        let environment: [String: String] = [
            "MCL_PLUGIN_PROTOCOL": String(PluginManifest.protocolVersion), "MCL_PLUGIN_NAME": plugin,
            "PYTHONUNBUFFERED": "1",
        ]
        let connection: any PluginConnection = launcher(session.package, environment, handlers)
        do {
            try connection.start()
        } catch {
            session.phase = .failed(error.message)
            messages.add("[" + session.name + "] " + language.tr("Plugin nelze spustit: %s", .string(error.message)),
                         at: now())
            return
        }
        session.connection = connection
        session.phase = .starting
        router.add(plugin: plugin, generation: generation, events: session.package.manifest.events,
                   connection: connection)
        let contest = context.contest()
        let rig: PluginRigState? = context.rig()
        let hello = PluginOutbound.Hello(
            appVersion: appVersion, contestId: contest.id, contestName: contest.name,
            band: rig.flatMap { Band.from(frequencyHz: Int(clamping: $0.freqHz))?.adif }, mode: rig?.mode,
            windows: session.package.manifest.windows.map(\.id), permissions: session.package.manifest.permissions)
        send(session, PluginOutbound.hello(hello))
        session.helloTimer = clock.schedule(afterMilliseconds: Self.helloTimeoutMs) { [weak self, weak session] in
            guard let self, let session, session.generation == generation, session.phase == .starting else { return }
            self.markHung(session)
        }
    }

    /// Stops a plugin with its windows (no banner: its windows are gone).
    private func stop(_ plugin: String) {
        guard let session = sessions[plugin] else { return }
        router.remove(plugin: plugin)
        session.helloTimer?.cancel()
        session.helloTimer = nil
        if let connection = session.connection, connection.isRunning {
            session.stopping = true
            connection.terminate(graceMs: 1_000)
        }
        session.connection = nil
        session.phase = .stopped
    }

    private func markHung(_ session: PluginSession) {
        router.remove(plugin: session.package.id)
        session.helloTimer?.cancel()
        session.helloTimer = nil
        session.stopping = true
        session.connection?.kill()
        session.connection = nil
        session.phase = .hung
        messages.add("[" + session.name + "] " + language.tr("Plugin neodpovídá — byl zastaven"), at: now())
    }

    private func backpressure(plugin: String, generation: Int) {
        guard let session = sessions[plugin], session.generation == generation,
              session.phase == .running || session.phase == .starting else { return }
        markHung(session)
    }

    private func send(_ session: PluginSession, _ line: String) {
        guard let connection = session.connection else { return }
        if !connection.send(line) && connection.isRunning {
            markHung(session)
        }
    }

    private func current(_ plugin: String, _ generation: Int) -> PluginSession? {
        guard let session = sessions[plugin], session.generation == generation, !session.stopping,
              session.connection != nil else { return nil }
        return session
    }

    private func received(_ message: PluginInbound, plugin: String, generation: Int) {
        guard let session = current(plugin, generation) else { return }
        if session.phase == .starting {
            session.phase = .running
            session.helloTimer?.cancel()
            session.helloTimer = nil
        }
        switch message {
        case .ready:
            break
        case .set(let window, let content):
            guard session.package.manifest.window(window) != nil else {
                protocolError("set for an unknown window \(window)", plugin: plugin, generation: generation)
                return
            }
            for warning in content.warnings {
                protocolError(warning, plugin: plugin, generation: generation)
            }
            session.receive(window: window, content: content, clock: clock)
        case .request(let id, let method, let params):
            answer(session, id: id, method: method, params: params, generation: generation)
        case .log(let text):
            let cut: String = text.count > Self.maxLogText ? String(text.prefix(Self.maxLogText)) + "…" : text
            output(cut, plugin: plugin, generation: generation)
        case .unknown(let type):
            protocolError("unknown message type \(type)", plugin: plugin, generation: generation)
        }
    }

    private func answer(_ session: PluginSession, id: PluginJSON, method: String, params: [String: PluginJSON],
                        generation: Int) {
        let permissions: [String] = session.package.manifest.permissions
        let context: PluginHostContext = self.context
        let probe: (@Sendable (Bool) -> Void)? = readProbe
        let plugin: String = session.package.id
        Task { [weak self] in
            let result = await PluginRpc.answer(method: method, params: params, permissions: permissions,
                                                context: context, readProbe: probe)
            guard let self, let session = self.current(plugin, generation) else { return }
            switch result {
            case .success(let value):
                self.send(session, PluginOutbound.response(id: id, result: value))
            case .failure(let failure):
                self.send(session, PluginOutbound.error(id: id, code: failure.code, message: failure.message))
            }
        }
    }

    /// A line of stderr or a `log` message: into the messages window while the run's budget lasts.
    private func output(_ line: String, plugin: String, generation: Int) {
        guard let session = sessions[plugin], session.generation == generation else { return }
        guard session.outputBudget > 0 else { return }
        session.outputBudget -= 1
        var texts: [String] = ["[" + session.name + "] " + line]
        if session.outputBudget == 0 {
            texts.append("[" + session.name + "] " + language.tr("další výstup pluginu se nezobrazuje"))
        }
        messages.add(texts, at: now())
    }

    private func protocolError(_ text: String, plugin: String, generation: Int) {
        guard let session = sessions[plugin], session.generation == generation else { return }
        guard session.reportedErrors.insert(text).inserted else { return }
        messages.add("[" + session.name + "] " + language.tr("chyba protokolu: %s", .string(text)), at: now())
    }

    private func exited(_ code: Int32, plugin: String, generation: Int) {
        guard let session = sessions[plugin], session.generation == generation else { return }
        router.remove(plugin: plugin)
        session.helloTimer?.cancel()
        session.helloTimer = nil
        session.connection = nil
        if session.stopping {
            return
        }
        session.phase = .exited(code)
        messages.add("[" + session.name + "] " + language.tr("Plugin skončil (kód %s)", .int(Int(code))), at: now())
    }

    private func refusalText(_ package: PluginPackage) -> String {
        "[" + package.id + "] " + language.tr("Plugin vyžaduje oprávnění, které tato verze neumí: %s",
                                              .string(package.manifest.unsupportedPermissions.joined(separator: ", ")))
    }

    // MARK: - quit

    /// The first step of the quit, right after `app-quitting` was queued for the subscribers: no further event or
    /// start, and every plugin's input is closed after that last line (a plugin may end on its own meanwhile).
    func beginShutdown() {
        quitting = true
        for session in sessions.values {
            router.remove(plugin: session.package.id)
            session.connection?.closeInput()
        }
    }

    /// The quit's last step: every plugin still running gets `SIGTERM`, `SIGKILL` after `quitGraceMs`; the wait for
    /// the exits is bounded by that grace plus a little, so the quit is never held longer.
    func shutdown() async {
        quitting = true
        let running: [any PluginConnection] = sessions.values.compactMap { session in
            router.remove(plugin: session.package.id)
            session.helloTimer?.cancel()
            session.stopping = true
            return session.connection
        }
        guard !running.isEmpty else { return }
        let grace: Int = quitGraceMs
        for connection in running {
            connection.terminate(graceMs: grace)
        }
        let gate = WaitGate()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(grace + 500)) {
            gate.fire()
        }
        Task {
            for connection in running {
                await connection.waitForExit()
            }
            gate.fire()
        }
        await gate.wait()
    }
}
