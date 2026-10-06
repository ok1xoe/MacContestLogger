import Testing
@testable import MCLCore

/// `ConfigurerDraft(config)` and `applyTo` (`ui/configurer/ConfigurerDraft.kt:23-317, 330-533`). Values marked
/// "probe" are measured on the JVM by a maintainer-only probe (`settings-probe.tsv`); the
/// rest is read from the source.
@Suite struct ConfigurerDraftApplyTests {

    static let defaultDir = "/data/contest-data"
    static let now = JavaInstant.ofEpochSecond(1_790_000_000, 123_000_000)!

    static func draft(_ config: AppConfig) -> ConfigurerDraft {
        ConfigurerDraft(
            config: config, bandSegments: [], digi: DigiFreqFile.Table(channels: []), defaultContestDataDir: defaultDir)
    }

    /// Applies a draft of the default configuration with one field edited.
    static func apply(_ edit: (inout ConfigurerDraft) -> Void) -> AppConfig {
        var config = AppConfig()
        config.contestDataDir = defaultDir
        var d = draft(config)
        edit(&d)
        return d.applied(to: config, now: now)
    }

    // MARK: - Initial texts (`CD:24-317`)

    @Test func initialTexts() {
        var config = AppConfig()
        config.rig.port = 4555
        config.cluster.port = 1884
        config.runMode.repeatSeconds = 2.0
        config.keyBindings = ["log": "Ctrl+Alt+S", "wipe": ""]
        let d = Self.draft(config)
        #expect(d.rigPort == "4555")
        #expect(d.clusterPort == "1884")
        #expect(d.repeatSeconds == "2.0")
        #expect(d.contestDataDir == Self.defaultDir)
        #expect(d.keyOverrides == ["log": "Ctrl+Alt+S", "wipe": ""])
        #expect(d.cwSpeed == "28")
        #expect(d.rig2Port == String(config.rig2.port))
    }

    /// Probe `rep`: `String.format(Locale.US, "%.1f")` rounds half up on the decimal digits.
    @Test func repeatSecondsInitialText() {
        let cases: [(Double, String)] = [(2.0, "2.0"), (0.25, "0.3"), (0.35, "0.4"), (120.0, "120.0"), (1.05, "1.1")]
        for (value, text) in cases {
            var config = AppConfig()
            config.runMode.repeatSeconds = value
            #expect(Self.draft(config).repeatSeconds == text)
        }
    }

    @Test func configuredContestDirWinsOverDefault() {
        var config = AppConfig()
        config.contestDataDir = " /own/dir "
        #expect(Self.draft(config).contestDataDir == " /own/dir ")
    }

    @Test func blacklistsAndBandDataAreRead() {
        var config = AppConfig()
        config.dxCluster.callBlacklist = [BlacklistEntry(value: "ok1abc", addedAtUtc: "t", note: "n")]
        config.dxCluster.spotterBlacklist = [BlacklistEntry(value: "DL1X", addedAtUtc: "", note: "")]
        let segment = BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040)
        let channel = DigiFreqFile.Channel(mode: "FT8", fromKhz: 7074, toKhz: 7077)
        let d = ConfigurerDraft(
            config: config, bandSegments: [segment], digi: DigiFreqFile.Table(channels: [channel]),
            defaultContestDataDir: Self.defaultDir)
        #expect(d.blacklistedCalls == ["OK1ABC"])
        #expect(d.blacklistedSpotters == ["DL1X"])
        #expect(d.bandSegments.map(\.fromKhz) == ["7000"])
        #expect(d.digiChannels.map(\.toKhz) == ["7077"])
        #expect(d.bandData().segments == [segment])
        #expect(d.bandData().table == DigiFreqFile.Table(channels: [channel]))
    }

    // MARK: - applyTo

    @Test func unchangedDraftKeepsTheConfiguration() {
        var config = AppConfig()
        config.contestDataDir = Self.defaultDir
        config.station.gridSquare = "JN79FX"
        config.station.latitude = "49.9792"
        config.station.longitude = "14.4583"
        config.antennas = [AntennaEntry(code: 1, name: "Yagi", bands: "20", sector: "")]
        config.transverters = [TransverterEntry(name: "2m", ifLowKHz: 28000, ifHighKHz: 30000, offsetKHz: 116000, enabled: true)]
        #expect(Self.draft(config).applied(to: config, now: Self.now) == config)
    }

    /// `contestDataDir` (Java `null` = default) is written as the default directory's text.
    @Test func missingContestDirIsWrittenAsDefault() {
        let config = AppConfig()
        #expect(config.contestDataDir == nil)
        #expect(Self.draft(config).applied(to: config, now: Self.now).contestDataDir == Self.defaultDir)
    }

    /// Probe `apply clusterPort/srMinutes/spotBufferMinutes`: fixed fallback, `toIntOrNull` without trimming.
    @Test func fixedFallbacksDoNotTrim() {
        let cases: [(String, Int, Int, Int)] = [
            ("", 1883, 5, 90), ("1883", 1883, 1883, 1883), (" 1884", 1883, 5, 90), ("1884 ", 1883, 5, 90),
            ("+12", 12, 12, 12), ("-5", -5, 2, 90), ("abc", 1883, 5, 90), ("١٢", 12, 12, 12),
            ("99999999999", 1883, 5, 90),
        ]
        for (text, cluster, minutes, buffer) in cases {
            #expect(Self.apply { $0.clusterPort = text }.cluster.port == cluster, "\(text)")
            #expect(Self.apply { $0.srMinutes = text }.scoreReportingMinutes == minutes, "\(text)")
            #expect(Self.apply { $0.spotBufferMinutes = text }.dxCluster.spotBufferMinutes == buffer, "\(text)")
        }
    }

    /// Probe `apply rigPort/cwSpeed`: previous-value fallback after `trim()`; the setters normalise (`RigConfig.port`
    /// has none, as in Java: `-5` stays).
    @Test func previousValueFallbacksTrim() {
        let ports: [(String, Int)] = [
            ("", 4532), ("1883", 1883), (" 1884", 1884), ("1884 ", 1884), ("+12", 12), ("-5", -5), ("abc", 4532),
            ("١٢", 12), ("99999999999", 4532),
        ]
        for (text, port) in ports {
            #expect(Self.apply { $0.rigPort = text }.rig.port == port, "\(text)")
        }
        let speeds: [(String, Int)] = [("30", 30), (" 30 ", 30), ("x", 28), ("200", 60), ("1", 5)]
        for (text, speed) in speeds {
            #expect(Self.apply { $0.cwSpeed = text }.cwKeyer.speed == speed, "\(text)")
        }
    }

    /// Probe: the remaining fixed fallbacks (`CD:526-530`, `497`).
    @Test func otherFixedFallbacks() {
        #expect(Self.apply { $0.rig2Port = "" }.rig2.port == 4534)
        #expect(Self.apply { $0.rig2Port = "4535" }.rig2.port == 4535)
        #expect(Self.apply { $0.rig2Port = " 4535" }.rig2.port == 4534)
        #expect(Self.apply { $0.rotatorPort = "" }.rotatorPort == 4533)
        #expect(Self.apply { $0.rotatorPort = " 4600" }.rotatorPort == 4533)
        #expect(Self.apply { $0.rotorUdpPort = "x" }.rotorUdpPort == 12040)
        #expect(Self.apply { $0.autoBackupMinutes = "x" }.autoBackupMinutes == 15)
        let keeps: [(String, Int)] = [("", 10), ("3", 3), ("0", 10), ("-2", 10)]
        for (text, keep) in keeps {
            #expect(Self.apply { $0.autoBackupKeep = text }.autoBackupKeep == keep, "\(text)")
        }
        #expect(Self.apply { $0.wheelStepHz = "" }.dxCluster.wheelStepHz == 100)
        #expect(Self.apply { $0.wheelStepShiftHz = "" }.dxCluster.wheelStepShiftHz == 1000)
        #expect(Self.apply { $0.selfSpotThresholdHz = "" }.dxCluster.selfSpotThresholdHz == 2500)
        #expect(Self.apply { $0.minSkimmers = "" }.dxCluster.minSkimmers == 1)
    }

    /// Probe `apply cwSpeedStep/tuneStepCw/tuneStepSsb/cwPitch`.
    @Test func clamps() {
        let steps: [(String, Int)] = [("0", 1), ("5", 5), ("11", 10), (" 5", 2), ("x", 2)]
        for (text, value) in steps {
            #expect(Self.apply { $0.cwSpeedStep = text }.cwSpeedStep == value, "\(text)")
        }
        let cw: [(String, Int)] = [("0", 1), ("50", 50), ("5000", 1000), ("x", 20)]
        for (text, value) in cw {
            #expect(Self.apply { $0.tuneStepCw = text }.tuneStepCwHz == value, "\(text)")
        }
        let ssb: [(String, Int)] = [("0", 1), ("50", 50), ("9000", 5000), ("x", 100)]
        for (text, value) in ssb {
            #expect(Self.apply { $0.tuneStepSsb = text }.tuneStepSsbHz == value, "\(text)")
        }
        let pitch: [(String, Int)] = [
            ("199", 600), ("200", 200), ("1500", 1500), ("1501", 600), ("700", 700), (" 700", 600), ("x", 600),
        ]
        for (text, value) in pitch {
            #expect(Self.apply { $0.cwPitch = text }.cwPitchHz == value, "\(text)")
        }
    }

    /// Probe `apply repeatSeconds`. Java keeps `NaN` (`Math.max(0.2, Math.min(NaN, 120))`); the Swift setter turns
    /// it into 0.2 (known divergence).
    @Test func repeatSecondsParsing() {
        let cases: [(String, Double)] = [
            ("2.5", 2.5), ("2,5", 2.5), (" 3 ", 3.0), ("Infinity", 120.0), ("-1", 0.2), ("1e1", 10.0),
            ("500", 120.0), ("x", 2.0), ("0x1p1", 2.0), ("NaN", 0.2),
        ]
        for (text, value) in cases {
            #expect(Self.apply { $0.repeatSeconds = text }.runMode.repeatSeconds == value, "\(text)")
        }
    }

    /// Probe `apply rig2Host/clCallsign/password/grid`.
    @Test func textRules() {
        #expect(Self.apply { $0.rig2Host = "" }.rig2.host == "localhost")
        #expect(Self.apply { $0.rig2Host = "  " }.rig2.host == "localhost")
        #expect(Self.apply { $0.rig2Host = " host " }.rig2.host == "host")
        #expect(Self.apply { $0.rig2Host = "\u{00A0}" }.rig2.host == "localhost")
        #expect(Self.apply { $0.clCallsign = " ok1xoe " }.clubLog.callsign == "OK1XOE")
        #expect(Self.apply { $0.clCallsign = "straße" }.clubLog.callsign == "STRASSE")
        #expect(Self.apply { $0.password = " secret " }.cluster.password == " secret ")
        let station = Self.apply { $0.grid = " JN79fx " }.station
        #expect([station.gridSquare, station.latitude, station.longitude] == ["JN79fx", "49.9792", "14.4583"])
        let bad = Self.apply { $0.grid = "bad" }.station
        #expect([bad.gridSquare, bad.latitude, bad.longitude] == ["bad", "", ""])
    }

    /// Passwords are written as they are, everything else is trimmed (`CD:413-491`).
    @Test func passwordsAreNotTrimmed() {
        let c = Self.apply {
            $0.hamQthPassword = " a "
            $0.qrzPassword = " b "
            $0.clPassword = " c "
            $0.username = " user "
            $0.hamQthUsername = " hq "
            $0.qrzUsername = " qz "
            $0.clEmail = " e@x "
        }
        #expect([c.hamQth.password, c.qrz.password, c.clubLog.appPassword] == [" a ", " b ", " c "])
        #expect(c.cluster.username == " user ")
        #expect([c.hamQth.username, c.qrz.username, c.clubLog.email] == ["hq", "qz", "e@x"])
    }

    @Test func rowsAreFilteredAndConverted() {
        let c = Self.apply {
            $0.antennas = [
                AntennaDraft(AntennaEntry(code: 1, name: " Yagi ", bands: "20", sector: "")),
                AntennaDraft(AntennaEntry(code: 2, name: "  ", bands: "40", sector: "")),
            ]
            $0.transverters = [
                TransverterDraft(TransverterEntry(name: "2m", ifLowKHz: 28000, ifHighKHz: 30000, offsetKHz: 116000, enabled: true)),
                TransverterDraft(TransverterEntry(name: "bad", ifLowKHz: 30000, ifHighKHz: 28000, offsetKHz: 0, enabled: true)),
            ]
            $0.cwRun[0].label = " CQ "
        }
        #expect(c.antennas == [AntennaEntry(code: 1, name: "Yagi", bands: "20", sector: "")])
        #expect(c.transverters.map(\.name) == ["2m"])
        #expect(c.cwKeyer.runMessages[0].label == "CQ")
    }

    @Test func keyBindingsAreTheExactMap() {
        var config = AppConfig()
        config.keyBindings = ["log": "Ctrl+L", "wipe": "Alt+W"]
        var d = Self.draft(config)
        d.keyOverrides["wipe"] = nil
        d.keyOverrides["esm"] = ""
        #expect(d.applied(to: config, now: Self.now).keyBindings == ["log": "Ctrl+L", "esm": ""])
    }

    /// The blacklists are reconciled (`BlacklistService.sync`): a kept entry keeps its note and time, a removed
    /// one goes, a new one gets `now`.
    @Test func blacklistsAreSynced() {
        var config = AppConfig()
        config.dxCluster.callBlacklist = [
            BlacklistEntry(value: "OK1ABC", addedAtUtc: "2026-01-01T00:00:00Z", note: "pirate"),
            BlacklistEntry(value: "OK1OLD", addedAtUtc: "", note: ""),
        ]
        var d = Self.draft(config)
        d.blacklistedCalls = ["OK1ABC", "ok1new"]
        d.blacklistedSpotters = ["DL1X"]
        let dx = d.applied(to: config, now: Self.now).dxCluster
        #expect(dx.callBlacklist == [
            BlacklistEntry(value: "OK1ABC", addedAtUtc: "2026-01-01T00:00:00Z", note: "pirate"),
            BlacklistEntry(value: "OK1NEW", addedAtUtc: Self.now.toString(), note: ""),
        ])
        #expect(dx.spotterBlacklist.map(\.value) == ["DL1X"])
    }

    @Test func languageAndAppearanceAreWritten() {
        let c = Self.apply {
            $0.language = "en"
            $0.themeMode = "DARK"
            $0.themeAccent = "ORANGE"
        }
        #expect([c.language, c.themeMode, c.themeAccent] == ["en", "DARK", "ORANGE"])
    }

    /// A change made outside the window while it is open (here ESM and the auto-reload flag) is overwritten
    /// by the draft on OK; fields the draft does not have stay as they are in the live configuration.
    @Test func draftOverwritesConcurrentChangesButKeepsForeignFields() {
        let opened = AppConfig()
        let d = Self.draft(opened)
        var live = opened
        live.esm.enabled = true
        live.autoReloadLastContest = true
        live.lastDatabase = "/db/x.sqlite"
        live.openWindows = ["log", "bandmap"]
        live.windowGeometry = ["log": WindowGeometry(x: 1, y: 2, width: 3, height: 4)]
        live.goals = ["10": 5]
        let out = d.applied(to: live, now: Self.now)
        #expect(!out.esm.enabled)
        #expect(!out.autoReloadLastContest)
        #expect(out.lastDatabase == "/db/x.sqlite")
        #expect(out.openWindows == ["log", "bandmap"])
        #expect(out.windowGeometry == live.windowGeometry)
        #expect(out.goals == ["10": 5])
    }

    /// The draft adds no configuration field — the applied configuration has exactly the keys of the input,
    /// and the only Swift-only properties of the profile-merge schema are the two SCP / N+1 switches. (`contestDataDir` is set: a `nil`
    /// directory is not written and the draft fills it in.)
    @Test func appliedConfigurationHasNoNewKeys() throws {
        var config = AppConfig()
        config.contestDataDir = Self.defaultDir
        let out = Self.draft(config).applied(to: config, now: Self.now)
        let before = try ProfileMerge.fields(of: config)
        let after = try ProfileMerge.fields(of: out)
        #expect(Set(after.keys) == Set(before.keys))
        let extra = ProfileMergeSchema.swiftOnlyProperties.values.flatMap { $0.map(\.name) }
        #expect(Set(extra) == ["scpSuggestionsEnabled", "nPlusOneEnabled", "preferredCallbook"])
    }
}
