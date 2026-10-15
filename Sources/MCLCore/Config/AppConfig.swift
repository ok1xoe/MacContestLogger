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
    /// N1MM Configurer › Colors: a colour per slot (`ColorSlot` raw value → `#RRGGBB`) over the built-in light and
    /// dark colours; an absent slot keeps the built-in one. Swift-only key.
    public var colorOverrides: [String: String] = [:]
    /// N1MM Configurer › Fonts: the family of the proportional texts (empty = the system font). Swift-only key.
    public var fontFamily: String = ""
    /// N1MM Configurer › Fonts „fixed": the family of the monospaced texts and the entry fields (empty = the system
    /// monospaced font). Swift-only key.
    public var fixedFontFamily: String = ""
    /// N1MM „Tooltips": the spot tooltips of the band map and the multiplier windows (off = none). Swift-only key.
    public var spotTooltips: Bool = true

    /// Mode Control: the rule for the written mode (RADIO, BANDPLAN, ALWAYS) and a fixed mode for ALWAYS.
    public var modeRule = "RADIO"
    public var modeAlways = "RTTY"
    /// Digital Modes: how to write the rig's data mode (PKTUSB/PKTLSB) and RTTY over AFSK.
    public var dataMode = "DIGITAL"
    public var rttyAfsk = false
    /// N1MM „Mode sent to radio" for PSK, FT8 and the other digital modes: `PKTUSB`, `PKTLSB`, `USB` or `LSB`.
    /// Swift-only key.
    public var digiRadioMode: String = "PKTUSB"
    /// N1MM keeps the station data per database: switching databases switches the station (`DatabaseStation`).
    /// Swift-only key.
    public var stationPerDatabase: Bool = false
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
    /// The Dupesheet windows sort each column by suffix (N1MM), otherwise by the whole call (v1.1.1). Swift-only key.
    public var dupesheetSortBySuffix = true
    /// N1MM „CC Cabrillo to logs@supercheckpartial.com": after a Cabrillo export the mail client opens a message
    /// to that address with the file attached (the operator sends it). Off by default. Swift-only key.
    public var ccCabrilloToScp: Bool = false
    /// N1MM „Display Sent CW": the CW being sent is shown in the status line. Swift-only key.
    public var showSentCw: Bool = false
    /// N1MM „Secondary CW Speed Step" (Shift+PgUp/PgDn, WPM). Swift-only key.
    public var cwSpeedStepSecondary: Int = 1 {
        didSet {
            if cwSpeedStepSecondary <= 0 { cwSpeedStepSecondary = 1 }
        }
    }
    /// N1MM „Clear auto-populated exchange on callsign change": a call change clears the exchange values the call history or a spot filled in. Swift-only key.
    public var clearPrefilledExchange: Bool = false
    /// The bands (ADIF names) whose buttons the Entry window does not show. Swift-only key.
    public var entryHiddenBands: [String] = []
    /// N1MM „Band Button Left Click Enabled": a click on a band button changes the band. Swift-only key.
    public var entryBandButtonsClick: Bool = true
    /// N1MM „Show GMT Time": the UTC clock in the Entry window. Swift-only key.
    public var entryShowUtcClock: Bool = false
    /// N1MM „Show Mode Column" of the Log window. Swift-only key.
    public var logShowModeColumn: Bool = true
    /// N1MM „Set bands to be displayed" of the Multipliers windows: kind → bands (`160m,40m`). Swift-only key.
    public var multGridBands: [String: String] = [:]
    /// N1MM „Expected Multiplier List" of the Multipliers windows: kind → one multiplier per line. Swift-only key.
    public var multExpected: [String: String] = [:]
    /// The Multipliers window kinds that show every possible multiplier (N1MM „Show only worked & expected" off).
    /// Swift-only key.
    public var multGridShowAll: [String] = []
    /// N1MM Move Multipliers Display Options › Type over the spots (`MULT`, `POINTS`, `COUNTS`). Swift-only key.
    public var moveMultsDisplay: String = "MULT"
    /// N1MM Move Multipliers Display Count Range (`0-6`). Swift-only key.
    public var moveMultsRange: String = "0-6"
    /// The band columns of Move Multipliers over the spots (`160m,80m`; empty = the contest's bands). Swift-only key.
    public var moveMultsBands: String = ""
    /// The spot modes Move Multipliers lists (`CONTEST`, `ALL`, `CW`, `PHONE`, `DIGI`). Swift-only key.
    public var moveMultsModes: String = "CONTEST"
    /// N1MM Grayline setup: the map layers shown (`sun`, `equator`, `meridian`, `home`). Swift-only key.
    public var graylineLayers: [String] = WorldMapLayer.defaults
    /// N1MM Grayline „Number of Spots to Display" (0, 50 … 200; -1 = every spot). Swift-only key.
    public var graylineSpots: Int = -1
    /// The Entry window parts hidden by its right-click menu (`EntrySection` raw values). Swift-only key.
    public var entryHiddenSections: [String] = []
    /// N1MM „Reset RX freq when running split": after a Run QSO in split, the receive frequency goes to the transmit one. Swift-only key.
    public var resetRxAfterRunQso: Bool = false
    /// N1MM „PgUp/PgDn Incr (kHz)": the QSY step of the `{PGUP}`/`{PGDN}`/`{FREQUP}`/`{FREQDN}` macros. Swift-only key.
    /// N1MM „Use Separate Function Key Files for Each Operator": every operator signed on (Ctrl+O / OPON) other than
    /// the station call gets their own copy of the F-key messages. Swift-only key.
    public var functionKeysPerOperator: Bool = false
    public var macroQsyStepKHz: Int = 1 {
        didSet {
            if macroQsyStepKHz <= 0 { macroQsyStepKHz = 1 }
        }
    }

    /// The Check window (N1MM right-click menu, see `CheckSettings`). Swift-only keys.
    public var checkHiddenPanes: [String] = []
    public var checkPaneWeights: [String: Int] = [:]
    public var checkYankOrder: [String] = CheckSettings.defaultYankOrder.map(\.rawValue)
    public var checkYankAllowDupes = false
    public var checkFavorEndDifferences = false
    public var checkTelnetMinSpots = 3
    public var checkReverseEnabled = true
    public var checkReverseThreshold = 2
    public var checkReverseFromStart = true
    /// N1MM View → "Show ? on Unmatched Calls": a `?` after a call no Check source knows. Swift-only key.
    public var showUnmatchedCallMark = true

    /// Call history file in N1MM format (pre-filling the exchange); empty = none.
    public var callHistoryFile = ""
    /// N1MM „Config → Enable Call History Lookup": the exchange is prefilled from the call history. A file's
    /// `#CONTEST` lines switch it when a contest opens. Swift-only key.
    public var callHistoryLookupEnabled = true
    /// Further call history files merged after the primary one into one table (N1MM's import of several files).
    /// Swift-only key.
    public var callHistoryExtraFiles: [String] = []
    /// N1MM „Show User Information": the call history line and the UserText line under the entry fields.
    /// Swift-only key.
    public var callHistoryShowUserInfo = true
    /// N1MM „Check for New Program Version" at start: one request to GitHub's release API per start, only when the
    /// user switched it on (off by default — no outward call without consent). Swift-only key.
    public var checkUpdatesAtStart = false
    /// N1MM „Program announcements for blind operators": VoiceOver announcements of a dupe, a new multiplier, an
    /// incomplete exchange and the split (off by default). Swift-only key.
    public var accessibilityAnnouncements = false
    /// N1MM Config → WAE: the QTC options and messages (`QtcSetup.Key` → value; only non-default values are kept).
    /// Swift-only key.
    public var qtcSetup: [String: String] = [:]

    /// The QTC setup (WAE).
    public var qtc: QtcSetup {
        get { QtcSetup(qtcSetup) }
        set { qtcSetup = newValue.values }
    }
    /// N1MM Rotor program setup: the named rotors, the F1–F10 preset bearings, the network rotor display and the
    /// automatic antenna choice by bearing (`RotorSetup.Key` → value; only non-default values are kept). Swift-only key.
    public var rotorSetup: [String: String] = [:]

    /// The rotor setup.
    public var rotor: RotorSetup {
        get { RotorSetup(rotorSetup) }
        set { rotorSetup = newValue.values }
    }

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
        case colorOverrides, fontFamily, fixedFontFamily, spotTooltips
        case digiRadioMode, stationPerDatabase
        case modeRule, modeAlways, dataMode, rttyAfsk
        case cwSpeedStep, tuneStepCwHz, tuneStepSsbHz, beepOnDupe, ritClearAfterLog
        case scpSuggestionsEnabled, nPlusOneEnabled, preferredCallbook, dupesheetSortBySuffix
        case ccCabrilloToScp
        case showSentCw
        case cwSpeedStepSecondary
        case clearPrefilledExchange
        case entryHiddenBands
        case entryBandButtonsClick
        case entryShowUtcClock
        case logShowModeColumn
        case multGridBands, multExpected, multGridShowAll
        case moveMultsDisplay, moveMultsRange, moveMultsBands, moveMultsModes
        case graylineLayers, graylineSpots
        case entryHiddenSections
        case resetRxAfterRunQso
        case macroQsyStepKHz, functionKeysPerOperator
        case checkHiddenPanes, checkPaneWeights, checkYankOrder, checkYankAllowDupes, checkFavorEndDifferences
        case checkTelnetMinSpots, checkReverseEnabled, checkReverseThreshold, checkReverseFromStart
        case showUnmatchedCallMark
        case callHistoryFile, callHistoryLookupEnabled, callHistoryExtraFiles, callHistoryShowUserInfo
        case checkUpdatesAtStart, accessibilityAnnouncements, qtcSetup, rotorSetup
        case databasesDir, lastDatabase, windowGeometry, openWindows, goals
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
        checkHiddenPanes = c.value(.checkHiddenPanes, default: d.checkHiddenPanes)
        checkPaneWeights = c.value(.checkPaneWeights, default: d.checkPaneWeights)
        checkYankOrder = c.value(.checkYankOrder, default: d.checkYankOrder)
        checkYankAllowDupes = c.value(.checkYankAllowDupes, default: d.checkYankAllowDupes)
        checkFavorEndDifferences = c.value(.checkFavorEndDifferences, default: d.checkFavorEndDifferences)
        checkTelnetMinSpots = c.value(.checkTelnetMinSpots, default: d.checkTelnetMinSpots)
        checkReverseEnabled = c.value(.checkReverseEnabled, default: d.checkReverseEnabled)
        checkReverseThreshold = c.value(.checkReverseThreshold, default: d.checkReverseThreshold)
        checkReverseFromStart = c.value(.checkReverseFromStart, default: d.checkReverseFromStart)
        showUnmatchedCallMark = c.value(.showUnmatchedCallMark, default: d.showUnmatchedCallMark)
        dupesheetSortBySuffix = c.value(.dupesheetSortBySuffix, default: d.dupesheetSortBySuffix)
        ccCabrilloToScp = c.value(.ccCabrilloToScp, default: d.ccCabrilloToScp)
        showSentCw = c.value(.showSentCw, default: d.showSentCw)
        let secondaryStep: Int = c.value(.cwSpeedStepSecondary, default: d.cwSpeedStepSecondary)
        cwSpeedStepSecondary = secondaryStep <= 0 ? 1 : secondaryStep
        clearPrefilledExchange = c.value(.clearPrefilledExchange, default: d.clearPrefilledExchange)
        colorOverrides = c.value(.colorOverrides, default: d.colorOverrides)
        fontFamily = c.value(.fontFamily, default: d.fontFamily)
        fixedFontFamily = c.value(.fixedFontFamily, default: d.fixedFontFamily)
        spotTooltips = c.value(.spotTooltips, default: d.spotTooltips)
        digiRadioMode = HamlibModeMapping.normalizedDigiRadioMode(c.value(.digiRadioMode, default: d.digiRadioMode))
        stationPerDatabase = c.value(.stationPerDatabase, default: d.stationPerDatabase)
        entryHiddenBands = c.value(.entryHiddenBands, default: d.entryHiddenBands)
        entryBandButtonsClick = c.value(.entryBandButtonsClick, default: d.entryBandButtonsClick)
        entryShowUtcClock = c.value(.entryShowUtcClock, default: d.entryShowUtcClock)
        logShowModeColumn = c.value(.logShowModeColumn, default: d.logShowModeColumn)
        multGridBands = c.value(.multGridBands, default: d.multGridBands)
        multExpected = c.value(.multExpected, default: d.multExpected)
        multGridShowAll = c.value(.multGridShowAll, default: d.multGridShowAll)
        moveMultsDisplay = c.value(.moveMultsDisplay, default: d.moveMultsDisplay)
        moveMultsRange = c.value(.moveMultsRange, default: d.moveMultsRange)
        moveMultsBands = c.value(.moveMultsBands, default: d.moveMultsBands)
        moveMultsModes = c.value(.moveMultsModes, default: d.moveMultsModes)
        graylineLayers = c.value(.graylineLayers, default: d.graylineLayers)
        graylineSpots = c.value(.graylineSpots, default: d.graylineSpots)
        entryHiddenSections = c.value(.entryHiddenSections, default: d.entryHiddenSections)
        resetRxAfterRunQso = c.value(.resetRxAfterRunQso, default: d.resetRxAfterRunQso)
        let qsyStep: Int = c.value(.macroQsyStepKHz, default: d.macroQsyStepKHz)
        macroQsyStepKHz = qsyStep <= 0 ? 1 : qsyStep
        functionKeysPerOperator = c.value(.functionKeysPerOperator, default: d.functionKeysPerOperator)
        callHistoryFile = c.value(.callHistoryFile, default: d.callHistoryFile)
        callHistoryLookupEnabled = c.value(.callHistoryLookupEnabled, default: d.callHistoryLookupEnabled)
        callHistoryExtraFiles = c.value(.callHistoryExtraFiles, default: d.callHistoryExtraFiles)
        callHistoryShowUserInfo = c.value(.callHistoryShowUserInfo, default: d.callHistoryShowUserInfo)
        checkUpdatesAtStart = c.value(.checkUpdatesAtStart, default: d.checkUpdatesAtStart)
        accessibilityAnnouncements = c.value(.accessibilityAnnouncements, default: d.accessibilityAnnouncements)
        qtcSetup = QtcSetup(c.value(.qtcSetup, default: d.qtcSetup)).values
        rotorSetup = RotorSetup(c.value(.rotorSetup, default: d.rotorSetup)).values

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
