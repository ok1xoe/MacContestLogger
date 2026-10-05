/// What activating an entry window's VFO asks of the hardware (`AppState.activateVfo`, `AS:2286-2307`).
public struct VfoSwitch: Equatable, Sendable {

    public enum Hardware: Equatable, Sendable {
        /// SO2R: OTRSP `focus(rig, stereo)` (when a controller is open); the rigs stay as they are. The status is
        /// `RigTexts.activeRig(rig, hasOtrsp:)` right away.
        case otrspFocus(rig: Int, stereo: Bool)
        /// SO1V/SO2V: CAT `selectVfo(b)` on the active rig (nothing without CAT); the status after the result is
        /// `RigTexts.activeVfo(b:)` / `RigTexts.so2vFailure(_:)`.
        case selectVfo(b: Bool)
    }

    /// The new tuned frequency — the remembered frequency of the VFO when > 0, otherwise unchanged (`nil`).
    public let tunedFreqHz: Int64?
    public let hardware: Hardware
}

/// SO1V / SO2V / SO2R state of v1.1.1 (`AS:2240-2308`): the radio mode from `config.radioMode`, the active VFO (0 = A /
/// rig 1, 1 = B / rig 2), the remembered frequency of each VFO and SO2R stereo.
public struct VfoState: Sendable, Equatable {

    /// `config.radioMode` (`SO1V`, `SO2V`, `SO2R`; anything else = SO1V).
    public private(set) var radioMode: String
    public private(set) var activeVfo: Int = 0
    /// `vfoFreq` — the tuned frequency each VFO had when it was left.
    public private(set) var vfoFreq: [Int64] = [0, 0]
    /// `so2rStereo`.
    public private(set) var stereo = false

    public init(radioMode: String) {
        self.radioMode = radioMode
    }

    public var so2v: Bool { radioMode == "SO2V" }
    public var so2r: Bool { radioMode == "SO2R" }
    /// Two entry windows (SO2V and SO2R).
    public var twoEntryWindows: Bool { so2v || so2r }

    /// `catFor(vfo)` (`AS:142`): rig 2 (index 1) only for VFO B in SO2R.
    public func catIndex(for vfo: Int) -> Int {
        so2r && vfo == 1 ? 1 : 0
    }

    /// `cat` (`AS:139`): the rig the active entry window works with.
    public var activeCatIndex: Int {
        catIndex(for: activeVfo)
    }

    /// `syncRadioModeFromConfig` (`AS:2259-2269`) minus the OTRSP reopen: `true` = without two windows the active VFO is
    /// B, so the model must call `activate(0, force: true, …)` (the forced return to VFO A).
    public mutating func syncRadioMode(_ mode: String) -> Bool {
        radioMode = mode
        return !twoEntryWindows && activeVfo != 0
    }

    /// `activateVfo(vfo, force)` (`AS:2286-2307`): `nil` when `vfo` is already active and not forced. Otherwise the
    /// tuned frequency is stored for the VFO being left and the VFO's own one restored (outside `qsy`).
    public mutating func activate(_ vfo: Int, force: Bool = false, tunedFreqHz: Int64) -> VfoSwitch? {
        if vfo == activeVfo && !force { return nil }
        vfoFreq[activeVfo] = tunedFreqHz
        activeVfo = vfo
        let restored: Int64? = vfoFreq[vfo] > 0 ? vfoFreq[vfo] : nil
        let hardware: VfoSwitch.Hardware = so2r ? .otrspFocus(rig: vfo + 1, stereo: stereo) : .selectVfo(b: vfo == 1)
        return VfoSwitch(tunedFreqHz: restored, hardware: hardware)
    }

    /// `toggleSo2rStereo` (`AS:2279-2283`): the new stereo state; the model sends OTRSP `rx(activeVfo + 1, stereo)`
    /// and shows `RigTexts.so2rStereo(_:)`.
    public mutating func toggleStereo() -> Bool {
        stereo.toggle()
        return stereo
    }
}
