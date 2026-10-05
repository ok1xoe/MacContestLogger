import Foundation
import MCLCore

/// Tuning (`AS:544-551, 582-588, 811-838`): the shared tuned frequency, the previous one, the last one per band, and
/// the CAT half on the active rig's lane.
extension RigModel {

    /// The band of the tuned frequency (Kotlin `currentBand`).
    public var currentBand: Band? {
        Band.from(frequencyHz: Int(clamping: tuning.tunedFreqHz))
    }

    /// Kotlin `qsy(freqHz, mode, call)`: the previous frequency rule, the tuned frequency, `cat.tune` and
    /// `cat.setMode`, and `prefillCall = call` (the active entry window takes it as a call from a spot).: a
    /// frequency ≤ 0 is applied locally as Kotlin does, nothing reaches CAT. Never transmits.
    public func qsy(_ freqHz: Int64, mode: Mode? = nil, call: String? = nil) {
        qsy(freqHz, mode: mode, prefill: call.map { SpotPrefill(call: $0, exchange: JavaLinkedMap()) })
    }

    /// `qsy` with the prefill of a spot (`tuneToSpot`). Kotlin sets `tunedFreqHz` and `prefillCall` in one go and the
    /// entry windows' effects run afterwards in their order: the prefill reaches the active window before the
    /// tuning effects (the self-spot tracker then sees a call from a spot).
    func qsy(_ freqHz: Int64, mode: Mode?, prefill: SpotPrefill?) {
        var next: TuningState = tuning
        let effect: TuneEffect = next.qsy(freqHz)
        setTuning(next) {
            if let prefill {
                self.prefillActiveEntry(prefill)
            }
        }
        guard let rigHz = effect.rig else { return }
        activeLane.run { cat in
            try? cat.tune(rigHz)
        }
        if let mode {
            setMode(mode, freqHz: rigHz)
        }
    }

    /// Kotlin `tuneTo(freqHz)` (arrows, wheel): ≤ 0 does nothing; the previous frequency is untouched.
    public func tuneTo(_ freqHz: Int64) {
        var next: TuningState = tuning
        guard let effect = next.tuneTo(freqHz) else { return }
        setTuning(next)
        if let rigHz = effect.rig {
            activeLane.run { cat in
                try? cat.tune(rigHz)
            }
        }
    }

    /// Kotlin `returnToPreviousFrequency()` (Alt+F8): there and back again.
    public func returnToPrevious() {
        guard tuning.previousFreqHz > 0 else {
            show(RigTexts.noPreviousFrequency)
            return
        }
        qsy(tuning.previousFreqHz)
    }

    /// Kotlin `cat.setMode(mode, freqHz)` on the active rig.
    public func setMode(_ mode: Mode, freqHz: Int64) {
        activeLane.run { cat in
            try? cat.setMode(mode, freqHz: freqHz)
        }
    }

    /// Kotlin `updateTunedFreq(freqHz)`: only the shared frequency (a CAT poll, the frequency field), never the rig;
    /// a new band selects its antenna.
    public func updateTuned(_ freqHz: Int64) {
        var next: TuningState = tuning
        let band: Band? = next.updateTuned(freqHz)
        setTuning(next)
        if let band {
            autoSelectAntenna(band)
        }
    }

    /// Kotlin `bandsForStepping()`: the entry grid's bands (`entryGridBands()`, the BAND category) without WARC,
    /// outside a contest every band up to 10 m.
    public func bandsForStepping() -> [Band] {
        let grid: [Band]? = contest.isActive
            ? Band.allCases.filter { EntryGrid.of(contest).enabledBands.contains($0) } : nil
        return TuningState.bandsForStepping(contestBands: grid)
    }

    /// Sets the tuning; a changed tuned frequency reaches the entry windows (Kotlin `LaunchedEffect(tunedFreqHz)`).
    /// `beforeEffects` runs between the two (a spot's prefill, `qsy(…, call)`).
    func setTuning(_ next: TuningState, beforeEffects: () -> Void = {}) {
        let changed: Bool = next.tunedFreqHz != tuning.tunedFreqHz
        tuning = next
        beforeEffects()
        if changed {
            notifyEntries { $0.rigTunedChanged() }
        }
    }
}
