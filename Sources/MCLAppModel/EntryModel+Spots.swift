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

    /// WSJT-X's DX Call shown in the call field for the dupe and multiplier check (N1MM): no focus change, the call
    /// counts as from a spot (tuning away does not self-spot it). The same call does nothing.
    public func mirrorCall(_ call: String) {
        guard !KotlinStrings.isBlank(call), CallStack.normalize(form.call) != CallStack.normalize(call) else { return }
        selfSpot.prefilledFromSpot()
        setCallText(call)
    }

    /// Kotlin's `prefillExchange` effect (`EP:214-219`): the non-blank values go into the contest fields as they are
    /// (no touch mark), then the preview follows.
    public func prefillExchange(_ values: JavaLinkedMap<String>) {
        guard !values.isEmpty else { return }
        for (id, value) in values.entries {
            if let value, !KotlinStrings.isBlank(value) {
                form.contestExchange.put(id, value)
                autoFilled[id] = value
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
        // With the N1MM call-frame the call of a nearby spot shows above the field instead of filling it.
        let callFrame: Bool = config.config.dxCluster.callFrame
        let action: SelfSpotTracker.Action? = selfSpot.tunedChanged(
            tuned, call: form.call, thresholdHz: threshold,
            nearest: { callFrame ? nil : buffer.nearestWithin($0, toleranceHz: $1) })
        switch action {
        case .selfSpot(let call, let atHz):
            spots.store(call: call, freqHz: atHz)
            setCallText("")
            // N1MM warns when the operator tunes away before logging.
            status.show(ContestMessage("%s nezapsán — odladěno, uložen do bandmapy", .string(call)))
        case .prefill(let call):
            setCallText(call)
        case nil:
            break
        }
    }

    // MARK: - the call-frame

    /// N1MM's call-frame: the spot within the mode's tuning tolerance of this window's frequency (the nearest; the
    /// spot filter applies), shown above the call field. `nil` with the option off, without spots or a frequency.
    public var callFrameSpot: DxSpot? {
        let dx: DxClusterConfig = config.config.dxCluster
        guard dx.callFrame, let spots = spotNavigation else { return nil }
        return spots.callFrameSpot(freqHz: form.freqHz, toleranceHz: dx.tuningToleranceHz(form.mode))
    }

    /// The call-frame's call when the call field does not already hold it.
    public var callFrameCall: String? {
        guard let spot = callFrameSpot,
              CallStack.normalize(spot.dxCall) != CallStack.normalize(form.call) else { return nil }
        return spot.dxCall
    }

    /// The space bar with an empty call field takes the call-frame's call (and the spot's predicted exchange) as a
    /// call from a spot. `false` = nothing to take.
    @discardableResult
    func takeCallFrame() -> Bool {
        guard KotlinStrings.isBlank(form.call), let spot = callFrameSpot else { return false }
        selfSpot.prefilledFromSpot()
        setCallText(spot.dxCall)
        prefillExchange(rig?.predictedExchange(spot) ?? JavaLinkedMap())
        return true
    }

    /// N1MM „Always use packet spot mode": the spot's mode becomes the window's mode (unless the contest fixes it).
    func applySpotMode(_ mode: Mode) {
        guard !modeLocked, form.mode != mode else { return }
        form.applyDefaultRst(mode)
        setMode(mode)
    }

    // MARK: - shortcuts and buttons

    /// The spot shortcuts of `runShortcut` (`EP:924-936`).
    func runSpotShortcut(_ action: ShortcutAction) {
        if action == .dxClusterWindow {
            toggleDxClusterWindow()
            return
        }
        if action == .availNext || action == .availPrevious {
            guard let availMult else {
                unavailable()
                return
            }
            availMult.grab(forward: action == .availNext)
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
        case .otherSpotUp: spots.jumpOther(direction: 1)
        case .otherSpotDown: spots.jumpOther(direction: -1)
        case .otherMultUp: spots.jumpOther(direction: 1, onlyMult: true)
        case .otherMultDown: spots.jumpOther(direction: -1, onlyMult: true)
        case .spotIt: spotIt()
        case .spotWithComment:
            spots.spotWithComment(call: KotlinStrings.trim(form.call), freqHz: form.freqHz, initial: spotComment(form))
        case .store: storeCall()
        case .mark: spots.mark(freqHz: form.freqHz)
        case .removeSpot:
            // N1MM: Alt+D with an empty call field deletes the next call of the call stack.
            if KotlinStrings.isBlank(form.call), let stack = callStack, stack.removeTop() {
                return
            }
            spots.removeSpotOf(call: form.call, blacklist: false)
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
        spots.spotIt(call: form.call, isCommand: hasCommand, fieldFreqHz: loggedFreqHz, lastQso: lastQso,
                     fieldComment: spotComment(form), lastQsoComment: lastQso.map(spotComment(of:)) ?? "")
        focusRequest += 1
    }

    /// Store (Alt+O, the button, `EP:770-779`): the call of the field into the band map at the field's frequency (a
    /// blank call or a command: `tr("Store: zadej volačku")`; no frequency: `noFrequency`, nothing is stored); the call field takes the focus.
    public func storeCall() {
        guard let spots = spotNavigation else {
            unavailable()
            return
        }
        if KotlinStrings.isBlank(form.call) || hasCommand {
            status.show(ContestMessage(SpotActions.storeNoCall))
            return
        }
        if form.freqHz <= 0 {
            show(.tr(SpotActions.noFrequency))
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

    // MARK: - the spot comment (N1MM „Comment For All Spots")

    /// The spot comment of the QSO in `form`: the template with the exchange fields of the entry window.
    func spotComment(_ form: EntryForm) -> String {
        let template: String = config.config.dxCluster.spotComment
        guard !KotlinStrings.isBlank(template) else { return "" }
        let values = SpotComment.fields(received: contest.isActive ? contest.exchangeFields(call: form.call) : [],
                                        mode: form.mode.rawValue, value: { form.contestExchange[$0] })
        return SpotComment.expand(template, values)
    }

    /// The spot comment of a logged QSO (its stored exchange).
    func spotComment(of qso: Qso) -> String {
        let template: String = config.config.dxCluster.spotComment
        guard !KotlinStrings.isBlank(template) else { return "" }
        let fields = contest.isActive ? contest.exchangeFields(call: qso.call) : []
        return SpotComment.expand(template, SpotComment.fields(received: fields, qso: qso))
    }

    /// N1MM Config → „Spot all S&P QSOs" (opt-in): a live S&P QSO that is not a dupe, not entered after the contest
    /// and not the simulator's goes to the cluster unless its call is already in the band map.
    func autoSpotLogged(_ work: Submission, qso: Qso) {
        guard config.config.dxCluster.spotAllSpQsos, qso.runMode == .searchAndPounce, !work.dupe, work.at == nil,
              !logbook.simulatorActive(), logbook.outwardGate(qso), let spots = spotNavigation else { return }
        spots.autoSpot(call: qso.call, freqHz: Int64(qso.freqHz), comment: work.spotComment)
    }

    /// `{SPOTME}` (N1MM function-key macro): my own station spotted on this entry window's frequency with the spot
    /// comment (its mode only; „CQ" when the comment is blank).
    func spotMeMacro() {
        let template: String = config.config.dxCluster.spotComment
        let comment: String = SpotComment.expand(template, SpotComment.Fields(mode: form.mode.rawValue))
        spotMe(freqHz: loggedFreqHz, comment: comment)
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
