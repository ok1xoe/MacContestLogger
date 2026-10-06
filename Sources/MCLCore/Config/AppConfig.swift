import Foundation

/// Root configuration stored in `config.json`. Mirrors `AppConfig.java`
/// (70 properties) — done property by property top to bottom following
/// the Java original, including its read-time normalizations (getters) and
/// setter exceptions where there are any.
///
/// Note on `antennas`/`transverters`: in Java these are `AppConfig` fields, not
/// `RigConfig` ones (see the comment in `RigConfig.swift`).
public struct AppConfig: Codable, Equatable, Sendable {

    // MARK: - Nested configurations (17): getX()/setX() in Java only delegate

    public var rig = RigConfig()
    public var station = StationConfig()
    public var cluster = ClusterConfig()
    public var dxCluster = DxClusterConfig()
    public var hamQth = HamQthConfig()
    public var qrz = QrzConfig()
    public var map = MapConfig()
    public var infoWindow = InfoWindowConfig()
    public var broadcast = BroadcastConfig()
    public var wsjtx = WsjtxConfig()
    public var n1mmRecv = N1mmRecvConfig()
    public var adifUdp = AdifUdpConfig()
    public var voiceKeyer = VoiceKeyerConfig()
    public var cwKeyer = CwKeyerConfig()
    public var digital = DigitalConfig()
    public var esm = EsmConfig()
    public var runMode = RunModeConfig()

    // MARK: - Remaining properties, in the order of AppConfig.java

    /// Remapped keys of the entry window (action id → „Ctrl+Alt+S"; empty = no key).
    public var keyBindings: [String: String] = [:]
    /// On startup, open the last contest right away instead of the start dialog (DXLog AUTORELOAD).
    public var autoReloadLastContest = false
    public var contestSetups: [String: ContestSetup] = [:]
    /// The Java original has no initializer and no null-safe getter/setter — unlike
    /// all the other string fields in this file, here
    /// `null` stays `null` (`ConfigStoreContestDirTest.defaultIsNull`).
    /// Hence it is the only `String?` field in `AppConfig`, not `String = ""`.
    public var contestDataDir: String?
    /// Path to `master.scp` for callsign suggestions; empty = no suggestions.
    public var scpFile = ""
    /// Speech-synthesis voice for `[text]` items of voice messages; empty = system.
    public var ttsVoice = ""

    /// Record the whole contest (receiver audio) by the hour; empty directory = data/recordings.
    public var recordContest = false
    public var recordingsDir = ""

    /// Sound-card input with the receiver output (waterfall, CW decoder, contest recording); empty = default.
    public var rxAudioDevice = ""
    /// Pitch of the receiver CW tone (Hz) — where the signal is in the audio at the display frequency.
    public var cwPitchHz = 600 {
        didSet {
            let normalized = AppConfig.normalizedCwPitchHz(cwPitchHz)
            if normalized != cwPitchHz { cwPitchHz = normalized }
        }
    }

    /// Antenna table (N1MM Antennas) for the band decoder / switch.
    public var antennas: [AntennaEntry] = []
    /// Also switch the rig's antenna connector (hamlib Y) — codes 1–4 = ANT1–ANT4.
    public var antennaViaRig = false

    public var clubLog = ClubLogConfig()

    /// Online scoreboard (N1MM Score Reporting): enabled, URL, interval (min), breakdown by band.
    public var scoreReportingEnabled = false
    public var scoreReportingUrl: String = AppConfig.defaultScoreReportingUrl {
        didSet {
            let normalized = AppConfig.normalizedScoreReportingUrl(scoreReportingUrl)
            if normalized != scoreReportingUrl { scoreReportingUrl = normalized }
        }
    }
    public var scoreReportingMinutes = 5 {
        didSet {
            let normalized = AppConfig.normalizedScoreReportingMinutes(scoreReportingMinutes)
            if normalized != scoreReportingMinutes { scoreReportingMinutes = normalized }
        }
    }
    public var scoreReportingBreakdown = true

    /// Automatic logbook backup: interval in minutes (0 = off), number of backups, directory (empty = data/backups).
    public var autoBackupMinutes = 15 {
        didSet {
            let normalized = AppConfig.normalizedAutoBackupMinutes(autoBackupMinutes)
            if normalized != autoBackupMinutes { autoBackupMinutes = normalized }
        }
    }
    public var autoBackupKeep = 10 {
        didSet {
            let normalized = AppConfig.normalizedAutoBackupKeep(autoBackupKeep)
            if normalized != autoBackupKeep { autoBackupKeep = normalized }
        }
    }
    public var autoBackupDir = ""

    /// Band notes (DXLog Band notes).
    public var bandNotes: [BandNote] = []

    /// Foot switch: serial port (empty = off), wire and actions.
    public var footswitchPort = ""
    public var footswitchPin = "CTS"
    public var footswitchAction = "PTT"

    /// Transverters (IF range + offset) for VHF/UHF via an HF rig.
    public var transverters: [TransverterEntry] = []

    /// Rotator via hamlib rotctld (host:port, default localhost:4533); empty host = no rotator.
    public var rotatorHost = ""
    public var rotatorPort = 4533 {
        didSet {
            let normalized = AppConfig.normalizedRotatorPort(rotatorPort)
            if normalized != rotatorPort { rotatorPort = normalized }
        }
    }

    /// Rotator over UDP (N1MM Rotor protocol, PstRotator…): target host:port and rotator name; empty host = off.
    public var rotorUdpHost = ""
    public var rotorUdpPort = 12040 {
        didSet {
            let normalized = AppConfig.normalizedRotorUdpPort(rotorUdpPort)
            if normalized != rotorUdpPort { rotorUdpPort = normalized }
        }
    }
    public var rotorUdpName = ""

    /// Second rig for SO2R — a connection to a running rigctld (typically a second instance on port 4533).
    public var rig2 = AppConfig.defaultRig2()
    /// Serial port of the OTRSP SO2R controller (empty = no controller).
    public var otrspPort = ""

    /// Rig mode (N1MM Configurer → Hardware): SO1V, SO2V (two windows on VFO A/B), SO2R.
    public var radioMode: String = "SO1V" {
        didSet {
            let normalized = AppConfig.normalizedRadioMode(radioMode)
            if normalized != radioMode { radioMode = normalized }
        }
    }

    /// Time synchronization: NTP server (empty = off) and correction of QSO time by the measured offset.
    ///
    /// Note: the Java getter is inconsistent — a missing field and `null` in the getter
    /// fall back to `""`, not to the default `"pool.ntp.org"` from the field initializer. As
    /// with `StationConfig` (see its doc comment) we unify this asymmetry:
    /// a missing/`null`/invalid JSON falls back to the initializer value via
    /// `value(_:default:)`; no Java test touches this asymmetry.
    public var ntpServer = "pool.ntp.org"
    public var ntpCorrectQsoTime = false

    /// UI language: cs (default) or en.
    public var language = "cs"

    /// Appearance: SYSTEM / LIGHT / DARK and accent TEAL / BLUE / ORANGE / CONTRAST.
    public var themeMode = "SYSTEM"
    public var themeAccent = "TEAL"

    /// Mode Control: the rule for the written mode (RADIO, BANDPLAN, ALWAYS) and a fixed mode for ALWAYS.
    public var modeRule = "RADIO"
    public var modeAlways = "RTTY"
    /// Digital Modes: how to write the rig's data mode (PKTUSB/PKTLSB) and RTTY over AFSK.
    public var dataMode = "DIGITAL"
    public var rttyAfsk = false
    /// Other: CW speed step (PgUp/PgDn), arrow-key tuning step (Hz) and a beep on dupe.
    public var cwSpeedStep = 2 {
        didSet {
            let normalized = AppConfig.normalizedCwSpeedStep(cwSpeedStep)
            if normalized != cwSpeedStep { cwSpeedStep = normalized }
        }
    }
    public var tuneStepCwHz = 20 {
        didSet {
            let normalized = AppConfig.normalizedTuneStepCwHz(tuneStepCwHz)
            if normalized != tuneStepCwHz { tuneStepCwHz = normalized }
        }
    }
    public var tuneStepSsbHz = 100 {
        didSet {
            let normalized = AppConfig.normalizedTuneStepSsbHz(tuneStepSsbHz)
            if normalized != tuneStepSsbHz { tuneStepSsbHz = normalized }
        }
    }
    public var beepOnDupe = false

    /// Clear RIT after writing a QSO (N1MM „Clear RIT after logging").
    public var ritClearAfterLog = true

    /// Show the `SCP:` row (Check partial) under the call field and compute it. Swift-only key (v1.1.1 ignores it).
    public var scpSuggestionsEnabled = true
    /// Show the `N+1:` row (calls one character off) under the call field and compute it. Swift-only key.
    public var nPlusOneEnabled = true
    /// The online callbook of the entry window's manual lookup button: `"hamqth"` or `"qrz"` (see
    /// `CallbookService`). Swift-only key.
    public var preferredCallbook = CallbookService.hamQth.rawValue

    /// Call history file in N1MM format (pre-filling the exchange); empty = none.
    public var callHistoryFile = ""

    public var databasesDir = ""
    public var lastDatabase = ""
    public var windowGeometry: [String: WindowGeometry] = [:]
    /// IDs of tool windows open on the last run (restored after startup). Default = Logbook.
    public var openWindows: [String] = ["log"]

    /// The single active set of targets (key `dhh` as a string because of JSON). It is kept in
    /// the configuration, not with the contest — as in N1MM it stays active even after another
    /// contest is started, until something replaces it.
    public var goals: [String: Int] = [:]

    enum CodingKeys: String, CodingKey {
        case rig, station, cluster, dxCluster, hamQth, qrz, map, infoWindow, broadcast
        case wsjtx, n1mmRecv, adifUdp, voiceKeyer, cwKeyer, digital, esm, runMode
        case keyBindings, autoReloadLastContest, contestSetups, contestDataDir, scpFile, ttsVoice
        case recordContest, recordingsDir, rxAudioDevice, cwPitchHz
        case antennas, antennaViaRig, clubLog
        case scoreReportingEnabled, scoreReportingUrl, scoreReportingMinutes, scoreReportingBreakdown
        case autoBackupMinutes, autoBackupKeep, autoBackupDir
        case bandNotes, footswitchPort, footswitchPin, footswitchAction, transverters
        case rotatorHost, rotatorPort, rotorUdpHost, rotorUdpPort, rotorUdpName
        case rig2, otrspPort, radioMode, ntpServer, ntpCorrectQsoTime
        case language, themeMode, themeAccent
        case modeRule, modeAlways, dataMode, rttyAfsk
        case cwSpeedStep, tuneStepCwHz, tuneStepSsbHz, beepOnDupe, ritClearAfterLog
        case scpSuggestionsEnabled, nPlusOneEnabled, preferredCallbook
        case callHistoryFile, databasesDir, lastDatabase, windowGeometry, openWindows, goals
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()

        rig = c.value(.rig, default: d.rig)
        station = c.value(.station, default: d.station)
        cluster = c.value(.cluster, default: d.cluster)
        dxCluster = c.value(.dxCluster, default: d.dxCluster)
        hamQth = c.value(.hamQth, default: d.hamQth)
        qrz = c.value(.qrz, default: d.qrz)
        map = c.value(.map, default: d.map)
        infoWindow = c.value(.infoWindow, default: d.infoWindow)
        broadcast = c.value(.broadcast, default: d.broadcast)
        wsjtx = c.value(.wsjtx, default: d.wsjtx)
        n1mmRecv = c.value(.n1mmRecv, default: d.n1mmRecv)
        adifUdp = c.value(.adifUdp, default: d.adifUdp)
        voiceKeyer = c.value(.voiceKeyer, default: d.voiceKeyer)
        cwKeyer = c.value(.cwKeyer, default: d.cwKeyer)
        digital = c.value(.digital, default: d.digital)
        esm = c.value(.esm, default: d.esm)
        runMode = c.value(.runMode, default: d.runMode)

        keyBindings = c.value(.keyBindings, default: d.keyBindings)
        autoReloadLastContest = c.value(.autoReloadLastContest, default: d.autoReloadLastContest)
        contestSetups = c.value(.contestSetups, default: d.contestSetups)
        contestDataDir = (try? c.decodeIfPresent(String.self, forKey: .contestDataDir)) ?? nil
        scpFile = c.value(.scpFile, default: d.scpFile)
        ttsVoice = c.value(.ttsVoice, default: d.ttsVoice)

        recordContest = c.value(.recordContest, default: d.recordContest)
        recordingsDir = c.value(.recordingsDir, default: d.recordingsDir)

        rxAudioDevice = c.value(.rxAudioDevice, default: d.rxAudioDevice)
        cwPitchHz = AppConfig.normalizedCwPitchHz(c.value(.cwPitchHz, default: d.cwPitchHz))

        antennas = c.value(.antennas, default: d.antennas)
        antennaViaRig = c.value(.antennaViaRig, default: d.antennaViaRig)

        clubLog = c.value(.clubLog, default: d.clubLog)

        scoreReportingEnabled = c.value(.scoreReportingEnabled, default: d.scoreReportingEnabled)
        scoreReportingUrl = AppConfig.normalizedScoreReportingUrl(
            c.value(.scoreReportingUrl, default: d.scoreReportingUrl))
        scoreReportingMinutes = AppConfig.normalizedScoreReportingMinutes(
            c.value(.scoreReportingMinutes, default: d.scoreReportingMinutes))
        scoreReportingBreakdown = c.value(.scoreReportingBreakdown, default: d.scoreReportingBreakdown)

        autoBackupMinutes = AppConfig.normalizedAutoBackupMinutes(
            c.value(.autoBackupMinutes, default: d.autoBackupMinutes))
        autoBackupKeep = AppConfig.normalizedAutoBackupKeep(c.value(.autoBackupKeep, default: d.autoBackupKeep))
        autoBackupDir = c.value(.autoBackupDir, default: d.autoBackupDir)

        bandNotes = c.value(.bandNotes, default: d.bandNotes)

        footswitchPort = c.value(.footswitchPort, default: d.footswitchPort)
        footswitchPin = c.value(.footswitchPin, default: d.footswitchPin)
        footswitchAction = c.value(.footswitchAction, default: d.footswitchAction)

        transverters = c.value(.transverters, default: d.transverters)

        rotatorHost = c.value(.rotatorHost, default: d.rotatorHost)
        rotatorPort = AppConfig.normalizedRotatorPort(c.value(.rotatorPort, default: d.rotatorPort))

        rotorUdpHost = c.value(.rotorUdpHost, default: d.rotorUdpHost)
        rotorUdpPort = AppConfig.normalizedRotorUdpPort(c.value(.rotorUdpPort, default: d.rotorUdpPort))
        rotorUdpName = c.value(.rotorUdpName, default: d.rotorUdpName)

        rig2 = c.value(.rig2, default: d.rig2)
        otrspPort = c.value(.otrspPort, default: d.otrspPort)

        radioMode = AppConfig.normalizedRadioMode(c.value(.radioMode, default: d.radioMode))

        ntpServer = c.value(.ntpServer, default: d.ntpServer)
        ntpCorrectQsoTime = c.value(.ntpCorrectQsoTime, default: d.ntpCorrectQsoTime)

        language = c.value(.language, default: d.language)

        themeMode = c.value(.themeMode, default: d.themeMode)
        themeAccent = c.value(.themeAccent, default: d.themeAccent)

        modeRule = c.value(.modeRule, default: d.modeRule)
        modeAlways = c.value(.modeAlways, default: d.modeAlways)
        dataMode = c.value(.dataMode, default: d.dataMode)
        rttyAfsk = c.value(.rttyAfsk, default: d.rttyAfsk)

        cwSpeedStep = AppConfig.normalizedCwSpeedStep(c.value(.cwSpeedStep, default: d.cwSpeedStep))
        tuneStepCwHz = AppConfig.normalizedTuneStepCwHz(c.value(.tuneStepCwHz, default: d.tuneStepCwHz))
        tuneStepSsbHz = AppConfig.normalizedTuneStepSsbHz(c.value(.tuneStepSsbHz, default: d.tuneStepSsbHz))
        beepOnDupe = c.value(.beepOnDupe, default: d.beepOnDupe)

        ritClearAfterLog = c.value(.ritClearAfterLog, default: d.ritClearAfterLog)

        scpSuggestionsEnabled = c.value(.scpSuggestionsEnabled, default: d.scpSuggestionsEnabled)
        nPlusOneEnabled = c.value(.nPlusOneEnabled, default: d.nPlusOneEnabled)
        preferredCallbook = CallbookService(configValue: c.value(.preferredCallbook, default: d.preferredCallbook))
            .rawValue
        callHistoryFile = c.value(.callHistoryFile, default: d.callHistoryFile)

        databasesDir = c.value(.databasesDir, default: d.databasesDir)
        lastDatabase = c.value(.lastDatabase, default: d.lastDatabase)
        windowGeometry = c.value(.windowGeometry, default: d.windowGeometry)
        openWindows = c.value(.openWindows, default: d.openWindows)

        goals = c.value(.goals, default: d.goals)
    }

    // MARK: - Normalization matching the Java getters

    private static let defaultScoreReportingUrl = "https://contestonlinescore.com/post/"

    private static func normalizedCwPitchHz(_ v: Int) -> Int { v <= 0 ? 600 : v }

    /// Java `isBlank()` (`Character.isWhitespace`: NBSP and U+2007 are not blank) in the normalizing getters below.
    private static func normalizedScoreReportingUrl(_ v: String) -> String {
        JavaText.isBlank(v) ? defaultScoreReportingUrl : v
    }

    private static func normalizedScoreReportingMinutes(_ v: Int) -> Int { max(2, v) }

    private static func normalizedAutoBackupMinutes(_ v: Int) -> Int { max(0, v) }

    private static func normalizedAutoBackupKeep(_ v: Int) -> Int { v <= 0 ? 10 : v }

    private static func normalizedRotatorPort(_ v: Int) -> Int { v <= 0 ? 4533 : v }

    private static func normalizedRotorUdpPort(_ v: Int) -> Int { v <= 0 ? 12040 : v }

    private static func normalizedRadioMode(_ v: String) -> String {
        JavaText.isBlank(v) ? "SO1V" : v
    }

    private static func normalizedCwSpeedStep(_ v: Int) -> Int { v <= 0 ? 2 : v }

    private static func normalizedTuneStepCwHz(_ v: Int) -> Int { v <= 0 ? 20 : v }

    private static func normalizedTuneStepSsbHz(_ v: Int) -> Int { v <= 0 ? 100 : v }

    /// Default second rig for SO2R: a connection to a running second instance of `rigctld`
    /// on port 4534 (4533 is the default port of the first rig/rotctld).
    private static func defaultRig2() -> RigConfig {
        var r = RigConfig()
        r.mode = .connectRunning
        r.port = 4534
        r.modelLabel = "Rig 2 (rigctld :4534)"
        return r
    }
}
