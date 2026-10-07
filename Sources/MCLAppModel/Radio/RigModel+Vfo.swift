import Foundation
import MCLCore

/// VFO B, split, RIT, SO2V/SO2R, antennas and the footswitch PTT (`AS:636-665, 767-797, 957-981, 2239-2354`).
extension RigModel {

    // MARK: - VFO B and split

    /// Kotlin `vfoOperation(label, done, op)`: without CAT `tr("%s: připoj TRX (CAT) — bez něj druhé VFO ani split
    /// nejdou")`; otherwise the operation on the active rig's lane, then `done` or `"$label: ${it.message}"`.
    func vfoOperation(_ label: String, done: EntryStatus,
                      _ op: @escaping @Sendable (any RigController) throws -> Void) {
        guard active.connected else {
            show(RigTexts.vfoNeedsCat(label))
            return
        }
        activeLane.run({ cat in
            RigOutcome.run(cat, op)
        }, then: { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .done:
                self.show(done)
            case .noRig:
                self.show(RigTexts.vfoNeedsCat(label))
            case .failed(let message):
                self.show(RigTexts.vfoFailure(label, message))
            }
        })
    }

    /// `/14030`: the frequency of VFO B, no split.
    public func setOtherVfo(_ freqHz: Int64) {
        vfoOperation(RigTexts.otherVfoLabel, done: RigTexts.otherVfoDone(freqHz)) { rig in
            try rig.setOtherVfoFrequencyHz(freqHz)
        }
    }

    /// Alt+F12: the tuned frequency into VFO B.
    public func copyToVfoB() {
        setOtherVfo(tuning.tunedFreqHz)
    }

    /// Ctrl+Enter with a frequency / SPLIT: transmit on VFO B (`txFreqHz` 0 = keep its frequency).
    public func setSplit(_ txFreqHz: Int64) {
        vfoOperation(RigTexts.splitLabel, done: RigTexts.splitOn(txFreqHz: txFreqHz)) { rig in
            try rig.setSplit(true, txFreqHz: txFreqHz)
        }
    }

    /// NOSPLIT.
    public func splitOff() {
        vfoOperation(RigTexts.splitLabel, done: RigTexts.splitOff) { rig in
            try rig.setSplit(false, txFreqHz: 0)
        }
    }

    /// SWAP.
    public func swapVfo() {
        vfoOperation(RigTexts.swapLabel, done: RigTexts.swapped) { rig in
            try rig.swapVfo()
        }
    }

    /// Ctrl+Alt+S: by the last polled state (not the rig's current one).
    public func toggleSplit() {
        if activeState?.split == true {
            splitOff()
        } else {
            setSplit(0)
        }
    }

    /// Alt+F7 (`AS:965-981`): a prompt for the transmit frequency or an offset; blank = split off.
    public func promptSplit(currentFreqHz: Int64) {
        let otherHz: Int64 = activeState?.txFreqHz ?? 0
        dialogs.prompt(title: .verbatim(RigTexts.splitPromptTitle), hint: ContestMessage(RigTexts.splitPromptHint),
                       initial: "") { [weak self] text in
            self?.splitEntered(text, currentFreqHz: currentFreqHz, otherHz: otherHz)
        }
    }

    private func splitEntered(_ text: String, currentFreqHz: Int64, otherHz: Int64) {
        if KotlinStrings.isBlank(text) {
            splitOff()
            return
        }
        // Kotlin does not catch the parser's `Overflow` here (the window would close); it is an invalid entry.
        let command: CallFieldCommand? = try? CallFieldCommands.parse(text, currentFreqHz: currentFreqHz,
                                                                      otherVfoHz: otherHz, ctrlEnter: true)
        switch command {
        case .split(let txFreqHz)?:
            setSplit(txFreqHz)
        case .invalid(let message)?:
            status.showVerbatim(message)
        default:
            show(RigTexts.splitInvalid(text))
        }
    }

    /// Kotlin `applySplitFromSpot(spot)` (`AS:553-576`, called by `tuneToSpot`): the split of the spot's
    /// comment (`UP 5`, `QSX …`; a bare `UP` is 5 kHz in phone, 1 kHz otherwise); a spot without one turns off only
    /// a split that an earlier spot turned on.
    public func applySplitFromSpot(_ spot: DxSpot) {
        guard config.config.dxCluster.autoSplit else { return }
        let mode: String = SpotModeParser.fromComment(spot.comment) ?? ""
        let phone: Bool = ["SSB", "USB", "LSB", "PH"].contains(mode)
        let defaultUp: Int = phone ? 5_000 : 1_000
        if let tx = SplitFromComment.parse(spot.comment, spotFreqHz: spot.freqHz, defaultUpHz: defaultUp) {
            setSplit(Int64(tx))
            autoSplitActive = true
        } else if autoSplitActive {
            splitOff()
            autoSplitActive = false
        }
    }

    // MARK: - RIT

    /// Kotlin `setRit(offsetHz)`: clamped to ±9 999; `ritHz` changes only when the rig accepted it.
    public func setRit(_ offsetHz: Int) {
        let value: Int = RitState.clamp(offsetHz)
        guard active.connected else {
            show(RigTexts.ritNeedsCat)
            return
        }
        activeLane.run({ cat in
            RigOutcome.run(cat) { rig in try rig.setRit(value) }
        }, then: { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .done:
                self.rit.applied(value)
                self.show(RigTexts.rit(value))
            case .noRig:
                self.show(RigTexts.ritNeedsCat)
            case .failed(let message):
                self.show(RigTexts.ritFailure(message))
            }
        })
    }

    /// Kotlin `stepRit(direction, mode)`: one tuning step of the mode.
    public func stepRit(_ direction: Int, mode: Mode) {
        setRit(rit.step(direction: direction, stepHz: tuneStepHz(mode)))
    }

    /// `{CLEARRIT}` and the clearing after a logged QSO (`AS:2797`): `setRit(0)`.
    public func clearRit() {
        setRit(0)
    }

    // MARK: - SO2V / SO2R

    /// Kotlin `syncRadioModeFromConfig()` (`AS:2259-2269`): the radio mode, OTRSP reopened in SO2R with a port
    /// (`"SO2R: %s"` when it cannot be opened), and back to VFO A without two entry windows.: it also runs
    /// once at start-up (Kotlin forgets to, so OTRSP stays closed until Settings are saved).
    public func syncRadioModeFromConfig() {
        let mode: String = config.config.radioMode
        let forceVfoA: Bool = vfo.syncRadioMode(mode)
        let port: String = config.config.otrspPort
        peripherals.reopenOtrsp(vfo.so2r && !KotlinStrings.isBlank(port) ? port : nil)
        if forceVfoA {
            activateVfo(0, force: true)
        }
    }

    /// Kotlin `activateVfo(vfo, force)`: the left VFO keeps its frequency, the new one restores its own; SO2R
    /// switches the OTRSP focus (`tr("Aktivní rig %s")`), SO1V/SO2V selects the rig's VFO over CAT.
    public func activateVfo(_ index: Int, force: Bool = false) {
        var nextVfo: VfoState = vfo
        var nextTuning: TuningState = tuning
        guard let outcome = VfoActivation.apply(&nextVfo, &nextTuning, index: index, force: force,
                                                hasOtrsp: peripherals.otrspOpen) else { return }
        vfo = nextVfo
        if outcome.restoredFreqHz != nil {
            // Kotlin `tunedFreqHz = it` — no QSY, no previous frequency, no rig.
            setTuning(nextTuning)
        }
        // Kotlin `LaunchedEffect(…, active)`: the newly active window follows the rig.
        notifyEntries { $0.followRig() }
        switch outcome.hardware {
        case .otrspFocus(let rig, let stereo):
            // The lane holds the controller: without one the focus does nothing (Kotlin `o?.let`).
            peripherals.otrspFocus(rig: rig, stereo: stereo)
            if let status = outcome.status {
                show(status)
            }
        case .selectVfo(let b):
            guard active.connected else { return }
            activeLane.run({ cat in
                RigOutcome.run(cat) { rig in try rig.selectVfo(b) }
            }, then: { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .done:
                    self.show(RigTexts.activeVfo(b: b))
                case .noRig:
                    break
                case .failed(let message):
                    self.show(RigTexts.so2vFailure(message))
                }
            })
        }
    }

    /// Kotlin `requestFocusVfo(vfo)` (`\`): activate and move the focus there.
    public func requestFocusVfo(_ index: Int) {
        activateVfo(index)
        focusVfoRequest = index
    }

    /// Kotlin `toggleSo2rStereo()`: OTRSP `RXnS` / `RXn`.
    public func toggleSo2rStereo() {
        let stereo: Bool = vfo.toggleStereo()
        peripherals.otrspRx(rig: vfo.activeVfo + 1, stereo: stereo)
        show(RigTexts.so2rStereo(stereo))
    }

    // MARK: - antennas

    /// Kotlin `autoSelectAntenna(band)`: the band's antenna by the azimuth to the typed call.
    func autoSelectAntenna(_ band: Band) {
        let azimuth: Int? = azimuthTo(typedCall())
        var next: AntennaApply = antenna
        let plan: AntennaApply.Plan? = next.autoSelect(
            band: band, azimuth: azimuth, antennas: config.config.antennas, activeVfo: vfo.activeVfo,
            viaRig: config.config.antennaViaRig, rigConnected: active.connected)
        antenna = next
        apply(plan)
    }

    /// Kotlin `nextAntenna()` (a key): the band's next antenna.
    public func nextAntenna() {
        var next: AntennaApply = antenna
        let outcome: AntennaApply.NextOutcome = next.next(
            band: currentBand, antennas: config.config.antennas, activeVfo: vfo.activeVfo,
            viaRig: config.config.antennaViaRig, rigConnected: active.connected)
        antenna = next
        switch outcome {
        case .noBand:
            break
        case .none(let message):
            show(message)
        case .apply(let plan):
            apply(plan)
        }
    }

    /// Rule (b): `config.antennas` was written (every Settings save, a profile with `antennas`).
    public func resetAntennaIndex() {
        antenna.antennasChanged()
    }

    /// Kotlin `applyAntenna`: the status at once; OTRSP `AUX` and the rig's connector in the background,
    /// results ignored.
    private func apply(_ plan: AntennaApply.Plan?) {
        guard let plan else { return }
        peripherals.otrspAux(port: plan.otrspAux.port, code: plan.otrspAux.code)
        if let code = plan.rigAntenna {
            activeLane.run { cat in
                _ = RigOutcome.run(cat) { rig in try rig.setAntenna(code) }
            }
        }
        show(plan.status)
    }

    /// Kotlin `azimuthTo(call)`.
    public func azimuthTo(_ call: String) -> Int? {
        RotorAzimuth.to(call: call, grid: config.config.station.gridSquare, dxcc: contest.runtime.dxccLookup)
    }

    // MARK: - footswitch

    /// Kotlin `onFootswitch(pressed)` (`AS:659-665`): PTT holds the active rig's transmitter while pressed (a
    /// failure is ignored); ENTER / F1 count a press for the active entry window. A held PTT is always released on the
    /// rig that was keyed — even when the active rig or the action changed meanwhile, or a second press keys another.
    /// Once the quit closed the transmitter (`closeTransmit`) a press does nothing; a release edge still releases.
    func footswitch(_ pressed: Bool) {
        if !pressed && footswitchPttRig != nil {
            releaseFootswitchPtt()
            return
        }
        if pressed && transmitClosed {
            return
        }
        guard config.config.footswitchAction == Footswitch.Action.ptt.rawValue else {
            if pressed {
                peripherals.footswitchPressed()
            }
            return
        }
        if pressed, let locked = keyingGate() {
            status.showJoined(locked.parts, separator: "")
            return
        }
        let index: Int = vfo.activeCatIndex
        if pressed, let keyed = footswitchPttRig, keyed != index {
            // A second press while another rig is still keyed (an SO2R switch between two press edges): that rig is
            // released first, so it never stays keyed until a disconnect or the quit.
            releaseFootswitchPtt(onRig: keyed)
        }
        footswitchPttRig = pressed ? index : nil
        lanes[index].run { cat in
            try? cat.setPtt(pressed)
        }
    }

    /// The quit's transmit release: footswitch presses are refused from now on and a held PTT is released.
    func closeTransmit() {
        transmitClosed = true
        releaseFootswitchPtt()
        releasePluginPtt()
    }

    /// `setPtt(false)` on the rig the footswitch keyed (nothing when none is keyed): before the footswitch closes
    /// (a reload, the quit) and before the rigs disconnect at quit — the lane keeps it ahead of the disconnect.
    func releaseFootswitchPtt() {
        guard let index = footswitchPttRig else { return }
        releaseFootswitchPtt(onRig: index)
    }

    /// The release before a user-initiated disconnect of rig `index` (the LED, a reconnect, the reset, a scan): the
    /// lane sends `T 0` ahead of the disconnect, so the rig never stays keyed.
    func releaseFootswitchPtt(onRig index: Int) {
        guard footswitchPttRig == index else { return }
        footswitchPttRig = nil
        lanes[index].run { cat in
            try? cat.setPtt(false)
        }
    }
}
