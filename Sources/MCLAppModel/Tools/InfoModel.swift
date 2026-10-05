import Foundation
import MCLCore
import Observation

/// An option of the Info window's context menu (`RW:387-432`).
public enum InfoWindowOption: Equatable, Sendable {
    case callframeSpot
    case countryInfo
    case sunTimes
    case wwv
    case goals
    case messages
    case timers
    /// The length of the trend interval (20, 30 or 60 minutes).
    case trendMinutes(Int)
    /// A mode of the off-time timer (`InfoWindowConfig.offTimeModeOptions`).
    case offTimeMode(String)
}

/// One item of the Info window's context menu: the toggles carry a check mark (`✓ ` / two spaces), the actions do not.
public struct InfoMenuEntry: Equatable, Sendable, Identifiable {
    public enum Action: Equatable, Sendable {
        case option(InfoWindowOption)
        case editGoals
        case goalsFromLog
        /// Needs a file: the view asks for it and calls `InfoModel.importGoals(url:band:)`.
        case importGoals
        /// Needs a file: the view asks for it and calls `InfoModel.exportGoals(url:)`.
        case exportGoals
        case copyMessages
        case clearMessages
        case rbnSpots
    }

    public let action: Action
    public let title: String

    public var id: String {
        "\(action)"
    }
}

/// A goal file read and waiting for the choice of a band (`PendingGoalImport`, `RW:475`).
public struct PendingGoalImport: Equatable, Sendable {
    public let lines: [String]
    public let bands: [String]
}

/// The Info window (Kotlin `RateWindow.kt`): the header, the four information lines about the typed call, the rate
/// graphs with the goal, the timers, the program messages and the context menu.
///
/// The model ticks once a second on the injected clock **only while the window is open** (`open()`/`close()`).
/// `ContestStats` is recomputed off the main thread when the log's revision changes (not every second as Kotlin's
/// `produceState` does —), with a generation: a snapshot that was overtaken by a newer log is dropped. The
/// timers and graphs are computed from the finished snapshot and `now`. `tunedSince` (`RW:793-796`) is the moment the
/// tuned band last changed while the window was open.
@Observable @MainActor
public final class InfoModel {

    /// The inputs of the entry windows (wired by the app).
    public struct Sources {
        /// Kotlin `state.typedCall`.
        public var typedCall: @MainActor () -> String = { "" }
        /// Kotlin `state.sentExchangeLine`.
        public var sentExchange: @MainActor () -> String = { "" }
        /// The system pasteboard (`java.awt.Toolkit` clipboard); tests record.
        public var clipboard: @MainActor (String) -> Void = { _ in }

        public init() {}
    }

    // MARK: - what the window shows

    public private(set) var isOpen = false
    /// The latest finished snapshot of the log.
    public private(set) var stats: ContestStats = ContestStats.of([])
    /// The moment of the last tick.
    public private(set) var now: JavaInstant
    public private(set) var header: InfoHeader
    /// The information lines that have content, in Kotlin order: spot, country, sun, WWV.
    public private(set) var lines: [String] = []
    public private(set) var offTime: TimerCell
    public private(set) var onBand: TimerCell?
    public private(set) var bandChanges: TimerCell?
    public private(set) var nearTerm: NearTermRates
    public private(set) var trend: TrendView?
    /// The goals of the config (`GoalFileWriter.fromConfigMap`).
    public private(set) var goals: GoalSet = GoalSet.empty()
    /// The goal file waiting for the choice of a band.
    public private(set) var pendingImport: PendingGoalImport?
    /// `showGoalEditor` / `showGoalFromLog` of `AppState`: the windows the menu opens.
    public var showGoalEditor = false {
        didSet { windowSync("goals", showGoalEditor) }
    }
    public var showGoalFromLog = false {
        didSet { windowSync("goals-from-log", showGoalFromLog) }
    }
    /// Tells the windows model that a goal window opens or closes (`WindowsModel.setOpen`); wired by the app.
    @ObservationIgnored var windowSync: @MainActor (String, Bool) -> Void = { _, _ in }

    @ObservationIgnored public var sources = Sources()
    /// Runs after the goals changed (the goal editor and the import).
    @ObservationIgnored var onGoalsChanged: @MainActor () -> Void = {}
    /// Set by the quit: goal import and export are refused (nothing writes the config after its final flush).
    @ObservationIgnored var isShuttingDown: () -> Bool = { false }

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let messages: MessagesModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let operating: OperatingModel
    @ObservationIgnored private let rig: RigModel
    @ObservationIgnored private let dxCluster: DxClusterModel
    @ObservationIgnored private let callbook: CallbookModel
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let clockNow: @Sendable () -> Date
    @ObservationIgnored private let ioLane = SerialLane(name: "info-io")
    @ObservationIgnored private var tickTimer: RepeatingTick?
    @ObservationIgnored private var derived: LogDerived<ContestStats>?
    @ObservationIgnored private var tunedSince: JavaInstant?
    @ObservationIgnored private var bandToken = 0
    @ObservationIgnored private var ioTasks: [Task<Void, Never>] = []

    struct Dependencies {
        let contest: ContestModel
        let config: ConfigModel
        let logbook: LogbookModel
        let messages: MessagesModel
        let language: LanguageModel
        let status: StatusModel
        let operating: OperatingModel
        let rig: RigModel
        let dxCluster: DxClusterModel
        let callbook: CallbookModel
        let clock: any RescoreClock
        let now: @Sendable () -> Date
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        config = dependencies.config
        logbook = dependencies.logbook
        messages = dependencies.messages
        language = dependencies.language
        status = dependencies.status
        operating = dependencies.operating
        rig = dependencies.rig
        dxCluster = dependencies.dxCluster
        callbook = dependencies.callbook
        clock = dependencies.clock
        clockNow = dependencies.now
        let start = JavaInstant(date: dependencies.now())
        now = start
        header = InfoLines.header(stationCall: "", sentExchange: "", operatorCall: "")
        let empty: ContestStats = ContestStats.of([])
        offTime = InfoTimers.offTime(mode: "sinceLastQso", stats: empty, now: start, rules: nil, contestStart: nil)
        nearTerm = RatePanel.nearTerm(stats: empty, now: start, goal: nil)
    }

    // MARK: - open and close

    /// The window opened: the first snapshot at once, then a tick every second.
    public func open() {
        guard !isOpen else { return }
        isOpen = true
        if rig.currentBand != nil {
            tunedSince = JavaInstant(date: clockNow())
        }
        bandToken += 1
        trackBand(token: bandToken)
        let source: @MainActor () -> LogDerived<ContestStats>.Job = {
            { qsos in ContestStats.of(qsos) }
        }
        let derived = LogDerived<ContestStats>(
            logbook: logbook, tracked: { [weak self] in _ = self?.contest.activeId },
            source: source, apply: { [weak self] stats in
                self?.stats = stats
                self?.recompute()
            })
        self.derived = derived
        derived.start()
        recompute()
        let tick = RepeatingTick(clock: clock, milliseconds: 1_000) { [weak self] in
            self?.recompute()
        }
        tickTimer = tick
        tick.start()
    }

    /// The window closed: the tick and the log observation stop, a snapshot in flight is dropped.
    public func close() {
        guard isOpen else { return }
        isOpen = false
        tickTimer?.stop()
        tickTimer = nil
        derived?.stop()
        derived = nil
    }

    /// The ticks that ran, the generation of the snapshot job (tests) and the seam that computes it.
    var snapshotGeneration: Int {
        derived?.generation ?? 0
    }

    var snapshotSource: (@MainActor () -> LogDerived<ContestStats>.Job)? {
        get { derived?.source }
        set {
            if let newValue {
                derived?.source = newValue
            }
        }
    }

    /// Computes a snapshot now (tests install a gated job and call this).
    func refreshSnapshot() {
        derived?.refresh()
    }

    /// Waits for the snapshot in flight and the file work.
    func settle() async {
        await derived?.settle()
        let pending: [Task<Void, Never>] = ioTasks
        for task in pending {
            await task.value
        }
        await ioLane.settle()
    }

    // MARK: - tuned band

    private func trackBand(token: Int) {
        withObservationTracking {
            _ = rig.currentBand
        } onChange: { [weak self] in
            MainHop.post {
                guard let self, self.isOpen, token == self.bandToken else { return }
                // Kotlin `LaunchedEffect(currentBand)`: set whenever the tuned band is not `null`.
                let current: Band? = self.rig.currentBand
                if current != nil {
                    self.tunedSince = JavaInstant(date: self.clockNow())
                }
                self.recompute()
                self.trackBand(token: token)
            }
        }
    }

    /// The moment the tuned band last changed while the window was open (tests).
    var tunedSinceInstant: JavaInstant? {
        tunedSince
    }

    // MARK: - the snapshot

    /// The contest start (`AppState.contestStartedAt`).
    var contestStart: JavaInstant? {
        EntryModel.parseStartedAt(contest.activeSetup?.startedAt ?? "").map { JavaInstant(date: $0) }
    }

    /// Recomputes everything derived from the snapshot and the clock (one tick).
    func recompute() {
        let at = JavaInstant(date: clockNow())
        now = at
        let translator: Translator = language.translator
        let settings: InfoWindowConfig = config.config.infoWindow
        goals = GoalFileWriter.fromConfigMap(config.config.goals)
        let start: JavaInstant? = contestStart
        let operatingRules: ContestDefinition.Operating? = InfoTimers.rules(
            definition: contest.definition, category: contest.activeSetup?.category ?? [:])

        header = InfoLines.header(stationCall: config.config.station.call, sentExchange: sources.sentExchange(),
                                  operatorCall: operating.operatorCall, translate: translator)
        lines = infoLines(settings, at: at, translator: translator)

        offTime = InfoTimers.offTime(mode: settings.offTimeMode, stats: stats, now: at, rules: operatingRules,
                                     contestStart: start, translate: translator)
        onBand = InfoTimers.onBand(band: rig.currentBand, stats: stats, tunedSince: tunedSince, now: at,
                                   rules: operatingRules, translate: translator)
        bandChanges = InfoTimers.bandChanges(stats: stats, now: at, rules: operatingRules, translate: translator)

        let showGoals: Bool = settings.showGoals
        let goalSet: GoalSet = goals
        let goalAt: (JavaInstant) -> Int? = { instant in
            RatePanel.goal(goals: goalSet, contestStart: start, showGoals: showGoals, at: instant)
        }
        nearTerm = RatePanel.nearTerm(stats: stats, now: at, goal: goalAt(at), translate: translator)
        trend = try? RatePanel.trend(stats: stats, now: at, minutes: settings.trendMinutes, goalAt: goalAt,
                                     translate: translator)
    }

    private func infoLines(_ settings: InfoWindowConfig, at: JavaInstant, translator: Translator) -> [String] {
        let call: String = InfoLines.normalizedCall(sources.typedCall())
        let position = InfoLines.position(latitude: config.config.station.latitude,
                                          longitude: config.config.station.longitude)
        let info: CallsignInfo? = try? InfoLines.callsignInfo(
            typedCall: call, lookup: contest.runtime.dxccLookup, myLat: position.lat, myLon: position.lon, now: at)
        var out: [String] = []
        if settings.showCallframeSpot {
            out.append(InfoLines.spot(call: call, spots: dxCluster.spots, now: at,
                                      decimalSeparator: language.decimalSeparator))
        }
        if settings.showCountryInfo {
            out.append(InfoLines.country(info))
        }
        if settings.showSunTimes {
            out.append(InfoLines.sun(info, translate: translator))
        }
        if settings.showWwv {
            out.append(InfoLines.wwv(dxCluster.lastWwv))
        }
        return out.filter { !KotlinStrings.isBlank($0) }
    }

    /// The window options of the config (`config.infoWindow`): which parts the window shows.
    public var settings: InfoWindowConfig {
        config.config.infoWindow
    }

    // MARK: - messages

    /// `HHmmZ  text` per message, oldest first (`MESSAGE_TIME`).
    public var messageRows: [String] {
        messages.lines.map { Self.messageRow($0) }
    }

    static func messageRow(_ entry: MessageLog.Entry) -> String {
        let second: Int64 = (entry.at.epochSecond % 86_400 + 86_400) % 86_400
        let hour: Int64 = second / 3_600
        let minute: Int64 = second / 60 % 60
        let clock: String = String(format: "%02d%02d", Int(hour), Int(minute))
        return clock + "Z  " + entry.text
    }

    /// `messageRevision` (the area scrolls to the end when it changes).
    public var messageRevision: Int {
        messages.revision
    }

    /// „Kopírovat text zpráv".
    public func copyMessages() {
        let text: String = (try? messages.asText()) ?? ""
        if KotlinStrings.isBlank(text) {
            status.show("Okno zpráv je prázdné.")
        } else {
            sources.clipboard(text)
            status.show("Text zpráv zkopírován do schránky.")
        }
    }

    /// „Vyčistit okno zpráv".
    public func clearMessages() {
        messages.clear()
    }

    /// „Zobrazit RBN spoty této stanice": the page opens through the browser port (the inert port only logs).
    public func openRbnSpots() {
        guard let url = RbnLink.spotsOfStation(config.config.station.call) else {
            status.show("Není vyplněná volačka stanice.")
            return
        }
        callbook.open(url)
    }

    // MARK: - context menu

    /// The menu in Kotlin order (`RW:387-432`): the current language, the check marks of the current options.
    public var menuEntries: [InfoMenuEntry] {
        let settings: InfoWindowConfig = config.config.infoWindow
        let translator: Translator = language.translator
        let decimal: String = language.decimalSeparator
        func toggle(_ on: Bool, _ key: String, _ option: InfoWindowOption) -> InfoMenuEntry {
            InfoMenuEntry(action: .option(option), title: Self.check(on) + translator.translate(key))
        }
        func plain(_ key: String, _ action: InfoMenuEntry.Action) -> InfoMenuEntry {
            InfoMenuEntry(action: action, title: translator.translate(key))
        }
        var items: [InfoMenuEntry] = []
        items.append(toggle(settings.showCallframeSpot, "Spot rozepsané volačky", .callframeSpot))
        items.append(toggle(settings.showCountryInfo, "Země a azimut", .countryInfo))
        items.append(toggle(settings.showSunTimes, "Východ a západ slunce", .sunTimes))
        items.append(toggle(settings.showWwv, "Zprávy WWV", .wwv))
        items.append(toggle(settings.showGoals, "Zobrazit cíle", .goals))
        items.append(plain("Upravit cíle…", .editGoals))
        items.append(plain("Cíle z dřívějšího deníku…", .goalsFromLog))
        items.append(plain("Importovat cíle ze souboru…", .importGoals))
        items.append(plain("Exportovat cíle do souboru…", .exportGoals))
        items.append(toggle(settings.showMessages, "Okno zpráv", .messages))
        items.append(plain("Kopírovat text zpráv", .copyMessages))
        items.append(plain("Vyčistit okno zpráv", .clearMessages))
        items.append(plain("Zobrazit RBN spoty této stanice", .rbnSpots))
        items.append(toggle(settings.showTimers, "Zobrazit časovače QSO", .timers))
        for minutes in InfoWindowConfig.trendMinuteOptions {
            let title: String = Self.check(settings.trendMinutes == minutes)
                + translator.translate("Průběh — %smin průměry", [.int(minutes)], decimalSeparator: decimal)
            items.append(InfoMenuEntry(action: .option(.trendMinutes(minutes)), title: title))
        }
        for mode in InfoWindowConfig.offTimeModeOptions {
            let label: String = translator.translate(Self.offTimeLabelKey(mode))
            let title: String = Self.check(settings.offTimeMode == mode)
                + translator.translate("Časovač: %s", [.string(label)], decimalSeparator: decimal)
            items.append(InfoMenuEntry(action: .option(.offTimeMode(mode)), title: title))
        }
        return items
    }

    private static func check(_ on: Bool) -> String {
        on ? "✓ " : "  "
    }

    /// `OFF_TIME_LABELS` (`RW:817-823`).
    static func offTimeLabelKey(_ mode: String) -> String {
        switch mode {
        case "sinceLastQso": return "čas od posledního QSO"
        case "offTime": return "off time (celé minuty)"
        case "countUp": return "náběh aktuálního intervalu"
        case "countDown": return "odpočet aktuálního intervalu"
        default: return "kumulativní off time"
        }
    }

    /// Runs a menu action that needs no file; the import and export come with their URL.
    public func perform(_ action: InfoMenuEntry.Action) {
        switch action {
        case .option(let option):
            toggle(option)
        case .editGoals:
            showGoalEditor = true
        case .goalsFromLog:
            showGoalFromLog = true
        case .copyMessages:
            copyMessages()
        case .clearMessages:
            clearMessages()
        case .rbnSpots:
            openRbnSpots()
        case .importGoals, .exportGoals:
            break
        }
    }

    /// A toggle or a choice of the menu: saved with `saveSilently` (no `saveConfig` side effects).
    public func toggle(_ option: InfoWindowOption) {
        var settings: InfoWindowConfig = config.config.infoWindow
        switch option {
        case .callframeSpot: settings.showCallframeSpot.toggle()
        case .countryInfo: settings.showCountryInfo.toggle()
        case .sunTimes: settings.showSunTimes.toggle()
        case .wwv: settings.showWwv.toggle()
        case .goals: settings.showGoals.toggle()
        case .messages: settings.showMessages.toggle()
        case .timers: settings.showTimers.toggle()
        case .trendMinutes(let minutes): settings.trendMinutes = minutes
        case .offTimeMode(let mode): settings.offTimeMode = mode
        }
        config.config.infoWindow = settings
        config.saveSilently()
        recompute()
    }

    // MARK: - goal files

    /// „Importovat cíle ze souboru…": the file is read on the IO lane. With a `band` the goals of that band are
    /// taken; without one a file that has band columns waits for the choice (`pendingImport`), otherwise it is
    /// imported at once.
    public func importGoals(url: URL, band: String? = nil) {
        if isShuttingDown() { return }
        let path: String = url.path
        let task = Task { [weak self] in
            guard let self else { return }
            let read: Result<[String], JavaIOError> = await self.ioLane.run {
                do throws(JavaIOError) {
                    return .success(try GoalFileIO.readLines(path))
                } catch {
                    return .failure(error)
                }
            }
            switch read {
            case .failure(let error):
                self.status.show("Cíle se nepodařilo přečíst (%s)", .string(ErrorText.message(error)))
            case .success(let lines):
                if band == nil {
                    let bands: [String] = GoalFileParser.parse(lines, nil).bands
                    if !bands.isEmpty {
                        self.pendingImport = PendingGoalImport(lines: lines, bands: bands)
                        return
                    }
                }
                await self.applyGoalImport(lines, band: band)
            }
        }
        ioTasks.append(task)
    }

    /// The choice of the band dialog (`nil` = all bands); the goals are taken from the waiting file.
    public func chooseImportBand(_ band: String?) {
        if isShuttingDown() { return }
        guard let pending = pendingImport else { return }
        pendingImport = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.applyGoalImport(pending.lines, band: band)
        }
        ioTasks.append(task)
    }

    /// The dialog was dismissed.
    public func cancelImport() {
        pendingImport = nil
    }

    private func applyGoalImport(_ lines: [String], band: String?) async {
        let result: GoalImport = GoalFileParser.parse(lines, band)
        config.config.goals = GoalFileWriter.toConfigMap(result.goals)
        do {
            try await config.saveNow(config.config)
        } catch {
            status.showVerbatim(GoalEditing.saveFailedText(ErrorText.message(error), translate: language.translator))
            return
        }
        status.showVerbatim(GoalEditing.importStatus(result, band: band, translate: language.translator))
        recompute()
        onGoalsChanged()
    }

    /// „Exportovat cíle do souboru…" asks this before its file panel (Kotlin checks first): without goals the status
    /// says so and no file is chosen.
    public func canExportGoals() -> Bool {
        if GoalFileWriter.fromConfigMap(config.config.goals).isEmpty {
            status.show("Není co exportovat — žádné cíle nejsou načtené.")
            return false
        }
        return true
    }

    /// „Exportovat cíle do souboru…": nothing is written without goals.
    public func exportGoals(url: URL) {
        if isShuttingDown() { return }
        let goalSet: GoalSet = GoalFileWriter.fromConfigMap(config.config.goals)
        if goalSet.isEmpty {
            status.show("Není co exportovat — žádné cíle nejsou načtené.")
            return
        }
        let path: String = url.path
        let task = Task { [weak self] in
            guard let self else { return }
            let written: JavaIOError? = await self.ioLane.run {
                do throws(JavaIOError) {
                    try GoalFileIO.write(goalSet, to: path)
                    return nil
                } catch {
                    return error
                }
            }
            if let written {
                self.status.show("Export cílů selhal (%s)", .string(ErrorText.message(written)))
            } else {
                self.status.show("Cíle uloženy do %s", .string(path))
            }
        }
        ioTasks.append(task)
    }
}
