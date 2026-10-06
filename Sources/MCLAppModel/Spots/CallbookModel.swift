import Foundation
import MCLCore
import Observation

/// A callbook record of the call in the entry field (Kotlin `callbookRecord: Pair<String, HamQthRecord>?`).
public struct CallbookHit: Equatable, Sendable {
    public let call: String
    public let record: HamQthRecord
}

/// The callbooks of v1.1.1 (`AS:268-334, 403-471`): HamQTH, then QRZ.com, over `NetworkPorts.http`,
/// one cache of merged records shared by the entry window's lookup and the spot prefetch, the HTTP dump
/// (`hamQthLog`), the offline grid data and the browser pages of a call.
///
/// - `lookup` (the entry window, after its 700 ms debounce): a key shorter than 3 or **neither client configured**
///   clears the record (Kotlin's gate ignores `isEnabled`, kept); a cache hit answers at once; otherwise the lane asks
///   each source that is enabled and configured, merges the first non-blank value per field, caches the result
///   (also `EMPTY`) and shows it only when the entry field still holds the same call.
/// - `prefetch` (after every batch of spot changes): only in a contest that needs callbook data, only for spots without
///   a cached record or an offline grid and allowed by a source's modes, one per call, serially on the lane; a found
///   record touches the buffer so the windows redraw. Kotlin computes the selection on the network thread while the
///   main thread changes the cache (a data race); here the selection is made on the lane.
/// - Lookup errors are swallowed (Kotlin `runCatching`). `reload` (Settings) makes new clients and clears the cache.
@Observable @MainActor
public final class CallbookModel {

    /// The HTTP dump of the callbooks (the HamQTH log window) and the spot grid decisions.
    @ObservationIgnored public let hamQthLog: HamQthLog
    /// The record of the entry field's call; `nil` = none or not found.
    public private(set) var callbookRecord: CallbookHit?
    /// What the entry window's lookup button found for its call (shown on the callbook line when not found).
    public private(set) var entryLookup: ManualLookupResult?
    /// The result window's content (the log and band map menus); `nil` = nothing asked yet.
    public private(set) var windowLookup: ManualLookupResult?
    /// Rises when the offline grid data have loaded (a spot analysis built before must be rebuilt).
    public private(set) var gridGeneration: Int = 0

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let network: NetworkPorts
    @ObservationIgnored private let spots: SpotBuffer
    @ObservationIgnored private let dataDir: URL
    @ObservationIgnored let cache = CallbookCache()
    @ObservationIgnored let lane = CallbookLane()
    @ObservationIgnored private let browser = SerialLane(name: "browser")
    @ObservationIgnored private let grid = GridDataLoader()
    @ObservationIgnored private var gridRequested = false
    @ObservationIgnored private var hamQth: HamQthClient
    @ObservationIgnored private var qrz: QrzClient
    /// Opens the result window (wired by the app to `DialogsModel`).
    @ObservationIgnored var showLookupWindow: @MainActor () -> Void = {}
    /// The current spot analysis (needs-lookup gate, spot category); wired by the app.
    @ObservationIgnored var analyzer: @MainActor () -> SpotAnalyzer? = { nil }

    init(config: ConfigModel, contest: ContestModel, network: NetworkPorts, spots: SpotBuffer, dataDir: URL,
         hamQthLog: HamQthLog = HamQthLog()) {
        self.config = config
        self.contest = contest
        self.network = network
        self.spots = spots
        self.dataDir = dataDir
        self.hamQthLog = hamQthLog
        let settings: AppConfig = config.config
        hamQth = HamQthClient(username: settings.hamQth.username, password: settings.hamQth.password,
                              log: hamQthLog, http: network.http)
        qrz = QrzClient(username: settings.qrz.username, password: settings.qrz.password, log: hamQthLog,
                        http: network.http)
    }

    // MARK: - reading

    /// Kotlin `hamQthRecordFor(call)`: the cached record, `nil` when not looked up yet or found empty.
    public func record(for call: String) -> HamQthRecord? {
        CallbookPolicy.usable(cache.record(CallbookPolicy.key(call)))
    }

    /// The callbook closure of `SpotAnalyzer` — reads the live cache (no analyzer rebuild for new entries).
    public var analyzerLookup: @Sendable (String) -> HamQthRecord? {
        let cache: CallbookCache = self.cache
        return { call in
            CallbookPolicy.usable(cache.record(SpotAnalyzer.callbookKey(call)))
        }
    }

    /// Kotlin `gridFromCsv(call)` over the offline database; `nil` while it is still loading (the first use starts the
    /// load on the lane, `gridGeneration` rises when it is there).
    public func gridFromCsv(_ call: String) -> String? {
        guard let data = gridData else { return nil }
        return data.database.grid(CallbookPolicy.key(call))
    }

    /// The offline grid data once loaded; the first read starts the load.
    public var gridData: GridData? {
        _ = gridGeneration
        if let data = grid.current {
            return data
        }
        requestGridData()
        return nil
    }

    /// Starts the lazy load of the offline grid data (once).
    func requestGridData() {
        if gridRequested { return }
        gridRequested = true
        let root: URL = dataRoot()
        let dxcc: (any DxccLookup)? = contest.runtime.dxccLookup
        let loader: GridDataLoader = grid
        lane.submit({
            _ = loader.load(root: root, dxcc: dxcc)
            return true
        }, then: { [weak self] _ in
            self?.gridGeneration += 1
        })
    }

    // MARK: - the entry field

    /// Kotlin `lookupCallbook(call)`; `typedCall` = the entry field's call when the result arrives.
    public func lookup(_ call: String, typedCall: @escaping @MainActor () -> String) {
        guard let key = CallbookPolicy.lookupKey(call: call, hamQthConfigured: hamQth.configured,
                                                 qrzConfigured: qrz.configured) else {
            callbookRecord = nil
            return
        }
        if let cached = cache.record(key) {
            callbookRecord = cached.isEmpty ? nil : CallbookHit(call: key, record: cached)
            return
        }
        let settings: AppConfig = config.config
        let sources: [CallbookPolicy.Source] = CallbookPolicy.lookupSources(
            hamQthEnabled: settings.hamQth.enabled, hamQthConfigured: hamQth.configured,
            qrzEnabled: settings.qrz.enabled, qrzConfigured: qrz.configured)
        let clients: [CallbookPolicy.Source: any CallbookClient] = [.hamQth: hamQth, .qrz: qrz]
        let cache: CallbookCache = self.cache
        let generation: Int = cache.generation
        lane.submit({ () -> HamQthRecord in
            var records: [(record: HamQthRecord, fields: [String]?)] = []
            for source in sources {
                if let client = clients[source], let found = try? client.lookup(key) {
                    records.append((found, nil))
                }
            }
            let merged: HamQthRecord = CallbookPolicy.merge(records)
            cache.store(key, merged, generation: generation)
            return merged
        }, then: { [weak self] merged in
            guard let self, CallbookPolicy.key(typedCall()) == key else { return }
            self.callbookRecord = merged.isEmpty ? nil : CallbookHit(call: key, record: merged)
        })
    }

    // MARK: - manual lookups

    /// The service of the entry window's button (Settings → Online callbooks).
    public var preferredService: CallbookService {
        CallbookService(configValue: config.config.preferredCallbook)
    }

    /// Does the service have credentials? (Read from the config, so the buttons follow a saved Settings change.)
    public func isConfigured(_ service: CallbookService) -> Bool {
        let settings: AppConfig = config.config
        switch service {
        case .hamQth:
            return !KotlinStrings.trim(settings.hamQth.username).isEmpty && !settings.hamQth.password.isEmpty
        case .qrz:
            return !KotlinStrings.trim(settings.qrz.username).isEmpty && !settings.qrz.password.isEmpty
        }
    }

    /// The entry window's button: looks `call` up on `service` now (no debounce, no mode filter; credentials are
    /// required). A record goes to the callbook line and so through the prefill of the automatic lookup; a failure
    /// is shown on that line. `typedCall` = the call in the field when the answer arrives.
    public func lookupNow(_ call: String, service: CallbookService, typedCall: @escaping @MainActor () -> String) {
        let key: String = CallbookPolicy.key(call)
        guard !key.isEmpty else { return }
        entryLookup = ManualLookupResult(call: key, service: service, state: .loading)
        runManual(key, service) { [weak self] result in
            guard let self, CallbookPolicy.key(typedCall()) == key else { return }
            if let record = result.record {
                self.entryLookup = nil
                self.callbookRecord = CallbookHit(call: key, record: record)
            } else {
                self.entryLookup = result
            }
        }
    }

    /// The log and band map menus: looks `call` up on `service` and shows the result window.
    public func lookupInWindow(_ call: String, service: CallbookService) {
        let key: String = CallbookPolicy.key(call)
        guard !key.isEmpty else { return }
        windowLookup = ManualLookupResult(call: key, service: service, state: .loading)
        showLookupWindow()
        runManual(key, service) { [weak self] result in
            guard let self, self.windowLookup?.call == key, self.windowLookup?.service == service else { return }
            self.windowLookup = result
        }
    }

    /// „Otevřít na webu" of the result window.
    public func openOnWeb(_ result: ManualLookupResult) {
        open(result.service.pageURL(call: result.call))
    }

    private func runManual(_ key: String, _ service: CallbookService,
                           finish: @escaping @MainActor (ManualLookupResult) -> Void) {
        guard isConfigured(service) else {
            finish(ManualLookupResult(call: key, service: service, state: .notConfigured))
            return
        }
        if network.isInert {
            finish(ManualLookupResult(call: key, service: service, state: .networkDisabled))
            return
        }
        let settings: AppConfig = config.config
        let recorder = RecordingHttpGetter(network.http)
        let client: any CallbookClient = service == .hamQth
            ? HamQthClient(username: settings.hamQth.username, password: settings.hamQth.password,
                           log: hamQthLog, http: recorder)
            : QrzClient(username: settings.qrz.username, password: settings.qrz.password, log: hamQthLog,
                        http: recorder)
        let dxcc: (any DxccLookup)? = contest.runtime.dxccLookup
        let cache: CallbookCache = self.cache
        let generation: Int = cache.generation
        lane.submit({ () -> ManualLookupResult in
            let record: HamQthRecord = (try? client.lookup(key)) ?? .empty
            if !record.isEmpty {
                if !cache.contains(key) || cache.record(key)?.isEmpty == true {
                    cache.store(key, record, generation: generation)
                }
                return ManualLookupResult(call: key, service: service,
                                          state: .found(record, country: dxcc?.resolve(key)?.name))
            }
            let state = ManualLookupClassifier.problem(for: service, failure: recorder.failure,
                                                       exchanges: recorder.exchanges)
            return ManualLookupResult(call: key, service: service, state: state)
        }, then: finish)
    }

    // MARK: - the spots

    /// Kotlin `prefetchGridsForSpots()`.
    public func prefetch() {
        guard let analyzer = analyzer() else { return }
        guard CallbookPolicy.prefetchAllowed(needsLookup: analyzer.needsHamQthLookup,
                                             hamQthConfigured: hamQth.configured,
                                             qrzConfigured: qrz.configured) else { return }
        let job = PrefetchJob(spots: spots.snapshot(), analyzer: analyzer, settings: config.config, hamQth: hamQth,
                              qrz: qrz, cache: cache, root: dataRoot(), dxcc: contest.runtime.dxccLookup,
                              grid: grid)
        let buffer: SpotBuffer = spots
        lane.submit({ job.run() }, then: { found in
            if found {
                buffer.touch()
            }
        })
    }

    // MARK: - Settings and the browser

    /// Kotlin `reloadHamQth()` (the Settings port `hamQth`): new clients over the saved credentials, the cache
    /// emptied.
    public func reload() {
        let settings: AppConfig = config.config
        hamQth = HamQthClient(username: settings.hamQth.username, password: settings.hamQth.password,
                              log: hamQthLog, http: network.http)
        qrz = QrzClient(username: settings.qrz.username, password: settings.qrz.password, log: hamQthLog,
                        http: network.http)
        cache.clear()
    }

    /// Kotlin `openQrz(call)`.
    public func openQrz(_ call: String) {
        open("https://www.qrz.com/db/" + CallbookPolicy.key(call))
    }

    /// Kotlin `openHamqth(call)`.
    public func openHamQth(_ call: String) {
        open("https://www.hamqth.com/" + CallbookPolicy.key(call))
    }

    /// Kotlin `openHelp()` (`AS:1014`): the project's documentation.
    public static let helpUrl = "https://github.com/ok1xoe/MacContestLogger/tree/main/docs"

    public func openHelp() {
        open(Self.helpUrl)
    }

    func open(_ url: String) {
        let opener: UrlOpener = network.urlOpener
        browser.submit {
            opener.open(url)
        }
    }

    // MARK: - lifecycle

    /// Waits until the lookups and the browser requests queued so far have run (tests).
    func settle() async {
        await lane.settle()
        await browser.settle()
        await runPostedWork()
    }

    /// The quit's first part: queued lookups are skipped from now on (no wait — a lookup in flight may take the
    /// HTTP timeout).
    func closeLane() {
        lane.markClosed()
    }

    /// The quit's last part: the queued lookups are dropped, the running one finishes.
    func shutdown() async {
        await lane.close()
        await browser.settle()
    }

    /// Kotlin `config.contestDataDir` or the default directory.
    private func dataRoot() -> URL {
        let fallback: String = dataDir.appendingPathComponent("contest-data").path
        return ContestEnvironment.dataRoot(configured: config.config.contestDataDir, fallback: fallback)
    }

    private func runPostedWork() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MainHop.post {
                continuation.resume()
            }
        }
    }
}

/// One prefetch run on the callbook lane (Kotlin `prefetchGridsForSpots` IO coroutine with its selection).
private struct PrefetchJob: Sendable {
    let spots: [DxSpot]
    let analyzer: SpotAnalyzer
    let settings: AppConfig
    let hamQth: HamQthClient
    let qrz: QrzClient
    let cache: CallbookCache
    let root: URL
    let dxcc: (any DxccLookup)?
    let grid: GridDataLoader

    /// `true` when a non-empty record was found.
    func run() -> Bool {
        let data: GridData = grid.load(root: root, dxcc: dxcc)
        let selection: [DxSpot] = CallbookPolicy.prefetchSelection(
            spots: spots, cached: { cache.contains($0) }, hasOfflineGrid: { data.database.grid($0) != nil },
            allows: { allowsHamQth($0) || allowsQrz($0) })
        let generation: Int = cache.generation
        var found = false
        for spot in selection {
            let key: String = CallbookPolicy.key(spot.dxCall)
            if cache.contains(key) { continue }
            let record: HamQthRecord = fetchMerged(spot)
            // Also `EMPTY`, so the call is not asked again.
            cache.store(key, record, generation: generation)
            if !record.isEmpty {
                found = true
            }
        }
        return found
    }

    private func allowsHamQth(_ spot: DxSpot) -> Bool {
        CallbookPolicy.sourceAllows(enabled: settings.hamQth.enabled, configured: hamQth.configured,
                                    modes: settings.hamQth.callModes, category: analyzer.spotCategory(spot))
    }

    private func allowsQrz(_ spot: DxSpot) -> Bool {
        CallbookPolicy.sourceAllows(enabled: settings.qrz.enabled, configured: qrz.configured,
                                    modes: settings.qrz.callModes, category: analyzer.spotCategory(spot))
    }

    /// Kotlin `fetchMerged(spot)`: each allowed source with its `fetchFields`.
    private func fetchMerged(_ spot: DxSpot) -> HamQthRecord {
        var records: [(record: HamQthRecord, fields: [String]?)] = []
        if allowsHamQth(spot), let found = try? hamQth.lookup(spot.dxCall) {
            records.append((found, settings.hamQth.fetchFields))
        }
        if allowsQrz(spot), let found = try? qrz.lookup(spot.dxCall) {
            records.append((found, settings.qrz.fetchFields))
        }
        return CallbookPolicy.merge(records)
    }
}
