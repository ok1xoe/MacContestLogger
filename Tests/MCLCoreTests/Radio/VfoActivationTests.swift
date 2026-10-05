import Testing
@testable import MCLCore

/// `VfoActivation` (Kotlin `AppState.activateVfo`, `AS:2296-2315`) and `BandStepping` (the entry window's `stepBand`
/// and its `qsy(toKHz, toMode)`, `EP:611-621`, `EP:782-795`): the compositions `RigModel.activateVfo` and
/// `EntryModel.stepBand` call.
@Suite struct VfoActivationTests {

    // MARK: - VfoActivation

    @Test func theActiveVfoUnforcedChangesNothing() {
        var vfo = VfoState(radioMode: "SO2V")
        var tuning = TuningState()
        _ = tuning.qsy(14_025_000)
        let before: (VfoState, TuningState) = (vfo, tuning)
        #expect(VfoActivation.apply(&vfo, &tuning, index: 0, force: false, hasOtrsp: true) == nil)
        #expect(vfo == before.0)
        #expect(tuning == before.1)
    }

    /// SO2V: the VFO being left keeps the tuned frequency; VFO B has none yet, so the tuned one stays. Back on A its
    /// own frequency is restored through `tuneTo` — the previous frequency (Kotlin's `qsy` rule) does not move.
    @Test func so2vStoresAndRestoresThroughTuneTo() throws {
        var vfo = VfoState(radioMode: "SO2V")
        var tuning = TuningState()
        _ = tuning.qsy(14_025_000)
        let toB = try #require(VfoActivation.apply(&vfo, &tuning, index: 1, force: false, hasOtrsp: false))
        #expect(toB == VfoActivation.Outcome(hardware: .selectVfo(b: true), restoredFreqHz: nil, status: nil))
        #expect(vfo.activeVfo == 1)
        #expect(vfo.vfoFreq == [14_025_000, 0])
        #expect(tuning.tunedFreqHz == 14_025_000)
        _ = tuning.qsy(7_010_000)
        #expect(tuning.previousFreqHz == 14_025_000)
        _ = tuning.qsy(3_510_000)
        #expect(tuning.previousFreqHz == 7_010_000)
        let toA = try #require(VfoActivation.apply(&vfo, &tuning, index: 0, force: false, hasOtrsp: false))
        #expect(toA == VfoActivation.Outcome(hardware: .selectVfo(b: false), restoredFreqHz: 14_025_000, status: nil))
        #expect(vfo.vfoFreq == [14_025_000, 3_510_000])
        #expect(tuning.tunedFreqHz == 14_025_000)
        #expect(tuning.previousFreqHz == 7_010_000) // `tuneTo`, not `qsy`
        #expect(tuning.lastFrequency(on: .m20) == nil) // no CAT poll, no last-on-band entry
    }

    /// A forced activation of the active VFO (the return to VFO A of `syncRadioModeFromConfig`) runs.
    @Test func aForcedActivationOfTheActiveVfoRuns() throws {
        var vfo = VfoState(radioMode: "SO1V")
        var tuning = TuningState()
        _ = tuning.qsy(21_030_000)
        let outcome = try #require(VfoActivation.apply(&vfo, &tuning, index: 0, force: true, hasOtrsp: false))
        #expect(outcome.restoredFreqHz == 21_030_000)
        #expect(outcome.hardware == .selectVfo(b: false))
        #expect(tuning.tunedFreqHz == 21_030_000)
    }

    /// SO2R: the OTRSP focus with the stereo bit and the status at once, with and without a controller.
    @Test func so2rFocusesOtrspAndShowsTheActiveRig() throws {
        var vfo = VfoState(radioMode: "SO2R")
        var tuning = TuningState()
        _ = tuning.qsy(7_010_000)
        _ = vfo.toggleStereo()
        let toRig2 = try #require(VfoActivation.apply(&vfo, &tuning, index: 1, force: false, hasOtrsp: true))
        #expect(toRig2.hardware == .otrspFocus(rig: 2, stereo: true))
        #expect(toRig2.status == RigTexts.activeRig(2, hasOtrsp: true))
        #expect(toRig2.status?.czech == "Aktivní rig 2")
        #expect(vfo.activeCatIndex == 1)
        let toRig1 = try #require(VfoActivation.apply(&vfo, &tuning, index: 0, force: false, hasOtrsp: false))
        #expect(toRig1.status?.czech == "Aktivní rig 1 (bez OTRSP kontroléru)")
        #expect(toRig1.restoredFreqHz == 7_010_000)
    }

    // MARK: - BandStepping

    @Test func aBandStepEndsInTheRoundedQsyFrequency() throws {
        var tuning = TuningState()
        let allowed: [Band] = TuningState.bandsForStepping(contestBands: nil)
        let segment = try #require(BandStepping.target(tuning: tuning, band: .m20, mode: .ssb, allowed: allowed,
                                                       direction: 1))
        #expect(segment == BandStepping.Target(kHz: 21_200.0, hz: 21_200_000))
        _ = tuning.updateTuned(21_025_500)
        #expect(BandStepping.qsyTarget(tuning: tuning, band: .m20, mode: .cw, allowed: allowed, direction: 1)
                == 21_025_500)
        #expect(BandStepping.qsyTarget(tuning: tuning, band: .m20, mode: .cw, allowed: [], direction: 1) == nil)
    }

    /// `Math.round(toKHz * 1000.0)`: to the nearest (towards +∞ for negatives too), `NaN` → 0, saturating. A last
    /// frequency whose kHz value is not exact in binary comes back to the same Hz.
    @Test func theQsyConversionIsMathRound() {
        #expect(BandStepping.qsyHz(kHz: 14_025.0004) == 14_025_000)
        #expect(BandStepping.qsyHz(kHz: 14_025.0006) == 14_025_001)
        #expect(BandStepping.qsyHz(kHz: -0.0004) == 0)
        #expect(BandStepping.qsyHz(kHz: -0.0006) == -1)
        #expect(BandStepping.qsyHz(kHz: .nan) == 0)
        #expect(BandStepping.qsyHz(kHz: 1e300) == Int64.max)
        #expect(BandStepping.qsyHz(kHz: -1e300) == Int64.min)
        for hz: Int64 in [1_810_001, 3_799_999, 14_025_301, 28_123_457, 144_300_001] {
            #expect(BandStepping.qsyHz(kHz: Double(hz) / 1000.0) == hz)
        }
    }
}
