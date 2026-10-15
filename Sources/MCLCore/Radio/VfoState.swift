/// What activating an entry window's VFO asks of the hardware (`AppState.activateVfo`, `AS:2286-2307`).
public struct VfoSwitch: Equatable, Sendable {

    public enum Hardware: Equatable, Sendable {
        /// SO2R: OTRSP `focus(rig, stereo)` (when a controller is open); the rigs stay as they are. The status is
        /// `RigTexts.activeRig(rig, hasOtrsp:)` right away.
        case otrspFocus(rig: Int, stereo: Bool)
        /// SO2R, only the receive (entry) focus moves (N1MM `\`, a click into the window): OTRSP `rx(rig, stereo)`;
        /// the transmit focus stays on its radio.
        case otrspRx(rig: Int, stereo: Bool)
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
///
/// N1MM keeps two foci: the entry (RX, keyboard, green LED) focus — `activeVfo`, the window the operator types in —
/// and the transmit (red LED) focus — `txVfo`, the radio the keyer, the paddle and the PTT key. In SO2R they may sit
/// in different windows; in SO1V / SO2V (one rig) the transmit focus always follows the entry focus.
public struct VfoState: Sendable, Equatable {

    /// `config.radioMode` (`SO1V`, `SO2V`, `SO2R`; anything else = SO1V).
    public private(set) var radioMode: String
    public private(set) var activeVfo: Int = 0
    /// The transmit focus (N1MM's red LED): the VFO / radio that transmits. Equal to `activeVfo` outside SO2R.
    public private(set) var txVfo: Int = 0
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

    /// The rig that transmits: the keyer's CAT keying, the voice keyer's PTT and the footswitch.
    public var txCatIndex: Int {
        catIndex(for: txVfo)
    }

    /// The receive and the transmit focus are in different windows (SO2R only).
    public var fociSplit: Bool {
        txVfo != activeVfo
    }

    /// `syncRadioModeFromConfig` (`AS:2259-2269`) minus the OTRSP reopen: `true` = without two windows the active VFO is
    /// B, so the model must call `activate(0, force: true, …)` (the forced return to VFO A).
    public mutating func syncRadioMode(_ mode: String) -> Bool {
        radioMode = mode
        if !so2r {
            txVfo = activeVfo
        }
        return !twoEntryWindows && activeVfo != 0
    }

    /// `activateVfo(vfo, force)` (`AS:2286-2307`): `nil` when `vfo` is already active and not forced. Otherwise the
    /// tuned frequency is stored for the VFO being left and the VFO's own one restored (outside `qsy`).
    ///
    /// `rxOnly` (SO2R): only the entry focus moves (N1MM `\` and a click); the transmit focus stays. Otherwise both
    /// foci move (v1.1.1, N1MM Pause and Ctrl+←/→). Outside SO2R both always move.
    public mutating func activate(_ vfo: Int, force: Bool = false, tunedFreqHz: Int64,
                                  rxOnly: Bool = false) -> VfoSwitch? {
        if vfo == activeVfo && !force {
            // The entry focus is already here; without `rxOnly` the transmit focus joins it (N1MM Pause, SO2R).
            guard so2r, !rxOnly, txVfo != vfo else { return nil }
            txVfo = vfo
            return VfoSwitch(tunedFreqHz: nil, hardware: .otrspFocus(rig: vfo + 1, stereo: stereo))
        }
        vfoFreq[activeVfo] = tunedFreqHz
        activeVfo = vfo
        let restored: Int64? = vfoFreq[vfo] > 0 ? vfoFreq[vfo] : nil
        let hardware: VfoSwitch.Hardware
        if so2r && rxOnly {
            hardware = .otrspRx(rig: vfo + 1, stereo: stereo)
        } else {
            txVfo = vfo
            hardware = so2r ? .otrspFocus(rig: vfo + 1, stereo: stereo) : .selectVfo(b: vfo == 1)
        }
        return VfoSwitch(tunedFreqHz: restored, hardware: hardware)
    }

    /// N1MM: an F-key, ESM or a typed CW message moves the transmit focus to the window it is sent from (SO2R).
    /// `true` = the focus moved (the model switches OTRSP `TX` and waits the swap times); outside SO2R nothing moves.
    public mutating func claimTx(_ vfo: Int) -> Bool {
        guard so2r, vfo == 0 || vfo == 1, vfo != txVfo else { return false }
        txVfo = vfo
        return true
    }

    /// The inactive VFO was tuned without being activated (the Available window's QSY of the other radio): the
    /// frequency it gets back when it is activated. The active VFO's frequency is the tuned one, not kept here.
    public mutating func setInactiveFrequency(_ freqHz: Int64, vfo index: Int) {
        guard index != activeVfo, vfoFreq.indices.contains(index), freqHz > 0 else { return }
        vfoFreq[index] = freqHz
    }

    /// `toggleSo2rStereo` (`AS:2279-2283`): the new stereo state; the model sends OTRSP `rx(activeVfo + 1, stereo)`
    /// and shows `RigTexts.so2rStereo(_:)`.
    public mutating func toggleStereo() -> Bool {
        stereo.toggle()
        return stereo
    }

    /// `{STEREOON}` / `{STEREOOFF}`.
    public mutating func setStereo(_ on: Bool) {
        stereo = on
    }
}
