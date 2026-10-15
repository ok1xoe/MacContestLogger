import Foundation
import MCLCore

/// The entry window and the rig (`EP:141-196, 371-461, 782-803, 898-923, 1029-1062`): following the active rig, the
/// loop guard between the frequency field and the shared tuned frequency, the arrows, the wheel, Ctrl+PgUp/PgDn,
/// the rig shortcuts and commands, and the footswitch's F1 / Enter.
extension EntryModel {

    /// Kotlin `active`: without two entry windows always, otherwise the window of the active VFO. The VFO B window
    /// exists in Kotlin only with two entry windows; here its model lives on, so while hidden (no two entry windows,
    /// or its window not on screen) it is never active: it neither follows the rig nor reacts to the footswitch.
    public var isActivePanel: Bool {
        guard isWindowShown else { return false }
        guard let rig else { return vfo == 0 }
        guard rig.vfo.twoEntryWindows else { return vfo == 0 }
        return rig.vfo.activeVfo == vfo
    }

    /// `state.cat.state?.txFreqHz() ?: 0` (the commands' other VFO).
    var otherVfoHz: Int64 {
        rig?.activeState?.txFreqHz ?? 0
    }

    // MARK: - following the rig

    /// Kotlin `LaunchedEffect(state.cat.state, modeLocked, active)` (`EP:178-185`): only the active window copies
    /// the rig's frequency into its field and its mode (by Mode Control, not in a single-mode contest), then the
    /// shared tuned frequency follows the rig — and the field (`LaunchedEffect(freqKHz)` after the recomposition).
    func followRig() {
        guard isActivePanel, quickEdit == nil, let rig, let state = rig.activeState else { return }
        let text: String = CatStatusLine.fieldText(state.freqHz)
        let fieldChanged: Bool = text != form.freqKHz
        form.freqKHz = text
        if !modeLocked, let mode = rig.loggedMode(state.mode, freqHz: state.freqHz), mode != form.mode {
            setMode(mode)
        }
        rig.updateTuned(state.freqHz)
        if fieldChanged {
            rig.updateTuned(form.freqHz)
        }
        updatePreview()
    }

    /// Kotlin `LaunchedEffect(state.tunedFreqHz)` (`EP:189-196`) and `LaunchedEffect(state.tunedFreqHz, mode)`: the
    /// shared frequency changed elsewhere (a QSY, the bandmap, a VFO switch) — the active window's field follows
    /// unless it already says the same; the guard stops the loop with the field's own effect. Run/S&P follows.
    func rigTunedChanged() {
        followTunedFrequency()
        // `EP:240-256` runs in every window, after the event that tuned.
        scheduleSelfSpotEffect()
    }

    private func followTunedFrequency() {
        guard isActivePanel, quickEdit == nil, let rig else { return }
        let tuned: Int64 = rig.tuning.tunedFreqHz
        if tuned > 0 && form.freqHz != tuned {
            let text: String = CatStatusLine.fieldText(tuned)
            if text != form.freqKHz {
                form.freqKHz = text
                updatePreview()
                rig.updateTuned(form.freqHz)
            }
        }
        reportTuned(rig.tuning.tunedFreqHz)
    }

    /// Kotlin `LaunchedEffect(freqKHz) { if (active) state.updateTunedFreq(parseFreqHz(freqKHz)) }`: the field sets
    /// the shared frequency — never the rig.
    func fieldFrequencyChanged() {
        guard isActivePanel else { return }
        rig?.updateTuned(form.freqHz)
    }

    // MARK: - tuning keys

    /// ↑/↓ without suggestions (`tuneStep`, `EP:798-804`): ↑ = −1 step, ↓ = +1 step of the mode.
    public func tuneStep(_ direction: Int) {
        let app: AppConfig = config.config
        guard let next = TuningState.tuneStep(fieldHz: form.freqHz, mode: form.mode, direction: direction,
                                              cwHz: app.tuneStepCwHz, ssbHz: app.tuneStepSsbHz) else { return }
        tune(toFieldHz: next)
    }

    /// The mouse wheel (`EP:1032-1043`): up = +1 notch; Alt 1 kHz, Ctrl 10 kHz, Ctrl+Alt 100 kHz rounding. Only in
    /// the active window (a safety divergence: Kotlin tunes the active rig to the inactive window's frequency ± a
    /// step when the wheel turns over the other window).
    public func wheel(direction: Int, alt: Bool, ctrl: Bool) {
        guard isActivePanel else { return }
        guard let next = TuningState.wheel(fieldHz: form.freqHz, mode: form.mode, direction: direction, alt: alt,
                                           ctrl: ctrl) else { return }
        tune(toFieldHz: next)
    }

    /// `freqKHz = format(next)` and `state.tuneTo(next)` (≤ 0: the field shows it, the rig is not tuned).
    private func tune(toFieldHz next: Int64) {
        setFrequencyText(CatStatusLine.fieldText(next))
        rig?.tuneTo(next)
        fieldFrequencyChanged()
    }

    /// Ctrl+PgUp/PgDn (`stepBand`, `EP:783-795`): the next band's last frequency, otherwise its segment start. In
    /// SO2R the other radio's band is skipped (N1MM's software band lockout).
    public func stepBand(_ direction: Int) {
        guard let rig else { return }
        let allowed: [Band] = rig.lockedOut(rig.bandsForStepping(), otherBand: rig.otherRadioBand)
        guard let target = BandStepping.target(tuning: rig.tuning, band: band, mode: form.mode,
                                               allowed: allowed, direction: direction) else { return }
        qsy(toKHz: target.kHz, mode: form.mode)
    }

    /// N1MM Ctrl+Shift+PgUp/PgDn (SO2V / SO2R): the other radio / VFO one band up or down (its last frequency there,
    /// otherwise the segment start of its mode); in SO2R this radio's band is skipped. The focus stays.
    func stepOtherBand(_ direction: Int) {
        guard let rig, let other = rig.otherEntry(than: self) else {
            status.show("Druhé okno není otevřené (SO2V / SO2R)")
            return
        }
        let allowed: [Band] = rig.lockedOut(rig.bandsForStepping(), otherBand: band)
        guard let target = BandStepping.target(tuning: rig.tuning, band: rig.otherRadioBand ?? other.band,
                                               mode: other.form.mode,
                                               allowed: allowed, direction: direction) else { return }
        rig.qsyOtherRadio(target.hz)
    }

    /// N1MM Shift+Alt+Q: the other radio / VFO to the CQ frequency of its band; the focus stays.
    func otherToCqFrequency() {
        guard let rig, let other = rig.otherEntry(than: self) else {
            status.show("Druhé okno není otevřené (SO2V / SO2R)")
            return
        }
        guard let band = rig.otherRadioBand ?? other.band, let cq = operating.cqFrequency(band: band) else {
            show(.tr("Druhé rádio: na jeho pásmu není CQ frekvence"))
            return
        }
        rig.qsyOtherRadio(cq)
    }

    // MARK: - shortcuts and commands

    /// The rig shortcuts of `runShortcut` (`EP:898-923`); TUNE (Ctrl+T) goes to the keyer (`state.toggleTune()`).
    func runRadioShortcut(_ action: ShortcutAction) {
        if action == .tune {
            rig?.claimTx(vfo)
            if let message = ports.keyer.toggleTune() {
                show(message)
            }
            return
        }
        guard let rig else {
            unavailable()
            return
        }
        switch action {
        case .jumpCq:
            if jumpToCqFrequency() {
                wipe()
            }
        case .splitOn: rig.splitListenToggle()
        case .resetRx: rig.resetRxToTx()
        case .splitToggle: rig.toggleSplit()
        case .splitPrompt: rig.promptSplit(currentFreqHz: form.freqHz)
        case .previousFrequency: rig.returnToPrevious()
        case .swapVfo: rig.swapVfo()
        case .copyToVfoB:
            // N1MM Alt+F12: on a rig with a sub receiver the dual watch toggle, otherwise the copy A → B.
            if rig.altF12TogglesSubReceiver {
                rig.setSubReceiver(nil)
            } else {
                rig.copyToVfoB()
            }
        case .so2vDualCq:
            so2vDualReceiveCq()
        case .ritUp: rig.stepRit(1, mode: form.mode)
        case .ritDown: rig.stepRit(-1, mode: form.mode)
        case .ritClear: rig.setRit(0)
        case .switchRadio:
            // N1MM `\`: the entry (RX) focus to the other window; in SO2R the transmit focus stays.
            if rig.vfo.twoEntryWindows {
                rig.requestFocusVfo(1 - vfo, rxOnly: true)
            }
        case .focusSwap:
            rig.swapFocus()
        case .swapRadios, .swapRadiosKeepFocus:
            swapRadios(moveFocus: action == .swapRadios)
        case .otherBandUp: stepOtherBand(1)
        case .otherBandDown: stepOtherBand(-1)
        case .otherCqFrequency: otherToCqFrequency()
        case .so2rStereo:
            if rig.vfo.so2r {
                rig.toggleSo2rStereo()
            }
        case .nextAntenna: rig.nextAntenna()
        case .rotorTurn: rig.rotator.turnToCall(KotlinStrings.trim(form.call), longPath: false)
        case .rotorLong: rig.rotator.turnToCall(KotlinStrings.trim(form.call), longPath: true)
        case .rotorStop: rig.rotator.stop()
        case .bandUp: stepBand(1)
        case .bandDown: stepBand(-1)
        case .jumpLastCq:
            jumpToLastCqFrequency()
        case .toggleFilter:
            guard let controls = bandmapControls else { return unavailable() }
            controls.toggleFilterWidth()
        case .cwReverse:
            guard let controls = bandmapControls else { return unavailable() }
            controls.toggleCwReverse()
        default:
            unavailable()
        }
    }

    /// N1MM Ctrl+Alt+D (SO2V): CQ repeat on VFO A with the sub receiver on, so the sub receiver (VFO B) can be tuned
    /// on the rig between the CQs; again = the CQ repeat off and the sub receiver back to its „always on" option. A
    /// caller heard on the sub receiver is worked from the VFO B window (`\` or Pause).
    func so2vDualReceiveCq() {
        guard let rig, rig.vfo.so2v else {
            show(.tr("Ctrl+Alt+D: jen v SO2V"))
            return
        }
        if operating.cqRepeat && rig.subReceiverOn && operating.cqRepeatWindow == 0 {
            operating.setCqRepeat(false)
            if !rig.rigConfig(vfo: 0).subReceiverOn {
                rig.setSubReceiver(false)
            }
            return
        }
        guard rig.active.connected else {
            show(RigTexts.vfoNeedsCat(RigTexts.subReceiverLabel))
            return
        }
        if rig.vfo.activeVfo != 0 {
            rig.requestFocusVfo(0)
        }
        rig.setSubReceiver(true)
        operating.cqRepeatWindow = 0
        operating.setCqRepeat(true)
    }

    /// N1MM Alt+F5 / Alt+F6: the frequency, mode and call of the two windows swapped — the two rigs retuned (SO2R) or
    /// the rig's VFOs exchanged over CAT (SO2V). Alt+F5 moves the entry focus to the other window, Alt+F6 (SO2R only)
    /// keeps it. Only frequencies change — nothing transmits.
    func swapRadios(moveFocus: Bool) {
        guard let rig, let other = rig.otherEntry(than: self) else {
            status.show("Druhé okno není otevřené (SO2V / SO2R)")
            return
        }
        guard rig.vfo.so2r || moveFocus else {
            show(.tr("Alt+F6: jen v SO2R (dvě rádia)"))
            return
        }
        let mine: (freq: String, hz: Int64, mode: Mode, call: String) = (form.freqKHz, form.freqHz, form.mode, form.call)
        let theirs: (freq: String, hz: Int64, mode: Mode, call: String) =
            (other.form.freqKHz, other.form.freqHz, other.form.mode, other.form.call)
        if rig.vfo.so2r {
            rig.tuneRadio(vfo, freqHz: theirs.hz, mode: theirs.mode)
            rig.tuneRadio(other.vfo, freqHz: mine.hz, mode: mine.mode)
        } else {
            guard rig.active.connected else {
                // The rig's VFO exchange needs CAT (`swapVfo` says so).
                rig.swapVfo()
                return
            }
            rig.swapVfo()
            rig.rememberInactiveFrequency(mine.hz, vfo: other.vfo)
        }
        // The other window first: Run/S&P follows the last frequency reported, this (active) window's.
        for (entry, take) in [(other, mine), (self, theirs)] {
            if entry === self {
                entry.setFrequencyText(take.freq)
            } else {
                entry.showInactiveFrequency(take.freq)
            }
            if !entry.modeLocked && entry.form.mode != take.mode {
                entry.setMode(take.mode)
            }
            // The call moved with its station: retuning is no reason to store it in the band map and clear it.
            entry.selfSpot.prefilledFromSpot()
            entry.setCallText(take.call)
        }
        fieldFrequencyChanged()
        show(.tr("Rádia prohozena (frekvence, mód, volačka)"))
        if moveFocus {
            rig.requestFocusVfo(other.vfo, rxOnly: true)
        }
    }

    /// The inactive window's frequency field when its radio / VFO was tuned from elsewhere (the other radio's QSY, a
    /// swap): only the field and the preview — Run/S&P and the plugins follow the active window alone.
    func showInactiveFrequency(_ text: String) {
        form.freqKHz = text
        updatePreview()
    }

    /// A rig command of the call field (`EP:404-405, 436-440`).
    func runRigCommand(_ command: EntryRigCommand) {
        switch command {
        case .debugCat:
            windows.setOpen("catLog", true)
            return
        default:
            break
        }
        guard let rig else {
            unavailable()
            return
        }
        switch command {
        case .otherVfo(let freqHz):
            // N1MM `/14030`: VFO B of the rig — in SO2R the other radio.
            if rig.vfo.so2r {
                rig.qsyOtherRadio(freqHz)
            } else {
                rig.setOtherVfo(freqHz)
            }
        case .split(let txFreqHz): rig.setSplit(txFreqHz)
        case .splitOff: rig.splitOff()
        case .swapVfo: rig.swapVfo()
        case .rit(let offsetHz): rig.setRit(offsetHz)
        case .resetInterfaces: rig.resetInterfaces()
        case .debugCat: break
        }
    }

    /// `.rigQsy(hz)` of a QSY command: `state.qsy(hz)`, then the field's effect (the field was set before it).
    func runRigQsy(_ hz: Int64) {
        ports.rig.qsy(hz: hz)
        fieldFrequencyChanged()
    }

    // MARK: - footswitch

    /// Kotlin `LaunchedEffect(state.footswitchPresses)` (`EP:864-870`): only the active window acts — an F-key
    /// action sends that key, ENTER is the ESM Enter or logs, ESC stops sending (Esc's first step), SWITCH_RADIOS
    /// moves to the other entry window in SO2V / SO2R (`\`).
    func footswitchPressed() {
        guard isActivePanel, let action = Footswitch.Action(rawValue: config.config.footswitchAction) else { return }
        if let key = action.functionKey {
            sendKeys([key], refocus: true)
            return
        }
        switch action {
        case .enter:
            if esmActive {
                esmEnter()
            } else {
                submit()
            }
        case .esc:
            _ = stopSending()
        case .switchRadios:
            runShortcut(.switchRadio)
        default:
            break
        }
    }
}
