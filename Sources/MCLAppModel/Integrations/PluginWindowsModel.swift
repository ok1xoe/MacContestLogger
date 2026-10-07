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
    /// Requests of one plugin answered at the same time; more get the `busy` error at once.
    public static let maxRequestsInFlight = 4
    /// Raw CAT commands of one plugin per second; more get `rate_limited`.
    public static let catPerSecond = 10
    /// How often the transmit indicator checks whether a plugin's transmission ended.
    static let transmitCheckMs = 500

    /// The window plugins found by the last scan.
    public private(set) var catalog = PluginCatalog.Scan()
    /// `true` once the first scan finished.
    public private(set) var scanned = false
    /// The sessions of the plugins started at least once (by plugin id).
    public private(set) var sessions: [String: PluginSession] = [:]
    /// The operator's grants, key bindings and docked windows (`plugin-settings.json`).
    public private(set) var settings = PluginSettings()
    /// The plugin whose first-use consent sheet is up (`nil` = none).
    public private(set) var consentRequest: String?
    /// The plugin holding the PTT (`tx.ptt`), released after `settings.pttTimeoutSeconds` at the latest.
    public private(set) var pttHolder: String?
    /// The plugin whose transmission (a message, the PTT) is going on now: the entry window says so.
    public private(set) var transmitting: String?

    @ObservationIgnored let router = PluginEventRouter()
    @ObservationIgnored public var context = PluginHostContext()
    /// The quit's grace between `SIGTERM` and `SIGKILL`, and how long the quit waits for the exits; a test seam.
    @ObservationIgnored var quitGraceMs: Int = 1_000
    /// A test seam: told inside every database read of a request whether it runs on the main thread.
    @ObservationIgnored var readProbe: (@Sendable (Bool) -> Void)?

    @ObservationIgnored private let root: String
    @ObservationIgnored private let dataDir: URL
    @ObservationIgnored private var settingsLoaded = false
    @ObservationIgnored private var saveChain: Task<Void, Never>?
    @ObservationIgnored private var consentNoticeShown: Set<String> = []
    @ObservationIgnored private var keyRestarts: [String: [Date]] = [:]
    @ObservationIgnored private var keyRestartRefused: Set<String> = []
    /// The settings as last read from or written to the file (a change by anyone else is detected at the next scan).
    @ObservationIgnored private var settingsOnDisk: PluginSettings?
    @ObservationIgnored private var pttTimer: (any RescoreTimer)?
    @ObservationIgnored private var transmitTimer: (any RescoreTimer)?
    @ObservationIgnored private var catTimes: [String: [Date]] = [:]
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
    /// One counter for every run of every plugin: a late message of an earlier run never matches a later one,
    /// even when the session object was replaced.
    @ObservationIgnored private var lastGeneration = 0
    /// Stopped processes not yet ended (by run), held until their exit and killed at the quit.
    @ObservationIgnored private(set) var retiring: [Int: any PluginConnection] = [:]

    init(launcher: PluginLauncher?, dataDir: URL, windows: WindowsModel, messages: MessagesModel,
         language: LanguageModel, clock: any RescoreClock, now: @escaping @Sendable () -> Date, appVersion: String?) {
        self.launcher = launcher
        self.root = dataDir.appendingPathComponent("plugins").path
        self.dataDir = dataDir
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
        let dir: URL = dataDir
        let onDisk: PluginSettings = (try? await BlockingQueue.run { PluginSettings.load(dataDir: dir) })
            ?? PluginSettings()
        if !settingsLoaded {
            settingsLoaded = true
            settings = validated(onDisk, scan: scan)
            settingsOnDisk = onDisk
            if settings != onDisk {
                saveSettings()
            }
            shown.formUnion(settings.docked)
        } else if let known = settingsOnDisk, onDisk != known, saveChain == nil {
            // Changed by someone else while the app runs (a plugin could write it): the app's decisions win and
            // are written back; the operator is told.
            messages.add(language.tr("plugin-settings.json byl změněn mimo aplikaci — platí nastavení aplikace"),
                         at: now())
            saveSettings()
        }
        // A later scan started meanwhile: its result is the current one.
        guard generation == scanGeneration else { return }
        catalog = scan
        scanned = true
        var texts: [String] = []
        // Keyed by the plugin and the untranslated message, so a language switch does not repeat them.
        for problem in scan.problems
        where reportedProblems.insert(problem.plugin + "\u{0}" + String(describing: problem.message)).inserted {
            texts.append("[" + problem.plugin + "] " + language.text(problem.message))
        }
        for package in scan.packages where !package.manifest.unsupportedPermissions.isEmpty {
            let key: String = package.id + "\u{0}refused\u{0}" + package.manifest.unsupportedPermissions.joined(separator: ",")
            if reportedProblems.insert(key).inserted {
                texts.append(refusalText(package))
            }
        }
        if !texts.isEmpty {
            messages.add(texts, at: now())
        }
        for key in shown.sorted() {
            if let parsed = PluginCatalog.parseWindowKey(key), sessions[parsed.plugin]?.phase != .awaitingConsent {
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
        // A docked window's own window closes when it docks: the plugin keeps running for the panel.
        guard !settings.docked.contains(key) else { return }
        shown.remove(key)
        guard let parsed = PluginCatalog.parseWindowKey(key) else { return }
        let stillShown: Bool = shown.contains { PluginCatalog.parseWindowKey($0)?.plugin == parsed.plugin }
        if !stillShown {
            stop(parsed.plugin)
        }
    }

    // MARK: - grants

    /// The permissions `plugin` may use now (the implicit ones and the granted ones it asked for).
    public func effectivePermissions(_ plugin: String) -> [String] {
        guard let package = catalog.package(plugin) else { return [] }
        return settings.effectivePermissions(package.manifest)
    }

    /// Opens the consent sheet for `plugin` (the operator's click on the banner or in Settings → Plugins; never
    /// by itself, so the sheet never takes the keyboard in the middle of a QSO).
    public func requestConsent(_ plugin: String) {
        guard let package = catalog.package(plugin), settings.needsConsent(package.manifest) else { return }
        consentRequest = plugin
    }

    /// The permissions the consent sheet asks about for `plugin` (the undecided ones).
    public func consentPermissions(_ plugin: String) -> [String] {
        guard let package = catalog.package(plugin) else { return [] }
        return settings.undecided(package.manifest)
    }

    /// The consent sheet's answer: `granted` of the permissions it showed (`shown`); the rest of them is decided
    /// as not granted. The plugin starts if it waits for it.
    public func answerConsent(_ plugin: String, granted: [String], shown: [String]? = nil) {
        guard let package = catalog.package(plugin) else { return }
        let asked: [String] = shown ?? settings.undecided(package.manifest)
        settings.decide(package.manifest, granted: granted, decided: asked)
        saveSettings()
        if consentRequest == plugin {
            consentRequest = nil
        }
        if let session = sessions[plugin], session.phase == .awaitingConsent, !settings.needsConsent(package.manifest) {
            session.phase = .stopped
            ensureRunning(plugin)
        }
    }

    /// Sets the granted permissions (Settings → Plugins; every requested one counts as decided); a revoke applies
    /// to every request answered from now on, also one already queued.
    public func setGrants(_ plugin: String, _ granted: [String]) {
        guard let package = catalog.package(plugin) else { return }
        settings.decide(package.manifest, granted: granted, decided: package.manifest.permissionsNeedingGrant)
        saveSettings()
        if let session = sessions[plugin], session.phase == .awaitingConsent {
            session.phase = .stopped
            ensureRunning(plugin)
        }
    }

    // MARK: - keys

    /// A key a plugin action may take: an allowed shortcut (`KeyCombo.isAllowedShortcut`) that is not Esc, Enter,
    /// Tab, the space bar or a plain F1–F12 (the transmit and stop keys always stay the app's).
    public static func isBindable(_ combo: KeyCombo) -> Bool {
        guard combo.isAllowedShortcut else { return false }
        let reserved: Set<Int32> = [AwtKeyCodes.vkEscape, AwtKeyCodes.vkEnter, AwtKeyCodes.vkTab, AwtKeyCodes.vkSpace]
        if reserved.contains(combo.keyCode) {
            return false
        }
        let plainFKey: Bool = combo.keyCode >= AwtKeyCodes.vkF1 && combo.keyCode <= AwtKeyCodes.vkF12
            && !(combo.ctrl || combo.alt || combo.meta)
        return !plainFKey
    }

    /// Binds a key text (`KeyCombo` form) to a plugin action; `nil` removes the binding. `nil` = done, else why not
    /// (a key that may not be bound, or one another plugin action has).
    @discardableResult
    public func bindKey(plugin: String, action: String, key: String?) -> String? {
        let id: String = PluginSettings.actionKey(plugin: plugin, action: action)
        guard let key else {
            settings.keys[id] = nil
            saveSettings()
            return nil
        }
        guard let combo = KeyCombo.parse(key), Self.isBindable(combo) else {
            return language.tr("Tuto klávesu nelze pluginu přiřadit")
        }
        if let other = settings.keys.first(where: { $0.key != id && KeyCombo.parse($0.value) == combo }) {
            return language.tr("Klávesu už má akce %s", .string(other.key))
        }
        settings.keys[id] = combo.format()
        saveSettings()
        return nil
    }

    /// The app's own shortcut on the key of a plugin action (shown as a conflict; the plugin's key wins).
    public func keyConflict(plugin: String, action: String) -> String? {
        let id: String = PluginSettings.actionKey(plugin: plugin, action: action)
        guard let text = settings.keys[id], let combo = KeyCombo.parse(text) else { return nil }
        return context.shortcutLabel(combo)
    }

    /// Whether the bound key keeps its own entry-window function too.
    public func setPassThrough(plugin: String, action: String, _ on: Bool) {
        let id: String = PluginSettings.actionKey(plugin: plugin, action: action)
        settings.passThrough.removeAll { $0 == id }
        if on {
            settings.passThrough.append(id)
        }
        saveSettings()
    }

    /// The plugin action bound to `combo`, if any (a key that may not be bound never matches).
    public func keyAction(for combo: KeyCombo) -> (plugin: String, action: String, passThrough: Bool)? {
        guard Self.isBindable(combo) else { return nil }
        for (id, text) in settings.keys.sorted(by: { $0.key < $1.key }) where KeyCombo.parse(text) == combo {
            guard let slash = id.firstIndex(of: "/") else { continue }
            let plugin = String(id[..<slash])
            let action = String(id[id.index(after: slash)...])
            guard catalog.package(plugin)?.manifest.action(action) != nil else { continue }
            return (plugin, action, settings.passThrough.contains(id))
        }
        return nil
    }

    /// The entry windows' hook (`EntryModel.pluginKeyHook`): `nil` when no plugin action is bound to `combo`; on the
    /// press the action runs. Esc never reaches a plugin (it always stops the transmission).
    public func handleKey(_ combo: KeyCombo, pressed: Bool) -> Bool? {
        guard combo.keyCode != AwtKeyCodes.vkEscape, let bound = keyAction(for: combo) else { return nil }
        if pressed {
            pressKey(plugin: bound.plugin, action: bound.action)
        }
        return bound.passThrough
    }

    /// Automatic restarts by keys within a minute before a crashing plugin stays stopped (Restart starts it again).
    public static let maxKeyRestartsPerMinute = 3

    /// A bound key was pressed: the plugin is started if needed (also one without windows; it then runs until the
    /// quit) and gets `{"type":"key","action":…}`. A plugin that keeps crashing is restarted by keys at most
    /// `maxKeyRestartsPerMinute` times a minute.
    public func pressKey(plugin: String, action: String) {
        guard catalog.package(plugin)?.manifest.action(action) != nil else { return }
        if sessions[plugin]?.connection == nil {
            if let session = sessions[plugin], session.canRestart {
                let current: Date = now()
                let recent: [Date] = (keyRestarts[plugin] ?? []).filter { current.timeIntervalSince($0) < 60 }
                guard recent.count < Self.maxKeyRestartsPerMinute else {
                    keyRestarts[plugin] = recent
                    if !keyRestartRefused.contains(plugin) {
                        keyRestartRefused.insert(plugin)
                        messages.add("[" + session.name + "] " + language.tr(
                            "Plugin opakovaně padá — klávesa ho už nespustí, použij Restart"), at: now())
                    }
                    return
                }
                keyRestarts[plugin] = recent + [current]
                session.phase = .stopped
            }
            ensureRunning(plugin)
        }
        guard let session = sessions[plugin], session.connection != nil else { return }
        send(session, PluginOutbound.key(action: action))
    }

    // MARK: - docking

    public func isDocked(_ key: String) -> Bool {
        settings.docked.contains(key)
    }

    /// The docked windows, in docking order.
    public var dockedKeys: [String] {
        settings.docked
    }

    /// Docks a window into the main window: its own window closes, the plugin keeps running.
    public func dock(_ key: String) {
        guard PluginCatalog.parseWindowKey(key) != nil, !settings.docked.contains(key) else { return }
        settings.docked.append(key)
        saveSettings()
        shown.insert(key)
        windows.setOpen(key, false)
    }

    /// Back into a window of its own.
    public func undock(_ key: String) {
        guard settings.docked.contains(key) else { return }
        settings.docked.removeAll { $0 == key }
        saveSettings()
        windows.setOpen(key, true)
        windowAppeared(key)
    }

    /// The docked panel's close: as closing its window.
    public func closeDocked(_ key: String) {
        guard settings.docked.contains(key) else { return }
        settings.docked.removeAll { $0 == key }
        saveSettings()
        windowClosed(key)
    }

    private func saveSettings() {
        let snapshot: PluginSettings = settings
        settingsOnDisk = snapshot
        let dir: URL = dataDir
        let previous: Task<Void, Never>? = saveChain
        let task = Task { [weak self] in
            await previous?.value
            _ = try? await BlockingQueue.run { try snapshot.save(dataDir: dir) }
            self?.saveFinished()
        }
        saveChain = task
    }

    private func saveFinished() {
        // The chain is idle again once its last write finished (a scan compares the file only then).
        Task { [weak self] in
            await self?.saveChain?.value
            self?.saveChain = nil
        }
    }

    /// Drops what the file may hold but the app never accepts: keys that may not be bound or are bound twice, and
    /// docked windows of plugins or windows that no longer exist. Each dropped key is reported.
    private func validated(_ loaded: PluginSettings, scan: PluginCatalog.Scan) -> PluginSettings {
        var settings: PluginSettings = loaded
        var seen: Set<KeyCombo> = []
        for (id, text) in loaded.keys.sorted(by: { $0.key < $1.key }) {
            guard let combo = KeyCombo.parse(text), Self.isBindable(combo), seen.insert(combo).inserted else {
                settings.keys[id] = nil
                messages.add(language.tr("Klávesa %s pro akci pluginu %s se nepoužije", .string(text), .string(id)),
                             at: now())
                continue
            }
            settings.keys[id] = combo.format()
        }
        settings.docked = loaded.docked.filter { key in
            guard let parsed = PluginCatalog.parseWindowKey(key) else { return false }
            return scan.package(parsed.plugin)?.manifest.window(parsed.window) != nil
        }
        return settings
    }

    /// Waits for the settings writes queued so far (tests).
    func settleSettings() async {
        await saveChain?.value
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
        case .awaitingConsent:
            return language.tr("Plugin čeká na povolení oprávnění")
        case .stopped, .starting, .running:
            return nil
        }
    }

    /// Restart after a crash or a hang.
    public func restart(_ plugin: String) {
        guard let session = sessions[plugin], session.canRestart else { return }
        keyRestarts[plugin] = nil
        keyRestartRefused.remove(plugin)
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

    /// A click on a canvas: `value` is the point `{x, y}` in canvas coordinates.
    public func canvasClick(_ key: String, target: String, x: Double, y: Double) {
        sendUi(key, action: "click", target: target, row: nil, rowId: nil,
               value: .object(["x": .double((x * 10).rounded() / 10), "y": .double((y * 10).rounded() / 10)]))
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
        var session: PluginSession = sessions[plugin] ?? PluginSession(package: package)
        if session.package != package && session.connection == nil {
            // The manifest changed since the last run: the next run uses the new one.
            session = PluginSession(package: package)
        }
        sessions[plugin] = session
        switch session.phase {
        case .starting, .running, .exited, .hung, .failed, .awaitingConsent:
            return
        case .stopped, .refused, .disabled:
            break
        }
        let refused: [String] = package.manifest.unsupportedPermissions
        guard refused.isEmpty else {
            session.phase = .refused(refused)
            return
        }
        if launcher != nil && settings.needsConsent(package.manifest) {
            session.phase = .awaitingConsent
            if !consentNoticeShown.contains(plugin) {
                consentNoticeShown.insert(plugin)
                messages.add("[" + session.name + "] " + language.tr(
                    "Plugin čeká na povolení oprávnění — rozhodni v jeho okně nebo v Nastavení → Pluginy"), at: now())
            }
            return
        }
        guard let launcher else {
            session.phase = .disabled
            return
        }
        guard package.manifest.hasProcess else {
            // Only web windows: nothing to start, the pages talk to the app themselves.
            session.phase = .running
            return
        }
        start(session, launcher: launcher)
    }

    private func start(_ session: PluginSession, launcher: PluginLauncher) {
        session.resetForRun()
        lastGeneration += 1
        session.generation = lastGeneration
        let generation: Int = session.generation
        let plugin: String = session.package.id
        let inbox = PluginInbox(outputBudget: Self.outputLinesPerRun) { [weak self] batch in
            self?.received(batch, plugin: plugin, generation: generation)
        }
        let handlers = PluginProcess.Handlers(
            message: { message in inbox.receive(message) },
            protocolError: { text in inbox.protocolError(text) },
            stderr: { line in inbox.stderr(line) },
            exited: { [weak self] code in
                MainHop.post { self?.exited(code, plugin: plugin, generation: generation) }
            })
        let environment: [String: String] = [
            "MCL_PLUGIN_PROTOCOL": String(PluginManifest.protocolVersion), "MCL_PLUGIN_NAME": plugin,
            "PYTHONUNBUFFERED": "1",
        ]
        let connection: any PluginConnection = launcher(session.package, environment, handlers)
        session.connection = connection
        session.inbox = inbox
        session.phase = .starting
        let contest = context.contest()
        let rig: PluginRigState? = context.rig()
        let hello = PluginOutbound.Hello(
            appVersion: appVersion, contestId: contest.id, contestName: contest.name,
            band: rig.flatMap { Band.from(frequencyHz: Int(clamping: $0.freqHz))?.adif }, mode: rig?.mode,
            windows: session.package.manifest.windows.map(\.id),
            permissions: settings.effectivePermissions(session.package.manifest))
        send(session, PluginOutbound.hello(hello))
        session.helloTimer = clock.schedule(afterMilliseconds: Self.helloTimeoutMs) { [weak self, weak session] in
            guard let self, let session, session.generation == generation, session.phase == .starting else { return }
            self.markHung(session)
        }
        // The spawn (fork and exec) runs off the main actor; what is sent meanwhile waits in the session.
        Task { [weak self] in
            let failure: String?
            do {
                failure = try await BlockingQueue.run { () -> String? in
                    do throws(ProcessRunnerError) {
                        try connection.start()
                        return nil
                    } catch {
                        return error.message
                    }
                }
            } catch {
                failure = "the start was cancelled"
            }
            self?.spawned(plugin: plugin, generation: generation, connection: connection, failure: failure)
        }
    }

    private func spawned(plugin: String, generation: Int, connection: any PluginConnection, failure: String?) {
        guard let session = sessions[plugin], session.generation == generation, !session.stopping,
              session.connection === connection else {
            // Stopped while it was being started: it must not stay running.
            if failure == nil {
                connection.kill()
            }
            return
        }
        if let failure {
            _ = retire(session)
            session.phase = .failed(failure)
            messages.add("[" + session.name + "] " + language.tr("Plugin nelze spustit: %s", .string(failure)),
                         at: now())
            return
        }
        session.spawned = true
        router.add(plugin: plugin, generation: generation, events: session.package.manifest.events,
                   connection: connection)
        let pending: [String] = session.pendingLines
        session.pendingLines = []
        for line in pending {
            send(session, line)
        }
    }

    /// Takes the connection off a session that stops: no more events or messages; the process is held in
    /// `retiring` until it ended (so the quit can still kill it).
    private func retire(_ session: PluginSession) -> (any PluginConnection)? {
        // A plugin that stops never leaves the transmitter keyed.
        if pttHolder == session.package.id {
            releasePtt(reason: nil)
        }
        router.remove(plugin: session.package.id)
        session.helloTimer?.cancel()
        session.helloTimer = nil
        session.inbox?.close()
        session.inbox = nil
        session.inFlight = 0
        guard let connection = session.connection else { return nil }
        session.stopping = true
        session.connection = nil
        let generation: Int = session.generation
        retiring[generation] = connection
        Task { [weak self] in
            await connection.waitForExit()
            self?.retiring[generation] = nil
        }
        return connection
    }

    /// Stops a plugin with its windows (no banner: its windows are gone).
    private func stop(_ plugin: String) {
        guard let session = sessions[plugin] else { return }
        if pttHolder == plugin {
            releasePtt(reason: nil)
        }
        retire(session)?.terminate(graceMs: 1_000)
        session.phase = .stopped
    }

    private func markHung(_ session: PluginSession) {
        retire(session)?.kill()
        session.phase = .hung
        messages.add("[" + session.name + "] " + language.tr("Plugin neodpovídá — byl zastaven"), at: now())
    }

    private func backpressure(plugin: String, generation: Int) {
        guard let session = sessions[plugin], session.generation == generation,
              session.phase == .running || session.phase == .starting else { return }
        markHung(session)
    }

    /// Sends a line; a full input is a hang, a closed one (the plugin closed its stdin) only ends the sending.
    private func send(_ session: PluginSession, _ line: String) {
        guard let connection = session.connection else { return }
        guard session.spawned else {
            if session.pendingLines.count < 64 {
                session.pendingLines.append(line)
            }
            return
        }
        switch connection.send(line) {
        case .sent:
            break
        case .full:
            markHung(session)
        case .closed:
            if !session.inputClosedReported && connection.isRunning {
                session.inputClosedReported = true
                router.remove(plugin: session.package.id)
            }
        }
    }

    private func current(_ plugin: String, _ generation: Int) -> PluginSession? {
        guard let session = sessions[plugin], session.generation == generation, !session.stopping,
              session.connection != nil else { return nil }
        return session
    }

    private func received(_ batch: PluginInbox.Batch, plugin: String, generation: Int) {
        guard let session = current(plugin, generation) else { return }
        if session.phase == .starting {
            session.phase = .running
            session.helloTimer?.cancel()
            session.helloTimer = nil
        }
        var texts: [String] = []
        for item in batch.items {
            switch item {
            case .message(let message):
                handle(message, session: session, generation: generation, texts: &texts)
            case .output(let line):
                texts.append("[" + session.name + "] " + line)
            case .outputSuppressed:
                texts.append("[" + session.name + "] " + language.tr("další výstup pluginu se nezobrazuje"))
            case .protocolError(let text):
                texts.append(protocolText(session, text))
            }
            // A request answered `busy`, a hang: the run may have ended inside the loop.
            guard current(plugin, generation) != nil else { break }
        }
        if current(plugin, generation) != nil {
            for (window, content) in batch.sets {
                apply(window: window, content: content, session: session, texts: &texts)
            }
        }
        if !texts.isEmpty {
            messages.add(texts, at: now())
        }
    }

    private func handle(_ message: PluginInbound, session: PluginSession, generation: Int, texts: inout [String]) {
        switch message {
        case .ready, .set, .log:
            // `set` and `log` come through the inbox's own channels.
            break
        case .request(let id, let method, let params):
            answer(session, id: id, method: method, params: params, generation: generation)
        case .unknown(let type):
            reportOnce(session, "unknown message type \(type)", texts: &texts)
        }
    }

    private func apply(window: String, content: PluginUIContent, session: PluginSession, texts: inout [String]) {
        guard session.package.manifest.permissions.contains("ui") else {
            reportOnce(session, "set needs the ui permission", texts: &texts)
            return
        }
        guard session.package.manifest.window(window) != nil else {
            reportOnce(session, "set for an unknown window \(window)", texts: &texts)
            return
        }
        for warning in content.warnings {
            reportOnce(session, warning, texts: &texts)
        }
        session.receive(window: window, content: content, clock: clock)
    }

    private func reportOnce(_ session: PluginSession, _ text: String, texts: inout [String]) {
        guard session.reportedErrors.insert(text).inserted else { return }
        texts.append(protocolText(session, text))
    }

    private func protocolText(_ session: PluginSession, _ text: String) -> String {
        "[" + session.name + "] " + language.tr("chyba protokolu: %s", .string(text))
    }

    /// Answers a request off the main actor where it reads the database; at most `maxRequestsInFlight` at a time —
    /// more get `busy` at once (a looping plugin must not starve the logbook queue that logging uses).
    private func answer(_ session: PluginSession, id: PluginJSON, method: String, params: [String: PluginJSON],
                        generation: Int) {
        guard session.inFlight < Self.maxRequestsInFlight else {
            send(session, PluginOutbound.error(id: id, code: "busy", message: "more than \(Self.maxRequestsInFlight) requests at once"))
            return
        }
        if method == "cat.send" && settings.effectivePermissions(session.package.manifest).contains("cat")
            && !admitCat(session.package.id) {
            send(session, PluginOutbound.error(id: id, code: "rate_limited",
                                               message: "more than \(Self.catPerSecond) CAT commands a second"))
            return
        }
        session.inFlight += 1
        let context: PluginHostContext = self.context
        let probe: (@Sendable (Bool) -> Void)? = readProbe
        let plugin: String = session.package.id
        Task { [weak self] in
            // A plugin stopped meanwhile acts no more (above all: it never keys the transmitter afterwards); a
            // permission revoked meanwhile counts.
            guard let self, let running = self.current(plugin, generation) else { return }
            let permissions: [String] = self.settings.effectivePermissions(running.package.manifest)
            let result = await PluginRpc.answer(method: method, params: params, permissions: permissions,
                                                context: context, readProbe: probe)
            guard let session = self.current(plugin, generation) else {
                // The run ended while a PTT request was answered: release what it may have keyed.
                if method == "tx.ptt", case .success = result, self.pttHolder == nil {
                    _ = context.actions.ptt(false)
                }
                return
            }
            session.inFlight -= 1
            if case .success = result, method.hasPrefix("tx.") {
                self.transmitted(method: method, params: params, plugin: plugin, name: session.name)
            }
            switch result {
            case .success(let value):
                self.send(session, PluginOutbound.response(id: id, result: value))
            case .failure(let failure):
                self.send(session, PluginOutbound.error(id: id, code: failure.code, message: failure.message))
            }
        }
    }

    // MARK: - web windows

    /// Web pages' requests answered at the same time per plugin.
    @ObservationIgnored private var webInFlight: [String: Int] = [:]

    /// A request of a web window's page (`window.mcl.request`): the same methods, permissions, limits and transmit
    /// rules as a process's requests. Answers `{"result": …}` or `{"error": {"code", "message"}}`.
    public func webAnswer(_ key: String, method: String, params: [String: PluginJSON]) async -> PluginJSON {
        func error(_ code: String, _ message: String) -> PluginJSON {
            .object(["error": .object(["code": .string(code), "message": .string(message)])])
        }
        guard let parsed = PluginCatalog.parseWindowKey(key), let package = catalog.package(parsed.plugin),
              package.manifest.window(parsed.window)?.isWeb == true else {
            return error("unavailable", "not a web window")
        }
        let plugin: String = package.id
        guard sessions[plugin]?.phase == .running else {
            return error("unavailable", "the plugin is not running (permissions undecided, refused or switched off)")
        }
        let inFlight: Int = webInFlight[plugin] ?? 0
        guard inFlight < Self.maxRequestsInFlight else {
            return error("busy", "more than \(Self.maxRequestsInFlight) requests at once")
        }
        let permissions: [String] = settings.effectivePermissions(package.manifest)
        if method == "cat.send" && permissions.contains("cat") && !admitCat(plugin) {
            return error("rate_limited", "more than \(Self.catPerSecond) CAT commands a second")
        }
        webInFlight[plugin] = inFlight + 1
        defer { webInFlight[plugin] = max((webInFlight[plugin] ?? 1) - 1, 0) }
        let result = await PluginRpc.answer(method: method, params: params, permissions: permissions,
                                            context: context, readProbe: readProbe)
        switch result {
        case .success(let value):
            if method.hasPrefix("tx.") {
                transmitted(method: method, params: params, plugin: plugin, name: package.manifest.name)
            }
            // Rendered answers (`raw`) are parsed back, so the caller gets plain values.
            return .object(["result": (try? PluginJSON.parse(value.serialized())) ?? value])
        case .failure(let failure):
            return error(failure.code, failure.message)
        }
    }

    /// A web window's page listens to its plugin's subscribed events; `deliver` gets each event line (any thread).
    public func addWebListener(_ key: String, deliver: @escaping @Sendable (String) -> Void) -> Int? {
        guard let parsed = PluginCatalog.parseWindowKey(key), let package = catalog.package(parsed.plugin) else {
            return nil
        }
        return router.addSink(events: package.manifest.events, deliver: deliver)
    }

    public func removeWebListener(_ id: Int) {
        router.removeSink(id)
    }

    /// The page and the directory of a web window (`nil` for any other window).
    public func webPage(_ key: String) -> (page: URL, directory: URL, hosts: [String])? {
        guard let parsed = PluginCatalog.parseWindowKey(key), let package = catalog.package(parsed.plugin),
              let page = package.manifest.window(parsed.window)?.page else { return nil }
        let directory = URL(fileURLWithPath: package.directory, isDirectory: true)
        return (directory.appendingPathComponent(page), directory, package.manifest.webHosts)
    }

    // MARK: - transmit

    /// At most `catPerSecond` raw CAT commands of a plugin in any second (the app's clock).
    private func admitCat(_ plugin: String) -> Bool {
        let current: Date = now()
        var times: [Date] = (catTimes[plugin] ?? []).filter { current.timeIntervalSince($0) < 1 }
        guard times.count < Self.catPerSecond else {
            catTimes[plugin] = times
            return false
        }
        times.append(current)
        catTimes[plugin] = times
        return true
    }

    /// A transmit request succeeded: the PTT holder and its time limit, the indicator.
    private func transmitted(method: String, params: [String: PluginJSON], plugin: String, name: String) {
        switch method {
        case "tx.ptt" where params["on"]?.boolValue == true:
            pttHolder = plugin
            pttTimer?.cancel()
            let seconds: Int = settings.pttTimeoutSeconds
            pttTimer = clock.schedule(afterMilliseconds: seconds * 1000) { [weak self] in
                guard let self, self.pttHolder == plugin else { return }
                self.releasePtt(reason: "[" + name + "] " + self.language.tr(
                    "PTT pluginu uvolněno po %s s", .int(seconds)))
            }
        case "tx.ptt", "tx.stop":
            if pttHolder == plugin {
                pttTimer?.cancel()
                pttTimer = nil
                pttHolder = nil
            }
            if method == "tx.stop" || pttHolder == nil {
                transmitting = nil
            }
            return
        default:
            break
        }
        transmitting = name
        scheduleTransmitCheck()
    }

    private func releasePtt(reason: String?) {
        pttTimer?.cancel()
        pttTimer = nil
        pttHolder = nil
        _ = context.actions.ptt(false)
        if let reason {
            messages.add(reason, at: now())
        }
        if !context.actions.isSending() {
            transmitting = nil
        }
    }

    /// The indicator stays while the keyer sends or the PTT is held.
    private func scheduleTransmitCheck() {
        transmitTimer?.cancel()
        transmitTimer = clock.schedule(afterMilliseconds: Self.transmitCheckMs) { [weak self] in
            guard let self else { return }
            self.transmitTimer = nil
            if self.pttHolder == nil && !self.context.actions.isSending() {
                self.transmitting = nil
            } else {
                self.scheduleTransmitCheck()
            }
        }
    }

    /// The PTT time limit (Settings → Plugins), 5–300 s.
    public func setPttTimeout(seconds: Int) {
        settings.pttTimeoutSeconds = min(max(seconds, 5), 300)
        saveSettings()
    }

    private func exited(_ code: Int32, plugin: String, generation: Int) {
        guard let session = sessions[plugin], session.generation == generation else { return }
        let stopping: Bool = session.stopping
        _ = retire(session)
        if stopping {
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
        for session in sessions.values {
            _ = retire(session)
        }
        let running: [any PluginConnection] = Array(retiring.values)
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
