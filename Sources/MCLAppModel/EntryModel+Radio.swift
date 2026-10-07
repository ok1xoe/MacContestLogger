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
        guard isActivePanel, let rig, let state = rig.activeState else { return }
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
        guard isActivePanel, let rig else { return }
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

    /// Ctrl+PgUp/PgDn (`stepBand`, `EP:783-795`): the next band's last frequency, otherwise its segment start.
    public func stepBand(_ direction: Int) {
        guard let rig else { return }
        guard let target = BandStepping.target(tuning: rig.tuning, band: band, mode: form.mode,
                                               allowed: rig.bandsForStepping(), direction: direction) else { return }
        qsy(toKHz: target.kHz, mode: form.mode)
    }

    // MARK: - shortcuts and commands

    /// The rig shortcuts of `runShortcut` (`EP:898-923`); TUNE (Ctrl+T) goes to the keyer (`state.toggleTune()`).
    func runRadioShortcut(_ action: ShortcutAction) {
        if action == .tune {
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
        case .splitOn: rig.setSplit(0)
        case .splitToggle: rig.toggleSplit()
        case .splitPrompt: rig.promptSplit(currentFreqHz: form.freqHz)
        case .previousFrequency: rig.returnToPrevious()
        case .swapVfo: rig.swapVfo()
        case .copyToVfoB: rig.copyToVfoB()
        case .ritUp: rig.stepRit(1, mode: form.mode)
        case .ritDown: rig.stepRit(-1, mode: form.mode)
        case .ritClear: rig.setRit(0)
        case .switchRadio:
            if rig.vfo.twoEntryWindows {
                rig.requestFocusVfo(1 - vfo)
            }
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
        default:
            unavailable()
        }
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
        case .otherVfo(let freqHz): rig.setOtherVfo(freqHz)
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

    /// Kotlin `LaunchedEffect(state.footswitchPresses)` (`EP:864-870`): only the active window acts — F1 sends,
    /// ENTER is the ESM Enter or logs.
    func footswitchPressed() {
        guard isActivePanel else { return }
        switch config.config.footswitchAction {
        case Footswitch.Action.f1.rawValue:
            sendKeys([0], refocus: true)
        case Footswitch.Action.enter.rawValue:
            if esmActive {
                esmEnter()
            } else {
                submit()
            }
        default:
            break
        }
    }
}
