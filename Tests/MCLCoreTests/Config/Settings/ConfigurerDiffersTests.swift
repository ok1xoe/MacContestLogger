import Testing
@testable import MCLCore

/// Change predicates (`ui/configurer/ConfigurerDraft.kt:202-246, 319-327`) against the old configuration. Values
/// marked "probe" are measured by a maintainer-only probe.
@Suite struct ConfigurerDiffersTests {

    static let defaultDir = "/data/contest-data"

    static func draft(_ config: AppConfig, _ edit: (inout ConfigurerDraft) -> Void = { _ in }) -> ConfigurerDraft {
        var d = ConfigurerDraft(
            config: config, bandSegments: [], digi: DigiFreqFile.Table(channels: []), defaultContestDataDir: defaultDir)
        edit(&d)
        return d
    }

    @Test func unchangedDraftDiffersNowhere() {
        let c = AppConfig()
        let d = Self.draft(c)
        #expect(!d.rigDiffers(c.rig))
        #expect(!d.clusterDiffers(c.cluster))
        #expect(!d.scoringStationDiffers(c.station))
        #expect(!d.contestDirDiffers(c, defaultDir: Self.defaultDir))
        #expect(!d.broadcastDiffers(c.broadcast))
        #expect(!d.wsjtxDiffers(c.wsjtx))
        #expect(!d.n1mmDiffers(c.n1mmRecv))
        #expect(!d.adifUdpDiffers(c.adifUdp))
    }

    /// Probe `rigDiffers`: the port is `trim().toIntOrNull() ?: rig.port`.
    @Test func rigPortParsing() {
        let c = AppConfig()
        let cases: [(String, Bool)] = [("4532", false), (" 4532 ", false), ("x", false), ("4533", true)]
        for (text, differs) in cases {
            #expect(Self.draft(c) { $0.rigPort = text }.rigDiffers(c.rig) == differs, "\(text)")
        }
    }

    @Test func rigFields() {
        let c = AppConfig()
        #expect(Self.draft(c) { $0.rigMode = .connectRunning }.rigDiffers(c.rig))
        #expect(Self.draft(c) { $0.rigModel = 3073 }.rigDiffers(c.rig))
        #expect(Self.draft(c) { $0.baud = 38400 }.rigDiffers(c.rig))
        #expect(Self.draft(c) { $0.parity = .even }.rigDiffers(c.rig))
        #expect(Self.draft(c) { $0.dtr = .on }.rigDiffers(c.rig))
        #expect(Self.draft(c) { $0.device = "/dev/cu.x" }.rigDiffers(c.rig))
        #expect(!Self.draft(c) { $0.host = " localhost " }.rigDiffers(c.rig))
        #expect(!Self.draft(c) { $0.device = "  " }.rigDiffers(c.rig))
    }

    /// Probe `clusterDiffers`: the port is `toIntOrNull() ?: 1883` without trimming. Kotlin does not compare
    /// `interlock`, `serialServer`, `stationType` and `ruleEnforcement` (pinned).
    @Test func clusterRules() {
        let c = AppConfig()
        let ports: [(String, Bool)] = [("1883", false), (" 1883", false), ("1884", true), ("x", false)]
        for (text, differs) in ports {
            #expect(Self.draft(c) { $0.clusterPort = text }.clusterDiffers(c.cluster) == differs, "\(text)")
        }
        #expect(Self.draft(c) { $0.password = " " }.clusterDiffers(c.cluster))
        #expect(Self.draft(c) { $0.username = "u" }.clusterDiffers(c.cluster))
        #expect(!Self.draft(c) { $0.stationId = "  " }.clusterDiffers(c.cluster))
        #expect(Self.draft(c) { $0.shareSpots.toggle() }.clusterDiffers(c.cluster))
        #expect(!Self.draft(c) { $0.serialServer.toggle() }.clusterDiffers(c.cluster))
        #expect(!Self.draft(c) { $0.interlock = .sameBand }.clusterDiffers(c.cluster))
        #expect(!Self.draft(c) { $0.ruleEnforcement = .block }.clusterDiffers(c.cluster))
    }

    @Test func contestDirComparesTrimmedTextWithConfiguredOrDefault() {
        var c = AppConfig()
        #expect(!Self.draft(c) { $0.contestDataDir = " /data/contest-data " }.contestDirDiffers(c, defaultDir: Self.defaultDir))
        #expect(Self.draft(c) { $0.contestDataDir = "/other" }.contestDirDiffers(c, defaultDir: Self.defaultDir))
        c.contestDataDir = "/own"
        #expect(!Self.draft(c).contestDirDiffers(c, defaultDir: Self.defaultDir))
        #expect(Self.draft(c).contestDirDiffers(AppConfig(), defaultDir: Self.defaultDir))
    }

    @Test func networkPredicates() {
        let c = AppConfig()
        #expect(Self.draft(c) { $0.bcScoreEnabled = true }.broadcastDiffers(c.broadcast))
        #expect(Self.draft(c) { $0.bcAppInfoTargets = "1.2.3.4:12060" }.broadcastDiffers(c.broadcast))
        #expect(!Self.draft(c) { $0.bcRadioTargets = "  " }.broadcastDiffers(c.broadcast))
        #expect(Self.draft(c) { $0.wxSendTargets = "x" }.wsjtxDiffers(c.wsjtx))
        #expect(!Self.draft(c) { $0.wxReceiveBind = " 0.0.0.0:2237 " }.wsjtxDiffers(c.wsjtx))
        #expect(Self.draft(c) { $0.nrReceiveEnabled = true }.n1mmDiffers(c.n1mmRecv))
        #expect(Self.draft(c) { $0.auReceiveBind = "0.0.0.0:1" }.adifUdpDiffers(c.adifUdp))
    }

    /// Kotlin `!=` compares UTF-16 units: a decomposed `é` differs from the precomposed one.
    @Test func comparisonIsByUtf16Units() {
        var c = AppConfig()
        c.station.call = "OK1\u{00E9}"
        #expect(Self.draft(c) { $0.call = "OK1e\u{0301}" }.scoringStationDiffers(c.station))
    }
}
