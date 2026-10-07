/// `applyTo(config)` (`ui/configurer/ConfigurerDraft.kt:330-533`): every draft field written back into a copy of the
/// configuration. Fields the draft does not have (window geometry, open windows, last database, contest setups…)
/// keep their values. The order of the writes does not matter for the result.
///
/// Rules carried over from Kotlin:
/// - texts are Kotlin-trimmed, passwords (`cluster`, HamQTH, QRZ, Club Log) and DX-favorite login/password are not;
/// - numbers fall back either to the **previous** value (`?: speed`, …, after `trim()`) or to a **fixed** default
///   (`clusterPort` 1883, `spotBufferMinutes` 90, `wheelStepHz` 100, `wheelStepShiftHz` 1000, `selfSpotThresholdHz`
///   2500, `minSkimmers` 1, `srMinutes` 5, `autoBackupMinutes` 15, `autoBackupKeep` 10, `rotorUdpPort` 12040,
///   `rotatorPort` 4533, `rig2.port` 4534) — those use Kotlin `toIntOrNull` **without** trimming (`" 1884"` → 1883);
/// - clamps `cwSpeedStep` 1…10 (else 2), `tuneStepCw` 1…1000 (else 20), `tuneStepSsb` 1…5000 (else 100),
///   `cwPitch` outside 200…1500 → 600; the setters of the configuration then normalise as in Java;
/// - `repeatSeconds`: `trim().replace(',', '.')` + Kotlin `toDoubleOrNull` (NaN/Infinity/exponent accepted), an
///   unparsable text keeps the old value; the Java setter's NaN (which it keeps) becomes 0.2 here;
/// - `latitude`/`longitude` from `gridLatLon(grid.trim())` or `""`;
/// - the blacklists are reconciled with `BlacklistService.sync` (notes and times kept), `now` = `Instant.now()`;
/// - antennas with a blank name are dropped, transverters that do not convert are dropped;
/// - `keyBindings` = exactly the draft's map;
/// - `language` is written; switching the translation (Kotlin `I18n.use`) is the model's effect.
extension ConfigurerDraft {

    public func applied(to config: AppConfig, now: JavaInstant) -> AppConfig {
        var out = config
        applyOperating(&out)
        applyKeyers(&out)
        applyVoiceKeyer(&out.voiceKeyer)
        applyRig(&out.rig)
        applyStation(&out.station)
        applyCluster(&out.cluster)
        applyNetwork(&out)
        applyDxCluster(&out.dxCluster, now: now)
        applyCallbooks(&out)
        applyContestData(&out)
        applyOther(&out)
        applyRigExtras(&out)
        return out
    }

    // MARK: - Groups

    private func applyOperating(_ config: inout AppConfig) {
        config.runMode.autoSwitch = runAutoSwitch
        config.runMode.runOnCqFrequency = runOnCqFrequency
        let text: String = Self.replaceComma(Self.trim(repeatSeconds))
        if let seconds = KotlinNumber.toDoubleOrNull(text) {
            config.runMode.repeatSeconds = seconds
        }
        config.autoReloadLastContest = autoReload
        config.esm.enabled = esmEnabled
        config.esm.spCallOnce = esmSpCallOnce
        config.esm.workDupes = esmWorkDupes
    }

    private func applyKeyers(_ config: inout AppConfig) {
        config.cwKeyer.method = cwMethod
        config.cwKeyer.winkeyerPort = Self.trim(cwPort)
        config.cwKeyer.speed = Self.trimmedInt(cwSpeed) ?? config.cwKeyer.speed
        config.cwKeyer.cutNumbers = cwCutNumbers
        config.cwKeyer.leadingZeros = cwLeadingZeros
        config.cwKeyer.cutStyle = cwCutStyle
        config.cwKeyer.runMessages = cwRun.map { $0.toMessage() }
        config.cwKeyer.spMessages = cwSp.map { $0.toMessage() }
        config.digital.engine = digiEngine
        config.digital.fldigiHost = Self.trim(fldigiHost)
        config.digital.fldigiPort = Self.trimmedInt(fldigiPort) ?? config.digital.fldigiPort
        config.digital.runMessages = digiRun.map { $0.toMessage() }
        config.digital.spMessages = digiSp.map { $0.toMessage() }
    }

    private func applyVoiceKeyer(_ vk: inout VoiceKeyerConfig) {
        vk.outputDevice = vkOutput
        vk.inputDevice = vkInput
        vk.pttViaCat = vkPttViaCat
        vk.pttDelayMs = Self.trimmedInt(vkPttDelay) ?? vk.pttDelayMs
        vk.maxRecordSeconds = Self.trimmedInt(vkMaxRecord) ?? vk.maxRecordSeconds
        vk.wavDir = Self.trim(vkWavDir)
        vk.lettersPath = Self.trim(vkLettersPath)
        vk.runMessages = vkRun.map { $0.toMessage() }
        vk.spMessages = vkSp.map { $0.toMessage() }
    }

    private func applyRig(_ rig: inout RigConfig) {
        rig.mode = rigMode
        rig.model = rigModel
        rig.modelLabel = rigModelLabel
        rig.device = Self.trim(device)
        rig.baud = baud
        rig.dataBits = dataBits
        rig.stopBits = stopBits
        rig.parity = parity
        rig.flowControl = flow
        rig.dtr = dtr
        rig.rts = rts
        rig.host = Self.trim(host)
        rig.port = Self.trimmedInt(rigPort) ?? rig.port
    }

    private func applyStation(_ st: inout StationConfig) {
        st.call = Self.trim(call)
        st.operator = Self.trim(`operator`)
        st.gridSquare = Self.trim(grid)
        st.name = Self.trim(name)
        st.address1 = Self.trim(address1)
        st.address2 = Self.trim(address2)
        st.city = Self.trim(city)
        st.state = Self.trim(stateRegion)
        st.zip = Self.trim(zip)
        st.country = Self.trim(country)
        st.cqZone = Self.trim(cqZone)
        st.ituZone = Self.trim(ituZone)
        st.license = Self.trim(license)
        let latLon = GridLatLon.of(Self.trim(grid))
        st.latitude = latLon?.latitude ?? ""
        st.longitude = latLon?.longitude ?? ""
        st.stationTxRx = Self.trim(stationTxRx)
        st.power = Self.trim(power)
        st.antenna = Self.trim(antenna)
        st.antHeight = Self.trim(antHeight)
        st.asl = Self.trim(asl)
        st.arrlSection = Self.trim(arrlSection)
        st.roverQth = Self.trim(roverQth)
        st.club = Self.trim(club)
        st.email = Self.trim(email)
    }

    private func applyCluster(_ cluster: inout ClusterConfig) {
        cluster.enabled = clusterEnabled
        cluster.brokerHost = Self.trim(brokerHost)
        cluster.port = ConfigurerRows.toIntOrNull(clusterPort) ?? 1883
        cluster.username = username
        cluster.password = password
        cluster.stationId = Self.trim(stationId)
        cluster.tls = tls
        cluster.shareSpots = shareSpots
        cluster.interlock = interlock
        cluster.serialServer = serialServer
        cluster.stationType = stationType
        cluster.ruleEnforcement = ruleEnforcement
    }

    private func applyNetwork(_ config: inout AppConfig) {
        config.broadcast.contactsEnabled = bcContactsEnabled
        config.broadcast.contactsTargets = Self.trim(bcContactsTargets)
        config.broadcast.radioEnabled = bcRadioEnabled
        config.broadcast.radioTargets = Self.trim(bcRadioTargets)
        config.broadcast.scoreEnabled = bcScoreEnabled
        config.broadcast.scoreTargets = Self.trim(bcScoreTargets)
        config.broadcast.appInfoEnabled = bcAppInfoEnabled
        config.broadcast.appInfoTargets = Self.trim(bcAppInfoTargets)
        config.wsjtx.receiveEnabled = wxReceiveEnabled
        config.wsjtx.receiveBind = Self.trim(wxReceiveBind)
        config.wsjtx.sendEnabled = wxSendEnabled
        config.wsjtx.sendTargets = Self.trim(wxSendTargets)
        config.n1mmRecv.receiveEnabled = nrReceiveEnabled
        config.n1mmRecv.receiveBind = Self.trim(nrReceiveBind)
        config.adifUdp.receiveEnabled = auReceiveEnabled
        config.adifUdp.receiveBind = Self.trim(auReceiveBind)
    }

    private func applyDxCluster(_ dx: inout DxClusterConfig, now: JavaInstant) {
        dx.favorites = dxFavorites.map { $0.toFavorite() }
        dx.spotBufferMinutes = ConfigurerRows.toIntOrNull(spotBufferMinutes) ?? 90
        dx.wheelStepHz = ConfigurerRows.toIntOrNull(wheelStepHz) ?? 100
        dx.wheelStepShiftHz = ConfigurerRows.toIntOrNull(wheelStepShiftHz) ?? 1000
        dx.selfSpotThresholdHz = ConfigurerRows.toIntOrNull(selfSpotThresholdHz) ?? 2500
        dx.minSkimmers = ConfigurerRows.toIntOrNull(minSkimmers) ?? 1
        dx.autoSplit = autoSplit
        dx.showBandPlan = showBandPlan
        dx.spotFilter = spotFilter
        let stamp: String = now.toString()
        BlacklistService.sync(&dx.callBlacklist, blacklistedCalls, nowUtc: stamp)
        BlacklistService.sync(&dx.spotterBlacklist, blacklistedSpotters, nowUtc: stamp)
    }

    private func applyCallbooks(_ config: inout AppConfig) {
        config.hamQth.enabled = hamQthEnabled
        config.hamQth.username = Self.trim(hamQthUsername)
        config.hamQth.password = hamQthPassword
        config.hamQth.callModes = hamQthCallModes
        config.hamQth.fetchFields = hamQthFetchFields
        config.qrz.enabled = qrzEnabled
        config.qrz.username = Self.trim(qrzUsername)
        config.qrz.password = qrzPassword
        config.qrz.callModes = qrzCallModes
        config.qrz.fetchFields = qrzFetchFields
        config.map.scheme = mapScheme
        config.map.political = mapPolitical
    }

    private func applyContestData(_ config: inout AppConfig) {
        config.contestDataDir = Self.trim(contestDataDir)
        config.scpFile = Self.trim(scpFile)
        config.callHistoryFile = Self.trim(callHistoryFile)
        config.scpSuggestionsEnabled = scpSuggestionsEnabled
        config.nPlusOneEnabled = nPlusOneEnabled
        config.preferredCallbook = CallbookService(configValue: preferredCallbook).rawValue
        config.clubLog.enabled = clEnabled
        config.clubLog.email = Self.trim(clEmail)
        config.clubLog.appPassword = clPassword
        config.clubLog.callsign = JavaText.toUpperCase(Self.trim(clCallsign))
        config.clubLog.apiKey = Self.trim(clApiKey)
        config.clubLog.ctyEnabled = clCtyEnabled
        config.scoreReportingEnabled = srEnabled
        config.scoreReportingUrl = Self.trim(srUrl)
        config.scoreReportingMinutes = ConfigurerRows.toIntOrNull(srMinutes) ?? 5
        config.scoreReportingBreakdown = srBreakdown
        config.autoBackupMinutes = ConfigurerRows.toIntOrNull(autoBackupMinutes) ?? 15
        config.autoBackupKeep = ConfigurerRows.toIntOrNull(autoBackupKeep) ?? 10
        config.autoBackupDir = Self.trim(autoBackupDir)
        config.keyBindings = keyOverrides
    }

    private func applyOther(_ config: inout AppConfig) {
        config.rxAudioDevice = rxAudio
        config.ttsVoice = Self.trim(ttsVoice)
        config.radioMode = radioMode
        config.modeRule = modeRule
        config.modeAlways = modeAlways
        config.dataMode = dataMode
        config.rttyAfsk = rttyAfsk
        config.cwSpeedStep = Self.clamped(cwSpeedStep, 1, 10) ?? 2
        config.tuneStepCwHz = Self.clamped(tuneStepCw, 1, 1000) ?? 20
        config.tuneStepSsbHz = Self.clamped(tuneStepSsb, 1, 5000) ?? 100
        config.beepOnDupe = beepOnDupe
        config.themeMode = themeMode
        config.language = language
        config.ntpServer = Self.trim(ntpServer)
        config.ntpCorrectQsoTime = ntpCorrect
        config.themeAccent = themeAccent
        config.ritClearAfterLog = ritClearAfterLog
    }

    private func applyRigExtras(_ config: inout AppConfig) {
        let entries: [AntennaEntry] = antennas.map { $0.toEntry() }
        config.antennas = entries.filter { !KotlinText.isBlank($0.name) }
        config.antennaViaRig = antennaViaRig
        config.transverters = transverters.compactMap { $0.toEntry() }
        config.footswitchPort = footswitchPort
        config.footswitchPin = footswitchPin
        config.footswitchAction = footswitchAction
        config.rotatorHost = Self.trim(rotatorHost)
        config.rotorUdpHost = Self.trim(rotorUdpHost)
        config.rotorUdpPort = ConfigurerRows.toIntOrNull(rotorUdpPort) ?? 12040
        config.rotorUdpName = Self.trim(rotorUdpName)
        config.rotatorPort = ConfigurerRows.toIntOrNull(rotatorPort) ?? 4533
        let rig2: String = Self.trim(rig2Host)
        config.rig2.host = KotlinText.isBlank(rig2) ? "localhost" : rig2
        config.rig2.port = ConfigurerRows.toIntOrNull(rig2Port) ?? 4534
        config.otrspPort = Self.trim(otrspPort)
        config.cwPitchHz = Self.pitch(cwPitch)
    }

    // MARK: - Kotlin text helpers

    /// Kotlin `String.trim()`.
    static func trim(_ text: String) -> String {
        KotlinText.trim(text)
    }

    /// Kotlin `trim().toIntOrNull()`.
    static func trimmedInt(_ text: String) -> Int? {
        ConfigurerRows.toIntOrNull(trim(text))
    }

    /// Kotlin `toIntOrNull()?.coerceIn(low, high)` (no trimming).
    static func clamped(_ text: String, _ low: Int, _ high: Int) -> Int? {
        guard let value = ConfigurerRows.toIntOrNull(text) else { return nil }
        return min(max(value, low), high)
    }

    /// Kotlin `cwPitch.toIntOrNull()?.takeIf { it in 200..1500 } ?: 600`.
    static func pitch(_ text: String) -> Int {
        guard let value = ConfigurerRows.toIntOrNull(text), value >= 200, value <= 1500 else { return 600 }
        return value
    }

    /// Kotlin `replace(',', '.')` (by UTF-16 units; `,` and `.` are ASCII, so by scalars too).
    static func replaceComma(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { $0 == "," ? Unicode.Scalar(".") : $0 }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars)
        return String(out)
    }
}
