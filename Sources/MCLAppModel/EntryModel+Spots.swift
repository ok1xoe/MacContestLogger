import Foundation
import MCLCore

/// The entry window and the spots (`EP:150-153, 204-219, 235-256, 770-812, 924-936`): the prefill from a spot, the
/// self-spot anchor and the auto-prefill (`SelfSpotTracker`), and the spot shortcuts and buttons (Spot It,
/// Store, Mark, the navigation, Alt+D, Ctrl+P, the DX Cluster window).
extension EntryModel {

    /// Kotlin `callFromSpot`: the call came from the band map or a spot, so tuning away never self-spots it.
    public var callFromSpot: Bool {
        selfSpot.callFromSpot
    }

    // MARK: - the call field

    /// Sets the call without the typing semantics (Kotlin `call = …` from an effect): the ESM restart on a blank
    /// call, the preview and the self-spot anchor follow.
    func setCallText(_ text: String) {
        let previous: String = form.call
        form.call = text
        esmProgress = EsmFlow.afterCallChange(esmProgress, previousCall: previous, call: text)
        updatePreview()
        trackCallForSelfSpot()
    }

    /// The anchor effect (`LaunchedEffect(call.isNotBlank())`, `EP:236-239`) after any change of the call field.
    func trackCallForSelfSpot() {
        selfSpot.callChanged(form.call, tunedFreqHz: rig?.tuning.tunedFreqHz ?? 0)
    }

    /// Kotlin's `prefillCall` effect (`EP:205-211`): the call from a spot (the band map, `tuneToSpot`, the CW
    /// reader, the Digital Interface) replaces the field, it counts as a call from a spot, and the call field takes
    /// the focus. A blank call does nothing.
    public func prefillCall(_ call: String) {
        guard !KotlinStrings.isBlank(call) else { return }
        selfSpot.prefilledFromSpot()
        setCallText(call)
        focusRequest += 1
    }

    /// Kotlin's `prefillExchange` effect (`EP:214-219`): the non-blank values go into the contest fields as they are
    /// (no touch mark), then the preview follows.
    public func prefillExchange(_ values: JavaLinkedMap<String>) {
        guard !values.isEmpty else { return }
        for (id, value) in values.entries {
            if let value, !KotlinStrings.isBlank(value) {
                form.contestExchange.put(id, value)
            }
        }
        updatePreview()
    }

    /// Queues the tuning effect behind the current event. Kotlin changes the state in an event handler and runs the
    /// effects after the recomposition, so an action that tunes and wipes in one step (Alt+Q: the CQ frequency, then
    /// `wipe()`) reaches the effect with the call already blank — never a self-spot of the wiped call.
    func scheduleSelfSpotEffect() {
        guard !selfSpotEffectPending else { return }
        selfSpotEffectPending = true
        MainHop.post { [weak self] in
            guard let self else { return }
            self.selfSpotEffectPending = false
            self.selfSpotTuned()
        }
    }

    /// The tuning effect (`LaunchedEffect(state.tunedFreqHz)`, `EP:240-256`), in **every** entry window on screen as in
    /// Kotlin (exact parity, no `active` guard): tuning a threshold away from where a typed call was entered
    /// stores it in the band map at that place and clears the field; tuning with an empty field onto a spot within
    /// 100 Hz fills its call. Never transmits.
    func selfSpotTuned() {
        // A window off screen has no composition in Kotlin (the VFO B panel exists only while shown), so its
        // tracker never runs: the hidden VFO B model must not self-spot or pick up a spot's call.
        guard isWindowShown, let spots = spotNavigation else { return }
        let tuned: Int64 = rig?.tuning.tunedFreqHz ?? 0
        guard tuned != selfSpotTunedHz else { return }
        selfSpotTunedHz = tuned
        let buffer: SpotBuffer = spots.buffer
        let threshold = Int64(config.config.dxCluster.selfSpotThresholdHz)
        let action: SelfSpotTracker.Action? = selfSpot.tunedChanged(
            tuned, call: form.call, thresholdHz: threshold,
            nearest: { buffer.nearestWithin($0, toleranceHz: $1) })
        switch action {
        case .selfSpot(let call, let atHz):
            spots.store(call: call, freqHz: atHz)
            setCallText("")
        case .prefill(let call):
            setCallText(call)
        case nil:
            break
        }
    }

    // MARK: - shortcuts and buttons

    /// The spot shortcuts of `runShortcut` (`EP:924-936`).
    func runSpotShortcut(_ action: ShortcutAction) {
        if action == .dxClusterWindow {
            toggleDxClusterWindow()
            return
        }
        guard let spots = spotNavigation else {
            unavailable()
            return
        }
        switch action {
        case .nextSpotUp: spots.jump(direction: 1)
        case .nextSpotDown: spots.jump(direction: -1)
        case .nextMultUp: spots.jump(direction: 1, onlyMult: true)
        case .nextMultDown: spots.jump(direction: -1, onlyMult: true)
        case .nextSelfUp: spots.jump(direction: 1, onlySelf: true)
        case .nextSelfDown: spots.jump(direction: -1, onlySelf: true)
        case .spotIt: spotIt()
        case .spotWithComment: spots.spotWithComment(call: KotlinStrings.trim(form.call), freqHz: form.freqHz)
        case .store: storeCall()
        case .mark: spots.mark(freqHz: form.freqHz)
        case .removeSpot: spots.removeSpotOf(call: form.call, blacklist: false)
        case .removeSpotBlacklist: spots.removeSpotOf(call: form.call, blacklist: true)
        default: unavailable()
        }
    }

    /// Kotlin `showDxCluster = !showDxCluster` (`EP:936`) once the window exists.
    private func toggleDxClusterWindow() {
        let id = "dxCluster"
        guard WindowsModel.implemented.contains(id) else {
            unavailable()
            return
        }
        windows.setOpen(id, !windows.isOpen(id))
    }

    /// Spot It (Alt+P, the button, `EP:806-812`): the call of the field at its frequency unless it is a command,
    /// otherwise the last logged QSO; the call field takes the focus.
    public func spotIt() {
        guard let spots = spotNavigation else {
            unavailable()
            return
        }
        let lastQso: Qso? = logbook.lastRow
        spots.spotIt(call: form.call, isCommand: hasCommand, fieldFreqHz: form.freqHz, lastQso: lastQso)
        focusRequest += 1
    }

    /// Store (Alt+O, the button, `EP:770-779`): the call of the field into the band map at the field's frequency (a
    /// blank call or a command: `tr("Store: zadej volačku")`); the call field takes the focus.
    public func storeCall() {
        guard let spots = spotNavigation else {
            unavailable()
            return
        }
        if KotlinStrings.isBlank(form.call) || hasCommand {
            status.show(ContestMessage(SpotActions.storeNoCall))
            return
        }
        spots.store(call: KotlinStrings.trim(form.call), freqHz: form.freqHz)
        show(SpotActions.stored(call: form.call))
        focusRequest += 1
    }

    /// The Mark button (`EP:1361`): `markFrequency(field)` and the focus back in the call field (Alt+M keeps it).
    public func markButton() {
        guard let spots = spotNavigation else {
            unavailable()
            return
        }
        spots.mark(freqHz: form.freqHz)
        focusRequest += 1
    }

    /// SPOTME (`EP:432`).
    func spotMe(freqHz: Int64, comment: String) {
        guard let spots = spotNavigation else {
            unavailable()
            return
        }
        spots.spotMe(freqHz: freqHz, comment: comment)
    }
}
