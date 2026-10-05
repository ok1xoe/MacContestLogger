import Testing
@testable import MCLCore

/// Port of the Java `RadioNavigationTest` (4 tests, same names): `FrequencySteps`
/// and `SpotNavigator` over a minimal `DxSpot`.
@Suite struct RadioNavigationTests {

    @Test func arrowStepDependsOnMode() {
        #expect(FrequencySteps.stepHz(.cw) == 20)
        #expect(FrequencySteps.stepHz(.ssb) == 100)
        #expect(FrequencySteps.stepHz(.ft8) == 20)
    }

    @Test func wheelWithModifiersRoundsToNextRoundFrequency() {
        #expect(FrequencySteps.wheel(14_025_300, mode: .cw, notches: 1, alt: false, ctrl: false) == 14_025_320)
        #expect(FrequencySteps.wheel(14_025_300, mode: .ssb, notches: -2, alt: false, ctrl: false) == 14_025_100)
        #expect(FrequencySteps.wheel(14_025_300, mode: .cw, notches: 1, alt: true, ctrl: false) == 14_026_000)
        #expect(FrequencySteps.wheel(14_025_300, mode: .cw, notches: -1, alt: true, ctrl: false) == 14_025_000)
        #expect(
            FrequencySteps.wheel(14_025_000, mode: .cw, notches: -1, alt: true, ctrl: false) == 14_024_000,
            "from a round number one step further"
        )
        #expect(FrequencySteps.wheel(14_025_300, mode: .cw, notches: 1, alt: false, ctrl: true) == 14_030_000)
        #expect(FrequencySteps.wheel(14_025_300, mode: .cw, notches: 1, alt: true, ctrl: true) == 14_100_000)
        #expect(FrequencySteps.wheel(14_025_300, mode: .cw, notches: 3, alt: true, ctrl: false) == 14_028_000)
    }

    @Test func bandStepSkipsBandsOutsideTheContestAndWraps() {
        let contest: [Band] = [.m160, .m80, .m40, .m20, .m15, .m10]

        #expect(FrequencySteps.nextBand(.m20, allowed: contest, direction: 1) == .m15)
        #expect(FrequencySteps.nextBand(.m20, allowed: contest, direction: -1) == .m40)
        #expect(FrequencySteps.nextBand(.m10, allowed: contest, direction: 1) == .m160, "wraps around")
        #expect(FrequencySteps.nextBand(.m30, allowed: contest, direction: 1) == .m20, "from WARC to the nearest")
        #expect(FrequencySteps.isWarc(.m17))
    }

    @Test func nextSpotAboveAndBelowOnSameBand() throws {
        let spots: [DxSpot] = [
            DxSpot(spotter: "S", freqHz: 14_020_000, dxCall: "A1A", comment: ""),
            DxSpot(spotter: "S", freqHz: 14_030_000, dxCall: "B1B", comment: ""),
            DxSpot(spotter: "S", freqHz: 14_025_020, dxCall: "HERE", comment: ""), // here — skipped
            DxSpot(spotter: "S", freqHz: 7_025_000, dxCall: "OTHERBAND", comment: ""),
            DxSpot(spotter: "S", freqHz: 14_040_000, dxCall: "SELF", comment: "", selfSpotted: true),
        ]

        let above = try #require(SpotNavigator.next(spots, freqHz: 14_025_000, direction: 1) { _ in true })
        #expect(above.dxCall == "B1B")
        let below = try #require(SpotNavigator.next(spots, freqHz: 14_025_000, direction: -1) { _ in true })
        #expect(below.dxCall == "A1A")
        let selfSpot = try #require(SpotNavigator.next(spots, freqHz: 14_025_000, direction: 1) { $0.selfSpotted })
        #expect(selfSpot.dxCall == "SELF")
        #expect(SpotNavigator.next(spots, freqHz: 14_045_000, direction: 1) { _ in true } == nil)
    }
}
