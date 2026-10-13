import Testing
@testable import MCLCore

/// The band map's programmable buttons (`BandmapButtonCommand`) and the Wide/Narrow filter toggle.
@Suite struct BandmapButtonCommandTests {

    @Test func statesAndLabels() {
        #expect(BandmapButtonCommand.states("{CAT M CW 500} | {CAT M CW 250}") == ["{CAT M CW 500}", "{CAT M CW 250}"])
        #expect(BandmapButtonCommand.states("") == [""])
        #expect(BandmapButtonCommand.stateCount("CW|USB|RTTY") == 3)
        #expect(BandmapButtonCommand.label("Wide|Narrow", state: 1) == "Narrow")
        #expect(BandmapButtonCommand.label("Mode", state: 2) == "Mode")
        #expect(BandmapButtonCommand.label("A|B", state: -1) == "A")
    }

    @Test func steps() {
        #expect(BandmapButtonCommand.steps("{CAT L AF 0.5}{run} 14025 {NOSPLIT}") == [
            .cat("L AF 0.5"), .macro(.run), .text("14025"), .macro(.splitOff),
        ])
        #expect(BandmapButtonCommand.steps("  CW  ") == [.text("CW")])
        #expect(BandmapButtonCommand.steps("14025; CW ;;RIT 100") == [.text("14025"), .text("CW"), .text("RIT 100")])
        #expect(BandmapButtonCommand.steps("{S&P}{CLEARRIT}{RITCLEAR}{CQFREQ}{ALT-Q}{WIPE}{CLRSTACK}") == [
            .macro(.searchAndPounce), .macro(.clearRit), .macro(.clearRit), .macro(.cqFrequency), .macro(.jumpCq),
            .macro(.wipe), .macro(.clearStack),
        ])
        // Macros that transmit or are unknown are refused; an unclosed brace too.
        #expect(BandmapButtonCommand.steps("{F1}{TX}{LOG} {MYCALL") == [
            .refused("{F1}"), .refused("{TX}"), .refused("{LOG}"), .refused("{MYCALL"),
        ])
        #expect(BandmapButtonCommand.steps("").isEmpty)
    }

    @Test func filterWidthToggle() {
        #expect(!FilterWidthToggle.isNarrow(passbandHz: 500, wide: 500, narrow: 250))
        #expect(FilterWidthToggle.isNarrow(passbandHz: 300, wide: 500, narrow: 250))
        #expect(!FilterWidthToggle.isNarrow(passbandHz: 0, wide: 500, narrow: 250))
        #expect(!FilterWidthToggle.isNarrow(passbandHz: 250, wide: 250, narrow: 250))
        #expect(FilterWidthToggle.command(rawMode: "cw", passbandHz: 500, wide: 500, narrow: 250) == "M CW 250")
        #expect(FilterWidthToggle.command(rawMode: "USB", passbandHz: 1_800, wide: 2_400, narrow: 1_800)
            == "M USB 2400")
        #expect(FilterWidthToggle.command(rawMode: " ", passbandHz: 500, wide: 500, narrow: 250) == nil)
        #expect(PluginCatPolicy.refusal("M CW 250") == nil)
    }

    @Test func configurationLimitsAndWidths() throws {
        var config = DxClusterConfig()
        config.bandmapButtons = (0..<40).map { DxClusterCommand(label: String($0), command: "") }
        #expect(config.bandmapButtons.count == 36)
        config.filterSsbWideHz = 30_000
        config.filterCwNarrowHz = -1
        #expect(config.filterSsbWideHz == 20_000)
        #expect(config.filterCwNarrowHz == 0)
        #expect(config.filterWidths(.cw) == (500, 0))
        #expect(config.filterWidths(.fm) == (20_000, 1_800))
        #expect(config.filterWidths(.ft8) == (500, 250))
    }
}
