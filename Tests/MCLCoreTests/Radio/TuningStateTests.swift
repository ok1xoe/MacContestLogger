import Testing
@testable import MCLCore

/// `TuningState` against `AppState.qsy`/`tuneTo`/`updateTunedFreq`/`returnToPreviousFrequency`/`bandsForStepping`
/// (`AS:487-589`, `AS:811-838`) and the entry-window `stepBand`/`tuneStep`/wheel (`EP:783-804`, `EP:1032-1043`).
@Suite struct TuningStateTests {

    // MARK: - qsy (AS:544-551)

    /// The `previous` rows of the probe: old > 0 and `abs(old - new) > 1000` with Kotlin `Long` wrapping.
    @Test func previousRuleMatchesTheJvm() throws {
        let rows = RigKeyingProbeTable.area("previous")
        #expect(rows.count == 9)
        for row in rows {
            let parts = row.input.split(separator: " ").map(String.init)
            let old = try #require(Int64(parts[0]))
            let new = try #require(Int64(parts[1]))
            var state = TuningState()
            if old > 0 {
                _ = state.qsy(old)
            } else {
                _ = state.updateTuned(old)
            }
            #expect(state.tunedFreqHz == old)
            let before = state.previousFreqHz
            _ = state.qsy(new)
            let set = state.previousFreqHz == old && before != old
            #expect(String(set) == row.result, "\(row.input)")
        }
    }

    @Test func qsyRemembersThePreviousOnlyForJumpsOverOneKilohertz() {
        var state = TuningState()
        #expect(state.qsy(14_025_000) == TuneEffect(rig: 14_025_000))
        #expect(state.previousFreqHz == 0) // the old frequency was 0
        _ = state.qsy(14_026_000) // exactly 1 kHz — not remembered
        #expect(state.previousFreqHz == 0)
        _ = state.qsy(14_030_000)
        #expect(state.previousFreqHz == 14_026_000)
        #expect(state.tunedFreqHz == 14_030_000)
    }

    /// Both halves: the local state is Kotlin's (tuned 0, previous remembered), nothing goes to CAT.
    @Test func qsyToZeroOrBelowIsLocalOnly() {
        var state = TuningState()
        _ = state.qsy(7_010_000)
        let effect = state.qsy(0)
        #expect(effect.rig == nil)
        #expect(state.tunedFreqHz == 0)
        #expect(state.previousFreqHz == 7_010_000)
        let negative = state.qsy(-5)
        #expect(negative.rig == nil)
        #expect(state.tunedFreqHz == -5)
        #expect(state.previousFreqHz == 7_010_000) // the old one was 0, not > 0
    }

    @Test func qsyDoesNotTouchLastFrequencyOnBand() {
        var state = TuningState()
        _ = state.qsy(14_025_000)
        #expect(state.lastFrequency(on: .m20) == nil)
    }

    // MARK: - tuneTo (AS:827-831)

    @Test func tuneToIgnoresZeroAndKeepsThePrevious() {
        var state = TuningState()
        _ = state.qsy(14_025_000)
        _ = state.qsy(7_000_000)
        #expect(state.tuneTo(0) == nil)
        #expect(state.tuneTo(-1) == nil)
        #expect(state.tunedFreqHz == 7_000_000)
        #expect(state.tuneTo(7_050_000) == TuneEffect(rig: 7_050_000))
        #expect(state.tunedFreqHz == 7_050_000)
        #expect(state.previousFreqHz == 14_025_000) // a tuning step never writes the previous frequency
    }

    // MARK: - updateTunedFreq (AS:582-588)

    @Test func updateTunedRemembersTheBandAndSelectsAnAntennaOnlyOnABandChange() {
        var state = TuningState()
        #expect(state.updateTuned(14_025_000) == .m20)
        #expect(state.lastFrequency(on: .m20) == 14_025_000)
        #expect(state.updateTuned(14_030_000) == nil) // same band
        #expect(state.lastFrequency(on: .m20) == 14_030_000)
        #expect(state.updateTuned(7_010_000) == .m40)
        #expect(state.updateTuned(5_000_000) == nil) // out of any band — nothing remembered
        #expect(state.tunedFreqHz == 5_000_000)
        #expect(state.antennaBand == .m40)
        #expect(state.updateTuned(14_000_000) == .m20)
    }

    // MARK: - Alt+F8 (AS:817-823)

    @Test func returnToPreviousTogglesThereAndBack() {
        var state = TuningState()
        #expect(state.returnToPrevious() == nil)
        #expect(RigTexts.noPreviousFrequency.czech == "Alt+F8: žádná předchozí frekvence")
        _ = state.qsy(14_025_000)
        _ = state.qsy(21_010_000)
        #expect(state.returnToPrevious() == TuneEffect(rig: 14_025_000))
        #expect(state.tunedFreqHz == 14_025_000)
        #expect(state.previousFreqHz == 21_010_000)
        #expect(state.returnToPrevious() == TuneEffect(rig: 21_010_000))
        #expect(state.previousFreqHz == 14_025_000)
    }

    // MARK: - band stepping (AS:834-837, EP:783-795)

    @Test func bandsForSteppingDropsWarcAndOutsideAContestStopsAt10m() {
        #expect(TuningState.bandsForStepping(contestBands: nil)
                == [.m160, .m80, .m40, .m20, .m15, .m10])
        #expect(TuningState.bandsForStepping(contestBands: [.m80, .m30, .m6, .m2])
                == [.m80, .m6, .m2])
    }

    @Test func stepBandGoesToTheLastFrequencyOnTheBandElseTheSegmentOfTheMode() {
        var state = TuningState()
        let allowed = TuningState.bandsForStepping(contestBands: nil)
        #expect(state.stepBand(from: .m20, mode: .cw, allowed: allowed, direction: 1) == 21_000.0)
        #expect(state.stepBand(from: .m20, mode: .ssb, allowed: allowed, direction: 1) == 21_200.0)
        #expect(state.stepBand(from: .m20, mode: .fm, allowed: allowed, direction: -1) == 7_060.0)
        #expect(state.stepBand(from: .m20, mode: .rtty, allowed: allowed, direction: -1) == 7_040.0)
        #expect(state.stepBand(from: .m20, mode: .ft8, allowed: allowed, direction: -1) == 7_074.0)
        _ = state.updateTuned(21_025_500)
        #expect(state.stepBand(from: .m20, mode: .cw, allowed: allowed, direction: 1) == 21_025.5)
        // Wraps around (floorMod) and the nearest band when the current one is not allowed.
        #expect(state.stepBand(from: .m10, mode: .cw, allowed: allowed, direction: 1) == 1_810.0)
        #expect(state.stepBand(from: .m17, mode: .cw, allowed: allowed, direction: 1) == 21_025.5)
        #expect(state.stepBand(from: nil, mode: .cw, allowed: allowed, direction: -1) == 28_000.0)
        #expect(state.stepBand(from: .m20, mode: .cw, allowed: [], direction: 1) == nil)
    }

    /// 30 m has no phone segment and 60 m no RTTY segment: CW is the fallback (`?: r.cwKHz`).
    @Test func stepBandFallsBackToTheCwSegment() {
        let state = TuningState()
        #expect(state.stepBand(from: .m40, mode: .ssb, allowed: [.m40, .m30], direction: 1) == 10_100.0)
        #expect(state.stepBand(from: .m80, mode: .rtty, allowed: [.m80, .m60], direction: 1) == 5_352.0)
    }

    // MARK: - arrows and wheel (EP:798-804, EP:1032-1043)

    @Test func tuneStepUsesTheConfiguredStepOfTheMode() {
        #expect(TuningState.tuneStepHz(.ssb, cwHz: 20, ssbHz: 100) == 100)
        #expect(TuningState.tuneStepHz(.am, cwHz: 20, ssbHz: 100) == 100)
        #expect(TuningState.tuneStepHz(.rtty, cwHz: 20, ssbHz: 100) == 20)
        // ↑ = −1 (N1MM: up tunes down), ↓ = +1.
        #expect(TuningState.tuneStep(fieldHz: 14_025_000, mode: .cw, direction: -1, cwHz: 20, ssbHz: 100)
                == 14_024_980)
        #expect(TuningState.tuneStep(fieldHz: 14_200_000, mode: .ssb, direction: 1, cwHz: 20, ssbHz: 100)
                == 14_200_100)
        #expect(TuningState.tuneStep(fieldHz: 0, mode: .cw, direction: 1, cwHz: 20, ssbHz: 100) == nil)
        // The field may go to ≤ 0; `tuneTo` then refuses it.
        #expect(TuningState.tuneStep(fieldHz: 10, mode: .cw, direction: -1, cwHz: 20, ssbHz: 100) == -10)
    }

    @Test func wheelDelegatesToFrequencySteps() {
        #expect(TuningState.wheel(fieldHz: 14_025_000, mode: .cw, direction: 1, alt: false, ctrl: false)
                == 14_025_020)
        #expect(TuningState.wheel(fieldHz: 14_025_000, mode: .ssb, direction: -1, alt: false, ctrl: false)
                == 14_024_900)
        #expect(TuningState.wheel(fieldHz: 14_025_300, mode: .cw, direction: 1, alt: true, ctrl: false)
                == 14_026_000)
        #expect(TuningState.wheel(fieldHz: 14_025_300, mode: .cw, direction: -1, alt: false, ctrl: true)
                == 14_020_000)
        #expect(TuningState.wheel(fieldHz: 14_025_300, mode: .cw, direction: 1, alt: true, ctrl: true)
                == 14_100_000)
        #expect(TuningState.wheel(fieldHz: 14_025_000, mode: .cw, direction: 0, alt: false, ctrl: false) == nil)
        #expect(TuningState.wheel(fieldHz: 0, mode: .cw, direction: 1, alt: false, ctrl: false) == nil)
    }
}
