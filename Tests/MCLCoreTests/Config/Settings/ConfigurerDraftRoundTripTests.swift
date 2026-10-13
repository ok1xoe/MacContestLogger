import Foundation
import Testing
@testable import MCLCore

/// Field-by-field wiring of `ConfigurerDraft` (`ui/configurer/ConfigurerDraft.kt:24-317` load, `:330-533` apply).
///
/// For every draft-backed field one distinct, already-normalised, non-default value is checked in both directions
/// against the default configuration: the draft read from a configuration with only that field changed equals the
/// default draft with only the matching draft field changed (load), and that draft applied to the default
/// configuration changes exactly that configuration field (apply). A swapped or missing line in either direction
/// fails here. All values together form `fullConfig()`, which round-trips unchanged; the same configuration
/// (maintainer-only probe) round-trips unchanged through the v1.1.1 `applyTo` as well
/// (probe rows `roundtrip`, `applyToDefault`).
@Suite struct ConfigurerDraftRoundTripTests {

    static let defaultDir = "/data/contest-data"
    static let now = JavaInstant.ofEpochSecond(1_790_000_000, 0)!

    static func base() -> AppConfig {
        var c = AppConfig()
        c.contestDataDir = defaultDir
        return c
    }

    static func draft(_ config: AppConfig) -> ConfigurerDraft {
        ConfigurerDraft(
            config: config, bandSegments: [], digi: DigiFreqFile.Table(channels: []), defaultContestDataDir: defaultDir)
    }

    /// Checks one field pair and records its value in `full`.
    struct Wiring {
        let base: AppConfig = ConfigurerDraftRoundTripTests.base()
        var full: AppConfig = ConfigurerDraftRoundTripTests.base()
        var texts: [String] = []

        /// A draft field holding the configuration value as it is.
        mutating func same<V: Equatable>(
            _ draftField: WritableKeyPath<ConfigurerDraft, V>, _ configField: WritableKeyPath<AppConfig, V>,
            _ value: V, sourceLocation: SourceLocation = #_sourceLocation
        ) {
            var config = base
            config[keyPath: configField] = value
            #expect(config[keyPath: configField] == value, "value is not normalised", sourceLocation: sourceLocation)
            #expect(base[keyPath: configField] != value, "value is the default", sourceLocation: sourceLocation)
            var expected = ConfigurerDraftRoundTripTests.draft(base)
            expected[keyPath: draftField] = value
            check(config, expected, sourceLocation)
            full[keyPath: configField] = value
            if let text = value as? String { texts.append(text) }
        }

        /// A draft text holding a configuration number (`toString()` / `toIntOrNull()`).
        mutating func number(
            _ draftField: WritableKeyPath<ConfigurerDraft, String>, _ configField: WritableKeyPath<AppConfig, Int>,
            _ value: Int, sourceLocation: SourceLocation = #_sourceLocation
        ) {
            var config = base
            config[keyPath: configField] = value
            #expect(config[keyPath: configField] == value, "value is not normalised", sourceLocation: sourceLocation)
            #expect(base[keyPath: configField] != value, "value is the default", sourceLocation: sourceLocation)
            var expected = ConfigurerDraftRoundTripTests.draft(base)
            expected[keyPath: draftField] = String(value)
            check(config, expected, sourceLocation)
            full[keyPath: configField] = value
            texts.append(String(value))
        }

        /// A list of row drafts holding a configuration list.
        mutating func rows<R: Equatable, V: Equatable>(
            _ draftField: WritableKeyPath<ConfigurerDraft, [R]>, _ configField: WritableKeyPath<AppConfig, [V]>,
            _ value: [V], _ row: (V) -> R, sourceLocation: SourceLocation = #_sourceLocation
        ) {
            var config = base
            config[keyPath: configField] = value
            #expect(config[keyPath: configField] == value, "value is not normalised", sourceLocation: sourceLocation)
            var expected = ConfigurerDraftRoundTripTests.draft(base)
            expected[keyPath: draftField] = value.map(row)
            check(config, expected, sourceLocation)
            full[keyPath: configField] = value
        }

        func check(_ config: AppConfig, _ expected: ConfigurerDraft, _ sourceLocation: SourceLocation) {
            #expect(ConfigurerDraftRoundTripTests.draft(config) == expected, "load", sourceLocation: sourceLocation)
            let applied = expected.applied(to: base, now: ConfigurerDraftRoundTripTests.now)
            #expect(applied == config, "apply", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Every field

    @Test func everyFieldIsWiredBothWays() {
        let wiring = Self.wireEverything()
        let repeated = Dictionary(grouping: wiring.texts) { $0 }.filter { $0.value.count > 1 }.keys.sorted()
        #expect(repeated.isEmpty, "values are not distinct: \(repeated)")
    }

    /// The whole non-default configuration survives `draft → applied` unchanged, applied onto itself or onto the
    /// default configuration.
    @Test func fullConfigurationRoundTrips() {
        let full = Self.fullConfig()
        #expect(full != Self.base())
        #expect(Self.draft(full).applied(to: full, now: Self.now) == full)
        #expect(Self.draft(full).applied(to: Self.base(), now: Self.now) == full)
    }

    /// The probe's input is exactly this configuration (so the v1.1.1 identity measured there is about the same
    /// values).
    @Test func probeFixtureIsTheFullConfiguration() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/jvm-probes/full-config.json")
        let decoded = try JSONDecoder().decode(AppConfig.self, from: try Data(contentsOf: url))
        // The two SCP / N+1 switches, the preferred callbook, Club Log's DXCC switch and the DX cluster spot filter
        // are Swift-only keys (v1.1.1 would reject them), so the probe file has none of them (the filter decodes
        // to its defaults).
        var expected = Self.fullConfig()
        expected.dxCluster.spotFilter = .default
        expected.scpSuggestionsEnabled = true
        expected.nPlusOneEnabled = true
        expected.preferredCallbook = "hamqth"
        expected.dupesheetSortBySuffix = true
        expected.clubLog.ctyEnabled = true
        expected.esm.nextCallKey = -1
        expected.esm.callStackOrder = CallStack.Order.multsFirst.rawValue
        expected.esm.callStackClearOnBandChange = true
        expected.digital.digitalCallStacking = false
        expected.digital.rttyInterface = RttyInterface.fldigi.rawValue
        expected.digital.tncType = TncType.pk232.rawValue
        expected.digital.tncPort = ""
        expected.digital.tncBaud = 9600
        expected.digital.tncTx = ""
        expected.digital.tncRx = ""
        expected.digital.tncEsc = ""
        expected.digital.tinyFskPort = ""
        expected.digital.wkRttyBaud = 45
        expected.digital.wkRttyReverse = false
        expected.digital.wkRttyFskOnKey = false
        expected.digital.diFontName = ""
        expected.digital.diTextColor = ""
        expected.digital.diBackgroundColor = ""
        expected.digital.fldigi2Host = "127.0.0.1"
        expected.digital.fldigi2Port = 0
        expected.digital.extraRx = ""
        expected.digital.extraRxToGrab = true
        expected.wsjtx.highlightCalls = true
        expected.wsjtx.mirrorDxCall = true
        expected.wsjtx.clearDecodesOnBandChange = true
        expected.wsjtx.jtdxTcpEnabled = false
        expected.wsjtx.jtdxTcpBind = "127.0.0.1:52001"
        expected.wsjtx.programPath = ""
        expected.wsjtx.programArgs = ""
        expected.wsjtx.radio2Id = ""
        expected.wsjtx.openDecodesOnLaunch = true
        expected.digital.alignRttyHz = 2210
        expected.digital.alignOtherHz = 1500
        expected.digital.afcOnCq = false
        expected.digital.netWithRunChange = false
        expected.digital.shiftCompEnabled = false
        expected.digital.shiftCompHz = 170
        expected.digital.cwIdEnabled = false
        expected.digital.cwIdText = "DE {MYCALL}"
        expected.digital.diButtonCount = 0
        expected.digital.rxOutputToFile = false
        expected.digital.diMessages = DigitalConfig.emptyButtons()
        expected.digital.grabOrder = GrabList.Order.lifo.rawValue
        expected.digital.grabNoDupes = true
        expected.digital.grabOnlyScp = false
        expected.digital.grabClearOnQsy = false
        expected.digital.grabClearOnCq = false
        expected.digital.grabSendSpace = false
        expected.digital.grabAddToBandmap = false
        expected.digital.callValidity = DigitalCallValidity.combined.rawValue
        expected.digital.validateScp = true
        expected.digital.validateCallHistory = true
        expected.digital.validateSpotted = true
        expected.digital.validateLogged = true
        expected.digital.scpGarbageSearch = false
        expected.digital.highlightBackground = false
        expected.digital.nonScrollingRx = false
        expected.digital.pauseOnCallHover = false
        expected.digital.hoverMode = false
        expected.digital.rightClickReturn = false
        expected.digital.sendSpaceOnClick = false
        expected.digital.captionRadioFrequency = false
        expected.digital.autoTrxUpdate = true
        expected.digital.rttyModem = "RTTY"
        expected.digital.pskModem = "BPSK31"
        #expect(decoded == expected)
    }

    static func fullConfig() -> AppConfig {
        wireEverything().full
    }

    static func wireEverything() -> Wiring {
        var w = Wiring()
        wireHardware(&w)
        wireStation(&w)
        wireCluster(&w)
        wireDxCluster(&w)
        wireCallbooks(&w)
        wireContestData(&w)
        wireNetwork(&w)
        wireOther(&w)
        wireRigExtras(&w)
        wireVoiceKeyer(&w)
        wireOperating(&w)
        wireKeyers(&w)
        wireSpecial(&w)
        return w
    }

    static func messages(_ prefix: String) -> [FunctionKeyMessage] {
        (1...VoiceKeyerConfig.keyCount).map { FunctionKeyMessage(label: prefix + String($0), text: prefix + " text " + String($0)) }
    }

    static func wireHardware(_ w: inout Wiring) {
        w.same(\.rigMode, \.rig.mode, .connectRunning)
        w.same(\.rigModel, \.rig.model, 3073)
        w.same(\.rigModelLabel, \.rig.modelLabel, "3073 — IC-7300")
        w.same(\.device, \.rig.device, "/dev/cu.rig")
        w.same(\.baud, \.rig.baud, 19200)
        w.same(\.dataBits, \.rig.dataBits, 7)
        w.same(\.stopBits, \.rig.stopBits, 2)
        w.same(\.parity, \.rig.parity, .even)
        w.same(\.flow, \.rig.flowControl, .hardware)
        w.same(\.dtr, \.rig.dtr, .on)
        w.same(\.rts, \.rig.rts, .off)
        w.same(\.host, \.rig.host, "rig.host")
        w.number(\.rigPort, \.rig.port, 4600)
    }

    static func wireStation(_ w: inout Wiring) {
        w.same(\.call, \.station.call, "OK1TST")
        w.same(\.operator, \.station.operator, "OK1OPR")
        w.same(\.name, \.station.name, "Name Tst")
        w.same(\.address1, \.station.address1, "Street 1")
        w.same(\.address2, \.station.address2, "Street 2")
        w.same(\.city, \.station.city, "Praha")
        w.same(\.stateRegion, \.station.state, "CZ-PR")
        w.same(\.zip, \.station.zip, "11000")
        w.same(\.country, \.station.country, "Czech Republic")
        w.same(\.cqZone, \.station.cqZone, "15")
        w.same(\.ituZone, \.station.ituZone, "28")
        w.same(\.license, \.station.license, "LIC-1")
        w.same(\.stationTxRx, \.station.stationTxRx, "IC-7300")
        w.same(\.power, \.station.power, "100W")
        w.same(\.antenna, \.station.antenna, "Dipole")
        w.same(\.antHeight, \.station.antHeight, "12m")
        w.same(\.asl, \.station.asl, "300m")
        w.same(\.arrlSection, \.station.arrlSection, "DX")
        w.same(\.roverQth, \.station.roverQth, "JEF")
        w.same(\.club, \.station.club, "OK1KHL")
        w.same(\.email, \.station.email, "tst@example.org")
    }

    static func wireCluster(_ w: inout Wiring) {
        w.same(\.clusterEnabled, \.cluster.enabled, true)
        w.same(\.brokerHost, \.cluster.brokerHost, "broker.lan")
        w.number(\.clusterPort, \.cluster.port, 1900)
        w.same(\.username, \.cluster.username, "mquser")
        w.same(\.password, \.cluster.password, "secret")
        w.same(\.stationId, \.cluster.stationId, "RUN1")
        w.same(\.tls, \.cluster.tls, true)
        w.same(\.shareSpots, \.cluster.shareSpots, false)
        w.same(\.interlock, \.cluster.interlock, .sameBand)
        w.same(\.serialServer, \.cluster.serialServer, true)
        w.same(\.stationType, \.cluster.stationType, .mult)
        w.same(\.ruleEnforcement, \.cluster.ruleEnforcement, .block)
    }

    static func wireDxCluster(_ w: inout Wiring) {
        var favorite = DxClusterFavorite(name: "Node A", host: "dx.example", port: 8000, login: "OK1TST", password: "dxpw")
        favorite.parallel = true
        let second = DxClusterFavorite(name: "Node B", host: "dx2.example", port: 7373, login: "OK1TST-2", password: "")
        w.rows(\.dxFavorites, \.dxCluster.favorites, [favorite, second]) { DxFavoriteDraft($0) }
        w.number(\.spotBufferMinutes, \.dxCluster.spotBufferMinutes, 45)
        w.number(\.wheelStepHz, \.dxCluster.wheelStepHz, 25)
        w.number(\.wheelStepShiftHz, \.dxCluster.wheelStepShiftHz, 250)
        w.number(\.selfSpotThresholdHz, \.dxCluster.selfSpotThresholdHz, 3000)
        w.number(\.minSkimmers, \.dxCluster.minSkimmers, 3)
        w.same(\.autoSplit, \.dxCluster.autoSplit, false)
        w.same(\.showBandPlan, \.dxCluster.showBandPlan, false)
        w.same(\.spotFilter, \.dxCluster.spotFilter,
               SpotFilter(hiddenBands: [.m160, .cm9], hiddenModes: ["DIGI"], contestOnly: true,
                         spotterContinents: ["EU", "NA"], spotterOwnCountry: true, hideNonWorkable: true))
    }

    static func wireCallbooks(_ w: inout Wiring) {
        w.same(\.hamQthEnabled, \.hamQth.enabled, false)
        w.same(\.hamQthUsername, \.hamQth.username, "hquser")
        w.same(\.hamQthPassword, \.hamQth.password, "hqpw")
        w.same(\.hamQthCallModes, \.hamQth.callModes, ["CW", "SSB"])
        w.same(\.hamQthFetchFields, \.hamQth.fetchFields, ["grid"])
        w.same(\.qrzEnabled, \.qrz.enabled, false)
        w.same(\.qrzUsername, \.qrz.username, "qzuser")
        w.same(\.qrzPassword, \.qrz.password, "qzpw")
        w.same(\.qrzCallModes, \.qrz.callModes, ["SSB", "DIGI"])
        w.same(\.qrzFetchFields, \.qrz.fetchFields, ["name", "cqZone"])
    }

    static func wireContestData(_ w: inout Wiring) {
        w.same(\.mapScheme, \.map.scheme, "sepia")
        w.same(\.mapPolitical, \.map.political, true)
        w.same(\.keyOverrides, \.keyBindings, ["log": "Ctrl+Alt+L", "wipe": ""])
        w.same(\.scpFile, \.scpFile, "/data/master.scp")
        w.same(\.scpSuggestionsEnabled, \.scpSuggestionsEnabled, false)
        w.same(\.nPlusOneEnabled, \.nPlusOneEnabled, false)
        w.same(\.preferredCallbook, \.preferredCallbook, "qrz")
        w.same(\.dupesheetSortBySuffix, \.dupesheetSortBySuffix, false)
        w.same(\.callHistoryFile, \.callHistoryFile, "/data/history.txt")
        w.same(\.clEnabled, \.clubLog.enabled, true)
        w.same(\.clEmail, \.clubLog.email, "cl@example.org")
        w.same(\.clPassword, \.clubLog.appPassword, "clpw")
        w.same(\.clCallsign, \.clubLog.callsign, "OK1CLB")
        w.same(\.clApiKey, \.clubLog.apiKey, "api-key")
        w.same(\.clCtyEnabled, \.clubLog.ctyEnabled, false)
        w.same(\.srEnabled, \.scoreReportingEnabled, true)
        w.same(\.srUrl, \.scoreReportingUrl, "https://cqcontest.net/post.php")
        w.number(\.srMinutes, \.scoreReportingMinutes, 7)
        w.same(\.srBreakdown, \.scoreReportingBreakdown, false)
        w.number(\.autoBackupMinutes, \.autoBackupMinutes, 20)
        w.number(\.autoBackupKeep, \.autoBackupKeep, 4)
        w.same(\.autoBackupDir, \.autoBackupDir, "/data/backups-own")
    }

    static func wireNetwork(_ w: inout Wiring) {
        w.same(\.bcContactsEnabled, \.broadcast.contactsEnabled, true)
        w.same(\.bcContactsTargets, \.broadcast.contactsTargets, "10.0.0.1:12060")
        w.same(\.bcRadioEnabled, \.broadcast.radioEnabled, true)
        w.same(\.bcRadioTargets, \.broadcast.radioTargets, "10.0.0.2:12060")
        w.same(\.bcScoreEnabled, \.broadcast.scoreEnabled, true)
        w.same(\.bcScoreTargets, \.broadcast.scoreTargets, "10.0.0.3:12060")
        w.same(\.bcAppInfoEnabled, \.broadcast.appInfoEnabled, true)
        w.same(\.bcAppInfoTargets, \.broadcast.appInfoTargets, "10.0.0.4:12060")
        w.same(\.wxReceiveEnabled, \.wsjtx.receiveEnabled, true)
        w.same(\.wxReceiveBind, \.wsjtx.receiveBind, "127.0.0.1:2238")
        w.same(\.wxSendEnabled, \.wsjtx.sendEnabled, true)
        w.same(\.wxSendTargets, \.wsjtx.sendTargets, "127.0.0.1:2239")
        w.same(\.nrReceiveEnabled, \.n1mmRecv.receiveEnabled, true)
        w.same(\.nrReceiveBind, \.n1mmRecv.receiveBind, "127.0.0.1:12062")
        w.same(\.auReceiveEnabled, \.adifUdp.receiveEnabled, true)
        w.same(\.auReceiveBind, \.adifUdp.receiveBind, "127.0.0.1:2334")
    }

    static func wireOther(_ w: inout Wiring) {
        w.same(\.vkOutput, \.voiceKeyer.outputDevice, "Speakers X")
        w.same(\.vkInput, \.voiceKeyer.inputDevice, "Mic Y")
        w.same(\.rxAudio, \.rxAudioDevice, "Line In Z")
        w.same(\.ttsVoice, \.ttsVoice, "Zuzana")
        w.same(\.radioMode, \.radioMode, "SO2R")
        w.same(\.modeRule, \.modeRule, "BANDPLAN")
        w.same(\.modeAlways, \.modeAlways, "PSK")
        w.same(\.dataMode, \.dataMode, "FT8")
        w.same(\.rttyAfsk, \.rttyAfsk, true)
        w.number(\.cwSpeedStep, \.cwSpeedStep, 6)
        w.number(\.tuneStepCw, \.tuneStepCwHz, 30)
        w.number(\.tuneStepSsb, \.tuneStepSsbHz, 200)
        w.same(\.beepOnDupe, \.beepOnDupe, true)
        w.same(\.themeMode, \.themeMode, "DARK")
        w.same(\.language, \.language, "en")
        w.same(\.ntpServer, \.ntpServer, "ntp.example")
        w.same(\.ntpCorrect, \.ntpCorrectQsoTime, true)
        w.same(\.themeAccent, \.themeAccent, "ORANGE")
        w.same(\.ritClearAfterLog, \.ritClearAfterLog, false)
    }

    static func wireRigExtras(_ w: inout Wiring) {
        let antennas = [
            AntennaEntry(code: 2, name: "Yagi 20", bands: "20", sector: "0-90"),
            AntennaEntry(code: 15, name: "Vertical", bands: "40,80", sector: ""),
        ]
        w.rows(\.antennas, \.antennas, antennas) { AntennaDraft($0) }
        w.same(\.antennaViaRig, \.antennaViaRig, true)
        let transverters = [
            TransverterEntry(name: "2m", ifLowKHz: 28000, ifHighKHz: 30000, offsetKHz: 116000, enabled: true),
            TransverterEntry(name: "70cm", ifLowKHz: 144000, ifHighKHz: 146000, offsetKHz: 288000, enabled: false),
        ]
        w.rows(\.transverters, \.transverters, transverters) { TransverterDraft($0) }
        w.same(\.footswitchPort, \.footswitchPort, "/dev/cu.foot")
        w.same(\.footswitchPin, \.footswitchPin, "DSR")
        w.same(\.footswitchAction, \.footswitchAction, "F1")
        w.same(\.rotatorHost, \.rotatorHost, "rot.host")
        w.same(\.rotorUdpHost, \.rotorUdpHost, "udp.rot")
        w.number(\.rotorUdpPort, \.rotorUdpPort, 12041)
        w.same(\.rotorUdpName, \.rotorUdpName, "Rotor A")
        w.number(\.rotatorPort, \.rotatorPort, 4540)
        w.same(\.rig2Host, \.rig2.host, "rig2.host")
        w.number(\.rig2Port, \.rig2.port, 4541)
        w.same(\.otrspPort, \.otrspPort, "/dev/cu.otrsp")
        w.number(\.cwPitch, \.cwPitchHz, 650)
    }

    static func wireVoiceKeyer(_ w: inout Wiring) {
        w.same(\.vkPttViaCat, \.voiceKeyer.pttViaCat, false)
        w.number(\.vkPttDelay, \.voiceKeyer.pttDelayMs, 175)
        w.number(\.vkMaxRecord, \.voiceKeyer.maxRecordSeconds, 50)
        w.same(\.vkWavDir, \.voiceKeyer.wavDir, "/data/wav-own")
        w.same(\.vkLettersPath, \.voiceKeyer.lettersPath, "Letters/{CALL}")
        w.rows(\.vkRun, \.voiceKeyer.runMessages, messages("vkr")) { FunctionKeyDraft($0) }
        w.rows(\.vkSp, \.voiceKeyer.spMessages, messages("vks")) { FunctionKeyDraft($0) }
    }

    static func wireOperating(_ w: inout Wiring) {
        w.same(\.runAutoSwitch, \.runMode.autoSwitch, false)
        w.same(\.runOnCqFrequency, \.runMode.runOnCqFrequency, false)
        w.same(\.autoReload, \.autoReloadLastContest, true)
        w.same(\.esmEnabled, \.esm.enabled, true)
        w.same(\.esmSpCallOnce, \.esm.spCallOnce, true)
        w.same(\.esmWorkDupes, \.esm.workDupes, false)
        w.same(\.esmNextCallKey, \.esm.nextCallKey, 11)
        w.same(\.callStackOrder, \.esm.callStackOrder, "LIFO")
        w.same(\.callStackClearOnBandChange, \.esm.callStackClearOnBandChange, false)
        w.same(\.digitalCallStacking, \.digital.digitalCallStacking, true)
        w.same(\.rttyInterface, \.digital.rttyInterface, "TINYFSK")
        w.same(\.tncType, \.digital.tncType, "KAM")
        w.same(\.tncPort, \.digital.tncPort, "/dev/cu.tnc")
        w.same(\.tncBaud, \.digital.tncBaud, 4800)
        w.same(\.tncTx, \.digital.tncTx, "{CTRL-C}T")
        w.same(\.tncRx, \.digital.tncRx, "{CTRL-C}E")
        w.same(\.tncEsc, \.digital.tncEsc, "{CTRL-C}R{ENTER}")
        w.same(\.tinyFskPort, \.digital.tinyFskPort, "/dev/cu.usbmodem1")
        w.same(\.wkRttyBaud, \.digital.wkRttyBaud, 75)
        w.same(\.wkRttyReverse, \.digital.wkRttyReverse, true)
        w.same(\.wkRttyFskOnKey, \.digital.wkRttyFskOnKey, true)
        w.same(\.diFontName, \.digital.diFontName, "Menlo")
        w.same(\.diTextColor, \.digital.diTextColor, "#FFFF00")
        w.same(\.diBackgroundColor, \.digital.diBackgroundColor, "#000080")
        w.same(\.fldigi2Host, \.digital.fldigi2Host, "10.0.0.2")
        w.same(\.fldigi2Port, \.digital.fldigi2Port, 7363)
        w.same(\.extraRx, \.digital.extraRx, "127.0.0.1:7363")
        w.same(\.extraRxToGrab, \.digital.extraRxToGrab, false)
        w.same(\.highlightCalls, \.wsjtx.highlightCalls, false)
        w.same(\.mirrorDxCall, \.wsjtx.mirrorDxCall, false)
        w.same(\.clearDecodesOnBandChange, \.wsjtx.clearDecodesOnBandChange, false)
        w.same(\.jtdxTcpEnabled, \.wsjtx.jtdxTcpEnabled, true)
        w.same(\.jtdxTcpBind, \.wsjtx.jtdxTcpBind, "127.0.0.1:52002")
        w.same(\.programPath, \.wsjtx.programPath, "/Applications/wsjtx.app")
        w.same(\.programArgs, \.wsjtx.programArgs, "--config-dir x")
        w.same(\.radio2Id, \.wsjtx.radio2Id, "Radio2")
        w.same(\.openDecodesOnLaunch, \.wsjtx.openDecodesOnLaunch, false)
        w.same(\.alignRttyHz, \.digital.alignRttyHz, 1500)
        w.same(\.alignOtherHz, \.digital.alignOtherHz, 1000)
        w.same(\.afcOnCq, \.digital.afcOnCq, true)
        w.same(\.netWithRunChange, \.digital.netWithRunChange, true)
        w.same(\.shiftCompEnabled, \.digital.shiftCompEnabled, true)
        w.same(\.shiftCompHz, \.digital.shiftCompHz, -170)
        w.same(\.cwIdEnabled, \.digital.cwIdEnabled, true)
        w.same(\.cwIdText, \.digital.cwIdText, "{MYCALL}")
        w.same(\.diButtonCount, \.digital.diButtonCount, 16)
        w.same(\.rxOutputToFile, \.digital.rxOutputToFile, true)
        w.rows(\.diMessages, \.digital.diMessages, (1...DigitalConfig.buttonSlots).map { FunctionKeyMessage(label: "di" + String($0), text: "di text " + String($0)) }) { FunctionKeyDraft($0) }
        w.same(\.grabOrder, \.digital.grabOrder, "FIFO")
        w.same(\.grabNoDupes, \.digital.grabNoDupes, false)
        w.same(\.grabOnlyScp, \.digital.grabOnlyScp, true)
        w.same(\.grabClearOnQsy, \.digital.grabClearOnQsy, true)
        w.same(\.grabClearOnCq, \.digital.grabClearOnCq, true)
        w.same(\.grabSendSpace, \.digital.grabSendSpace, true)
        w.same(\.grabAddToBandmap, \.digital.grabAddToBandmap, true)
        w.same(\.callValidity, \.digital.callValidity, "RESOURCES")
        w.same(\.validateScp, \.digital.validateScp, false)
        w.same(\.validateCallHistory, \.digital.validateCallHistory, false)
        w.same(\.validateSpotted, \.digital.validateSpotted, false)
        w.same(\.validateLogged, \.digital.validateLogged, false)
        w.same(\.scpGarbageSearch, \.digital.scpGarbageSearch, true)
        w.same(\.highlightBackground, \.digital.highlightBackground, true)
        w.same(\.nonScrollingRx, \.digital.nonScrollingRx, true)
        w.same(\.pauseOnCallHover, \.digital.pauseOnCallHover, true)
        w.same(\.hoverMode, \.digital.hoverMode, true)
        w.same(\.rightClickReturn, \.digital.rightClickReturn, true)
        w.same(\.sendSpaceOnClick, \.digital.sendSpaceOnClick, true)
        w.same(\.captionRadioFrequency, \.digital.captionRadioFrequency, true)
        w.same(\.autoTrxUpdate, \.digital.autoTrxUpdate, false)
        w.same(\.rttyModem, \.digital.rttyModem, "RTTY-75N")
        w.same(\.pskModem, \.digital.pskModem, "BPSK63")
    }

    static func wireKeyers(_ w: inout Wiring) {
        w.same(\.cwMethod, \.cwKeyer.method, .winkeyer)
        w.same(\.cwPort, \.cwKeyer.winkeyerPort, "/dev/cu.wk")
        w.number(\.cwSpeed, \.cwKeyer.speed, 33)
        w.same(\.cwCutNumbers, \.cwKeyer.cutNumbers, true)
        w.same(\.cwLeadingZeros, \.cwKeyer.leadingZeros, true)
        w.same(\.cwCutStyle, \.cwKeyer.cutStyle, .allO)
        w.rows(\.cwRun, \.cwKeyer.runMessages, messages("cwr")) { FunctionKeyDraft($0) }
        w.rows(\.cwSp, \.cwKeyer.spMessages, messages("cws")) { FunctionKeyDraft($0) }
        w.same(\.digiEngine, \.digital.engine, .fldigi)
        w.same(\.fldigiHost, \.digital.fldigiHost, "fldigi.host")
        w.number(\.fldigiPort, \.digital.fldigiPort, 7400)
        w.rows(\.digiRun, \.digital.runMessages, messages("dgr")) { FunctionKeyDraft($0) }
        w.rows(\.digiSp, \.digital.spMessages, messages("dgs")) { FunctionKeyDraft($0) }
    }

    /// Fields whose draft and configuration forms differ: the locator (with its derived coordinates), the
    /// repeat pause, the contest-data directory and the blacklists.
    static func wireSpecial(_ w: inout Wiring) {
        var grid = w.base
        grid.station.gridSquare = "JN79FX"
        grid.station.latitude = "49.9792"
        grid.station.longitude = "14.4583"
        var gridDraft = draft(w.base)
        gridDraft.grid = "JN79FX"
        w.check(grid, gridDraft, #_sourceLocation)
        w.full.station = mergeStation(w.full.station, grid.station)

        var repeatConfig = w.base
        repeatConfig.runMode.repeatSeconds = 3.5
        var repeatDraft = draft(w.base)
        repeatDraft.repeatSeconds = "3.5"
        w.check(repeatConfig, repeatDraft, #_sourceLocation)
        w.full.runMode.repeatSeconds = 3.5

        var dirConfig = w.base
        dirConfig.contestDataDir = "/data/contest-own"
        var dirDraft = draft(w.base)
        dirDraft.contestDataDir = "/data/contest-own"
        w.check(dirConfig, dirDraft, #_sourceLocation)
        w.full.contestDataDir = "/data/contest-own"

        let stamp = now.toString()
        var blackConfig = w.base
        blackConfig.dxCluster.callBlacklist = [BlacklistEntry(value: "OK1BAD", addedAtUtc: stamp, note: "")]
        blackConfig.dxCluster.spotterBlacklist = [BlacklistEntry(value: "DL1BAD", addedAtUtc: stamp, note: "")]
        var blackDraft = draft(w.base)
        blackDraft.blacklistedCalls = ["OK1BAD"]
        blackDraft.blacklistedSpotters = ["DL1BAD"]
        w.check(blackConfig, blackDraft, #_sourceLocation)
        w.full.dxCluster.callBlacklist = blackConfig.dxCluster.callBlacklist
        w.full.dxCluster.spotterBlacklist = blackConfig.dxCluster.spotterBlacklist
    }

    static func mergeStation(_ station: StationConfig, _ grid: StationConfig) -> StationConfig {
        var out = station
        out.gridSquare = grid.gridSquare
        out.latitude = grid.latitude
        out.longitude = grid.longitude
        return out
    }
}
