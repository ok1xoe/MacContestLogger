/// Kotlin `AppState.activateVfo(vfo, force)` (`AS:2296-2315`) as one core step: the VFO state, the restored tuned
/// frequency and the immediate status. The app model only performs the hardware half (`hardware`) on its lanes.
public enum VfoActivation {

    public struct Outcome: Equatable, Sendable {
        /// What the switch asks of the hardware (OTRSP focus in SO2R, CAT `selectVfo` otherwise).
        public let hardware: VfoSwitch.Hardware
        /// The VFO's own frequency, now the tuned one (`tunedFreqHz = it` — no QSY, no previous frequency, no rig);
        /// `nil` = the tuned frequency is unchanged.
        public let restoredFreqHz: Int64?
        /// The status shown at once: SO2R `tr("Aktivní rig %s")` (+ „ (bez OTRSP kontroléru)"). `nil` for SO1V/SO2V,
        /// whose status follows the CAT result (`RigTexts.activeVfo` / `RigTexts.so2vFailure`).
        public let status: EntryStatus?

        public init(hardware: VfoSwitch.Hardware, restoredFreqHz: Int64?, status: EntryStatus?) {
            self.hardware = hardware
            self.restoredFreqHz = restoredFreqHz
            self.status = status
        }
    }

    /// `activateVfo(index, force)`: `nil` when `index` is already active and not forced (nothing changes). Otherwise
    /// the tuned frequency is stored for the VFO being left, the new VFO becomes active and its own frequency (> 0)
    /// is restored into `tuning` through `tuneTo`. `hasOtrsp` = an OTRSP controller is open (Kotlin `otrsp != null`).
    public static func apply(_ vfo: inout VfoState, _ tuning: inout TuningState, index: Int, force: Bool,
                             hasOtrsp: Bool) -> Outcome? {
        guard let change = vfo.activate(index, force: force, tunedFreqHz: tuning.tunedFreqHz) else { return nil }
        if let restored = change.tunedFreqHz {
            _ = tuning.tuneTo(restored)
        }
        let status: EntryStatus?
        switch change.hardware {
        case .otrspFocus(let rig, _):
            status = RigTexts.activeRig(rig, hasOtrsp: hasOtrsp)
        case .selectVfo:
            status = nil
        }
        return Outcome(hardware: change.hardware, restoredFreqHz: change.tunedFreqHz, status: status)
    }
}
