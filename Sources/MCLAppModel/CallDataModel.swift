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
@Observable @MainActor
public final class CallDataModel {

    /// `master.scp` (Kotlin `state.scp`).
    public private(set) var scp: ScpDatabase = .empty()
    /// The call history (Kotlin `state.callHistory`).
    public private(set) var callHistory: CallHistory = .empty
    /// Raised with every adopted `master.scp` load.
    public private(set) var scpRevision: Int = 0
    /// Raised with every adopted call history load.
    public private(set) var callHistoryRevision: Int = 0

    /// Runs after a load was adopted (the suggestions recompute).
    @ObservationIgnored public var onLoaded: (@MainActor () -> Void)?

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let dataDir: URL
    /// Where `downloadScp()` downloads from (Kotlin `ScpDownloader.DEFAULT_URI`; tests pass a local server).
    @ObservationIgnored private let scpSource: String
    @ObservationIgnored private var scpGeneration: Int = 0
    @ObservationIgnored private var callHistoryGeneration: Int = 0
    /// The trimmed paths of the last started loads (`observePaths()` reloads only on a change).
    @ObservationIgnored private var scpPath: String?
    @ObservationIgnored private var callHistoryPath: String?
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

    /// Kotlin `reloadCallHistory()`: the trimmed `config.callHistoryFile`; blank = an empty call history.
    public func reloadCallHistory() {
        let path: String = KotlinStrings.trim(config.config.callHistoryFile)
        callHistoryPath = path
        callHistoryGeneration += 1
        let generation: Int = callHistoryGeneration
        track { [weak self] in
            let loaded: CallHistory = await Self.loadCallHistory(path)
            guard let self, generation == self.callHistoryGeneration else { return }
            self.callHistory = loaded
            self.callHistoryRevision += 1
            self.onLoaded?()
        }
    }

    /// Takes over a call history the app has just saved to `path` (Kotlin `callHistory = merged` after "Update call
    /// history from log", `AS:226`) without reading the file again: a load in flight is superseded, and `path`
    /// (trimmed) becomes the loaded path, so writing it into `config.callHistoryFile` does not reload it.
    public func adoptCallHistory(_ history: CallHistory, path: String) {
        callHistoryPath = KotlinStrings.trim(path)
        callHistoryGeneration += 1
        callHistory = history
        callHistoryRevision += 1
        onLoaded?()
    }

    /// Reloads a database whose configured path changed, then keeps watching the config (re-armed after each
    /// change, on the main queue).
    public func observePaths() {
        withObservationTracking {
            _ = config.config.scpFile
            _ = config.config.callHistoryFile
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
        if KotlinStrings.trim(config.config.callHistoryFile) != callHistoryPath {
            reloadCallHistory()
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
