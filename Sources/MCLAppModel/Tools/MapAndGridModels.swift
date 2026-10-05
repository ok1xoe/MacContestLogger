import Foundation
import MCLCore
import Observation

/// Where the world map's outlines come from (Kotlin `WorldMapGeo.loadDefault()`: a local file). Loading blocks, so the
/// map model calls it on its IO lane; tests pass a fixture.
public protocol MapDataPort: Sendable {
    func loadGeo() -> WorldMapGeo
}

/// No map data: the window shows an empty map (Kotlin `WorldMapGeo.empty`).
public struct EmptyMapData: MapDataPort {
    public init() {}

    public func loadGeo() -> WorldMapGeo {
        .empty
    }
}

/// `~/dxcc-world-map/dxcc.geojson` (or the given home); a missing or broken file gives an empty map.
public struct LocalMapData: MapDataPort {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func loadGeo() -> WorldMapGeo {
        WorldMapGeo.loadDefault(home: home)
    }
}

/// The map data of a file given by the test or the caller (a fixture).
public struct FileMapData: MapDataPort {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func loadGeo() -> WorldMapGeo {
        guard let data = try? Data(contentsOf: file) else { return .empty }
        return WorldMapGeo.fromData(data)
    }
}

/// The world map window (`WorldMapWindow.kt`): the outlines (loaded once on the IO lane), the spots (one observer of
/// the shared `SpotFeed`), the strongest state per Maidenhead field, the DXCC dots, the night side recomputed every
/// 60 s and a click that tunes to a spot. The geometry is the core's `WorldMapModel`; drawing stays in the view.
///
/// Dots and the night layer are computed off the main thread with a generation. Tuning goes through `RigModel`
/// (`tuneToSpot`); nothing transmits and nothing is fetched.
@Observable @MainActor
public final class WorldMapWindowModel {

    /// Kotlin `delay(60_000)` of the night layer.
    public static let nightMilliseconds = 60_000

    public private(set) var isOpen = false
    /// The outlines; empty until loaded and without a file.
    public private(set) var geo: WorldMapGeo = .empty
    public private(set) var geoLoaded = false
    /// The spots of the buffer (updated by the feed's observer).
    public private(set) var spots: [DxSpot] = []
    /// The DXCC mode (dots and grey line) or the squares mode (Kotlin `dxccMode`).
    public var dxccMode = false
    /// The DXCC entities with their state (worked, spotted, neither).
    public private(set) var dots: [WorldMapModel.Dot] = []
    /// Strongest state per field for the squares mode (`dbl > spotted > worked`).
    public private(set) var fieldStates: [String: MultCell] = [:]
    /// Kotlin `grid.worked` (the title of the squares mode).
    public private(set) var workedFields = 0
    /// The moment of the night layer (`nowMs`).
    public private(set) var nowMillis: Int64 = 0
    /// The night columns for the last canvas size.
    public private(set) var night: [WorldMapModel.NightColumn] = []
    public private(set) var nightSize: (width: Float, height: Float)?

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let feed: SpotFeed
    @ObservationIgnored private let analysis: SpotAnalysisModel
    @ObservationIgnored private let callbook: CallbookModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let data: any MapDataPort
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let lane = SerialLane(name: "world-map")
    @ObservationIgnored private var observer: SpotFeed.ObserverID?
    @ObservationIgnored private var nightTick: RepeatingTick?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var nightGeneration = 0
    @ObservationIgnored private var logToken = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// Kotlin `worldMapStartDxcc`: the window opens in DXCC mode (`window.dxccmap`, `worldmap-dxcc`).
    @ObservationIgnored public var startDxcc = false

    struct Dependencies {
        let contest: ContestModel
        let config: ConfigModel
        let logbook: LogbookModel
        let language: LanguageModel
        let feed: SpotFeed
        let analysis: SpotAnalysisModel
        let callbook: CallbookModel
        let rig: RigModel
        let data: any MapDataPort
        let clock: any RescoreClock
        let now: @Sendable () -> Date
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        config = dependencies.config
        logbook = dependencies.logbook
        language = dependencies.language
        feed = dependencies.feed
        analysis = dependencies.analysis
        callbook = dependencies.callbook
        rig = dependencies.rig
        data = dependencies.data
        clock = dependencies.clock
        now = dependencies.now
    }

    private var translator: Translator {
        language.translator
    }

    // MARK: - open and close

    /// The window opened: the outlines are loaded once on the IO lane, the feed observer and the 60 s tick start.
    public func open() {
        guard !isOpen else { return }
        isOpen = true
        dxccMode = WorldMapModel.initialDxccMode(startDxcc: startDxcc, contestActive: contest.isActive)
        spots = feed.snapshot()
        observer = feed.addObserver { [weak self] in
            guard let self, self.isOpen else { return }
            self.spots = self.feed.snapshot()
            self.recompute()
        }
        nowMillis = Int64(now().timeIntervalSince1970 * 1_000)
        loadGeoOnce()
        recompute()
        logToken += 1
        observeLog(token: logToken)
        let tick = RepeatingTick(clock: clock, milliseconds: Self.nightMilliseconds) { [weak self] in
            self?.nightTicked()
        }
        nightTick = tick
        tick.start()
    }

    /// The window closed: the observer and the tick are gone, results in flight are dropped.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        if let observer {
            feed.removeObserver(observer)
        }
        observer = nil
        nightTick?.stop()
        nightTick = nil
        generation += 1
        nightGeneration += 1
    }

    /// Kotlin recomputes the dots when the number of QSOs changes: the log's revision does the same here.
    private func observeLog(token: Int) {
        withObservationTracking {
            _ = logbook.revision
            _ = contest.activeId
        } onChange: { [weak self] in
            MainHop.post {
                guard let self, self.isOpen, token == self.logToken else { return }
                self.recompute()
                self.observeLog(token: token)
            }
        }
    }

    /// Whether the window holds a subscription to the feed (tests).
    var isSubscribed: Bool {
        observer != nil
    }

    func settle() async {
        let pending: [Task<Void, Never>] = tasks
        for task in pending {
            await task.value
        }
        await lane.settle()
    }

    private func loadGeoOnce() {
        guard !geoLoaded else { return }
        let port: any MapDataPort = data
        let task = Task { [weak self] in
            let loaded: WorldMapGeo = await self?.lane.run { port.loadGeo() } ?? .empty
            guard let self else { return }
            self.geo = loaded
            self.geoLoaded = true
        }
        tasks.append(task)
    }

    // MARK: - station and projection

    /// The station position: latitude and longitude, else the centre of the locator.
    public var station: (lat: Double, lon: Double)? {
        let settings: StationConfig = config.config.station
        return WorldMapModel.stationPosition(latitude: settings.latitude, longitude: settings.longitude,
                                             gridSquare: settings.gridSquare)
    }

    /// The projection centred on the station.
    public var projection: WorldMapModel {
        WorldMapModel(station: station)
    }

    /// The colours of the configured scheme and the political shading.
    public var scheme: MapScheme {
        MapPalette.scheme(key: config.config.map.scheme)
    }

    public var political: Bool {
        config.config.map.political
    }

    // MARK: - what is shown

    /// The title of the shown mode.
    public var title: String {
        if dxccMode {
            return WorldMapModel.dxccTitle(dots: dots, epochMillis: nowMillis, translate: translator)
        }
        return WorldMapModel.squaresTitle(worked: workedFields, translate: translator)
    }

    /// The squares mode without a contest says so instead of drawing.
    public var needsContest: Bool {
        !dxccMode && !contest.isActive
    }

    public var noContestText: String {
        WorldMapModel.noContestText(translator)
    }

    /// Recomputes the dots (off the main thread) and the squares (the analysis is cheap and main-actor bound).
    func recompute() {
        guard isOpen else { return }
        if contest.isActive {
            let grid: MultGridView = analysis.current().multiplierGrid(kind: "grid", spots: spots)
            fieldStates = WorldMapModel.fieldStates(grid: grid)
            workedFields = grid.worked
        } else {
            fieldStates = [:]
            workedFields = 0
        }
        generation += 1
        let mine: Int = generation
        let rows: [Qso] = logbook.rows
        let current: [DxSpot] = spots
        let lookup: (any DxccLookup)? = contest.runtime.dxccLookup
        let task = Task { [weak self] in
            let computed: [WorldMapModel.Dot]? = try? await BlockingQueue.run {
                WorldMapModel.dxccDots(qsos: rows, spots: current, lookup: lookup)
            }
            guard let self, self.isOpen, mine == self.generation, let computed else { return }
            self.dots = computed
        }
        tasks.append(task)
        if tasks.count > 8 {
            tasks.removeFirst(tasks.count - 8)
        }
    }

    /// The canvas size: the night columns are computed for it.
    public func setCanvas(width: Float, height: Float) {
        guard width > 0, height > 0 else { return }
        nightSize = (width, height)
        computeNight()
    }

    private func nightTicked() {
        nowMillis = Int64(now().timeIntervalSince1970 * 1_000)
        computeNight()
    }

    private func computeNight() {
        guard let size = nightSize, isOpen else { return }
        nightGeneration += 1
        let mine: Int = nightGeneration
        let projection: WorldMapModel = self.projection
        let millis: Int64 = nowMillis
        let task = Task { [weak self] in
            let columns: [WorldMapModel.NightColumn]? = try? await BlockingQueue.run {
                projection.terminatorColumns(width: size.width, height: size.height, epochMillis: millis)
            }
            guard let self, self.isOpen, mine == self.nightGeneration, let columns else { return }
            self.night = columns
        }
        tasks.append(task)
    }

    // MARK: - click

    /// A click on the canvas: the field under it, the first spot whose grid begins with it, tuned to it
    /// (`onFieldTap`). Returns the spot tuned to.
    @discardableResult
    public func tap(x: Float, y: Float, width: Int, height: Int) -> DxSpot? {
        let point = projection.coordinates(x: x, y: y, width: width, height: height)
        let spot: DxSpot? = WorldMapModel.tap(lon: point.lon, lat: point.lat, spots: spots,
                                              hasLookup: contest.runtime.dxccLookup != nil) { [callbook] call in
            callbook.gridFromCsv(call) ?? callbook.record(for: call)?.grid
        }
        if let spot {
            rig.tuneToSpot(spot)
        }
        return spot
    }
}

/// The window of one multiplier kind (`MultiplierGridWindow.kt`, `mult-<kind>`): the grid of prefixes (or keys) by band,
/// coloured worked / spotted / spotted double multiplier, the continent filter and a click that tunes to the spot.
///
/// One observer of the shared `SpotFeed` while the window is open; it is removed on `close()`.
@Observable @MainActor
public final class MultGridModel {

    public let kind: String
    public private(set) var isOpen = false
    /// The continents shown (all at first).
    public private(set) var selected: Set<String> = Set(MultGridLayout.continents)
    public private(set) var spots: [DxSpot] = []

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let analysis: SpotAnalysisModel
    @ObservationIgnored private let feed: SpotFeed
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private var observer: SpotFeed.ObserverID?
    @ObservationIgnored private var cache: (key: String, grid: MultGridView)?

    init(kind: String, contest: ContestModel, analysis: SpotAnalysisModel, feed: SpotFeed, rig: RigModel,
         language: LanguageModel) {
        self.kind = kind
        self.contest = contest
        self.analysis = analysis
        self.feed = feed
        self.rig = rig
        self.language = language
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        spots = feed.snapshot()
        observer = feed.addObserver { [weak self] in
            guard let self, self.isOpen else { return }
            self.spots = self.feed.snapshot()
        }
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        if let observer {
            feed.removeObserver(observer)
        }
        observer = nil
    }

    var isSubscribed: Bool {
        observer != nil
    }

    public var title: String {
        MultGridLayout.title(kind: kind, translate: language.translator)
    }

    public var contestActive: Bool {
        contest.isActive
    }

    /// „Žádný aktivní závod."
    public var noContestText: String {
        MultGridLayout.noContestText(language.translator)
    }

    /// „Aktivní závod tento typ násobiče nemá…"
    public var unavailableText: String {
        MultGridLayout.unavailableText(kind: kind, translate: language.translator)
    }

    /// The grid for the current spots (`contest.multiplierGrid(kind, spots)`), cached per analysis revision and spots.
    public var grid: MultGridView {
        let key: String = [String(analysis.revision), String(feed.revision), String(spots.count),
                           String(contest.isActive)].joined(separator: ":")
        if let cache, cache.key == key {
            return cache.grid
        }
        let computed: MultGridView = contest.isActive
            ? analysis.current().multiplierGrid(kind: kind, spots: spots) : .unavailable
        cache = (key, computed)
        return computed
    }

    /// The headline over the grid (`worked` and `possible`).
    public var headline: String {
        let value: MultGridView = grid
        return MultGridLayout.headline(kind: kind, worked: value.worked, possible: value.possible,
                                       translate: language.translator)
    }

    /// The rows after the continent filter.
    public var visibleRows: [MultGridRow] {
        MultGridLayout.filter(rows: grid.rows, continents: selected)
    }

    /// Whether the grid has continents to filter by.
    public var hasContinents: Bool {
        MultGridLayout.hasContinents(grid.rows)
    }

    public func toggle(continent: String) {
        selected = MultGridLayout.toggle(continent, in: selected)
    }

    public func toggleAll() {
        selected = MultGridLayout.toggleAll(selected)
    }

    /// The tooltip of a spotted cell (`spotTooltip`: call, frequency, mode and its category, grid, spotter, comment);
    /// `nil` for a cell without a spot.
    public func tooltip(key: String, band: Band) -> String? {
        guard let spot = grid.spotAt[MultGridView.CellKey(key: key, band: band.adif)] else { return nil }
        return analysis.current().spotTooltip(spot, translator: language.translator)
    }

    /// A click on a coloured cell: tune to the spot of (key, band). Returns the spot, `nil` for a cell without one.
    @discardableResult
    public func tune(key: String, band: Band) -> DxSpot? {
        guard let spot = grid.spotAt[MultGridView.CellKey(key: key, band: band.adif)] else { return nil }
        rig.tuneToSpot(spot)
        return spot
    }
}
