/// Working copy of the configuration for the Settings window — `ConfigurerDraft` (`ui/configurer/ConfigurerDraft.kt:
/// 23-317`). The window edits the draft; the configuration changes only on OK (`applied(to:now:)`), Cancel drops it.
///
/// Fields and their initial texts match Kotlin one by one: numbers as `toString()` text, `repeatSeconds` as
/// `String.format(Locale.US, "%.1f")`, `contestDataDir` as the configured directory or the default one. Kotlin reads
/// the band plan and the digi frequencies in the constructor from the **old** `contestDataDir`; Swift takes them as
/// arguments so that the caller reads the files off the main thread.
///
/// Stored properties start from neutral values and are filled per group in the initializer (short expressions).
public struct ConfigurerDraft: Sendable, Equatable {

    // MARK: Hardware (rig / rigctld) — `CD:24-37`

    public var rigMode: ConnectionMode = .launchDaemon
    public var rigModel: Int = 0
    public var rigModelLabel: String = ""
    public var device: String = ""
    public var baud: Int = 0
    public var dataBits: Int = 0
    public var stopBits: Int = 0
    public var parity: SerialParity = .none
    public var flow: FlowControl = .auto
    public var dtr: PinState = .unset
    public var rts: PinState = .unset
    public var host: String = ""
    public var rigPort: String = ""

    // MARK: Station — `CD:39-62` (latitude/longitude are derived from the locator, `gridLatLon`)

    public var call: String = ""
    public var `operator`: String = ""
    public var grid: String = ""
    public var name: String = ""
    public var address1: String = ""
    public var address2: String = ""
    public var city: String = ""
    public var stateRegion: String = ""
    public var zip: String = ""
    public var country: String = ""
    public var cqZone: String = ""
    public var ituZone: String = ""
    public var license: String = ""
    public var stationTxRx: String = ""
    public var power: String = ""
    public var antenna: String = ""
    public var antHeight: String = ""
    public var asl: String = ""
    public var arrlSection: String = ""
    public var roverQth: String = ""
    public var club: String = ""
    public var email: String = ""

    // MARK: Cluster (network multi-op log) — `CD:64-76`

    public var clusterEnabled: Bool = false
    public var brokerHost: String = ""
    public var clusterPort: String = ""
    public var username: String = ""
    public var password: String = ""
    public var stationId: String = ""
    public var tls: Bool = false
    public var shareSpots: Bool = false
    public var interlock: Interlock.Scope = .none
    public var serialServer: Bool = false
    public var stationType: OperatingGuard.StationType = .none
    public var ruleEnforcement: OperatingGuard.Enforcement = .warn

    // MARK: DX Cluster — `CD:78-103`

    public var dxFavorites: [DxFavoriteDraft] = []
    /// Blacklist values from `callBlacklist`/`spotterBlacklist` (`BlacklistService.values`).
    public var blacklistedCalls: [String] = []
    public var blacklistedSpotters: [String] = []
    public var spotBufferMinutes: String = ""
    public var wheelStepHz: String = ""
    public var wheelStepShiftHz: String = ""
    public var selfSpotThresholdHz: String = ""
    public var minSkimmers: String = ""
    public var autoSplit: Bool = false
    public var showBandPlan: Bool = false

    // MARK: HamQTH and QRZ.com — `CD:105-117`

    public var hamQthEnabled: Bool = false
    public var hamQthUsername: String = ""
    public var hamQthPassword: String = ""
    public var hamQthCallModes: [String] = []
    public var hamQthFetchFields: [String] = []
    public var qrzEnabled: Bool = false
    public var qrzUsername: String = ""
    public var qrzPassword: String = ""
    public var qrzCallModes: [String] = []
    public var qrzFetchFields: [String] = []

    // MARK: Band plan and digi frequencies — `CD:119-129`

    public var bandSegments: [BandSegmentDraft] = []
    public var digiChannels: [DigiChannelDraft] = []

    // MARK: Map, keys, contest data — `CD:149-176`

    public var mapScheme: String = ""
    public var mapPolitical: Bool = false
    /// Remapped keys (action id → keys, `""` = no key) — the whole `keyBindings` map.
    public var keyOverrides: [String: String] = [:]
    public var scpFile: String = ""
    public var callHistoryFile: String = ""
    public var scpSuggestionsEnabled: Bool = true
    public var nPlusOneEnabled: Bool = true
    /// The online callbook of the entry window's lookup button (`CallbookService.rawValue`).
    public var preferredCallbook: String = CallbookService.hamQth.rawValue
    public var clEnabled: Bool = false
    public var clEmail: String = ""
    public var clPassword: String = ""
    public var clCallsign: String = ""
    public var clApiKey: String = ""
    public var srEnabled: Bool = false
    public var srUrl: String = ""
    public var srMinutes: String = ""
    public var srBreakdown: Bool = false
    public var autoBackupMinutes: String = ""
    public var autoBackupKeep: String = ""
    public var autoBackupDir: String = ""
    public var contestDataDir: String = ""

    // MARK: Broadcast, WSJT-X, N1MM, ADIF UDP — `CD:178-200`

    public var bcContactsEnabled: Bool = false
    public var bcContactsTargets: String = ""
    public var bcRadioEnabled: Bool = false
    public var bcRadioTargets: String = ""
    public var bcScoreEnabled: Bool = false
    public var bcScoreTargets: String = ""
    public var bcAppInfoEnabled: Bool = false
    public var bcAppInfoTargets: String = ""
    public var wxReceiveEnabled: Bool = false
    public var wxReceiveBind: String = ""
    public var wxSendEnabled: Bool = false
    public var wxSendTargets: String = ""
    public var nrReceiveEnabled: Bool = false
    public var nrReceiveBind: String = ""
    public var auReceiveEnabled: Bool = false
    public var auReceiveBind: String = ""

    // MARK: Voice keyer, modes, steps, appearance, antennas, rotator, SO2R — `CD:248-289`

    public var vkOutput: String = ""
    public var vkInput: String = ""
    public var rxAudio: String = ""
    public var ttsVoice: String = ""
    public var radioMode: String = ""
    public var modeRule: String = ""
    public var modeAlways: String = ""
    public var dataMode: String = ""
    public var rttyAfsk: Bool = false
    public var cwSpeedStep: String = ""
    public var tuneStepCw: String = ""
    public var tuneStepSsb: String = ""
    public var beepOnDupe: Bool = false
    public var themeMode: String = ""
    public var language: String = ""
    public var ntpServer: String = ""
    public var ntpCorrect: Bool = false
    public var themeAccent: String = ""
    public var ritClearAfterLog: Bool = false
    public var antennas: [AntennaDraft] = []
    public var antennaViaRig: Bool = false
    public var transverters: [TransverterDraft] = []
    public var footswitchPort: String = ""
    public var footswitchPin: String = ""
    public var footswitchAction: String = ""
    public var rotatorHost: String = ""
    public var rotorUdpHost: String = ""
    public var rotorUdpPort: String = ""
    public var rotorUdpName: String = ""
    public var rotatorPort: String = ""
    public var rig2Host: String = ""
    public var rig2Port: String = ""
    public var otrspPort: String = ""
    public var cwPitch: String = ""
    public var vkPttViaCat: Bool = false
    public var vkPttDelay: String = ""
    public var vkMaxRecord: String = ""
    public var vkWavDir: String = ""
    public var vkLettersPath: String = ""
    public var vkRun: [FunctionKeyDraft] = []
    public var vkSp: [FunctionKeyDraft] = []

    // MARK: Run / S&P, ESM — `CD:291-300`

    public var runAutoSwitch: Bool = false
    public var runOnCqFrequency: Bool = false
    public var repeatSeconds: String = ""
    public var autoReload: Bool = false
    public var esmEnabled: Bool = false
    public var esmSpCallOnce: Bool = false
    public var esmWorkDupes: Bool = false

    // MARK: CW keyer and digital modes — `CD:302-317`

    public var cwMethod: CwKeyerConfig.Method = .cat
    public var cwPort: String = ""
    public var cwSpeed: String = ""
    public var cwCutNumbers: Bool = false
    public var cwLeadingZeros: Bool = false
    public var cwCutStyle: CutStyle = .tn
    public var cwRun: [FunctionKeyDraft] = []
    public var cwSp: [FunctionKeyDraft] = []
    public var digiEngine: DigitalConfig.Engine = .none
    public var fldigiHost: String = ""
    public var fldigiPort: String = ""
    public var digiRun: [FunctionKeyDraft] = []
    public var digiSp: [FunctionKeyDraft] = []

    /// `ConfigurerDraft(config)`. `bandSegments`/`digi` are what Kotlin reads in the constructor
    /// (`BandPlanFile.read`/`DigiFreqFile.read` of the old `contestDataDir ?: default`); `defaultContestDataDir`
    /// is `AppPaths.defaultContestDataDir()` as text.
    public init(
        config: AppConfig, bandSegments: [BandPlanFile.Segment], digi: DigiFreqFile.Table,
        defaultContestDataDir: String
    ) {
        loadHardware(config.rig)
        loadStation(config.station)
        loadCluster(config.cluster)
        loadDxCluster(config.dxCluster)
        loadCallbooks(config)
        self.bandSegments = bandSegments.map { BandSegmentDraft($0) }
        self.digiChannels = digi.channels.map { DigiChannelDraft($0) }
        loadContestData(config, defaultContestDataDir: defaultContestDataDir)
        loadNetwork(config)
        loadOther(config)
        loadRigExtras(config)
        loadVoiceKeyer(config.voiceKeyer)
        loadOperating(config)
        loadKeyers(config)
    }

    /// `addDxFavorite()`: a new favorite with the defaults of `DxClusterFavorite()`.
    public mutating func addDxFavorite() {
        dxFavorites.append(DxFavoriteDraft(DxClusterFavorite()))
    }

    /// Directory the band data are written to on OK (`writeBandData`: `Path.of(contestDataDir.trim())`, the **new**
    /// directory).
    public var bandDataDir: String {
        KotlinText.trim(contestDataDir)
    }

    /// Band plan and digi table written on OK (`writeBandData`, `CD:132-139`): rows that do not convert are dropped.
    public func bandData() -> (segments: [BandPlanFile.Segment], table: DigiFreqFile.Table) {
        let segments: [BandPlanFile.Segment] = bandSegments.compactMap { $0.toSegment() }
        let channels: [DigiFreqFile.Channel] = digiChannels.compactMap { $0.toChannel() }
        return (segments, DigiFreqFile.Table(channels: channels))
    }
}

// MARK: - Initial values per group

extension ConfigurerDraft {

    private mutating func loadHardware(_ rig: RigConfig) {
        rigMode = rig.mode
        rigModel = rig.model
        rigModelLabel = rig.modelLabel
        device = rig.device
        baud = rig.baud
        dataBits = rig.dataBits
        stopBits = rig.stopBits
        parity = rig.parity
        flow = rig.flowControl
        dtr = rig.dtr
        rts = rig.rts
        host = rig.host
        rigPort = String(rig.port)
    }

    private mutating func loadStation(_ station: StationConfig) {
        call = station.call
        `operator` = station.operator
        grid = station.gridSquare
        name = station.name
        address1 = station.address1
        address2 = station.address2
        city = station.city
        stateRegion = station.state
        zip = station.zip
        country = station.country
        cqZone = station.cqZone
        ituZone = station.ituZone
        license = station.license
        stationTxRx = station.stationTxRx
        power = station.power
        antenna = station.antenna
        antHeight = station.antHeight
        asl = station.asl
        arrlSection = station.arrlSection
        roverQth = station.roverQth
        club = station.club
        email = station.email
    }

    private mutating func loadCluster(_ cluster: ClusterConfig) {
        clusterEnabled = cluster.enabled
        brokerHost = cluster.brokerHost
        clusterPort = String(cluster.port)
        username = cluster.username
        password = cluster.password
        stationId = cluster.stationId
        tls = cluster.tls
        shareSpots = cluster.shareSpots
        interlock = cluster.interlock
        serialServer = cluster.serialServer
        stationType = cluster.stationType
        ruleEnforcement = cluster.ruleEnforcement
    }

    private mutating func loadDxCluster(_ dx: DxClusterConfig) {
        dxFavorites = dx.favorites.map { DxFavoriteDraft($0) }
        blacklistedCalls = BlacklistService.values(dx.callBlacklist)
        blacklistedSpotters = BlacklistService.values(dx.spotterBlacklist)
        spotBufferMinutes = String(dx.spotBufferMinutes)
        wheelStepHz = String(dx.wheelStepHz)
        wheelStepShiftHz = String(dx.wheelStepShiftHz)
        selfSpotThresholdHz = String(dx.selfSpotThresholdHz)
        minSkimmers = String(dx.minSkimmers)
        autoSplit = dx.autoSplit
        showBandPlan = dx.showBandPlan
    }

    private mutating func loadCallbooks(_ config: AppConfig) {
        hamQthEnabled = config.hamQth.enabled
        hamQthUsername = config.hamQth.username
        hamQthPassword = config.hamQth.password
        hamQthCallModes = config.hamQth.callModes
        hamQthFetchFields = config.hamQth.fetchFields
        qrzEnabled = config.qrz.enabled
        qrzUsername = config.qrz.username
        qrzPassword = config.qrz.password
        qrzCallModes = config.qrz.callModes
        qrzFetchFields = config.qrz.fetchFields
    }

    private mutating func loadContestData(_ config: AppConfig, defaultContestDataDir: String) {
        mapScheme = config.map.scheme
        mapPolitical = config.map.political
        keyOverrides = config.keyBindings
        scpFile = config.scpFile
        callHistoryFile = config.callHistoryFile
        scpSuggestionsEnabled = config.scpSuggestionsEnabled
        nPlusOneEnabled = config.nPlusOneEnabled
        preferredCallbook = config.preferredCallbook
        clEnabled = config.clubLog.enabled
        clEmail = config.clubLog.email
        clPassword = config.clubLog.appPassword
        clCallsign = config.clubLog.callsign
        clApiKey = config.clubLog.apiKey
        srEnabled = config.scoreReportingEnabled
        srUrl = config.scoreReportingUrl
        srMinutes = String(config.scoreReportingMinutes)
        srBreakdown = config.scoreReportingBreakdown
        autoBackupMinutes = String(config.autoBackupMinutes)
        autoBackupKeep = String(config.autoBackupKeep)
        autoBackupDir = config.autoBackupDir
        contestDataDir = config.contestDataDir ?? defaultContestDataDir
    }

    private mutating func loadNetwork(_ config: AppConfig) {
        bcContactsEnabled = config.broadcast.contactsEnabled
        bcContactsTargets = config.broadcast.contactsTargets
        bcRadioEnabled = config.broadcast.radioEnabled
        bcRadioTargets = config.broadcast.radioTargets
        bcScoreEnabled = config.broadcast.scoreEnabled
        bcScoreTargets = config.broadcast.scoreTargets
        bcAppInfoEnabled = config.broadcast.appInfoEnabled
        bcAppInfoTargets = config.broadcast.appInfoTargets
        wxReceiveEnabled = config.wsjtx.receiveEnabled
        wxReceiveBind = config.wsjtx.receiveBind
        wxSendEnabled = config.wsjtx.sendEnabled
        wxSendTargets = config.wsjtx.sendTargets
        nrReceiveEnabled = config.n1mmRecv.receiveEnabled
        nrReceiveBind = config.n1mmRecv.receiveBind
        auReceiveEnabled = config.adifUdp.receiveEnabled
        auReceiveBind = config.adifUdp.receiveBind
    }

    private mutating func loadOther(_ config: AppConfig) {
        vkOutput = config.voiceKeyer.outputDevice
        vkInput = config.voiceKeyer.inputDevice
        rxAudio = config.rxAudioDevice
        ttsVoice = config.ttsVoice
        radioMode = config.radioMode
        modeRule = config.modeRule
        modeAlways = config.modeAlways
        dataMode = config.dataMode
        rttyAfsk = config.rttyAfsk
        cwSpeedStep = String(config.cwSpeedStep)
        tuneStepCw = String(config.tuneStepCwHz)
        tuneStepSsb = String(config.tuneStepSsbHz)
        beepOnDupe = config.beepOnDupe
        themeMode = config.themeMode
        language = config.language
        ntpServer = config.ntpServer
        ntpCorrect = config.ntpCorrectQsoTime
        themeAccent = config.themeAccent
        ritClearAfterLog = config.ritClearAfterLog
    }

    private mutating func loadRigExtras(_ config: AppConfig) {
        antennas = config.antennas.map { AntennaDraft($0) }
        antennaViaRig = config.antennaViaRig
        transverters = config.transverters.map { TransverterDraft($0) }
        footswitchPort = config.footswitchPort
        footswitchPin = config.footswitchPin
        footswitchAction = config.footswitchAction
        rotatorHost = config.rotatorHost
        rotorUdpHost = config.rotorUdpHost
        rotorUdpPort = String(config.rotorUdpPort)
        rotorUdpName = config.rotorUdpName
        rotatorPort = String(config.rotatorPort)
        rig2Host = config.rig2.host
        rig2Port = String(config.rig2.port)
        otrspPort = config.otrspPort
        cwPitch = String(config.cwPitchHz)
    }

    private mutating func loadVoiceKeyer(_ vk: VoiceKeyerConfig) {
        vkPttViaCat = vk.pttViaCat
        vkPttDelay = String(vk.pttDelayMs)
        vkMaxRecord = String(vk.maxRecordSeconds)
        vkWavDir = vk.wavDir
        vkLettersPath = vk.lettersPath
        vkRun = vk.runMessages.map { FunctionKeyDraft($0) }
        vkSp = vk.spMessages.map { FunctionKeyDraft($0) }
    }

    private mutating func loadOperating(_ config: AppConfig) {
        runAutoSwitch = config.runMode.autoSwitch
        runOnCqFrequency = config.runMode.runOnCqFrequency
        repeatSeconds = JavaFormat.format("%.1f", .double(config.runMode.repeatSeconds))
        autoReload = config.autoReloadLastContest
        esmEnabled = config.esm.enabled
        esmSpCallOnce = config.esm.spCallOnce
        esmWorkDupes = config.esm.workDupes
    }

    private mutating func loadKeyers(_ config: AppConfig) {
        cwMethod = config.cwKeyer.method
        cwPort = config.cwKeyer.winkeyerPort
        cwSpeed = String(config.cwKeyer.speed)
        cwCutNumbers = config.cwKeyer.cutNumbers
        cwLeadingZeros = config.cwKeyer.leadingZeros
        cwCutStyle = config.cwKeyer.cutStyle
        cwRun = config.cwKeyer.runMessages.map { FunctionKeyDraft($0) }
        cwSp = config.cwKeyer.spMessages.map { FunctionKeyDraft($0) }
        digiEngine = config.digital.engine
        fldigiHost = config.digital.fldigiHost
        fldigiPort = String(config.digital.fldigiPort)
        digiRun = config.digital.runMessages.map { FunctionKeyDraft($0) }
        digiSp = config.digital.spMessages.map { FunctionKeyDraft($0) }
    }
}
