import Testing
@testable import MCLCore

/// `src/test/kotlin/…/ui/configurer/ScoringStationDiffersTest.kt` — the same five methods and data. After OK in
/// Settings the log is rescored only when a station field the score really uses has changed.
@Suite struct ScoringStationDiffersTests {

    private func config() -> AppConfig {
        var c = AppConfig()
        c.station.call = "OK1DXX"
        c.station.gridSquare = "JN79FX"
        c.station.cqZone = "15"
        c.station.ituZone = "28"
        c.station.roverQth = ""
        c.station.name = "Tomas"
        c.station.power = "100"
        return c
    }

    private func draft(_ c: AppConfig, _ edit: (inout ConfigurerDraft) -> Void = { _ in }) -> ConfigurerDraft {
        var d = ConfigurerDraft(
            config: c, bandSegments: [], digi: DigiFreqFile.Table(channels: []), defaultContestDataDir: "/data")
        edit(&d)
        return d
    }

    @Test func unchangedDraftDoesNotAskForRescore() {
        let c = config()
        #expect(!draft(c).scoringStationDiffers(c.station))
    }

    @Test func locatorChangeAsksForRescore() {
        let c = config()
        let d = draft(c) { $0.grid = "JN79" }
        #expect(d.scoringStationDiffers(c.station))
    }

    @Test func callZonesAndRoverQthAskForRescore() {
        let c = config()
        #expect(draft(c) { $0.call = "OK1XOE" }.scoringStationDiffers(c.station))
        #expect(draft(c) { $0.cqZone = "14" }.scoringStationDiffers(c.station))
        #expect(draft(c) { $0.ituZone = "27" }.scoringStationDiffers(c.station))
        #expect(draft(c) { $0.roverQth = "JEF" }.scoringStationDiffers(c.station))
    }

    @Test func fieldsOutsideScoringDoNotAskForRescore() {
        let c = config()
        #expect(!draft(c) { $0.name = "Někdo jiný" }.scoringStationDiffers(c.station))
        #expect(!draft(c) { $0.power = "5" }.scoringStationDiffers(c.station))
        #expect(!draft(c) { $0.antenna = "GP" }.scoringStationDiffers(c.station))
    }

    @Test func onlyWhitespaceAroundValueIsNotAChange() {
        let c = config()
        #expect(!draft(c) { $0.grid = "  JN79FX  " }.scoringStationDiffers(c.station))
    }
}
