import Foundation
import MCLCore

/// The models of the Info window and the tool windows: Info, goals, statistics, score, dupesheet, skeds with the
/// watchers, QTC, band notes, propagation, the world map and the multiplier grids.
@MainActor
public final class InfoTools {
    public let info: InfoModel
    public let goals: GoalsModel
    public let statistics: StatisticsModel
    public let score: ScoreWindowModel
    public let dupesheet: DupesheetModel
    public let skeds: SkedModel
    public let skedWatcher: SkedWatcher
    public let tourWatcher: TourWatcher
    public let qtc: QtcModel
    public let bandNotes: BandNotesModel
    public let propagation: PropagationWindowModel
    public let worldMap: WorldMapWindowModel

    private let makeGrid: @MainActor (String) -> MultGridModel
    private var grids: [String: MultGridModel] = [:]

    init(info: InfoModel, goals: GoalsModel, statistics: StatisticsModel, score: ScoreWindowModel,
         dupesheet: DupesheetModel, skeds: SkedModel, skedWatcher: SkedWatcher, tourWatcher: TourWatcher,
         qtc: QtcModel, bandNotes: BandNotesModel, propagation: PropagationWindowModel,
         worldMap: WorldMapWindowModel, makeGrid: @escaping @MainActor (String) -> MultGridModel) {
        self.info = info
        self.goals = goals
        self.statistics = statistics
        self.score = score
        self.dupesheet = dupesheet
        self.skeds = skeds
        self.skedWatcher = skedWatcher
        self.tourWatcher = tourWatcher
        self.qtc = qtc
        self.bandNotes = bandNotes
        self.propagation = propagation
        self.worldMap = worldMap
        self.makeGrid = makeGrid
    }

    /// The model of a multiplier window (`mult-<kind>`), made on first use.
    public func multGrid(kind: String) -> MultGridModel {
        if let existing = grids[kind] {
            return existing
        }
        let created: MultGridModel = makeGrid(kind)
        grids[kind] = created
        return created
    }

    /// The multiplier windows made so far.
    var multGridModels: [MultGridModel] {
        Array(grids.values)
    }

    /// The quit: the watchers stop and every window model closes (their observers and ticks go).
    func shutdown() {
        skedWatcher.stop()
        tourWatcher.stop()
        info.close()
        statistics.close()
        score.close()
        dupesheet.close()
        worldMap.close()
        for grid in grids.values {
            grid.close()
        }
    }

    /// Waits for the work the models have in flight (tests, the quit).
    func settle() async {
        await info.settle()
        await statistics.settle()
        await score.settle()
        await dupesheet.settle()
        await worldMap.settle()
    }
}

extension AppModel {

    public var info: InfoModel { infoTools.info }
    public var goals: GoalsModel { infoTools.goals }
    public var statistics: StatisticsModel { infoTools.statistics }
    public var scoreWindow: ScoreWindowModel { infoTools.score }
    public var dupesheet: DupesheetModel { infoTools.dupesheet }
    public var skeds: SkedModel { infoTools.skeds }
    public var qtc: QtcModel { infoTools.qtc }
    public var bandNotes: BandNotesModel { infoTools.bandNotes }
    public var propagation: PropagationWindowModel { infoTools.propagation }
    public var worldMap: WorldMapWindowModel { infoTools.worldMap }

    /// The model of the multiplier window of a kind (`mult:<kind>`), made on first use.
    public func multGrid(kind: String) -> MultGridModel { infoTools.multGrid(kind: kind) }

    /// The info and tool models, wired to the others: the typed call and the sent exchange of the entry window, the info
    /// strip's SKED and 📝 items, and the sked and TOUR watchers (running from the start, like Kotlin's `init`).
    static func wireInfoTools(_ model: AppModel, environment: Environment) {
        let clock: any RescoreClock = environment.toolClock ?? MainQueueRescoreClock()
        let now: @Sendable () -> Date = environment.now
        let info = InfoModel(InfoModel.Dependencies(
            contest: model.contest, config: model.config, logbook: model.logbook, messages: model.messages,
            language: model.language, status: model.status, operating: model.operating, rig: model.rig,
            dxCluster: model.dxCluster, callbook: model.callbook, clock: clock, now: now))
        info.sources.typedCall = { [weak model] in
            model?.typedCall ?? ""
        }
        info.sources.sentExchange = { [weak model] in
            model?.entry.sentExchangeText ?? ""
        }
        info.sources.clipboard = environment.clipboard
        info.windowSync = { [weak model] id, open in
            model?.windows.setOpen(id, open)
        }
        let goals = GoalsModel(GoalsModel.Dependencies(
            contest: model.contest, config: model.config, database: model.database, status: model.status,
            language: model.language, info: info))
        let statistics = StatisticsModel(logbook: model.logbook, language: model.language)
        let score = ScoreWindowModel(logbook: model.logbook, contest: model.contest, language: model.language,
                                     clock: clock)
        let dupesheet = DupesheetModel(logbook: model.logbook, contest: model.contest, rig: model.rig,
                                       language: model.language)
        dupesheet.typedCall = { [weak model] in
            model?.typedCall ?? ""
        }
        let skeds = SkedModel(SkedModel.Dependencies(
            contest: model.contest, status: model.status, language: model.language, rig: model.rig, now: now))
        let skedWatcher = SkedWatcher(skeds: skeds, status: model.status, messages: model.messages, clock: clock,
                                      now: now)
        let tourWatcher = TourWatcher(contest: model.contest, language: model.language, status: model.status,
                                      messages: model.messages, clock: clock, now: now)
        let qtc = QtcModel(QtcModel.Dependencies(
            contest: model.contest, logbook: model.logbook, database: model.database, status: model.status,
            language: model.language, rig: model.rig, now: now))
        qtc.typedCall = { [weak model] in
            model?.typedCall ?? ""
        }
        let bandNotes = BandNotesModel(config: model.config, status: model.status, language: model.language,
                                       rig: model.rig)
        let propagation = PropagationWindowModel(config: model.config, contest: model.contest,
                                                 language: model.language, dxCluster: model.dxCluster, now: now)
        propagation.typedCall = { [weak model] in
            model?.typedCall ?? ""
        }
        let worldMap = WorldMapWindowModel(WorldMapWindowModel.Dependencies(
            contest: model.contest, config: model.config, logbook: model.logbook, language: model.language,
            feed: model.spotFeed, analysis: model.spotAnalysis, callbook: model.callbook, rig: model.rig,
            data: environment.mapData, clock: clock, now: now))
        // Kotlin `worldMapStartDxcc = "worldmap-dxcc" in openOnStart`.
        worldMap.startDxcc = model.windows.isOpen("worldmap-dxcc")
        let contest: ContestModel = model.contest
        let analysis: SpotAnalysisModel = model.spotAnalysis
        let feed: SpotFeed = model.spotFeed
        let rig: RigModel = model.rig
        let language: LanguageModel = model.language
        model.infoTools = InfoTools(
            info: info, goals: goals, statistics: statistics, score: score, dupesheet: dupesheet, skeds: skeds,
            skedWatcher: skedWatcher, tourWatcher: tourWatcher, qtc: qtc, bandNotes: bandNotes,
            propagation: propagation, worldMap: worldMap, makeGrid: { kind in
                MultGridModel(kind: kind, contest: contest, analysis: analysis, feed: feed, rig: rig,
                              language: language)
            })
        model.infoStrip.sources.bandNote = { [weak bandNotes] in
            bandNotes?.stripNote()
        }
        model.infoStrip.sources.sked = { [weak skeds] in
            skeds?.stripSked()
        }
        let quitting: () -> Bool = { [weak model] in
            model?.isShuttingDown ?? true
        }
        info.isShuttingDown = quitting
        goals.isShuttingDown = quitting
        qtc.isShuttingDown = quitting
        skedWatcher.start()
        tourWatcher.start()
    }
}
