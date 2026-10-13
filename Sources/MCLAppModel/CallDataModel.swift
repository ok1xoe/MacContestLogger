import Foundation
import MCLCore
import Observation

/// The callsign databases of the entry window (Kotlin `AppState.scp`/`callHistory`, `AS:168-253`): `master.scp` for
/// Check partial and N+1, the call history for the exchange prefill and the reverse lookup.
///
/// Both files are read on `BlockingQueue` (a full `master.scp` has tens of thousands of lines), at start-up and when
/// the configured path changes; a missing or unreadable file gives an empty database (the core's `load`). Each load
/// carries a generation, so a slow older load never replaces a newer one (Kotlin has no guard; the last started load
/// wins here). `revision`s change with every adopted load — the Kotlin keys `state.scp`/`state.callHistory` compare
/// by identity, so a reload of the same file restarts the effects keyed on them.
///
/// Kotlin reloads both on **every** `saveConfig()`; this app reloads on a path change (`observePaths()`) and after the
/// `master.scp` download. The settings dialog calls `reload()` after saving.
///
/// The call history follows N1MM (Swift-only): the active contest's own file (`ContestSetup.callHistoryFile`, N1MM
/// Associated Files) replaces the global `callHistoryFile`, the additional files (`callHistoryExtraFiles`) are merged
/// after it into one table, and when a contest opens, the loaded files' `#CONTEST` lines switch
/// `callHistoryLookupEnabled` (`applyContestTags`).
@Observable @MainActor
public final class CallDataModel {

    /// `master.scp` (Kotlin `state.scp`).
    public private(set) var scp: ScpDatabase = .empty()
    /// The call history (Kotlin `state.callHistory`): the primary file merged with the additional ones.
    public private(set) var callHistory: CallHistory = .empty
    /// The primary file alone (what "Update call history from log" and "Clear call history" rewrite).
    public private(set) var primaryCallHistory: CallHistory = .empty
    /// Raised with every adopted `master.scp` load.
    public private(set) var scpRevision: Int = 0
    /// Raised with every adopted call history load.
    public private(set) var callHistoryRevision: Int = 0

    /// Runs after a load was adopted (the suggestions recompute).
    @ObservationIgnored public var onLoaded: (@MainActor () -> Void)?

    /// The active contest as the `#CONTEST` association sees it.
    public struct ContestContext: Equatable, Sendable {
        /// The opened contest (its database id).
        public let contestId: String
        /// `CallHistory.contestKey` of the contest's definition id and name.
        public let keys: Set<String>
        /// The keys of every definition of the catalog (which `#` lines name a contest).
        public let known: Set<String>

        public init(contestId: String, keys: Set<String>, known: Set<String>) {
            self.contestId = contestId
            self.keys = keys
            self.known = known
        }
    }

    /// The active contest (`nil` = none); read inside `observePaths()`'s tracking (wired by the app).
    @ObservationIgnored public var contestContext: @MainActor () -> ContestContext? = { nil }
    /// The active contest's own call history file (`ContestSetup.callHistoryFile`; wired by the app).
    @ObservationIgnored public var contestCallHistoryFile: @MainActor () -> String? = { nil }

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let dataDir: URL
    /// Where `downloadScp()` downloads from (Kotlin `ScpDownloader.DEFAULT_URI`; tests pass a local server).
    @ObservationIgnored private let scpSource: String
    @ObservationIgnored private var scpGeneration: Int = 0
    @ObservationIgnored private var callHistoryGeneration: Int = 0
    /// The trimmed paths of the last started loads (`observePaths()` reloads only on a change).
    @ObservationIgnored private var scpPath: String?
    /// The files of the last started call history load.
    @ObservationIgnored private var callHistorySources: CallHistorySources?
    /// The files of the adopted call history (`nil` until the first load).
    @ObservationIgnored private var loadedSources: CallHistorySources?
    /// Contest + files the `#CONTEST` lines were last applied for.
    @ObservationIgnored private var appliedTagsKey: String?
    /// The additional files of the adopted call history, each loaded on its own (merged after the primary one).
    @ObservationIgnored private var extraHistories: [CallHistory] = []
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTaskId: Int = 0

    public init(config: ConfigModel, status: StatusModel, dataDir: URL,
                scpSource: String = ScpDownloader.defaultURI) {
        self.config = config
        self.status = status
        self.dataDir = dataDir
        self.scpSource = scpSource
    }

    // MARK: - loading

    /// Settings switch of the `SCP:` row: off = hidden and Check partial is not computed (observed through the config).
    public var scpSuggestionsEnabled: Bool { config.config.scpSuggestionsEnabled }
    /// Settings switch of the `N+1:` row, same meaning.
    public var nPlusOneEnabled: Bool { config.config.nPlusOneEnabled }
    /// N1MM „Enable Call History Lookup" (observed through the config): off = no exchange prefill.
    public var callHistoryLookupEnabled: Bool { config.config.callHistoryLookupEnabled }
    /// N1MM „Show User Information": the call history and UserText lines of the entry window.
    public var showsCallHistoryUserInfo: Bool { config.config.callHistoryShowUserInfo }

    /// The call history files: the primary one (the contest's own, otherwise the global one; trimmed) and the
    /// additional ones (trimmed, blank ones and repeats of the primary left out).
    struct CallHistorySources: Equatable {
        let primary: String
        let extras: [String]

        var signature: String {
            ([primary] + extras).joined(separator: "\u{0}")
        }
    }

    /// The file "Update call history from log" and "Clear call history" write: the active contest's own file,
    /// otherwise the global `callHistoryFile` (trimmed; blank = none).
    public var primaryCallHistoryPath: String {
        currentSources().primary
    }

    private func currentSources() -> CallHistorySources {
        let own: String = KotlinStrings.trim(contestCallHistoryFile() ?? "")
        let primary: String = own.isEmpty ? KotlinStrings.trim(config.config.callHistoryFile) : own
        var extras: [String] = []
        for raw in config.config.callHistoryExtraFiles {
            let path: String = KotlinStrings.trim(raw)
            if !path.isEmpty && path != primary && !extras.contains(path) {
                extras.append(path)
            }
        }
        return CallHistorySources(primary: primary, extras: extras)
    }

    /// Menu Nastavení → „Zapnout dohledávání v call history" (N1MM Config → Enable Call History Lookup).
    public func toggleLookup() {
        config.config.callHistoryLookupEnabled.toggle()
        config.save(failureKey: "Uložení nastavení selhalo: %s")
        status.show(config.config.callHistoryLookupEnabled ? "Dohledávání v call history zapnuto"
                    : "Dohledávání v call history vypnuto")
    }

    /// Kotlin `reloadScp()` + `reloadCallHistory()` (start-up, settings saved).
    public func reload() {
        reloadScp()
        reloadCallHistory()
    }

    /// Kotlin `reloadScp()`: the trimmed `config.scpFile`; blank = an empty database.
    public func reloadScp() {
        let path: String = KotlinStrings.trim(config.config.scpFile)
        scpPath = path
        scpGeneration += 1
        let generation: Int = scpGeneration
        track { [weak self] in
            let loaded: ScpDatabase = await Self.loadScp(path)
            guard let self, generation == self.scpGeneration else { return }
            self.scp = loaded
            self.scpRevision += 1
            self.onLoaded?()
        }
    }

    /// Kotlin `reloadCallHistory()`: the primary file (`primaryCallHistoryPath`; blank = an empty call history) and
    /// the additional ones, merged in order.
    public func reloadCallHistory() {
        loadCallHistory(currentSources())
    }

    private func loadCallHistory(_ sources: CallHistorySources) {
        callHistorySources = sources
        callHistoryGeneration += 1
        let generation: Int = callHistoryGeneration
        track { [weak self] in
            let primary: CallHistory = await Self.loadCallHistory(sources.primary)
            var extras: [CallHistory] = []
            for path in sources.extras {
                extras.append(await Self.loadCallHistory(path))
            }
            guard let self, generation == self.callHistoryGeneration else { return }
            self.extraHistories = extras
            self.loadedSources = sources
            self.adoptPrimary(primary)
            self.applyContestTags()
        }
    }

    /// The primary history becomes current, merged with the loaded additional files.
    private func adoptPrimary(_ primary: CallHistory) {
        primaryCallHistory = primary
        callHistory = extraHistories.reduce(primary) { $0.merging($1) }
        callHistoryRevision += 1
        onLoaded?()
    }

    /// N1MM: when a contest is opened, a file whose comments name known contests (`#CQWWCW`) enables the lookup if
    /// one is this contest and disables it otherwise; a file naming none leaves the switch alone. Applied once per
    /// contest and set of files, after their load, so the operator's later choice in the menu stands.
    func applyContestTags() {
        guard let context = contestContext(), let loaded = loadedSources, loaded == currentSources() else { return }
        let key: String = context.contestId + "\u{1}" + loaded.signature
        guard key != appliedTagsKey else { return }
        appliedTagsKey = key
        guard let enabled = CallHistory.lookupDecision(tags: callHistory.contestTags, contest: context.keys,
                                                       known: context.known),
              enabled != config.config.callHistoryLookupEnabled else { return }
        config.config.callHistoryLookupEnabled = enabled
        config.saveSilently()
        status.show(enabled ? "Call history patří k tomuto závodu — dohledávání zapnuto"
                    : "Call history patří k jinému závodu — dohledávání vypnuto")
    }

    /// A loaded Master.scp takes effect (also the tests' way in).
    func adoptScp(_ database: ScpDatabase) {
        scp = database
        scpRevision += 1
    }

    /// Takes over a call history the app has just saved (Kotlin `callHistory = merged` after "Update call history from
    /// log", `AS:226`). The primary file was rewritten by the app: `history` is its content, merged again with the loaded additional
    /// files, without reading the file again (a load in flight is superseded). When the configuration names no
    /// primary file yet (the default `CALLHISTORY.txt`), `path` (trimmed) becomes it, so writing it into
    /// `config.callHistoryFile` does not reload it.
    public func adoptCallHistory(_ history: CallHistory, path: String) {
        var sources: CallHistorySources = currentSources()
        if sources.primary.isEmpty {
            sources = CallHistorySources(primary: KotlinStrings.trim(path), extras: sources.extras)
        }
        let extrasLoaded: Bool = loadedSources?.extras == sources.extras
        callHistorySources = sources
        callHistoryGeneration += 1
        if extrasLoaded {
            loadedSources = sources
            adoptPrimary(history)
        } else {
            // The additional files of these sources are not loaded yet: read everything again.
            loadCallHistory(sources)
        }
    }

    /// Reloads a database whose configured path changed, then keeps watching the config (re-armed after each
    /// change, on the main queue).
    public func observePaths() {
        withObservationTracking {
            _ = config.config.scpFile
            _ = config.config.callHistoryFile
            _ = config.config.callHistoryExtraFiles
            _ = contestCallHistoryFile()
            _ = contestContext()
        } onChange: { [weak self] in
            MainHop.post {
                self?.pathsChanged()
                self?.observePaths()
            }
        }
    }

    private func pathsChanged() {
        if KotlinStrings.trim(config.config.scpFile) != scpPath {
            reloadScp()
        }
        if currentSources() != callHistorySources {
            reloadCallHistory()
        } else {
            applyContestTags()
        }
    }

    nonisolated private static func loadScp(_ path: String) async -> ScpDatabase {
        if KotlinStrings.isBlank(path) {
            return .empty()
        }
        let loaded: ScpDatabase? = try? await BlockingQueue.run {
            Perf.measure("scp-load") { ScpDatabase.load(path) }
        }
        return loaded ?? .empty()
    }

    nonisolated private static func loadCallHistory(_ path: String) async -> CallHistory {
        if KotlinStrings.isBlank(path) {
            return .empty
        }
        let loaded: CallHistory? = try? await BlockingQueue.run {
            Perf.measure("call-history-load") { CallHistory.load(path) }
        }
        return loaded ?? .empty
    }

    // MARK: - download

    /// Kotlin `downloadScp()` (menu `settings.downloadScp`): downloads `MASTER.SCP` into the configured file, without
    /// one into `<data>/MASTER.SCP` (and remembers that path), then loads it. The core's `ScpDownloader` replaces the
    /// file atomically only after checking its content; it blocks, so it runs on `BlockingQueue`.
    public func downloadScp() {
        let configured: String = KotlinStrings.trim(config.config.scpFile)
        let target: String = KotlinStrings.isBlank(configured)
            ? dataDir.appendingPathComponent("MASTER.SCP").path
            : configured
        let source: String = scpSource
        // Kotlin sets this text without `tr`.
        status.showVerbatim("Stahuji master.scp…")
        track { [weak self] in
            let outcome: Result<ScpDownloader.Result, any Error>
            do {
                outcome = .success(try await BlockingQueue.run {
                    try ScpDownloader().download(source, to: target)
                })
            } catch {
                outcome = .failure(error)
            }
            self?.downloaded(outcome, configured: configured)
        }
    }

    private func downloaded(_ outcome: Result<ScpDownloader.Result, any Error>, configured: String) {
        switch outcome {
        case .success(let result):
            if KotlinStrings.isBlank(configured) {
                config.config.scpFile = result.file
            }
            // Kotlin `runCatching { saveConfig() }`: a failed write is silent; `saveConfig` reloads both databases.
            config.writer.enqueue(config.config) { _ in }
            reload()
            status.show("master.scp stažen: %s volaček → %s", .int(result.calls), .string(result.file))
        case .failure(let error):
            status.show("Stažení master.scp selhalo: %s", .string(Self.message(error)))
        }
    }

    /// Kotlin `it.message` (`null` formats as "null").
    private static func message(_ error: any Error) -> String {
        if let http = error as? JavaHttpError {
            return http.message ?? "null"
        }
        return ErrorText.message(error)
    }

    // MARK: - tasks

    private func track(_ body: @escaping @MainActor () async -> Void) {
        let id: Int = nextTaskId
        nextTaskId += 1
        tasks[id] = Task { [weak self] in
            await body()
            self?.tasks[id] = nil
        }
    }

    /// Waits for the loads and downloads in flight (tests, shutdown).
    func settle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }
}
