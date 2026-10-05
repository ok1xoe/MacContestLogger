import Testing
@testable import MCLCore

/// `RitState` (`AS:2316-2335`, `AS:2797`), `VfoState` (`AS:2240-2307`, `AS:130-143`) and `RigTexts` (`tr` vs.
/// verbatim as Kotlin).
@Suite struct RitVfoStateTests {

    // MARK: - RIT

    @Test func ritIsClampedToPlusMinus9999() {
        #expect(RitState.clamp(12_000) == 9_999)
        #expect(RitState.clamp(-10_000) == -9_999)
        #expect(RitState.clamp(-9_999) == -9_999)
        #expect(RitState.clamp(150) == 150)
    }

    @Test func ritStepsByTheModeStepFromTheLastAppliedValue() {
        var rit = RitState()
        #expect(rit.step(direction: 1, stepHz: TuningState.tuneStepHz(.cw, cwHz: 20, ssbHz: 100)) == 20)
        rit.applied(9_990)
        #expect(rit.step(direction: 1, stepHz: 20) == 9_999)
        #expect(rit.step(direction: -1, stepHz: 100) == 9_890)
        // Kotlin `Int` arithmetic: the step is `toInt()` of the `Long`, the sum wraps before the clamp.
        rit.applied(9_999)
        #expect(rit.step(direction: 1, stepHz: Int64(Int32.max)) == -9_999)
        #expect(rit.step(direction: 1, stepHz: Int64(UInt32.max) + 21) == 9_999) // `toInt()` = 20
    }

    /// `ritHz` changes only on success (`applied`), so a failed `setRit` keeps the last value.
    @Test func ritHzIsTheLastAppliedValue() {
        var rit = RitState()
        #expect(rit.ritHz == 0)
        rit.applied(-40)
        #expect(rit.ritHz == -40)
    }

    @Test func ritClearsAfterLogOnlyWhenEnabledAndNonZero() {
        var rit = RitState()
        #expect(!rit.clearAfterLog(enabled: true))
        rit.applied(20)
        #expect(rit.clearAfterLog(enabled: true))
        #expect(!rit.clearAfterLog(enabled: false))
    }

    @Test func ritTexts() {
        #expect(RigTexts.rit(0) == .verbatim("RIT vypnut"))
        #expect(RigTexts.rit(40) == .verbatim("RIT +40 Hz"))
        #expect(RigTexts.rit(-9_999) == .verbatim("RIT -9999 Hz"))
        #expect(RigTexts.ritFailure("Timeout") == .verbatim("RIT: Timeout"))
        #expect(RigTexts.ritNeedsCat == .tr("RIT: připoj TRX (CAT)"))
    }

    // MARK: - VFO / SO2V / SO2R

    @Test func radioModeFlags() {
        #expect(!VfoState(radioMode: "SO1V").twoEntryWindows)
        #expect(VfoState(radioMode: "SO2V").so2v)
        #expect(VfoState(radioMode: "SO2V").twoEntryWindows)
        #expect(VfoState(radioMode: "SO2R").so2r)
        #expect(!VfoState(radioMode: "so2r").so2r) // Kotlin compares exactly
        #expect(!VfoState(radioMode: "").twoEntryWindows)
    }

    @Test func catIndexIsRig2OnlyForVfoBInSo2r() {
        #expect(VfoState(radioMode: "SO2R").catIndex(for: 1) == 1)
        #expect(VfoState(radioMode: "SO2R").catIndex(for: 0) == 0)
        #expect(VfoState(radioMode: "SO2V").catIndex(for: 1) == 0)
        var so2r = VfoState(radioMode: "SO2R")
        #expect(so2r.activeCatIndex == 0)
        _ = so2r.activate(1, tunedFreqHz: 14_000_000)
        #expect(so2r.activeCatIndex == 1)
    }

    @Test func activateStoresAndRestoresTheVfoFrequency() throws {
        var vfo = VfoState(radioMode: "SO2V")
        #expect(vfo.activate(0, tunedFreqHz: 14_025_000) == nil) // already active, not forced
        let toBSwitch = vfo.activate(1, tunedFreqHz: 14_025_000)
        let toB = try #require(toBSwitch)
        #expect(toB.tunedFreqHz == nil) // B has no frequency yet — the tuned one stays
        #expect(toB.hardware == .selectVfo(b: true))
        #expect(vfo.vfoFreq == [14_025_000, 0])
        let toASwitch = vfo.activate(0, tunedFreqHz: 14_030_000)
        let toA = try #require(toASwitch)
        #expect(toA.tunedFreqHz == 14_025_000)
        #expect(toA.hardware == .selectVfo(b: false))
        #expect(vfo.vfoFreq == [14_025_000, 14_030_000])
        #expect(vfo.activate(1, tunedFreqHz: 14_026_000)?.tunedFreqHz == 14_030_000)
    }

    @Test func so2rActivationFocusesTheOtrspRigWithStereo() throws {
        var vfo = VfoState(radioMode: "SO2R")
        let result13 = vfo.toggleStereo()
        #expect(result13)
        let toRig2Switch = vfo.activate(1, tunedFreqHz: 7_000_000)
        let toRig2 = try #require(toRig2Switch)
        #expect(toRig2.hardware == .otrspFocus(rig: 2, stereo: true))
        let result14 = vfo.toggleStereo()
        #expect(!result14)
        #expect(RigTexts.activeRig(2, hasOtrsp: true).czech == "Aktivní rig 2")
        #expect(RigTexts.activeRig(2, hasOtrsp: false).czech == "Aktivní rig 2 (bez OTRSP kontroléru)")
        #expect(RigTexts.activeRig(2, hasOtrsp: false)
                == EntryStatus.tr("Aktivní rig %s", .int(2)).appending(.verbatim(" (bez OTRSP kontroléru)")))
    }

    /// Losing the two windows while VFO B is active forces a return to VFO A (`AS:2268`).
    @Test func syncRadioModeForcesTheReturnToVfoA() throws {
        var vfo = VfoState(radioMode: "SO2V")
        let result15 = vfo.syncRadioMode("SO2V")
        #expect(!result15)
        _ = vfo.activate(1, tunedFreqHz: 14_000_000)
        let result16 = vfo.syncRadioMode("SO2R")
        #expect(!result16) // still two windows
        let result17 = vfo.syncRadioMode("SO1V")
        #expect(result17)
        let backSwitch = vfo.activate(0, force: true, tunedFreqHz: 14_010_000)
        let back = try #require(backSwitch)
        #expect(back.tunedFreqHz == 14_000_000)
        #expect(back.hardware == .selectVfo(b: false))
        let result18 = vfo.syncRadioMode("SO1V")
        #expect(!result18)
        // Forced on the active VFO still re-selects it.
        #expect(vfo.activate(0, force: true, tunedFreqHz: 14_010_000) != nil)
    }

    @Test func vfoTexts() {
        #expect(RigTexts.activeVfo(b: true) == .tr("Aktivní VFO %s", .string("B")))
        #expect(RigTexts.so2vFailure("x") == .tr("SO2V: %s", .string("x")))
        #expect(RigTexts.so2rStereo(true) == .verbatim("SO2R: stereo (oba rigy)"))
        #expect(RigTexts.so2rStereo(false) == .tr("SO2R: poslech jen aktivního rigu"))
        #expect(RigTexts.so2rOpenFailure("busy") == .verbatim("SO2R: busy"))
        #expect(RigTexts.otherVfoDone(14_025_050) == .verbatim("VFO B 14025.1 kHz"))
        #expect(RigTexts.splitOn(txFreqHz: 14_027_000) == .tr("Split: vysílám na %s", .string("14027.0 kHz")))
        #expect(RigTexts.splitOn(txFreqHz: 0) == .tr("Split zapnut (vysílám na VFO B)"))
        #expect(RigTexts.splitOff == .verbatim("Split vypnut"))
        #expect(RigTexts.swapped == .verbatim("VFO A ↔ B prohozena"))
        #expect(RigTexts.vfoNeedsCat("Split").czech
                == "Split: připoj TRX (CAT) — bez něj druhé VFO ani split nejdou")
        #expect(RigTexts.vfoFailure("SWAP", "RPRT -1") == .verbatim("SWAP: RPRT -1"))
        #expect(RigTexts.splitInvalid("x").czech == "Split: neplatná frekvence „x“")
    }

    @Test func otherRigTexts() {
        #expect(RigTexts.noCqOnBand(.m20).czech == "Na pásmu 20m zatím nebylo CQ")
        #expect(RigTexts.noCqOnBand(nil).czech == "Na pásmu  zatím nebylo CQ")
        #expect(RigTexts.runModeToggled(run: true, freqHz: 14_025_000) == .verbatim("Run (CQ frekvence 14025.0 kHz)"))
        #expect(RigTexts.runModeToggled(run: false, freqHz: 0) == .verbatim("S&P"))
        #expect(RigTexts.tuneFailure("x").czech == "Ladění: x")
        #expect(RigTexts.interfacesReset(wasConnected: true).czech == "Rozhraní resetována — připojuji TRX znovu")
        #expect(RigTexts.interfacesReset(wasConnected: false).czech
                == "Rozhraní resetována (CW klíč se otevře při dalším vysílání)")
        #expect(RigTexts.footswitchFailure(nil) == .tr("Footswitch nejde otevřít"))
        #expect(RigTexts.footswitchFailure("port busy") == .verbatim("port busy"))
    }
}
