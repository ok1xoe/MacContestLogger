import Foundation
import MCLCore
import Observation
#if canImport(AppKit)
import AppKit
#endif

/// Root of the app models: bootstrap in the Kotlin order (`KApp:110-144`), the models and the shutdown
/// order (`KApp:197-207`).
@Observable @MainActor
public final class AppModel {

    /// What the bootstrap reads from the outside world; tests pass temporary directories and fake clocks.
    public struct Environment {
        /// Application data directory (`AppPaths.dataDir()`, honouring `MCL_DATA_DIR`).
        public var dataDir: URL
        /// DXCC data (Kotlin `~/dxcc-json`); `nil` = none.
        public var dxccDir: URL?
        public var decimalSeparator: String
        public var rescoreClock: any RescoreClock
        public var geometryClock: any RescoreClock
        public var now: @Sendable () -> Date
        /// The bundle version (Kotlin `jpackage.app-version`); `nil` = „vývojová verze".
        public var appVersion: String?
        /// The keyer, the rig and the dupe beep of the entry window (no keyer, no rig).
        public var ports: EntryPorts
        /// The clock of the call history prefill delay; `nil` = the main queue.
        public var suggestionClock: (any RescoreClock)?
        /// The clock of the periodic automatic backup (`AutoBackupLoop`); `nil` = the main queue.
        public var backupClock: (any RescoreClock)?
        /// Where the contest definition updates download from; `nil` = `DefinitionUpdater.defaultBase` over
        /// `URLSession` (tests pass a local server).
        public var definitionSource: DataToolsModel.DefinitionSource?
        /// The clock of the definition editor's check delay (250 ms); `nil` = the main queue.
        public var definitionCheckClock: (any RescoreClock)?
        /// The effects of a saved configuration owned by other subsystems; no-ops until they are wired.
        public var settingsServices: SettingsServices = SettingsServices()
        /// Writes `config.json`; `nil` = the file in `dataDir` (tests pass a failing writer).
        public var configWriter: ConfigWriter?
        /// The rig list, rig scan, devices and fldigi of the Settings tabs; the default touches nothing.
        public var settingsToolPorts: SettingsToolPorts = SettingsToolPorts()
        /// The clock of the Settings counts' delay (300 ms); `nil` = the main queue.
        public var settingsCountsClock: (any RescoreClock)?
        /// The rig, OTRSP, the footswitch, the rotator and the playback. Inert by default: nothing opens; only
        /// `production()` passes the live ports, and not when `MCL_INERT_HARDWARE=1`.
        public var hardware: HardwarePorts = .inert
        /// The CAT traffic log of the rigs (`CatTrafficLog.shared` in the app; a private one per environment, so
        /// tests never write into each other's directories).
        public var catLog = CatTrafficLog(maxLines: 1000)
        /// The clock of the rotator's 2 s poll; `nil` = the main queue.
        public var rotatorClock: (any RescoreClock)?
        /// The clock of the keying (the CW lamp's estimate, the 30 s tuning safeguard, the fldigi watch, the message
        /// recording limit, the CQ repeat loop); `nil` = the main queue.
        public var keyerClock: (any RescoreClock)?
        /// The clock of the radio tool windows' refresh (CW reader 150 ms, waterfall 100 ms, digital interface
        /// 300 ms / 1 s); `nil` = the main queue.
        public var radioWindowClock: (any RescoreClock)?
        /// The DX cluster, RBN, callbook and browser ports. Inert by default: nothing connects; only
        /// `production()` passes the live ports, and not when `MCL_INERT_NETWORK` is set.
        public var network: NetworkPorts = .inert
        /// The clock of the spot feed's 15 s tick; `nil` = the main queue.
        public var spotClock: (any RescoreClock)?
        /// The clock of the integrations' loops (the broadcast snapshot 1 s, the score 60 s, the NTP check 30 min, the
        /// Club Log retry 60 s); `nil` = the main queue.
        public var integrationClock: (any RescoreClock)?
        /// The clock of the cluster sync's 1 s state loop, the 50 ms transmit announcement and the 3 s bound of the
        /// quit; `nil` = the main queue.
        public var clusterClock: (any RescoreClock)?
        /// The clock of the Info window's 1 s tick, the 300 ms score debounce, the sked (15 s) and TOUR (5 s) watchers
        /// and the world map's 60 s night layer; `nil` = the main queue.
        public var toolClock: (any RescoreClock)?
        /// The world map's outlines (a local file); nothing by default, `production` reads `~/dxcc-world-map`.
        public var mapData: any MapDataPort = EmptyMapData()
        /// The system pasteboard of „Kopírovat text zpráv"; nothing by default, `production` writes the pasteboard.
        public var clipboard: @MainActor (String) -> Void = { _ in }

        public init(dataDir: URL, dxccDir: URL?, decimalSeparator: String = LanguageModel.systemDecimalSeparator,
                    rescoreClock: any RescoreClock, geometryClock: any RescoreClock,
                    now: @escaping @Sendable () -> Date = Date.init, appVersion: String? = nil,
                    ports: EntryPorts = EntryPorts(), suggestionClock: (any RescoreClock)? = nil,
                    backupClock: (any RescoreClock)? = nil,
                    definitionSource: DataToolsModel.DefinitionSource? = nil,
                    definitionCheckClock: (any RescoreClock)? = nil) {
            self.dataDir = dataDir
            self.dxccDir = dxccDir
            self.decimalSeparator = decimalSeparator
            self.rescoreClock = rescoreClock
            self.geometryClock = geometryClock
            self.now = now
            self.appVersion = appVersion
            self.ports = ports
            self.suggestionClock = suggestionClock
            self.backupClock = backupClock
            self.definitionSource = definitionSource
            self.definitionCheckClock = definitionCheckClock
        }

        /// The running app: the real data directory and `~/dxcc-json`, main-queue clocks, the bundle's version, the
        /// live hardware unless `MCL_INERT_HARDWARE` is in `processEnvironment` with any value but `0`.
        @MainActor public static func production(
            processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> Environment {
            let home: URL = FileManager.default.homeDirectoryForCurrentUser
            let version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            var environment = Environment(dataDir: AppPaths.dataDir(),
                                          dxccDir: home.appendingPathComponent("dxcc-json"),
                                          rescoreClock: MainQueueRescoreClock(),
                                          geometryClock: MainQueueRescoreClock(), appVersion: version,
                                          ports: EntryPorts(beep: { @MainActor in SystemBeep.beep() }))
            environment.hardware = .production(environment: processEnvironment)
            // With `MCL_INERT_HARDWARE=1` the Settings tools stay inert too (no rig scan, no fldigi probe, no
            // serial or CoreAudio listing).
            environment.settingsToolPorts = environment.hardware.isInert ? SettingsToolPorts() : .live
            environment.network = .production(environment: processEnvironment)
            environment.catLog = .shared
            environment.mapData = LocalMapData()
            environment.clipboard = { text in
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif
            }
            return environment
        }
    }

    /// Steps of the quit sequence. Each defaults to a no-op so that tests can record the order; `bootstrap` wires every
    /// one to its production service (transmit release, keyers, CAT, DX cluster, cluster sync, integrations).
    public struct ShutdownServices {
        /// The first step of the quit: everything that transmits is released and its lanes awaited — the CQ repeat
        /// runners stopped, a held footswitch PTT released (`T 0`), voice and CW aborted, a tune carrier switched
        /// off. `bootstrap` wires it; `keyers` and `cat` repeat these releases idempotently as a backstop.
        public var releaseTransmit: @MainActor () async -> Void = {}
        /// `shutdownKeyers()` — `bootstrap` wires the CQ repeat loop, the voice keyer, fldigi and the CW keyer.
        public var keyers: @MainActor () async -> Void = {}
        /// `cat.disconnect("ukončeno")` — `bootstrap` wires both rigs, then the footswitch, OTRSP and the rotator,
        /// the contest recorder and the receiver audio.
        public var cat: @MainActor () async -> Void = {}
        /// `dxCluster.disconnect("ukončeno")` — `bootstrap` wires every connection, the callbook lane and the spot
        /// feed.
        public var dxCluster: @MainActor () async -> Void = {}
        /// The DX cluster's last part, the quit's last step (after the database close and the geometry and config
        /// flushes): the sessions' threads awaited (a connect in flight), the callbook lane closed (its lookup in
        /// flight finishes).
        public var dxClusterDrain: @MainActor () async -> Void = {}
        /// `stopCluster()`.
        public var cluster: @MainActor () async -> Void = {}
        /// `stopBroadcast()`, `stopWsjtx()`, `stopN1mm()`, `stopAdifUdp()`.
        public var integrations: @MainActor () async -> Void = {}

        public init() {}
    }

    public let language: LanguageModel
    public let status: StatusModel
    public let config: ConfigModel
    public let database: DatabaseModel
    public let logbook: LogbookModel
    public let contest: ContestModel
    public let entry: EntryModel
    public let operating: OperatingModel
    public let windows: WindowsModel
    public let menu: MenuModel
    public let dialogs: DialogsModel
    /// Import, merge, the exports and printing.
    public let exports: ImportExportModel
    /// The program messages of the Info window.
    public let messages: MessagesModel
    /// The periodic automatic backup.
    @ObservationIgnored public let autoBackup: AutoBackupLoop
    /// `master.scp` and the call history.
    public let callData: CallDataModel
    /// Check partial, N+1, worked-before, the call history prefill and the reverse lookup.
    public let suggestions: SuggestionsModel
    /// The info strip next to Run/S&P.
    public let infoStrip: InfoStripModel
    /// The DXCC refill, call history from the log and the definition updates.
    public let dataTools: DataToolsModel
    /// The contest definition editor (window `defeditor`).
    public let definitionEditor: DefinitionEditorModel
    /// The configuration profiles (window `profiles`).
    public let profiles: ProfilesModel
    /// The Settings window (`settings`), its commit and the effects of a saved configuration.
    public let settings: SettingsModel
    /// The tools of the Settings tabs: rig list and scan, ports, devices, fldigi, counts, languages, menu file.
    public let settingsTools: SettingsToolsModel
    /// The look from Settings → Other.
    public let appearance: AppearanceModel
    /// The two rigs, tuning, VFOs, RIT, split and antennas.
    public let rig: RigModel
    /// The footswitch and the OTRSP controller.
    public let peripherals: PeripheralsModel
    /// The rotator.
    public var rotator: RotatorModel { rig.rotator }
    /// The CAT log window's lines.
    public let catLog: CatLogModel
    /// The CW keyer, the voice keyer and fldigi.
    public let keyer: KeyerModel
    /// The shared receiver audio.
    public let audio: AudioModel
    /// The contest recording and the QSO playback.
    public let recording: RecordingModel
    /// The DX cluster connections, main and parallel.
    public let dxCluster: DxClusterModel
    /// The network log: the MQTT session, the stations' presence, the serial server and shared spots.
    public let cluster: ClusterSyncModel
    /// Chat, PASS and the partner's call stack over the network log.
    public let network: NetworkModel
    /// The one subscription to the spot buffer.
    public let spotFeed: SpotFeed
    /// The DX cluster blacklist.
    public let blacklist: BlacklistModel
    /// HamQTH and QRZ.com, the offline grids and the browser pages of a call.
    public let callbook: CallbookModel
    /// The current spot analysis.
    public let spotAnalysis: SpotAnalysisModel
    /// The spot actions of the entry windows (navigation, Spot It, Store, Mark, Alt+D, SPOTME, BEACONS).
    public let spotNavigation: SpotNavigation
    /// The Bandmap window.
    public let bandmap: BandmapModel
    /// The Available Multipliers window and its filter.
    public let availMult: AvailMultModel
    /// The UDP integrations: broadcast, WSJT-X, N1MM and ADIF receive.
    @ObservationIgnored public internal(set) var integrations: IntegrationsModel!
    /// Club Log, the scoreboard and the clock check.
    @ObservationIgnored public internal(set) var onlineServices: OnlineServicesModel!
    /// The plugins.
    @ObservationIgnored public internal(set) var plugins: PluginsModel!
    /// The Info window and the tool windows' models.
    @ObservationIgnored public internal(set) var infoTools: InfoTools!
    /// The pileup simulator and its safety gate.
    @ObservationIgnored public internal(set) var simulator: SimulatorModel!
    /// The Move Multipliers window.
    @ObservationIgnored public internal(set) var moveMults: MoveMultsModel!
    /// "Odvysílat CW" of the QTC window.
    @ObservationIgnored public internal(set) var qtcSending: QtcSending!
    /// The CQ repeat loop of the main entry window.
    @ObservationIgnored var cqRepeatRunner: CqRepeatRunner?
    /// The VFO B / rig 2 entry window (`entry-vfob`, SO2V/SO2R).
    public let vfoB: EntryPanel
    /// The CQ repeat loop of the VFO B window (Kotlin: one loop per panel; idle while the window is hidden).
    @ObservationIgnored var cqRepeatRunnerB: CqRepeatRunner?
    @ObservationIgnored public let geometry: WindowGeometryStore
    /// The refresh clock of the radio tool windows (`Environment.radioWindowClock`).
    @ObservationIgnored var radioWindowClock: any RescoreClock = MainQueueRescoreClock()
    @ObservationIgnored public var shutdownServices = ShutdownServices()
    /// Menu actions whose model lives outside this file's wiring (by menu id); `MenuActions.perform` runs them.
    @ObservationIgnored public var extraMenuActions: [String: @MainActor () -> Void] = [:]
    public let dataDir: URL
    /// Set when `shutdown()` starts; the entry accepts no input from then on.
    public private(set) var isShuttingDown: Bool = false
    /// Quit milestone: `releaseTransmit` finished — nothing keys a transmitter any more.
    public private(set) var transmitReleased: Bool = false
    /// The quit's forced backup is being written (`database.close`).
    public private(set) var writingFinalBackup: Bool = false
    /// Called on the main actor whenever a quit milestone changes (`TerminationSignals` waits for them).
    @ObservationIgnored public var onQuitMilestone: (@MainActor () -> Void)?
    /// Test seam: the quit is about to wait for a Settings commit in flight.
    @ObservationIgnored var beforeSettingsSettle: (@MainActor () -> Void)?
    /// Test observation point of the quit steps that have no port of their own (the quit order test records them
    /// together with the `shutdownServices` ports); never set in production.
    @ObservationIgnored var quitStepObserver: (@MainActor (String) -> Void)?

    /// A further SIGTERM/SIGINT/SIGHUP may end the process at once: only after the quit's transmit release and not
    /// while the forced backup is written (a quit that never starts is ended by the signals' deadline).
    public var signalExitAllowed: Bool {
        transmitReleased && !writingFinalBackup
    }

    /// The entry window accepts input: not while quitting or switching the database (a QSO typed then would be
    /// logged into a closing database or lost with the old one), and not while a contest activates (it would get
    /// the previous contest's serial and dupe state).
    public var acceptsEntryInput: Bool {
        let switching: Bool = database.isSwitching
        let activating: Bool = contest.isActivating
        return !isShuttingDown && !switching && !activating
    }

    private init(language: LanguageModel, status: StatusModel, config: ConfigModel, database: DatabaseModel,
                 logbook: LogbookModel, contest: ContestModel, entry: EntryModel, operating: OperatingModel,
                 windows: WindowsModel, menu: MenuModel, dialogs: DialogsModel, exports: ImportExportModel,
                 messages: MessagesModel, autoBackup: AutoBackupLoop, callData: CallDataModel,
                 suggestions: SuggestionsModel, infoStrip: InfoStripModel, tools: Tools, radio: Radio,
                 spots: Spots, spotTools: SpotTools, net: NetModels, vfoB: EntryPanel,
                 geometry: WindowGeometryStore, dataDir: URL) {
        self.language = language
        self.status = status
        self.config = config
        self.database = database
        self.logbook = logbook
        self.contest = contest
        self.entry = entry
        self.operating = operating
        self.windows = windows
        self.menu = menu
        self.dialogs = dialogs
        self.exports = exports
        self.messages = messages
        self.autoBackup = autoBackup
        self.callData = callData
        self.suggestions = suggestions
        self.infoStrip = infoStrip
        self.dataTools = tools.dataTools
        self.definitionEditor = tools.definitionEditor
        self.profiles = tools.profiles
        self.settings = tools.settings
        self.settingsTools = tools.settingsTools
        self.appearance = tools.appearance
        self.rig = radio.rig
        self.peripherals = radio.peripherals
        self.catLog = radio.catLog
        self.keyer = radio.keyer
        self.audio = radio.audio
        self.recording = radio.recording
        self.dxCluster = spots.dxCluster
        self.spotFeed = spots.feed
        self.blacklist = spots.blacklist
        self.callbook = spots.callbook
        self.spotAnalysis = spots.analysis
        self.spotNavigation = spotTools.navigation
        self.bandmap = spotTools.bandmap
        self.availMult = spotTools.availMult
        self.cluster = net.cluster
        self.network = net.network
        self.vfoB = vfoB
        self.geometry = geometry
        self.dataDir = dataDir
    }

    /// Kotlin start-up (`App.kt:110-144`), in its order:
    /// 1. `ConfigStore.load`;
    /// 2. the language (`LanguageCatalog.ensureDir` + `I18n.use`) **before** any other model exists (commit #159);
    /// 3. the databases directory: the configured one when valid, otherwise `dataDir/databases` (a configured but
    ///    missing one logs a warning and raises the first-run flag);
    /// 4. `DatabaseCatalog`, `lastDatabase` or `ensureDefault`, `LogbookRepository` (off the main thread);
    /// 5. the models (`AppState(…)`; the contest environment is built in its constructor);
    /// 6. `offerStartupDialog`, then the menu (`menu.json`).
    ///
    /// Then `CatTrafficLog.setFile(dataDir/cat.log)` (`App.kt:138`) and the rigs' start (`applyModeSettings`, the
    /// footswitch, the rotator poll, and the radio mode with OTRSP), and after the start-up dialog
    /// `setRecording(true)` for `recordContest` (`App.kt:144`). Handled by the network services:
    /// `start{Broadcast,Wsjtx,N1mm,AdifUdp}IfEnabled`.
    public static func bootstrap(_ environment: Environment) async throws -> AppModel {
        let dataDir: URL = environment.dataDir
        let configFile: URL = dataDir.appendingPathComponent("config.json")
        let store = ConfigStore(file: configFile)
        let loaded: AppConfig = try await BlockingQueue.run {
            store.load()
        }
        let languageDir: URL = dataDir.appendingPathComponent("language")
        let translator: Translator = await LanguageModel.load(code: loaded.language, languageDir: languageDir)
        let language = LanguageModel(translator: translator, languageDir: languageDir,
                                     decimalSeparator: environment.decimalSeparator)
        let status = StatusModel(language: language)
        let config = ConfigModel(config: loaded, store: store,
                                 writer: environment.configWriter ?? ConfigWriter(file: configFile), status: status)

        let resolved = DatabaseModel.resolveDatabasesDir(configured: loaded.databasesDir, dataDir: dataDir)
        if let missing = resolved.missing {
            let warning: String = language.tr("Nakonfigurovaný adresář databází neexistuje: %s — nutný nový výběr",
                                              .string(missing))
            appLog.warning("\(warning, privacy: .public)")
        }
        let databasesDir: URL = resolved.dir
        let lastDatabase: String = loaded.lastDatabase
        let handle: LogbookHandle = try await BlockingQueue.run {
            try DatabaseModel.openInitial(databasesDir: databasesDir, lastDatabase: lastDatabase)
        }
        let database = DatabaseModel(databasesDir: databasesDir, currentName: handle.name, handle: handle,
                                     needsDatabasesDir: resolved.needsChoice, dataDir: dataDir, config: config,
                                     status: status, now: environment.now)

        let contestEnvironment: ContestEnvironment = await ContestModel.loadEnvironment(
            contestDataDir: loaded.contestDataDir, dxccDir: environment.dxccDir, dataDir: dataDir,
            clubLogDxcc: loaded.clubLog.ctyEnabled)
        let logbook = LogbookModel(database: database, status: status)
        logbook.ownStationId = { [weak config] in
            config?.config.cluster.stationId ?? ""
        }
        let contest = ContestModel(environment: contestEnvironment, config: config, status: status,
                                   database: database, logbook: logbook, clock: environment.rescoreClock)
        contest.environmentSource = (dxccDir: environment.dxccDir, dataDir: dataDir)
        let operating = OperatingModel(config: config, status: status)
        let windows = WindowsModel(config: config)
        let menu = MenuModel(language: language, status: status, contest: contest, dataDir: dataDir)
        menu.keyBindingsSource = { [weak config] in
            config?.config.keyBindings
        }
        let dialogs = DialogsModel(contest: contest, database: database, config: config, status: status,
                                   logbook: logbook, operating: operating, now: environment.now)
        let radio: Radio = Self.makeRadio(environment, config: config, status: status, language: language,
                                          contest: contest, dialogs: dialogs, windows: windows, operating: operating)
        var ports: EntryPorts = environment.ports
        if ports.rig is NoRig {
            ports.rig = LiveRig(model: radio.rig)
        }
        if ports.keyer is NoKeyer {
            ports.keyer = LiveKeyer(model: radio.keyer)
        }
        let entryDependencies = EntryModel.Dependencies(
            contest: contest, logbook: logbook, status: status, config: config, database: database,
            operating: operating, dialogs: dialogs, windows: windows, menu: menu, ports: ports,
            dataDir: dataDir, appVersion: environment.appVersion, now: environment.now)
        let entry = EntryModel(entryDependencies)
        wire(radio, entry: entry, logbook: logbook)
        wireKeyer(radio, entry: entry, config: config)
        let callData = CallDataModel(config: config, status: status, dataDir: dataDir)
        let suggestionClock: any RescoreClock = environment.suggestionClock ?? MainQueueRescoreClock()
        let vfoB: EntryPanel = Self.makeVfoB(entryDependencies, callData: callData, logbook: logbook,
                                             contest: contest, clock: suggestionClock)
        logbook.settleInserts = { [weak entry, weak second = vfoB.entry] in
            await entry?.settleSubmissions()
            await second?.settleSubmissions()
        }
        dialogs.onWipeLog = { [weak entry] in
            entry?.track { [weak entry] in await entry?.wipeLogNow() }
        }
        dialogs.onDeleteLast = { [weak entry] in
            entry?.track { [weak entry] in await entry?.deleteLastNow() }
        }
        let messages = MessagesModel()
        let exports = ImportExportModel(contest: contest, config: config, database: database, logbook: logbook,
                                        status: status, language: language, messages: messages,
                                        appVersion: environment.appVersion, now: environment.now)
        let now: @Sendable () -> Date = environment.now
        // Kotlin `autoBackupIfDue()` every minute (`AS:2045-2052`).
        let autoBackup = AutoBackupLoop(clock: environment.backupClock ?? MainQueueRescoreClock()) {
            [weak database, weak logbook] in
            guard let database, let logbook else { return }
            await database.backup(force: false, revision: logbook.revision, now: now())
        }
        let geometry = WindowGeometryStore(config: config, clock: environment.geometryClock)
        let suggestions = SuggestionsModel(callData: callData, logbook: logbook, contest: contest,
                                           clock: suggestionClock)
        let infoStrip = InfoStripModel(contest: contest, config: config, language: language, now: environment.now)
        let spots: Spots = Self.makeSpots(environment, config: config, status: status, language: language,
                                          messages: messages, contest: contest)
        let net: NetModels = Self.makeNet(environment, config: config, status: status, language: language,
                                          database: database, logbook: logbook, contest: contest, spots: spots)
        wire(entry: entry, operating: operating, callData: callData, suggestions: suggestions, infoStrip: infoStrip)
        let dataTools = DataToolsModel(DataToolsModel.Dependencies(
            contest: contest, logbook: logbook, callData: callData, config: config, status: status,
            language: language, messages: messages, dataDir: dataDir, now: environment.now,
            definitionSource: environment.definitionSource ?? DataToolsModel.DefinitionSource(),
            clubLogFetcher: environment.network.clubLogCty))
        let definitionEditor = DefinitionEditorModel(
            config: config, contest: contest, language: language, dataDir: dataDir,
            clock: environment.definitionCheckClock ?? MainQueueRescoreClock())
        let settings = SettingsModel(SettingsModel.Dependencies(
            config: config, language: language, status: status, menu: menu, windows: windows, contest: contest,
            callData: callData, operating: operating, dataDir: dataDir, now: environment.now,
            services: Self.clusterServices(
                Self.spotServices(Self.rigServices(environment.settingsServices, radio: radio, config: config),
                                  spots: spots, config: config), cluster: net.cluster)))
        let profiles = ProfilesModel(dir: dataDir.appendingPathComponent("profiles"), config: config, status: status,
                                     settings: settings)
        let settingsTools = SettingsToolsModel(SettingsToolsModel.Dependencies(
            ports: environment.settingsToolPorts, settings: settings, language: language, status: status, menu: menu,
            dataDir: dataDir, countsClock: environment.settingsCountsClock ?? MainQueueRescoreClock()))
        let tools = Tools(dataTools: dataTools, definitionEditor: definitionEditor, profiles: profiles,
                          settings: settings, settingsTools: settingsTools, appearance: AppearanceModel(config: config))
        let spotTools: SpotTools = Self.makeSpotTools(spots, radio: radio, environment: environment, config: config,
                                                      status: status, language: language, contest: contest,
                                                      operating: operating, dialogs: dialogs)
        let model = AppModel(language: language, status: status, config: config, database: database,
                             logbook: logbook, contest: contest, entry: entry, operating: operating,
                             windows: windows, menu: menu, dialogs: dialogs, exports: exports, messages: messages,
                             autoBackup: autoBackup, callData: callData, suggestions: suggestions,
                             infoStrip: infoStrip, tools: tools, radio: radio, spots: spots, spotTools: spotTools,
                             net: net, vfoB: vfoB, geometry: geometry, dataDir: dataDir)
        Self.wireSpotTools(model)
        Self.wireIntegrations(model, environment: environment)
        Self.wireNetwork(model)
        Self.wireInfoTools(model, environment: environment)
        if let scan = environment.settingsToolPorts.rigScan as? LiveRigScan {
            scan.link.attach(radio.rig)
        }
        let runner = CqRepeatRunner(entry: entry, operating: operating, keyer: radio.keyer, config: config,
                                    status: status, clock: environment.keyerClock ?? MainQueueRescoreClock())
        model.cqRepeatRunner = runner
        model.radioWindowClock = environment.radioWindowClock ?? MainQueueRescoreClock()
        let runnerB: CqRepeatRunner = Self.wireVfoB(model, radio: radio,
                                                    clock: environment.keyerClock ?? MainQueueRescoreClock())
        model.cqRepeatRunnerB = runnerB
        Self.wireInfoStrip(model)
        model.shutdownServices.releaseTransmit = { [weak runner, weak runnerB, weak rig = radio.rig,
                                                    weak keyer = radio.keyer] in
            rig?.closeTransmit()
            runner?.stop()
            runnerB?.stop()
            await keyer?.shutdown()
            await rig?.settle()
        }
        model.shutdownServices.keyers = { [weak runner, weak runnerB, weak keyer = radio.keyer] in
            runner?.stop()
            runnerB?.stop()
            await keyer?.shutdown()
        }
        model.shutdownServices.cat = { [weak rig = radio.rig, weak peripherals = radio.peripherals,
                                        weak recording = radio.recording, weak audio = radio.audio] in
            await rig?.shutdown()
            await peripherals?.shutdown()
            await rig?.rotator.shutdown()
            await recording?.shutdown()
            await audio?.shutdown()
        }
        model.shutdownServices.dxCluster = { [weak dxCluster = spots.dxCluster, weak callbook = spots.callbook,
                                              weak feed = spots.feed] in
            feed?.stop()
            callbook?.closeLane()
            await dxCluster?.shutdown()
        }
        model.shutdownServices.cluster = { [weak cluster = net.cluster] in
            await cluster?.shutdown()
        }
        model.shutdownServices.dxClusterDrain = { [weak dxCluster = spots.dxCluster, weak callbook = spots.callbook] in
            await dxCluster?.drain()
            await callbook?.shutdown()
        }
        Self.wireSimulator(model, environment: environment)
        environment.catLog.setFile(dataDir.appendingPathComponent("cat.log"))
        ClubLogTrafficLog.shared.setFile(dataDir.appendingPathComponent("clublog.log"))
        Self.startSpots(spots)
        Self.startRadio(radio)
        runner.start()
        runnerB.start()
        model.extraMenuActions["settings.downloadScp"] = { [weak callData] in
            callData?.downloadScp()
        }
        model.extraMenuActions["contest.record"] = { [weak recording = radio.recording] in
            recording?.toggle()
        }
        registerToolActions(model)
        // The log warnings read `master.scp` and the DXCC lookup (Kotlin `remember(snapshot, state.scp, …)`).
        logbook.warningSources = { [weak callData, weak contest] in
            WarningSources(scp: callData?.scp, dxcc: contest?.runtime.dxccLookup)
        }
        let onLoaded: (@MainActor () -> Void)? = callData.onLoaded
        callData.onLoaded = { [weak logbook] in
            onLoaded?()
            logbook?.refreshWarnings()
        }
        contest.onActivated = { [weak entry, weak second = vfoB.entry, weak analysis = spots.analysis] in
            analysis?.activated()
            entry?.contestActivated()
            second?.contestActivated()
        }
        database.onOpened = { [weak contest, weak model] in
            await contest?.databaseSwitched()
            // The periodic backup resumes on the new database (not while quitting).
            if let model, !model.isShuttingDown {
                model.autoBackup.start()
            }
            await contest?.offerStartupDialog()
        }
        database.drain = { [weak model] in
            // No periodic backup beside the switch (a tick in flight finishes on the old database first).
            await model?.autoBackup.stop()
            await model?.drainDatabaseWork()
            // The cluster session belongs to the old database (Kotlin stops it right after the swap); the
            // activation of the next contest starts it again. Nothing of the old log reaches the new one.
            await model?.cluster.stopAndAwaitRefresh()
        }
        entry.inputGate = { [weak model] in
            model?.acceptsEntryInput ?? false
        }
        // Kotlin offers the start-up dialog during the first composition (`remember`) and loads the menu in a
        // `LaunchedEffect` after it, so a broken `menu.json` has the last word in the status line.
        await contest.offerStartupDialog()
        model.activateIntegrations()
        await radio.recording.startIfConfigured()
        await menu.load()
        autoBackup.start()
        model.plugins.appStarted(contestId: contest.activeId, name: contest.activeName)
        return model
    }

    /// The rig models (one init argument).
    struct Radio {
        let rig: RigModel
        let peripherals: PeripheralsModel
        let catLog: CatLogModel
        let keyer: KeyerModel
        let audio: AudioModel
        let recording: RecordingModel
    }

    private static func makeRadio(_ environment: Environment, config: ConfigModel, status: StatusModel,
                                  language: LanguageModel, contest: ContestModel, dialogs: DialogsModel,
                                  windows: WindowsModel, operating: OperatingModel) -> Radio {
        let hardware: HardwarePorts = environment.hardware
        let peripherals = PeripheralsModel(hardware: hardware, config: config, status: status)
        let rotator = RotatorModel(hardware: hardware, config: config, status: status, language: language,
                                   clock: environment.rotatorClock ?? MainQueueRescoreClock())
        let rig = RigModel(RigModel.Dependencies(
            hardware: hardware, catLog: environment.catLog, config: config, status: status, language: language,
            contest: contest, dialogs: dialogs, windows: windows, peripherals: peripherals, rotator: rotator))
        let clock: any RescoreClock = environment.keyerClock ?? MainQueueRescoreClock()
        let keyer = KeyerModel(KeyerModel.Dependencies(
            hardware: hardware, config: config, status: status, language: language, operating: operating, rig: rig,
            clock: clock, dataDir: environment.dataDir))
        let audio = AudioModel(hardware: hardware, config: config)
        let recording = RecordingModel(RecordingModel.Dependencies(
            audio: audio, config: config, status: status, hardware: hardware, dataDir: environment.dataDir,
            now: environment.now))
        return Radio(rig: rig, peripherals: peripherals, catLog: CatLogModel(log: environment.catLog), keyer: keyer,
                     audio: audio, recording: recording)
    }

    /// The keyer and the main entry window: the free CW text and the voice messages use the window's `cwContext`,
    /// `canSend` its mode, and the interface reset drops the CW keyer.
    private static func wireKeyer(_ radio: Radio, entry: EntryModel, config: ConfigModel) {
        let keyer: KeyerModel = radio.keyer
        keyer.messageContext = { [weak entry] in
            guard let entry else { return nil }
            let context: FunctionKeyContext = entry.functionKeyContext()
            var base: CwMessageBuilder.Context = context.cwBase
            base.functionKeys = context.cw.messages(run: context.run, opposite: false).map(\.text)
            return base
        }
        keyer.entryModeKeyable = { [weak entry, weak keyer] in
            guard let entry, let keyer else { return false }
            return CqRepeatLoop.isKeyable(mode: entry.form.mode, digitalReady: keyer.digital.ready)
        }
        radio.rig.resetKeyer = { [weak keyer] in
            keyer?.resetKeyer()
        }
        radio.rig.keyerRelease = { [weak keyer] index in
            keyer?.releaseBeforeDisconnect(rigIndex: index)
        }
        radio.rig.connectRelease.set(keyer.owedReleaseHook())
    }

    /// The rigs and the main entry window: the window follows the rig, the footswitch reaches the rig (PTT) and the
    /// window (F1 / Enter), the rotator and the antennas read the window and the log, a logged QSO clears RIT.
    private static func wire(_ radio: Radio, entry: EntryModel, logbook: LogbookModel) {
        let rig: RigModel = radio.rig
        rig.attach(entry)
        rig.typedCall = { [weak entry] in
            entry?.form.call ?? ""
        }
        rig.rotator.currentBand = { [weak rig] in
            rig?.currentBand
        }
        rig.rotator.azimuthTo = { [weak rig] call in
            rig?.azimuthTo(call)
        }
        rig.rotator.lastQsoCall = { [weak logbook] in
            logbook?.rows.last?.call
        }
        radio.peripherals.onFootswitch = { [weak rig] pressed in
            rig?.footswitch(pressed)
        }
        radio.peripherals.beforeFootswitchCloses = { [weak rig] in
            rig?.releaseFootswitchPtt()
        }
        radio.peripherals.pressObservers.append { [weak entry] in
            entry?.footswitchPressed()
        }
        logbook.clearRit = { [weak rig] in
            rig?.clearRit()
        }
    }

    /// The Settings ports of the radio tools (`SettingsServices`): the CW speed, the antenna index, the footswitch, the radio
    /// mode, the mode mapping, and the CAT state and reconnect read at their step (the effect plan waits before it).
    private static func rigServices(_ injected: SettingsServices, radio: Radio,
                                    config: ConfigModel) -> SettingsServices {
        let rig: RigModel = radio.rig
        let peripherals: PeripheralsModel = radio.peripherals
        var services: SettingsServices = injected
        let injectedCwSpeed: @MainActor () -> Void = injected.cwSpeed
        services.cwSpeed = { [weak keyer = radio.keyer, weak config] in
            injectedCwSpeed()
            guard let config else { return }
            keyer?.updateCwSpeed(config.config.cwKeyer.speed)
        }
        services.resetAntennaIndex = { [weak rig] in
            rig?.resetAntennaIndex()
        }
        services.footswitch = { [weak peripherals] in
            peripherals?.reloadFootswitch()
        }
        services.radioMode = { [weak rig] in
            rig?.syncRadioModeFromConfig()
        }
        services.modeSettings = { [weak rig] in
            rig?.applyModeSettings()
        }
        services.catConnected = { [weak rig] in
            rig?.catConnected ?? false
        }
        services.reconnectCat = { [weak rig] disconnectFirst in
            rig?.reconnect(disconnectFirst: disconnectFirst)
        }
        return services
    }

    /// The rigs' start in Kotlin's `AppState` order: `applyModeSettings()` (`AS:345`), `reloadFootswitch()`
    /// (`AS:643`), the rotator poll (`AS:680`); then: `syncRadioModeFromConfig()` once (OTRSP opens).
    private static func startRadio(_ radio: Radio) {
        radio.rig.applyModeSettings()
        radio.peripherals.reloadFootswitch()
        radio.rig.rotator.start()
        radio.rig.syncRadioModeFromConfig()
    }

    /// The spot models (one init argument).
    struct Spots {
        let dxCluster: DxClusterModel
        let feed: SpotFeed
        let blacklist: BlacklistModel
        let callbook: CallbookModel
        let analysis: SpotAnalysisModel
    }

    private static func makeSpots(_ environment: Environment, config: ConfigModel, status: StatusModel,
                                  language: LanguageModel, messages: MessagesModel, contest: ContestModel) -> Spots {
        let dxCluster = DxClusterModel(config: config, status: status, language: language, messages: messages,
                                       network: environment.network, now: environment.now)
        let feed = SpotFeed(buffer: dxCluster.spots, clock: environment.spotClock ?? MainQueueRescoreClock())
        let blacklist = BlacklistModel(config: config, spots: dxCluster.spots, now: environment.now)
        let callbook = CallbookModel(config: config, contest: contest, network: environment.network,
                                     spots: dxCluster.spots, dataDir: environment.dataDir)
        let analysis = SpotAnalysisModel(contest: contest, config: config, callbook: callbook,
                                         translator: dxCluster.translator,
                                         now: environment.now)
        callbook.analyzer = { [weak analysis] in
            analysis?.current()
        }
        return Spots(dxCluster: dxCluster, feed: feed, blacklist: blacklist, callbook: callbook, analysis: analysis)
    }

    /// The spot windows' and actions' models.
    struct SpotTools {
        let navigation: SpotNavigation
        let bandmap: BandmapModel
        let availMult: AvailMultModel
    }

    private static func makeSpotTools(_ spots: Spots, radio: Radio, environment: Environment, config: ConfigModel,
                                      status: StatusModel, language: LanguageModel, contest: ContestModel,
                                      operating: OperatingModel, dialogs: DialogsModel) -> SpotTools {
        let navigation = SpotNavigation(SpotNavigation.Dependencies(
            dxCluster: spots.dxCluster, analysis: spots.analysis, blacklist: spots.blacklist, rig: radio.rig,
            status: status, config: config, language: language, dialogs: dialogs, now: environment.now))
        let bandmap = BandmapModel(BandmapModel.Dependencies(
            feed: spots.feed, analysis: spots.analysis, contest: contest, config: config, operating: operating,
            blacklist: spots.blacklist, callbook: spots.callbook, rig: radio.rig))
        let availMult = AvailMultModel(AvailMultModel.Dependencies(
            feed: spots.feed, analysis: spots.analysis, contest: contest, blacklist: spots.blacklist,
            callbook: spots.callbook, rig: radio.rig))
        return SpotTools(navigation: navigation, bandmap: bandmap, availMult: availMult)
    }

    /// The spots and the entry windows: `tuneToSpot` reads the buffer and predicts the exchange, both
    /// windows get the spot actions and the self-spot tracker (its tuning effect once at start, Kotlin's first
    /// composition), the suggestions read the spot calls and the callbook, the callbook lookup follows the active
    /// window's call, and an opening activation sets the available multipliers' default filter.
    private static func wireSpotTools(_ model: AppModel) {
        let analysis: SpotAnalysisModel = model.spotAnalysis
        model.rig.spotSources = SpotSources(buffer: model.dxCluster.spots, predictExchange: { [weak analysis] spot in
            analysis?.current().predictExchange(spot) ?? JavaLinkedMap()
        })
        let buffer: SpotBuffer = model.dxCluster.spots
        for panel in [model.panel(vfo: 0), model.vfoB] {
            let entry: EntryModel = panel.entry
            entry.spotNavigation = model.spotNavigation
            entry.helpOpener = { [weak callbook = model.callbook] in
                callbook?.openHelp()
            }
            panel.suggestions.spotCalls = {
                buffer.snapshot().map(\.dxCall)
            }
            panel.suggestions.callbookSource = { [weak callbook = model.callbook] in
                callbook?.callbookRecord
            }
            panel.suggestions.lookupSource = { [weak callbook = model.callbook] in
                callbook?.entryLookup
            }
            panel.suggestions.callbookActive = { [weak entry] in
                entry?.isActivePanel ?? false
            }
            panel.suggestions.callbookLookup = { [weak model] call in
                guard let model else { return }
                model.callbook.lookup(call, typedCall: { [weak model] in model?.typedCall ?? "" })
            }
            entry.selfSpotTuned()
        }
        model.bandmap.spotNavigation = model.spotNavigation
        model.bandmap.keyEntry = { [weak model] in
            guard let model else { return nil }
            return model.vfoB.entry.isActivePanel ? model.vfoB.entry : model.entry
        }
        model.contest.onDefaultSpotFilters = { [weak availMult = model.availMult] bands, modes in
            availMult?.setDefaults(bands: bands, modes: modes)
        }
    }

    /// The spots' start in Kotlin's `AppState.init` order (`AS:337-342`): `migrateLegacyBlacklist()`,
    /// `applyDxClusterBlacklist()`, the buffer listener of the callbook prefetch, then `wireSelfSpotMessages()` —
    /// which wires the main connection (its `myCall` from the station) and runs `syncParallelClusters()`
    /// (the parallel favourites connect now).
    private static func startSpots(_ spots: Spots) {
        spots.blacklist.migrateLegacy()
        spots.blacklist.apply()
        spots.feed.start()
        spots.feed.addObserver { [weak callbook = spots.callbook] in
            callbook?.prefetch()
        }
        spots.dxCluster.syncParallelClusters()
    }

    /// The Settings ports of the spot windows: the station call of every cluster connection, the parallel plan, the
    /// buffer age, the skimmer threshold, the blacklist and the callbook clients. An injected port (tests) runs
    /// first, then the live one.
    private static func spotServices(_ base: SettingsServices, spots: Spots,
                                     config: ConfigModel) -> SettingsServices {
        var services: SettingsServices = base
        let dxCluster: DxClusterModel = spots.dxCluster
        services.dxMyCall = chain(base.dxMyCall) { [weak dxCluster] in
            dxCluster?.applyMyCall()
        }
        services.parallelClusters = chain(base.parallelClusters) { [weak dxCluster] in
            dxCluster?.syncParallelClusters()
        }
        services.spotBuffer = chain(base.spotBuffer) { [weak dxCluster] in
            dxCluster?.setBufferMinutes()
        }
        services.minSkimmers = chain(base.minSkimmers) { [weak dxCluster, weak config] in
            guard let config else { return }
            dxCluster?.spots.setMinSkimmers(config.config.dxCluster.minSkimmers)
        }
        services.blacklist = chain(base.blacklist) { [weak blacklist = spots.blacklist] in
            blacklist?.apply()
        }
        services.hamQth = chain(base.hamQth) { [weak callbook = spots.callbook] in
            callbook?.reload()
        }
        return services
    }

    private static func chain(_ injected: @escaping @MainActor () -> Void,
                              _ live: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        {
            injected()
            live()
        }
    }

    /// The network models (one init argument).
    struct NetModels {
        let cluster: ClusterSyncModel
        let network: NetworkModel
    }

    private static func makeNet(_ environment: Environment, config: ConfigModel, status: StatusModel,
                                language: LanguageModel, database: DatabaseModel, logbook: LogbookModel,
                                contest: ContestModel, spots: Spots) -> NetModels {
        let cluster = ClusterSyncModel(ClusterSyncModel.Dependencies(
            config: config, status: status, database: database, logbook: logbook, contest: contest,
            spots: spots.dxCluster.spots, network: environment.network, dataDir: environment.dataDir,
            clock: environment.clusterClock ?? MainQueueRescoreClock(), now: environment.now))
        logbook.cluster = cluster
        contest.onStartClusterIfIdle = { [weak cluster] in
            cluster?.startIfIdle()
        }
        let network = NetworkModel(cluster: cluster, status: status, language: language,
                                   spots: spots.dxCluster.spots, now: environment.now)
        return NetModels(cluster: cluster, network: network)
    }

    /// The network log and the entry windows, the keyers and the DX cluster: the own status reads the rig, the
    /// operating state and the keyer; the TX interlock gates every transmission and announces it; the own DX cluster
    /// spots are shared; Ctrl+Alt+P / Ctrl+Alt+K, NETON and NETOFF reach the models; the info strip shows SNS and
    /// the call stack.
    private static func wireNetwork(_ model: AppModel) {
        let cluster: ClusterSyncModel = model.cluster
        let rig: RigModel = model.rig
        let operating: OperatingModel = model.operating
        let keyer: KeyerModel = model.keyer
        cluster.sources.catFreqHz = { [weak rig] in
            rig?.activeState.map { Int(clamping: $0.freqHz) }
        }
        cluster.sources.catMode = { [weak rig] in
            rig?.activeState?.mode
        }
        cluster.sources.tunedFreqHz = { [weak rig] in
            Int(clamping: rig?.tuning.tunedFreqHz ?? 0)
        }
        cluster.sources.runMode = { [weak operating] in
            operating?.runMode ?? .searchAndPounce
        }
        cluster.sources.operatorCall = { [weak operating] in
            operating?.operatorCall ?? ""
        }
        cluster.sources.typedCall = { [weak model] in
            model?.typedCall ?? ""
        }
        cluster.sources.isSending = { [weak keyer] in
            keyer?.isSending ?? false
        }
        let interlock = TxInterlock(cluster: cluster, config: model.config)
        keyer.tx.txGate = {
            interlock.gate()
        }
        keyer.tx.announceTx = {
            interlock.announce()
        }
        model.dxCluster.spotShare = { [weak cluster] spot in
            MainHop.post { cluster?.shareSpot(spot) }
        }
        model.network.prefillCall = { [weak model] call in
            model?.prefillCall(call)
        }
        model.network.openStatusWindow = { [weak model] in
            model?.windows.setOpen("netstatus", true)
        }
        model.network.isChatOpen = { [weak windows = model.windows] in
            windows?.isOpen("chat") ?? false
        }
        model.dialogs.clusterConnected = { [weak cluster] in
            cluster?.connected ?? false
        }
        for panel in [model.panel(vfo: 0), model.vfoB] {
            panel.entry.network = model.network
            panel.entry.cluster = cluster
        }
        let network: NetworkModel = model.network
        let config: ConfigModel = model.config
        model.infoStrip.sources.snsWaiting = { [weak cluster, weak config] in
            guard let cluster, let config else { return nil }
            return config.config.cluster.serialServer && cluster.isRunning && cluster.reservedSerial == nil
        }
        model.infoStrip.sources.stackedCalls = { [weak network] in
            network?.chat.stack ?? []
        }
    }

    /// The Settings port of the network services: a saved cluster change stops and starts the session again. An injected port
    /// (tests) runs first, then the live one.
    private static func clusterServices(_ base: SettingsServices, cluster: ClusterSyncModel) -> SettingsServices {
        var services: SettingsServices = base
        services.restartCluster = chain(base.restartCluster) { [weak cluster] in
            cluster?.restart()
        }
        return services
    }

    /// The models of the data tools, the definition editor, the profiles and the Settings (one init argument).
    struct Tools {
        let dataTools: DataToolsModel
        let definitionEditor: DefinitionEditorModel
        let profiles: ProfilesModel
        let settings: SettingsModel
        let settingsTools: SettingsToolsModel
        let appearance: AppearanceModel
    }

    /// The menu actions of the extra models (`MenuActions.perform` runs `extraMenuActions`) and the editor's refresh
    /// after a contest-data reload or a changed `contestDataDir`.
    private static func registerToolActions(_ model: AppModel) {
        model.extraMenuActions["settings.profiles"] = { [weak model] in
            // Kotlin `showProfiles = true` (not saved in `openWindows`); the list is read when the window opens.
            guard let model else { return }
            model.windows.setOpen("profiles", true)
            Task { await model.profiles.refresh() }
        }
        model.extraMenuActions["contest.updateCallHistory"] = { [weak model] in
            model?.dataTools.updateCallHistoryFromLog()
        }
        model.extraMenuActions["database.updateClubLogDxcc"] = { [weak model] in
            model?.dataTools.updateClubLogDxcc()
        }
        model.extraMenuActions["contest.updateDefinitions"] = { [weak model] in
            model?.dataTools.updateDefinitions()
        }
        model.contest.onDataReloaded = { [weak model] in
            model?.definitionEditor.refresh()
        }
        model.definitionEditor.observeDataDir()
        // Club Log `cty.xml`: the daily check in the background (no network without the fetcher).
        model.dataTools.startClubLogDxccCheck()
    }

    /// The callsign help of the entry window (Kotlin `EP:271-295, 623-669`): the databases load at start
    /// (`AS:343-344`) and follow their configured paths; the suggestions follow the entry form, the log and the
    /// contest. The highlighted suggestion has one owner (`SuggestionsModel`); the entry's keys reach it through
    /// `suggestionSource`, and the prefill comes back through `formSink` without touch marks.
    private static func wire(entry: EntryModel, operating: OperatingModel, callData: CallDataModel,
                             suggestions: SuggestionsModel, infoStrip: InfoStripModel) {
        callData.reload()
        callData.observePaths()
        suggestions.formSource = { [weak entry] in
            entry?.form ?? EntryForm()
        }
        suggestions.formSink = { [weak entry] form in
            entry?.applyCallHistoryPrefill(form)
        }
        entry.suggestionSource = EntryModel.SuggestionSource(
            list: { [weak suggestions] in suggestions?.suggestions ?? [] },
            pick: { [weak suggestions] in suggestions?.scpPick ?? -1 },
            setPick: { [weak suggestions] in suggestions?.setScpPick($0) })
        suggestions.observe()
        infoStrip.sources.countyLine = { [weak entry] in
            entry?.countyLine ?? []
        }
        infoStrip.sources.cqRepeat = { [weak operating] in
            operating?.cqRepeat ?? false
        }
        infoStrip.sources.postContest = { [weak operating] in
            operating?.postContest ?? false
        }
    }

    /// Kotlin quit (`KApp:197-207`), in its order, after the transmit release (milestone `transmitReleased`, before
    /// any other wait): keyers, CAT, DX cluster, cluster sync, the integrations, then
    /// `closeDatabase` with the forced backup (milestone `writingFinalBackup` around it). Before CAT
    /// the pending recount timer is cancelled and the database work in flight is awaited (Kotlin's synchronous UI
    /// thread gives the same: a submitted QSO is stored, and in the backup, before the database closes). Afterwards
    /// pending window geometry is written and the config writes are awaited.
    public func shutdown() async {
        isShuttingDown = true
        // The plugins hear of the quit first (APP_QUITTING); its run is a lane job, and the quit deadline starts here.
        plugins?.appQuitting(contestId: contest.activeId, name: contest.activeName)
        // The transmit release comes before everything else (a second signal waits for it, then may exit at once).
        await shutdownServices.releaseTransmit()
        // The watchers and the window models stop (no tick or observer outlives the quit); they only cancel timers
        // and observers, and never key the rig.
        quitStepObserver?("infoTools")
        infoTools.shutdown()
        // Kotlin `shutdownKeyers()` saves the config (the CW speed, `AS:2147`). With no Settings commit or profile load
        // in flight it is written now, before a second signal may end the process (`signalExitAllowed`); with one in
        // flight it waits for the save after the settles below (an earlier save would overwrite the commit's).
        if !settings.isSaving && !profiles.isLoading {
            config.saveSilently()
            await config.flush()
        }
        transmitReleased = true
        onQuitMilestone?()
        // Kotlin `shutdownKeyers()` comes first (`App.kt:197-198`): nothing keeps transmitting while the database
        // work below drains (the rigs are still connected, so the carrier and PTT are released over them).
        await shutdownServices.keyers()
        // A rig scan stops before its next candidate (no new `rigctld` on the rig's port during the quit).
        settingsTools.windowClosed()
        contest.scheduler.cancel()
        // The periodic backup stops (a tick in flight finishes) before the forced backup of `close`.
        quitStepObserver?("autoBackup.stop")
        await autoBackup.stop()
        // Dialog actions (create, open) and exports read or write the database; they are not part of the drain of a
        // database switch, which itself runs as a dialog action.
        await dialogs.settle()
        await exports.settle()
        // Definition updates (they reload the contest data) and call-history saves in flight, and the editor's
        // checks, saves and imports, and profile loads (each with its contest-data reload) finish before the database closes; their config writes are part of the flush below.
        await dataTools.settle()
        await definitionEditor.settle()
        await profiles.settle()
        // A Settings commit in flight (its contest-data reload, the band data) finishes too.
        beforeSettingsSettle?()
        await settings.settle()
        // The config again, from the current state, after the commit and the profile load above have adopted theirs
        // (and with what changed since the early save).
        config.saveSilently()
        await drainDatabaseWork()
        // The scan's current candidate ends (its `rigctld` closed) before CAT goes.
        await settingsTools.settle()
        await shutdownServices.cat()
        await shutdownServices.dxCluster()
        await shutdownServices.cluster()
        await shutdownServices.integrations()
        writingFinalBackup = true
        quitStepObserver?("database.close")
        await database.close(revision: logbook.revision)
        quitStepObserver?("database.closed")
        writingFinalBackup = false
        onQuitMilestone?()
        // A `master.scp` download in flight finishes (its config write is part of the flush below).
        await callData.settle()
        quitStepObserver?("geometry.flush")
        geometry.flush()
        await config.flush()
        quitStepObserver?("config.flushed")
        // Last: the DX cluster connections finish (a connect hanging in DNS or its timeout, a held auto-login). Nothing
        // above waits for them, so the geometry and the config are written even if a second signal ends the quit here.
        await shutdownServices.dxClusterDrain()
    }

    /// Waits until the work that writes or reads the open database has finished: submissions in flight, activations
    /// and a running recount (with its DXCC backfill). Kotlin does all of it synchronously on the UI thread, so its
    /// quit and database switch never overtake a write.
    func drainDatabaseWork() async {
        // An import or merge started before writes into this database (Kotlin runs it synchronously).
        await exports.settle()
        await entry.settle()
        await vfoB.entry.settle()
        await logbook.settleMutations()
        await contest.settleActivations()
        await contest.settleRescore()
        await entry.settle()
        await vfoB.entry.settle()
        await logbook.settleMutations()
    }
}

/// The system beep of the dupe warning (Kotlin `Toolkit.getDefaultToolkit().beep()`).
enum SystemBeep {
    @MainActor static func beep() {
        #if canImport(AppKit)
        NSSound.beep()
        #endif
    }
}
