import Foundation
import MCLCore

/// Call-field commands, shortcuts, F-keys, ESM and the key decisions of the entry window (Kotlin `runCommand`,
/// `runShortcut`, `functionKeys`, `esmEnter`, `keys`; `EP:368-461, 569-609, 719-861, 873-1005`).
///
/// What needs spots or the network shows `tr("Zatím nedostupné")` and never logs; the local half of mixed
/// actions (QSY: field + status; mode: mode + reports; Alt+Q / `{CQFREQ}`: field + Run) is done here and the rest
/// goes to the ports (the rig and the keyer: F-keys, ESM, Esc, Ctrl+T, PgUp/PgDn, Ctrl+Shift+F).
extension EntryModel {

    // MARK: - derived state

    /// A digital modem is configured (`config.digital.engine != NONE`).
    var digitalReady: Bool {
        let digital: DigitalConfig = config.config.digital
        // RTTY through a hardware keyer needs no fldigi.
        return digital.engine != .none || (form.mode == .rtty && digital.rttyRoute != .fldigi)
    }

    /// Kotlin `phone || cw || digi`.
    public var canTransmit: Bool {
        EsmFlow.canTransmit(mode: form.mode, digitalReady: digitalReady)
    }

    /// Kotlin `esmActive` (`EP:679`).
    public var esmActive: Bool {
        EsmFlow.isActive(esmEnabled: operating.esmEnabled, mode: form.mode, digitalReady: digitalReady,
                         postContest: operating.postContest)
    }

    /// Kotlin `exchangeValid` (`EP:678`).
    public var exchangeValid: Bool {
        EsmFlow.exchangeValid(contestActive: contest.isActive, contestReady: contestReady, call: form.call)
    }

    private var esmInput: EsmFlow.Input {
        EsmFlow.Input(progress: esmProgress, run: operating.isRun, call: form.call, dupe: isDupe,
                      exchangeValid: exchangeValid, options: operating.esmOptions, nextCallKey: nextCallKey,
                      keyMap: config.config.esm.keys)
    }

    /// The N1MM Next Call key ESM sends instead of TU: configured, holding `{LOGTHENPOP}` in the set of this mode, and
    /// a call waiting on the stack (Run only).
    var nextCallKey: Int? {
        let key: Int = config.config.esm.nextCallKey
        guard operating.isRun, key >= 0, let stack = callStack, stack.next != nil else { return nil }
        let set: [FunctionKeyMessage] = currentKeySet(opposite: false)
        guard key < set.count, CallStackMacro.hasLogThenPop(set[key].text) else { return nil }
        return key
    }

    /// The F-key messages the keys send now: the voice set in phone, the digital set in a ready digital mode, else
    /// the CW set.
    func currentKeySet(opposite: Bool) -> [FunctionKeyMessage] {
        let app: AppConfig = config.config
        let keys: FunctionKeySet
        if EsmFlow.isPhone(form.mode) {
            keys = FunctionKeySet(run: app.voiceKeyer.runMessages, sp: app.voiceKeyer.spMessages)
        } else if form.mode.isDigital && digitalReady {
            keys = FunctionKeySet(run: app.digital.runMessages, sp: app.digital.spMessages)
        } else {
            keys = FunctionKeySet(run: app.cwKeyer.runMessages, sp: app.cwKeyer.spMessages)
        }
        return keys.messages(run: operating.isRun, opposite: opposite)
    }

    /// Kotlin `esmStep`: what the next Enter does (the F-keys and "Log It" are highlighted); `nil` without ESM.
    public var esmStep: EsmEngine.Step? {
        EsmFlow.nextStep(esmInput, active: esmActive)
    }

    /// The call field holds a command (`parseCommand() != null`).
    public var hasCommand: Bool {
        EntryCommandPlan.isCommand(form.call, currentFreqHz: form.freqHz, otherVfoHz: otherVfoHz)
            || CallFieldClusterCommand.command(form.call) != nil
    }

    /// What the key router needs at the moment of the event, for the field with the focus.
    public func keyContext(field: EntryKeyField) -> EntryKeyContext {
        EntryKeyContext(bindings: KeyBindings(config.config.keyBindings), field: field, callText: form.call,
                        isCw: form.mode == .cw, esmActive: esmActive, hasLastSent: !operating.lastSentKeys.isEmpty,
                        isSending: ports.keyer.isSending || operating.cqRepeat, scpPick: scpPick,
                        suggestionCount: suggestions().count, hasCommand: hasCommand,
                        twoRadios: rig?.otherEntry(than: self) != nil)
    }

    // MARK: - key decisions

    /// Executes a decision of `EntryKeyRouter`; `true` = the event is consumed.
    @discardableResult
    public func handle(_ decision: EntryKeyDecision) -> Bool {
        switch decision {
        case .passThrough:
            return false
        case .consume:
            return true
        case .shiftHeld(let held, let then):
            shiftHeld = held
            return handle(then)
        case .action(let action):
            runShortcut(action)
        case .functionKey(let index, let shift, let ctrlShift):
            if !ctrlShift && !voiceStackMacros([index], opposite: shift) {
                return true
            }
            let outcome = FunctionKeyRouter.press(index: index, shift: shift, ctrlShift: ctrlShift,
                                                  context: functionKeyContext())
            noteSerialSent([index], opposite: shift, outcome: outcome)
            apply(outcome, opposite: shift)
        case .cwSpeed(let steps):
            // Kotlin `changeCwSpeed(±config.cwSpeedStep)` on the press (`EP:966-967`).
            if let message = ports.keyer.changeCwSpeed(by: steps * config.config.cwSpeedStep) {
                show(message)
            }
        case .cwSpeedSecondary(let steps):
            // N1MM Shift+PgUp/PgDn: the secondary CW speed step.
            if let message = ports.keyer.changeCwSpeed(by: steps * config.config.cwSpeedStepSecondary) {
                show(message)
            }
        case .tune(let direction):
            tuneStep(direction)
        case .spectrumJump(let direction):
            // Without a spectrum (window closed, no line yet) the keys tune like the plain arrows.
            if spectrumJump?(direction, form.freqHz) != true {
                tuneStep(direction)
            }
        case .enter(let ctrl, let step):
            if ctrl, step == .esm, rig?.otherEntry(than: self) != nil {
                // N1MM Ctrl+Enter (SO2R / SO2V): the next ESM step on the alternate radio.
                esmOnOtherRadio()
            } else {
                enter(step)
            }
        case .alternateFunctionKey(let index):
            sendOnOtherRadio(index)
        case .escape(let step):
            escape(step)
        case .resendLast:
            sendKeys(operating.lastSentKeys, refocus: false)
        case .scpMove(_, let to):
            scpPick = to
        case .focusMove(let by, let skipReports):
            focusMoveCounter += 1
            focusMoveRequest = FocusMove(id: focusMoveCounter, by: by, skipReports: skipReports)
        case .jumpToExchange:
            jumpToExchange()
        }
        return true
    }

    /// Enter released (`EP:974-985`).
    private func enter(_ step: EntryEnterStep) {
        switch step {
        case .takeSuggestion(let index):
            takeSuggestion(index)
        case .logQso where quickEdit != nil, .esm where quickEdit != nil:
            saveQuickEdit()
        case .logQso(let ctrlEnter):
            submit(ctrlEnter: ctrlEnter)
        case .esm:
            esmEnter()
        }
    }

    /// Esc released (`EP:970`, `EP:992-993`): Kotlin evaluates `state.stopSending()` on every release that gets
    /// this far — when it stops something the release ends there, otherwise its side effects (the CQ repeat off, an
    /// open CW keyer aborted) still happen before the suggestion is cancelled or the fields are wiped (which
    /// keeps the unwipe memory).
    private func escape(_ step: EntryEscapeStep) {
        switch step {
        case .stopSending:
            _ = stopSending()
        case .cancelSuggestion:
            _ = stopSending()
            scpPick = -1
        case .wipe:
            _ = stopSending()
            wipe()
        }
    }

    /// Kotlin `stopSending()` (`AS:1757-1765`): tuning first (the CQ repeat stays); otherwise the CQ repeat goes
    /// off and the first of voice, fldigi and CW that was active is stopped (`StopSendingChain`). `true` =
    /// something was stopped (the CQ repeat counts).
    @discardableResult
    public func stopSending() -> Bool {
        // Esc releases a plugin's PTT too (plugin transmissions stay blocked until allowed again), and goes on to
        // stop everything else.
        rig?.operatorStopped()
        cancelDeferred()
        let pluginPtt: Bool = rig?.releasePluginPtt(stoppingEverything: true) ?? false
        let keyer: any KeyerPort = ports.keyer
        if keyer.isTuning {
            _ = keyer.stopSending()
            return true
        }
        let repeating: Bool = operating.cqRepeat
        operating.applyCqRepeat(false)
        let stopped: Bool = keyer.stopSending()
        return stopped || repeating || pluginPtt
    }

    /// Kotlin `takeSuggestion(index)`.
    public func takeSuggestion(_ index: Int) {
        let shown: [String] = suggestions()
        guard index >= 0, index < shown.count else { return }
        callChanged(shown[index])
        scpPick = -1
    }

    /// Kotlin `takeCall(c)` (a click on an N+1 or a reverse lookup call): the call, no highlight.
    public func takeCall(_ call: String) {
        callChanged(call)
        scpPick = -1
    }

    /// The call history prefill (Kotlin writes `cexch[id]` directly in `LaunchedEffect(call, state.callHistory, …)`):
    /// the contest fields of `prefilled` replace the form's without touch marks, and the preview follows (`cexch` is
    /// a key of the preview effect).
    public func applyCallHistoryPrefill(_ prefilled: EntryForm) {
        for (id, value) in prefilled.contestExchange.entries {
            if let value, !KotlinStrings.isBlank(value), form.contestExchange[id] != value {
                autoFilled[id] = value
            }
        }
        form.contestExchange = prefilled.contestExchange
        updatePreview()
    }

    // MARK: - shortcuts

    /// Kotlin `runShortcut(action)` (`EP:873-938`) for the actions handled here; the others are unavailable.
    public func runShortcut(_ action: ShortcutAction) {
        switch EntryActionAvailability.area(of: action) {
        case .local:
            runLocalShortcut(action)
        case .windows:
            if action == .functionKeysSetup {
                // Kotlin `openSettingsTab("function-keys")` (`EP:895`).
                openSettingsTab("function-keys")
            } else if action == .help {
                openHelp()
            } else {
                unavailable()
            }
        case .radio:
            runRadioShortcut(action)
        case .keyer:
            runKeyerShortcut(action)
        case .spots:
            runSpotShortcut(action)
        case .network:
            runNetworkShortcut(action)
        }
    }

    /// Alt+H (`AppState.openHelp`): the project's documentation in the browser, through the URL port (inert under
    /// `MCL_INERT_NETWORK`, a recording fake in tests). Without the wiring the action is unavailable.
    public func openHelp() {
        guard let helpOpener else {
            unavailable()
            return
        }
        helpOpener()
    }

    /// The network's shortcuts (`EP:906-909`): Ctrl+Alt+P passes the typed call, Ctrl+Alt+K takes the next call of the
    /// partner's stack.
    private func runNetworkShortcut(_ action: ShortcutAction) {
        switch action {
        case .passCall:
            network?.startPass()
        case .popStack:
            grabFromStack()
        case .toggleStationType:
            toggleStationType()
        case .passFrequency:
            promptPassFrequency()
        default:
            unavailable()
        }
    }

    /// N1MM Ctrl+Alt+M: the multi-op station type Run ↔ Mult (saved; the network status carries it).
    func toggleStationType() {
        let next: OperatingGuard.StationType = config.config.cluster.stationType == .run ? .mult : .run
        config.config.cluster.stationType = next
        config.saveSilently()
        status.show("Typ stanice: %s", .string(config.config.cluster.announcedStationType))
    }

    /// N1MM Alt+Z: the pass frequency (kHz, the current one offered; empty = clear) for the other stations.
    func promptPassFrequency() {
        guard let network else {
            unavailable()
            return
        }
        let initial: String = form.freqHz > 0 ? FrequencyText.formatKHz(Double(form.freqHz) / 1000) : ""
        dialogs.prompt(title: ContestMessage("Pass frekvence"),
                       hint: ContestMessage("Frekvence v kHz, na které přijímáš předané stanice (prázdné = zrušit)"),
                       initial: initial) { [weak network] text in
            network?.setPassFrequency(text)
        }
    }

    /// The keyer's shortcuts: Ctrl+K opens the CW keyboard window (`EP:916`) once that window exists.
    private func runKeyerShortcut(_ action: ShortcutAction) {
        if action == .cwKeyboard && form.mode.isDigital && digitalReady {
            // N1MM Ctrl+K in a digital mode: transmit and type in the Digital Interface's TX window.
            windows.setOpen("digitalinterface", true)
            digitalKeyer?.startHold()
            digitalKeyer?.txFocusRequest += 1
        } else if action == .cwKeyboard && WindowsModel.implemented.contains("cwkeyboard") {
            windows.setOpen("cwkeyboard", true)
        } else {
            unavailable()
        }
    }

    private func runLocalShortcut(_ action: ShortcutAction) {
        switch action {
        case .sendCallExchange, .tuAndLog, .logWithoutSending:
            sendAndLog(action)
        case .forceLog:
            forceLog()
        case .wipe:
            wipeMemory.clear()
            wipe()
        case .wipeUndo:
            unwipe()
        case .deleteLast:
            dialogs.ask(.deleteLast)
        case .note:
            promptNote()
        case .find:
            findInLog()
        case .editLast:
            editLastContact()
        case .quickEditBack:
            quickEditStep(-1)
        case .quickEditForward:
            quickEditStep(1)
        case .gridSearch:
            gridSearch()
        case .gridToggle:
            toggleGrid()
        case .incrementNr:
            incrementNumber()
        case .wipeOther:
            wipeOtherWindow()
        case .qtcMode:
            toggleQtcMode()
        case .stackCall:
            // Digital Call Stacking: Ctrl+Alt+G moves the Grab window's call onto the stack (N1MM).
            if form.mode.isDigital, config.config.digital.digitalCallStacking, let grabList,
               let call = grabList.highlighted {
                if callStack?.push(call) == true {
                    grabList.remove(call)
                }
            } else {
                stackAnother(label: "Ctrl+Alt+G", runOnly: false)
            }
        case .grabStack:
            // Alt+G: in a digital mode the Grab window's call (N1MM), otherwise the next stacked call.
            if form.mode.isDigital, grabList?.highlighted != nil {
                grabFromList()
            } else {
                grabFromStack()
            }
        case .insertGrab:
            insertKey()
        case .toggleTx:
            toggleDigitalTx()
        case .digitalLeft, .digitalRight:
            // N1MM Ctrl+←/→: both foci to VFO A / rig 1 or VFO B / rig 2; in a digital mode with its Digital
            // Interface.
            let side: Int = action == .digitalLeft ? 0 : 1
            if let rig, rig.vfo.twoEntryWindows {
                rig.focusBoth(side)
            }
            if form.mode.isDigital || rig?.vfo.twoEntryWindows != true {
                windows.setOpen(side == 0 ? "digitalinterface" : "digitalinterface2", true)
            }
        default:
            runOperatingShortcut(action)
        }
    }

    /// N1MM Ctrl+F / Find Again: the log window shows the typed call's QSOs; Ctrl+F again with the same call (the log
    /// still showing them) selects the next one.
    func findInLog() {
        let query: String = WindowsModel.findQuery(form.call)
        if !query.isEmpty, windows.isOpen("log"), logbook.query == query {
            windows.findNextInLog()
        } else {
            windows.findInLog(form.call)
        }
    }

    /// N1MM Alt+Y: the Check window's next call into the call field (or its exchange value into the exchange field
    /// being typed); without one the first Check partial suggestion, as before.
    func yank() {
        let field: EntryFieldKey? = focusedField?()
        if let checkYank, let value = checkYank(self, field) {
            if case .contest(let id)? = field {
                editContestField(id, value)
            } else {
                takeCall(value)
            }
            return
        }
        if !suggestions().isEmpty {
            takeSuggestion(0)
        }
    }

    private func runOperatingShortcut(_ action: ShortcutAction) {
        switch action {
        case .toggleEsm:
            operating.setEsm(!operating.esmEnabled)
        case .toggleCut:
            operating.toggleCutNumbers()
        case .yankScp:
            yank()
        case .operator:
            dialogs.openOperator()
        case .toggleRun:
            operating.toggleRun(freqHz: form.freqHz)
        case .cqRepeat:
            operating.setCqRepeat(!operating.cqRepeat)
        case .cqRepeatTime:
            promptRepeatTime()
        case .autoRunSp:
            operating.setAutoRunSwitch(!operating.autoRunSwitch)
        default:
            unavailable()
        }
    }

    /// `SEND_CALL_EXCHANGE`, `TU_AND_LOG`, `LOG_WITHOUT_SENDING` (`EP:875-884`).
    private func sendAndLog(_ action: ShortcutAction) {
        if let keys = EsmFlow.shortcutKeys(action, canTransmit: canTransmit, esmActive: esmActive,
                                           exchangeValid: exchangeValid, keyMap: config.config.esm.keys) {
            sendKeys(keys, refocus: false)
        }
        if action != .sendCallExchange {
            submit()
        }
    }

    /// Kotlin `promptRepeatTime()` (Ctrl+R).
    private func promptRepeatTime() {
        let operating: OperatingModel = self.operating
        dialogs.prompt(title: ContestMessage("Opakování CQ"),
                       hint: ContestMessage("Pauza mezi CQ v sekundách (např. 2.5); číslo nad 100 se bere jako milisekundy"),
                       initial: operating.repeatTimeText) { text in
            operating.applyRepeatTime(text)
        }
    }

    // MARK: - entry actions

    /// Alt+W (`wipeReversible`, `EP:569-589`): wipe and remember, or restore into empty fields.
    public func unwipe() {
        let outcome = wipeMemory.wipeReversible(form: form, contestActive: contest.isActive,
                                                rstFieldIds: EntryForm.rstFieldIds(fields))
        wipeMemory = outcome.memory
        if outcome.wiped {
            form = outcome.form
            esmProgress = .empty
            // Kotlin `wipe()`: `callFromSpot = false`.
            selfSpot.typed()
        } else {
            let previous: String = form.call
            form = outcome.form
            esmProgress = EsmFlow.afterCallChange(esmProgress, previousCall: previous, call: form.call)
            if let message = outcome.status {
                show(message)
            }
        }
        updatePreview()
        trackCallForSelfSpot()
        focusRequest += 1
    }

    /// Ctrl+U (`incrementExchangeNumber`, `EP:599-609`).
    public func incrementNumber() {
        form = ExchangeIncrement.apply(form: form, fields: fields, contestActive: contest.isActive)
        updatePreview()
    }

    /// Ctrl+N (`promptNote`, `AS:911-929`): a note for the QSO in progress (kept until it is logged) or for the
    /// last logged QSO (saved at once).
    public func promptNote() {
        let forCurrent: Bool = !KotlinStrings.isBlank(form.call)
        let last: Qso? = logbook.lastRow
        if !forCurrent && last == nil {
            status.show(EntryTexts.noteEmptyLog)
            return
        }
        let title: ContestMessage = forCurrent
            ? ContestMessage(EntryTexts.noteTitleCurrent)
            : ContestMessage(EntryTexts.noteTitleLast, .string(last?.call ?? ""))
        let initial: String = forCurrent ? (pendingNote ?? "") : (last?.comment ?? "")
        dialogs.prompt(title: title, hint: ContestMessage(EntryTexts.noteHint), initial: initial) { [weak self] note in
            self?.noteEntered(note, forCurrent: forCurrent, last: last)
        }
    }

    private func noteEntered(_ note: String, forCurrent: Bool, last: Qso?) {
        if forCurrent {
            pendingNote = KotlinStrings.isBlank(note) ? nil : note
            status.show(EntryTexts.notePending)
            return
        }
        guard let last else { return }
        var edited: Qso = last
        edited.comment = KotlinStrings.isBlank(note) ? "" : note
        let logbook: LogbookModel = self.logbook
        let edit = LogbookMutations.Edit(old: last, new: edited)
        track {
            await logbook.update(edit)
        }
        status.show(EntryTexts.noteSaved, .string(last.call))
    }

    /// Ctrl+Alt+Enter (`forceLog`, `EP:592-597`): a note prompt, then the QSO is logged past the exchange check and
    /// the operating rules.
    public func forceLog() {
        guard !KotlinStrings.isBlank(form.call) else { return }
        dialogs.prompt(title: ContestMessage(EntryTexts.forcedTitle, .string(form.call)),
                       hint: ContestMessage(EntryTexts.forcedHint), initial: "") { [weak self] note in
            self?.submit(force: true, comment: EntryTexts.forcedNote(note))
        }
    }

    /// Space in the call field (`jumpToExchange`, `EP:856-861`).
    public func jumpToExchange() {
        // N1MM: the space bar puts the call-frame's call into an empty call field.
        takeCallFrame()
        esmProgress = EsmFlow.jumpToExchange(esmProgress, esmEnabled: operating.esmEnabled, mode: form.mode,
                                             run: operating.isRun, call: form.call)
        exchangeFocusRequest += 1
        if isActivePanel {
            rig?.callEntered()
        }
        integrations?.callLookedUp(call: form.call, freqHz: Int(form.freqHz), mode: form.mode,
                                   radioNr: rig?.vfo.so2r == true ? (rig?.vfo.catIndex(for: vfo) ?? 0) + 1 : 1)
    }

    /// Kotlin `jumpToCqFrequency(band)` (Alt+Q, `{CQFREQ}`): the band's CQ frequency into the field, Run, the QSY to
    /// the rig port; the tuning effect follows as in Kotlin (`LaunchedEffect(tunedFreqHz, mode)`, section 46).
    @discardableResult
    func jumpToCqFrequency() -> Bool {
        guard let cq = operating.jumpToCqFrequency(band: band) else { return false }
        form.freqKHz = FrequencyText.formatHz(cq)
        if cq > 0 {
            ports.rig.qsy(hz: cq)
        }
        fieldFrequencyChanged()
        updatePreview()
        reportTuned(cq)
        return true
    }

    /// N1MM Ctrl+Alt+Q: the last CQ frequency on any band into the field, Run, the QSY to the rig port (the band map
    /// follows the rig).
    @discardableResult
    func jumpToLastCqFrequency() -> Bool {
        guard let cq = operating.jumpToLastCqFrequency() else { return false }
        form.freqKHz = FrequencyText.formatHz(cq)
        ports.rig.qsy(hz: cq)
        fieldFrequencyChanged()
        updatePreview()
        reportTuned(cq)
        return true
    }

    /// N1MM Ctrl+Shift+W: wipe the other entry window (SO2V / SO2R); the focus stays here.
    func wipeOtherWindow() {
        guard let other = rig?.otherEntry(than: self) else {
            status.show("Druhé okno není otevřené (SO2V / SO2R)")
            return
        }
        other.wipeMemory.clear()
        other.wipe(focus: false)
    }

    // MARK: - ESM and F-keys

    /// Enter in ESM (`esmEnter`, `EP:817-835`).
    public func esmEnter() {
        let outcome: EsmFlow.Outcome = EsmFlow.enter(esmInput)
        if let message = outcome.status {
            show(message)
            return
        }
        var keys: [Int] = outcome.keys
        if autoSentCurrentCall {
            // AutoSend already sent the call while it was typed: the ESM Enter sends the rest without it.
            keys.removeAll { $0 == config.config.esm.keys.hisCall }
        }
        if !keys.isEmpty {
            // N1MM „Send partial calls": the corrected call's resend carries only the part that changed.
            if config.config.esm.sendPartialCalls, operating.isRun, esmProgress.callCorrected(form.call) {
                partialCallSend = PartialCall.part(sent: esmProgress.sentCall, call: form.call)
            }
            sendKeys(keys, refocus: false)
            partialCallSend = nil
        }
        if outcome.log {
            submit()
            return
        }
        switch outcome.focus {
        case .exchange:
            exchangeFocusRequest += 1
        case .call:
            focusRequest += 1
        default:
            break
        }
    }

    /// Kotlin `functionKeys(indices, refocus, opposite)` (ESM, the send shortcuts, `=`).
    func sendKeys(_ indices: [Int], opposite: Bool = false, refocus: Bool) {
        guard !indices.isEmpty else { return }
        guard voiceStackMacros(indices, opposite: opposite) else { return }
        let outcome = FunctionKeyRouter.send(indices, opposite: opposite, refocus: refocus,
                                             context: functionKeyContext())
        noteSerialSent(indices, opposite: opposite, outcome: outcome)
        apply(outcome, opposite: opposite)
    }

    /// N1MM's serial sequence warning: the first transmitted message of the QSO that carries the serial number
    /// remembers it (compared when the QSO is logged).
    private func noteSerialSent(_ indices: [Int], opposite: Bool, outcome: FunctionKeyOutcome) {
        guard outcome.transmission != nil, serialSentInQso == nil, contest.isActive,
              !KotlinStrings.isBlank(form.call) else { return }
        let set: [FunctionKeyMessage] = currentKeySet(opposite: opposite)
        let exchange: String = cwExchange()
        if indices.contains(where: { $0 < set.count && EntryAssist.sendsSerial(set[$0].text, sentExchange: exchange) }) {
            serialSentInQso = logbook.nextSerial(band: band)
        }
    }

    /// The outcome of an F-key press in Kotlin order: status, ESM progress and last keys, the transmission, the macro
    /// actions, `onCqSent`, the focus. The keyer's own failure text comes last, as Kotlin's asynchronous `sendCw`
    /// failure does.
    private func apply(_ outcome: FunctionKeyOutcome, opposite: Bool) {
        if let message = outcome.status {
            show(message)
        }
        if let progress = outcome.progress {
            esmProgress = progress
        }
        if let keys = outcome.lastSentKeys {
            operating.lastSentKeys = keys
        }
        var keyerStatus: EntryStatus?
        if let transmission = outcome.transmission {
            // N1MM: the transmit focus moves to the window the message is sent from (SO2R).
            rig?.claimTx(vfo)
            if config.config.showSentCw || rig?.vfo.so2r == true, case .cw(let message, _) = transmission {
                // N1MM „Display Sent CW" (always on in SO2R): what goes out, in the status line.
                show(.verbatim(sentCwPrefix + EntryAssist.sentText(message)))
            }
            keyerStatus = ports.keyer.send(transmission, settings: keyerSettings(opposite: opposite))
            afcWithCq(transmission)
        }
        if let key = outcome.recordKey, let message = ports.keyer.toggleRecording(key) {
            show(message)
        }
        if outcome.transmission != nil {
            operating.noteVaryUsed(outcome.varyUsed)
        }
        // The parameterized macros first: a `{COMMENT}` belongs to the QSO a `{LOG}` of the same message logs.
        performMacroCommands(outcome.commands)
        scheduleDeferred(outcome)
        for action in outcome.actions {
            if action == .logThenPop {
                logThenPop(next: outcome.stackNextCall, progress: outcome.stackProgress,
                           fromGrab: outcome.nextFromGrab)
            } else {
                performMacroAction(action)
            }
        }
        if let freqHz = outcome.cqSentFreqHz {
            operating.onCqSent(freqHz)
            grabList?.cqSent()
        }
        if outcome.refocus {
            focusRequest += 1
        }
        if let keyerStatus {
            show(keyerStatus)
        }
    }

    /// `CwMessage.Action` of a sent message (`EP:731-741`).
    func performMacroAction(_ action: CwMessage.Action) {
        switch action {
        case .log:
            submit()
        case .wipe:
            wipe()
        case .run:
            operating.runMode = .run
        case .searchAndPounce:
            operating.runMode = .searchAndPounce
        case .clearRit:
            if let message = ports.rig.clearRit() {
                show(message)
            }
        case .cqFrequency:
            if jumpToCqFrequency() {
                wipe()
            }
        case .splitOff:
            if let message = ports.rig.splitOff() {
                show(message)
            }
        case .soCallStack:
            soCallStack()
        case .stackAnother:
            stackAnother(label: "{STACKANOTHER}", runOnly: true)
        case .clearStack:
            callStack?.clear()
        case .logThenPop:
            logThenPop(next: callStack?.next, progress: nil)
        case .grab:
            grabFromList()
        case .grabDeleteAll:
            grabList?.clear()
        case .grabDeleteTop:
            grabList?.removeTop()
        case .grabDeleteSelected:
            grabList?.removeSelected()
        case .resumeCq:
            if operating.isRun {
                operating.applyCqRepeat(true)
            }
        case .digitalTx:
            if form.mode.isDigital && digitalReady {
                digitalKeyer?.startHold()
            }
        case .digitalRx:
            digitalKeyer?.endHold()
        case .toggleTx:
            toggleDigitalTx()
        case .clearRx:
            digitalKeyer?.clearRxWindow?()
        case .clearTx:
            digitalKeyer?.clearTxBuffer()
        case .jumpCq:
            if jumpToCqFrequency() {
                wipe()
            }
        case .align:
            alignDigital()
        case .afcOn:
            digitalKeyer?.set(.afc, true)
        case .afcOff:
            digitalKeyer?.set(.afc, false)
        case .netOn:
            digitalKeyer?.setNet(true)
        case .netOff:
            digitalKeyer?.setNet(false)
        case .spotMe:
            spotMeMacro()
        case .cq:
            if canTransmit {
                operating.onCqSent(form.freqHz)
                grabList?.cqSent()
            }
        case .exchangeSent:
            esmProgress = esmProgress.withExchangeSent()
        case .ctrlHome:
            focusRequest += 1
        case .forceLog:
            if !KotlinStrings.isBlank(form.call) {
                // A `{COMMENT}` (or Ctrl+N) note stays the QSO's note; otherwise the forced-QSO note.
                submit(force: true, comment: pendingNote == nil ? EntryTexts.forcedNote("") : nil)
            }
        case .forceLogNote:
            forceLog()
        case .space:
            jumpToExchange()
        case .pageUp, .freqDown:
            // N1MM: {PGUP} moves the rig down and {PGDN} up by the PgUp/PgDn step.
            macroQsy(-config.config.macroQsyStepKHz)
        case .pageDown, .freqUp:
            macroQsy(config.config.macroQsyStepKHz)
        case .turnRotor:
            rig?.rotator.turnToCall(KotlinStrings.trim(form.call), longPath: false)
        case .longPath:
            rig?.rotator.turnToCall(KotlinStrings.trim(form.call), longPath: true)
        case .stopRotor:
            rig?.rotator.stop()
        case .manualPtt:
            if let message = ports.keyer.manualPtt() {
                show(message)
            }
        case .jumpRx, .jumpRxTx:
            jumpToOtherWindow(withTx: action == .jumpRxTx)
        case .condJump:
            if rig?.activeState?.split != true {
                jumpToOtherWindow()
            }
        case .stopTx:
            ports.keyer.releasePtt()
        case .stereoOn, .stereoOff:
            rig?.setSo2rStereo(action == .stereoOn)
        case .activeAudioToggle, .activeAudioOn, .activeAudioOff:
            rig?.setAudio(inactive: false, on: action == .activeAudioToggle ? nil : action == .activeAudioOn)
        case .inactiveAudioToggle, .inactiveAudioOn, .inactiveAudioOff:
            rig?.setAudio(inactive: true, on: action == .inactiveAudioToggle ? nil : action == .inactiveAudioOn)
        case .popPrevNeeded, .popNextNeeded:
            popNeeded(forward: action == .popNextNeeded)
        case .qtcReceive, .qtcSend:
            openQtcWindow(send: action == .qtcSend)
        }
    }

    // MARK: - two radios

    /// The prefix of the sent CW echo: in SO2R the radio it goes out on (N1MM echoes it in that radio's window).
    var sentCwPrefix: String {
        rig?.vfo.so2r == true ? "CW R" + String(vfo + 1) + ": " : "CW: "
    }

    /// `{JUMPRX}` / `{JUMPRXTX}`: the other entry window becomes the active one with the focus (SO2R / SO2V);
    /// `{JUMPRX}` moves only the entry focus in SO2R (N1MM), `{JUMPRXTX}` the transmit focus too.
    func jumpToOtherWindow(withTx: Bool = true) {
        guard let rig, let other = rig.otherEntry(than: self) else {
            status.show("Druhé okno není otevřené (SO2V / SO2R)")
            return
        }
        rig.requestFocusVfo(other.vfo, rxOnly: !withTx)
    }

    /// `{CTRLFn}` and Ctrl+F1–F12 (N1MM): the key's message of the other entry window, sent on its radio.
    func sendOnOtherRadio(_ index: Int) {
        alternateRadio { other in
            other.handle(.functionKey(index, shift: false, ctrlShift: false))
        }
    }

    /// N1MM Ctrl+Enter (SO2R / SO2V): the next ESM step of the other entry window, on its radio.
    func esmOnOtherRadio() {
        alternateRadio { other in
            guard other.esmActive else {
                other.status.show("ESM není zapnutý")
                return
            }
            other.esmEnter()
        }
    }

    /// N1MM „send on the alternate radio": in SO2R the other window sends on its rig and only the transmit focus
    /// moves there (the entry focus stays here, the transmit focus stays there afterwards). One rig (SO2V) has one
    /// transmitter: the other VFO becomes active for the message — with the focus when this window's call field is
    /// empty, otherwise it comes back here once the message has been sent.
    private func alternateRadio(_ send: (EntryModel) -> Void) {
        guard let rig, let other = rig.otherEntry(than: self) else {
            status.show("Druhé okno není otevřené (SO2V / SO2R)")
            return
        }
        if rig.vfo.so2r {
            send(other)
            return
        }
        let stay: Bool = !KotlinStrings.isBlank(form.call)
        if stay {
            rig.activateVfo(other.vfo)
        } else {
            rig.requestFocusVfo(other.vfo)
        }
        send(other)
        guard stay else { return }
        returnGeneration &+= 1
        let generation: Int = returnGeneration
        if ports.keyer.isSending {
            watchReturn(generation)
        } else {
            rig.activateVfo(vfo)
        }
    }

    private func watchReturn(_ generation: Int) {
        withObservationTracking {
            _ = ports.keyer.isSending
        } onChange: { [weak self] in
            MainHop.post {
                guard let self, generation == self.returnGeneration else { return }
                if self.ports.keyer.isSending {
                    self.watchReturn(generation)
                } else {
                    self.rig?.activateVfo(self.vfo)
                }
            }
        }
    }

    // MARK: - needed QSOs (VHF)

    /// `{POPPREVNEEDEDQ}` / `{POPNEXTNEEDEDQ}` (N1MM): the stations of the log not yet worked on this window's band,
    /// in log order; the previous / next one (from the call in the field) comes into the window with its exchange
    /// (the serial and the reports excepted).
    func popNeeded(forward: Bool) {
        guard let band else {
            status.show("Potřebné stanice: neznámé pásmo")
            return
        }
        var order: [String] = []
        var latest: [String: Qso] = [:]
        var worked: Set<String> = []
        for qso in logbook.rows {
            let key: String = KotlinStrings.uppercase(KotlinStrings.trim(qso.call))
            guard !key.isEmpty else { continue }
            if latest[key] == nil {
                order.append(key)
            }
            latest[key] = qso
            if qso.band == band {
                worked.insert(key)
            }
        }
        let needed: [String] = order.filter { !worked.contains($0) }
        guard !needed.isEmpty else {
            status.show("Žádná potřebná stanice na pásmu %s", .string(band.adif))
            return
        }
        let current: String = KotlinStrings.uppercase(KotlinStrings.trim(form.call))
        let next: Int
        if let at = needed.firstIndex(of: current) {
            next = (at + (forward ? 1 : needed.count - 1)) % needed.count
        } else {
            next = forward ? 0 : needed.count - 1
        }
        guard let qso = latest[needed[next]] else { return }
        wipe(focus: false)
        callChanged(qso.call)
        if contest.isActive {
            let received = try? contest.runtime.freshSession()?.receivedFromFlat(
                call: qso.call, exchangeRcvdFlat: qso.exchangeRcvd, serialRcvd: qso.serialRcvd)
            for field in contest.exchangeFields(call: qso.call) {
                guard let id = field.id, ![.RST, .RS, .SERIAL].contains(field.type),
                      let value = received?.entries.first(where: { $0.0 == id })?.1 ?? nil,
                      !value.isEmpty else { continue }
                editContestField(id, value)
            }
        }
        status.show("Potřebná stanice %s (%s z %s)", .string(qso.call), .int(next + 1), .int(needed.count))
    }

    // MARK: - contests

    /// `{SWAPCONTESTS}` / `{SWAPCONTESTSn}` (N1MM): the oldest of the last `count` contests opened (so repeating it
    /// cycles through them); `{SWAPCONTESTS name}`: the recent contest whose title holds the name. The QSO in
    /// progress (call and exchange) moves to the opened contest.
    func swapContests(count: Int?, name: String? = nil) {
        let recent: [ContestModel.RecentContest] = contest.recent.filter { $0.contestId != contest.activeId }
        let target: ContestModel.RecentContest?
        if let name {
            target = recent.first { $0.title.localizedCaseInsensitiveContains(name) }
        } else if let count {
            target = recent.isEmpty ? nil : recent[min(count - 1, recent.count) - 1]
        } else {
            target = nil
        }
        guard let target else {
            status.show("Není jiný naposledy otevřený závod")
            return
        }
        let call: String = form.call
        let exchange = form.contestExchange
        let opening: Task<Void, Never> = contest.openRecent(contestId: target.contestId)
        Task { [weak self] in
            await opening.value
            guard let self, !KotlinStrings.isBlank(call) else { return }
            self.callChanged(call)
            for (id, value) in exchange.entries {
                if let id, let value, !value.isEmpty {
                    self.editContestField(id, value)
                }
            }
        }
    }

    /// A parameterized macro of a sent message (N1MM `{COMMENT text}`…).
    func performMacroCommand(_ command: MacroCommand) {
        performMacroCommands([command])
    }

    /// The parameterized macros of a message in order; `{CATDELAY}` pauses the rig's lane after the message's last CAT
    /// command (N1MM: wherever it stands).
    func performMacroCommands(_ commands: [MacroCommand]) {
        var delay = 0
        for case .catDelay(let n) in commands {
            delay = n
        }
        let lastCat: Int? = commands.lastIndex { if case .cat = $0 { true } else { false } }
        for (index, command) in commands.enumerated() {
            switch command {
            case .comment(let text):
                addComment(text)
            case .cat(let macro):
                rig?.sendMacroCat(macro, delayMs: index == lastCat ? delay * 50 : 0)
            case .catDelay:
                break
            case .telnet(let text):
                if clusterCommand?(text) != true {
                    show(.tr("{TELNET}: DX cluster není připojený"))
                }
            case .setWavDir(let text):
                operating.setWavDir(text)
            case .auxAntenna(let code):
                rig?.selectAntenna(code: code)
            case .antennaRx(let port):
                rig?.toggleRxAntenna(port: port, transmitting: ports.keyer.isSending)
            case .otherRadioKey(let index):
                sendOnOtherRadio(index)
            case .otrsp(let text, let other):
                rig?.sendOtrsp(text, other: other)
            case .swapContests(let count):
                swapContests(count: count)
            case .swapContest(let name):
                swapContests(count: nil, name: name)
            case .networkMessage(let text):
                network?.sendMacroMessage(text)
            case .passAlert(_, let hz):
                network?.lastPassedFreqHz = hz
            case .passLastQso(let argument):
                network?.passLastQso(argument, call: logbook.rows.last?.call ?? "")
            }
        }
    }

    /// `{PGUP}` / `{PGDN}` / `{FREQUP}` / `{FREQDN}`: the entry window and the rig by `deltaKHz`.
    private func macroQsy(_ deltaKHz: Int) {
        let current: Int64 = form.freqHz
        guard current > 0 else { return }
        let hz: Int64 = current + Int64(deltaKHz) * 1000
        guard hz > 0 else { return }
        form.freqKHz = FrequencyText.formatHz(hz)
        ports.rig.qsy(hz: hz)
        fieldFrequencyChanged()
        updatePreview()
        reportTuned(hz)
    }

    // MARK: - {END}

    /// N1MM `{END}`: the macros after it run once the transmission has finished. A message that sent nothing drops
    /// them; a newer message or Esc cancels them.
    private func scheduleDeferred(_ outcome: FunctionKeyOutcome) {
        deferredGeneration &+= 1
        pendingDeferred = nil
        guard outcome.transmission != nil,
              !outcome.deferredActions.isEmpty || !outcome.deferredCommands.isEmpty,
              ports.keyer.isSending else { return }
        pendingDeferred = (outcome.deferredActions, outcome.deferredCommands)
        watchDeferred(deferredGeneration)
    }

    private func watchDeferred(_ generation: Int) {
        withObservationTracking {
            _ = ports.keyer.isSending
        } onChange: { [weak self] in
            MainHop.post {
                self?.deferredCheck(generation)
            }
        }
    }

    private func deferredCheck(_ generation: Int) {
        guard generation == deferredGeneration, let pending = pendingDeferred else { return }
        if ports.keyer.isSending {
            watchDeferred(generation)
            return
        }
        pendingDeferred = nil
        performMacroCommands(pending.commands)
        for action in pending.actions {
            performMacroAction(action)
        }
    }

    /// Esc: the `{END}` macros of the stopped message never run.
    func cancelDeferred() {
        deferredGeneration &+= 1
        pendingDeferred = nil
    }

    /// `{COMMENT text}`: the text joins the note of the QSO in progress, or of the last logged QSO when the call
    /// field is empty.
    private func addComment(_ text: String) {
        if !KotlinStrings.isBlank(form.call) {
            let current: String = pendingNote ?? ""
            pendingNote = KotlinStrings.isBlank(current) ? text : current + " " + text
            return
        }
        guard let last = logbook.lastRow else { return }
        var edited: Qso = last
        edited.comment = KotlinStrings.isBlank(last.comment) ? text : last.comment + " " + text
        let logbook: LogbookModel = self.logbook
        let edit = LogbookMutations.Edit(old: last, new: edited)
        track {
            await logbook.update(edit)
        }
    }

    /// The outcome of a template send (a QTC message) applied as an F-key press's.
    func applyTemplateOutcome(_ outcome: FunctionKeyOutcome) {
        apply(outcome, opposite: false)
    }

    /// A Digital Interface message button: its text through fldigi, as an F-key message would go.
    public func sendDigitalButton(_ index: Int) {
        let buttons: [FunctionKeyMessage] = config.config.digital.diMessages
        guard index >= 0, index < buttons.count, !KotlinStrings.isBlank(buttons[index].text) else { return }
        let outcome = FunctionKeyRouter.sendDigitalTemplate(buttons[index].text, context: functionKeyContext())
        apply(outcome, opposite: false)
    }

    /// N1MM Align (`{ALIGN}`, the Digital Interface's button): the rig moves so the signal under fldigi's cursor is
    /// on the alignment frequency; the cursor follows.
    @discardableResult
    public func alignDigital() -> Bool {
        guard let digitalKeyer, let state = rig?.activeState else { return false }
        let rigPort = ports.rig
        return digitalKeyer.align(dialHz: state.freqHz, rawMode: state.rawMode) { hz in
            rigPort.qsy(hz: hz)
        }
    }

    /// Alt+T / `{ALT-T}` (digital, N1MM): fldigi transmits (the TX window takes the typing) or returns to receive.
    func toggleDigitalTx() {
        guard form.mode.isDigital, digitalReady, let digitalKeyer else {
            unavailable()
            return
        }
        let holding: Bool = digitalKeyer.isHolding
        digitalKeyer.toggleHold()
        if !holding {
            digitalKeyer.txFocusRequest += 1
        }
    }

    /// N1MM „AFC On/Off with CQ": the Run CQ and TU messages turn fldigi's AFC on, the S&P messages off.
    private func afcWithCq(_ transmission: FunctionKeyTransmission) {
        guard config.config.digital.afcOnCq, case .digital(_, let index, _) = transmission else { return }
        if !operating.isRun {
            digitalKeyer?.set(.afc, false)
        } else if index == config.config.esm.keys.cq || index == config.config.esm.keys.end {
            digitalKeyer?.set(.afc, true)
        }
    }

    // MARK: - the Grab window (digital, N1MM)

    /// Alt+G / `{GRAB}` / the Grab button: the Grab window's highlighted call into a wiped entry window. Options: the
    /// call in the field goes into the bandmap first (Alt+O) or — with Digital Call Stacking in Run — onto the call
    /// stack; the cursor moves on to the exchange (Send Space on Using Grab).
    public func grabFromList() {
        guard let grabList, let next = grabList.grab() else { return }
        let digital: DigitalConfig = config.config.digital
        let typed: String = CallStack.normalize(form.call)
        if !typed.isEmpty && typed != next {
            if digital.grabAddToBandmap {
                storeCall()
            }
            if digital.digitalCallStacking && operating.isRun {
                callStack?.push(typed)
            }
        }
        wipe()
        takeStacked(next)
        if digital.grabSendSpace {
            jumpToExchange()
        }
    }

    /// N1MM Insert (digital; also usable in the other modes): an empty call field grabs the Grab window's call, then
    /// his call + exchange (or F4 / F6) by Run/S&P, ESM and the dupe state; the cursor goes to the exchange.
    public func insertKey() {
        if KotlinStrings.isBlank(form.call), let grabList, let next = grabList.grab() {
            takeStacked(next)
        }
        guard !KotlinStrings.isBlank(form.call) else { return }
        let keys: [Int] = config.config.esm.keys.keys(
            InsertKey.keys(run: operating.isRun, esm: esmActive, dupe: isDupe,
                           workDupes: operating.esmOptions.workDupes, exchangeValid: exchangeValid))
        if !keys.isEmpty && canTransmit {
            sendKeys(keys, refocus: false)
        }
        exchangeFocusRequest += 1
    }

    // MARK: - call stacking (N1MM)

    /// Ctrl+Alt+G / `{STACKANOTHER}`: the call field onto the stack and a wiped entry window for the next one. A dupe
    /// is not stacked (the field stays).
    func stackAnother(label: String, runOnly: Bool) {
        guard let callStack else { return }
        if runOnly && !operating.isRun {
            show(.tr(CallStackTexts.runOnlyKey, .string(label)))
            return
        }
        if callStack.push(form.call) {
            wipe()
        }
    }

    /// `{SOCALLSTACK}` (Run only): an empty field takes the next call; a call with an empty stack is stacked and the
    /// field cleared; a call with a stacked call is exchanged with it. With an empty stack a dupe does nothing.
    func soCallStack() {
        guard let callStack else { return }
        if !operating.isRun {
            show(.tr(CallStackTexts.runOnlyKey, .string(CallStackMacro.soCallStack)))
            return
        }
        let typed: String = CallStack.normalize(form.call)
        if typed.isEmpty {
            if let next = callStack.pop() {
                takeStacked(next)
            }
            return
        }
        guard callStack.next != nil else {
            if !isDupe && callStack.push(typed) {
                wipe()
            }
            return
        }
        guard let next = callStack.pop(showEmpty: false) else { return }
        callStack.push(typed, quiet: true)
        wipe()
        takeStacked(next)
    }

    /// Alt+G (Ctrl+Alt+K): a wiped entry window with the next call from the stack.
    func grabFromStack() {
        guard let callStack else {
            unavailable()
            return
        }
        guard let next = callStack.pop() else { return }
        wipe()
        takeStacked(next)
    }

    /// A call from the stack in the field: it counts as typed (it is the operator's QSO), the call field has the focus.
    private func takeStacked(_ call: String) {
        callChanged(call)
        focusRequest += 1
    }

    /// `{LOGTHENPOP}`: the QSO is logged; when it was, the next call comes off the stack into the field and the ESM
    /// progress is what the rest of the message already sent to it.
    func logThenPop(next: String?, progress: EsmProgress?, fromGrab: Bool = false) {
        let logged: String = form.call
        submit()
        guard KotlinStrings.isBlank(form.call), !KotlinStrings.isBlank(logged) else { return }
        callStack?.remove(logged)
        grabList?.remove(logged)
        guard let next else { return }
        if fromGrab {
            grabList?.remove(next)
        } else {
            callStack?.remove(next)
        }
        takeStacked(next)
        if let progress {
            esmProgress = progress
        }
    }

    /// The stack macros of an SSB message run before it plays (the next call must be in the field for `!`):
    /// `false` = the press is refused (`{LOGTHENPOP}` outside Run or before the exchange was sent).
    private func voiceStackMacros(_ indices: [Int], opposite: Bool) -> Bool {
        guard EsmFlow.isPhone(form.mode), callStack != nil else { return true }
        let set: [FunctionKeyMessage] = currentKeySet(opposite: opposite)
        let texts: [String] = indices.compactMap { i in i >= 0 && i < set.count ? set[i].text : nil }
        let macros: [String] = texts.flatMap { CallStackMacro.voiceMacros($0) }
        for macro in macros {
            switch macro {
            case CallStackMacro.logThenPop, CallStackMacro.logThenNext:
                if !operating.isRun {
                    show(.tr("%s: {LOGTHENPOP} jen v Run", .string(FunctionKeyRouter.keysLabel(indices))))
                    return false
                }
                if KotlinStrings.isBlank(form.call) || !exchangeValid || !esmProgress.exchangeSent {
                    show(.tr("%s: výměna nebyla odeslána nebo není úplná — {LOGTHENPOP} nic nezapíše",
                             .string(FunctionKeyRouter.keysLabel(indices))))
                    return false
                }
                let next: String? = callStack?.next
                // The ESM progress of the next QSO: the keys the rest of the message plays to it ({F5}, {F2}).
                let keys: [Int] = texts.flatMap { CallStackMacro.functionKeys(in: $0) }
                let map: EsmKeyMap = config.config.esm.keys
                logThenPop(next: next, progress: next.map { EsmProgress.empty.afterSent(keys, $0, map: map) })
                if next == nil {
                    // Nothing on the stack: the QSO is logged and TU (F3) is sent instead.
                    sendKeys([config.config.esm.keys.end], opposite: opposite, refocus: false)
                    return false
                }
            case CallStackMacro.soCallStack:
                soCallStack()
            case CallStackMacro.stackAnother:
                stackAnother(label: CallStackMacro.stackAnother, runOnly: true)
            case CallStackMacro.clearStack:
                callStack?.clear()
            default:
                break
            }
        }
        return true
    }

    /// The F-key context of this moment (`cwContext` without the per-press values, `AS:1526-1539`).
    public func functionKeyContext() -> FunctionKeyContext {
        let app: AppConfig = config.config
        let station: StationConfig = app.station
        let data = CwMessageBuilder.StationData(name: station.name, grid: station.gridSquare, cqZone: station.cqZone,
                                                ituZone: station.ituZone, state: station.state,
                                                operator: operating.operatorCall)
        let base = CwMessageBuilder.Context(
            myCall: station.call, hisCall: "", lastLogged: logbook.rows.last?.call ?? "",
            serial: logbook.nextSerial(band: band),
            rst: "", exchange: cwExchange(), cutNumbers: app.cwKeyer.cutNumbers, leadingZeros: app.cwKeyer.leadingZeros,
            roverQth: station.roverQth, countyLine: countyLine, cutStyle: app.cwKeyer.cutStyle, station: data,
            functionKeys: [], now: now(), leftDigitalFrequency: digitalFrequencyText(vfo: 0),
            rightDigitalFrequency: digitalFrequencyText(vfo: 1))
        var context = FunctionKeyContext(
            mode: form.mode, digitalReady: digitalReady, postContest: operating.postContest, run: operating.isRun,
            call: form.call, rstSent: form.rstSent, freqHz: form.freqHz, progress: esmProgress,
            stationCall: station.call,
            voice: FunctionKeySet(run: app.voiceKeyer.runMessages, sp: app.voiceKeyer.spMessages),
            cw: FunctionKeySet(run: app.cwKeyer.runMessages, sp: app.cwKeyer.spMessages),
            digital: FunctionKeySet(run: app.digital.runMessages, sp: app.digital.spMessages),
            cwBase: base, exchangeValid: exchangeValid, stackNext: operating.isRun ? callStack?.next : nil,
            serialAfterLog: logbook.nextSerial(band: band) + 1, grabNext: grabList?.highlighted)
        context.esmKeys = app.esm.keys
        context.callExchangeSeparator = app.esm.callExchangeSeparator
        context.partialCall = partialCallSend
        context.radio = radioNumber
        context.cwBase.hisName = callHistoryName
        context.cwBase.digitalButtons = app.digital.diMessages.map(\.text)
        if let qtc, windows.isOpen(QtcModel.windowId) {
            context.cwBase.qtcHeader = qtc.header
        }
        fillMacroData(&context.cwBase, app: app)
        let messagesDir: URL = dataDir.appendingPathComponent("FunctionKeyMessages")
        context.cwBase.fileText = { name in Self.readMessageFile(messagesDir, name) }
        return context
    }

    /// The data of the Swift-only N1MM text macros: the Name and locator fields, the last logged QSO, the cluster
    /// login, the rigs' MHz and the `{VARYMSGn}` counters.
    private func fillMacroData(_ base: inout CwMessageBuilder.Context, app: AppConfig) {
        base.entryName = fields.first { ($0.id ?? "").lowercased() == "name" }
            .flatMap { $0.id }.flatMap { form.contestExchange[$0] }
        base.hisGrid = fields.first { $0.type == .LOCATOR }.flatMap { $0.id }
            .flatMap { form.contestExchange[$0] } ?? ""
        if let last = logbook.rows.last {
            base.lastSerial = last.serialSent.map { String($0) } ?? ""
            base.lastExchange = last.exchangeRcvd
            base.lastTime = last.timestampUtc
        }
        let cluster: DxClusterConfig = app.dxCluster
        let favorite: DxClusterFavorite? = cluster.favorites.first { $0.name == cluster.lastFavorite }
            ?? cluster.favorites.first
        let login: String = KotlinStrings.trim(favorite?.login ?? "")
        base.clusterCall = login.isEmpty ? app.station.call : login
        base.leftMHz = rigMHz(vfo: 0)
        base.rightMHz = rigMHz(vfo: 1)
        base.otherFreqHz = otherRadioHz
        base.varyCounts = operating.varyCounts
        if let network, network.isConnected {
            base.multiUser = true
            base.passTargets = network.macroPassTargets()
            base.lastPassedFreqHz = network.lastPassedFreqHz
        }
    }

    /// `{FKEY(r1%r2)}`: 2 for the VFO B / radio 2 window while two entry windows are shown, otherwise 1.
    var radioNumber: Int {
        guard let rig, rig.vfo.twoEntryWindows else { return 1 }
        return vfo == 1 ? 2 : 1
    }

    /// `{OTHERFREQ}`…: the other entry window's frequency (SO2R / SO2V), otherwise the rig's other VFO (its split
    /// TX frequency); 0 = unknown.
    var otherRadioHz: Int64 {
        guard let rig else { return 0 }
        if let other = rig.otherEntry(than: self), other.form.freqHz > 0 {
            return other.form.freqHz
        }
        if let state = rig.snapshot(vfo: 1 - rig.vfo.activeVfo).state, rig.vfo.twoEntryWindows, state.freqHz > 0 {
            return state.freqHz
        }
        return rig.activeState.map { $0.txFreqHz != $0.freqHz ? $0.txFreqHz : 0 } ?? 0
    }

    /// `{LRMHZ}` / `{RRMHZ}`: the whole MHz of rig / VFO `vfo`; `""` without a rig state.
    private func rigMHz(vfo: Int) -> String {
        guard let rig, let state = rig.snapshot(vfo: vfo).state, state.freqHz > 0 else { return "" }
        return String(state.freqHz / 1_000_000)
    }

    /// `{LDIGFQ}` / `{RDIGFQ}`: the transmitted frequency of rig / VFO `vfo` (dial ± fldigi's audio in a sideband
    /// mode), in kHz; `""` without a rig state.
    func digitalFrequencyText(vfo: Int) -> String {
        guard let rig, let state = rig.snapshot(vfo: vfo).state else { return "" }
        let hz: Int64 = digitalKeyer?.transmitHz(dialHz: state.freqHz, rawMode: state.rawMode) ?? state.freqHz
        return DigitalFrequency.macroText(hz)
    }

    /// `{NAME}`: the name column of the call history for the typed call (`""` when unknown).
    var callHistoryName: String {
        guard let history = callHistory?() else { return "" }
        return history.lookup(form.call)?["name"] ?? ""
    }

    /// `{FILE:name}`: a text file in `<data>/FunctionKeyMessages` (at most 64 kB; a path outside it is refused).
    nonisolated static func readMessageFile(_ dir: URL, _ name: String) -> String? {
        guard !name.isEmpty, !name.contains(".."), !name.hasPrefix("/") else { return nil }
        let url: URL = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), data.count <= 65_536 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The message set the F-keys send now (the voice set in phone, the digital set in a ready digital mode, else CW).
    public var currentKeyKind: FunctionKeyKind {
        if EsmFlow.isPhone(form.mode) {
            return .ssb
        }
        return form.mode.isDigital && digitalReady ? .digital : .cw
    }

    /// The text of an F-key of the set shown now (the hover text of its button).
    public func functionKeyText(_ index: Int) -> String {
        let set: [FunctionKeyMessage] = currentKeySet(opposite: shiftHeld)
        return index >= 0 && index < set.count ? set[index].text : ""
    }

    /// N1MM right click on an F-key button (like Alt+K): Settings → Function Keys on the set the keys send now.
    public func openFunctionKeyEditor() {
        menu.functionKeysFocus = FunctionKeysFocus(kind: currentKeyKind, run: operating.isRun != shiftHeld)
        openSettingsTab("function-keys")
    }

    /// The F-key button label (`*FunctionKeyLabel(i, shiftHeld)`).
    public func functionKeyLabel(_ index: Int) -> String {
        FunctionKeyRouter.label(index: index, shift: shiftHeld, context: functionKeyContext())
    }

    /// Kotlin `cwExchange()` (`AS:1490-1503`): the sent fields without reports — `#` for the automatic serial,
    /// otherwise the setup's value (Kotlin-trimmed, empty skipped) — joined with a space.
    func cwExchange() -> String {
        guard let definition = contest.definition else { return "" }
        let station: [String: String] = contest.activeSetup?.sentExchange ?? [:]
        var parts: [String] = []
        for field in definition.exchange?.sent ?? [] {
            guard let field else { continue }
            if field.type == .RST || field.type == .RS {
                continue
            }
            if field.source == .AUTO_SERIAL {
                parts.append("#")
                continue
            }
            if let part = field.derivesFromLastCall {
                let value: String = LastCall.value(part, logbook.rows.last?.call)
                if !value.isEmpty {
                    parts.append(value)
                }
                continue
            }
            guard let id = field.id, let value = station[id] else { continue }
            let trimmed: String = KotlinStrings.trim(value)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }
        return parts.joined(separator: " ")
    }

    func keyerSettings(opposite: Bool) -> KeyerSettings {
        let app: AppConfig = config.config
        let set = FunctionKeySet(run: app.voiceKeyer.runMessages, sp: app.voiceKeyer.spMessages)
        let texts: [String] = set.messages(run: operating.isRun, opposite: opposite).map(\.text)
        return KeyerSettings(cwMethod: app.cwKeyer.method, winkeyerPort: app.cwKeyer.winkeyerPort, voiceTexts: texts)
    }

    // MARK: - call-field commands

    /// Kotlin `runCommand(command)` (`EP:368-457`) through `EntryCommandPlan`: the call is cleared first, the
    /// command runs, the call field takes the focus. `SCRIPT` reads its file off the main thread first.
    public func runCommand(_ command: CallFieldCommand) {
        if case .runScript(let name) = command {
            let dir: String = scriptsDir
            setCall("")
            track { [weak self] in
                let lines: [String]? = (try? await BlockingQueue.run { MacroScript.load(dir, name) }) ?? nil
                guard let self else { return }
                let context: EntryCommandContext = self.commandContext { requested in
                    requested == name ? lines : nil
                }
                await self.perform(EntryCommandPlan.plan(command, context: context)[...])
            }
            return
        }
        let effects: [EntryCommandEffect] = EntryCommandPlan.plan(command, context: commandContext())
        perform(effects: effects[...])
    }

    /// `state.scriptsDir()` = `<dataDir>/scripts`.
    var scriptsDir: String {
        dataDir.appendingPathComponent("scripts").path
    }

    /// What the plan needs, read on the main actor.
    func commandContext(loadScript: ((String) -> [String]?)? = nil) -> EntryCommandContext {
        let station: StationConfig = config.config.station
        let contest: ContestModel = self.contest
        return EntryCommandContext(
            currentFreqHz: form.freqHz, otherVfoHz: otherVfoHz, modeLocked: modeLocked, primaryMode: contest.primaryMode,
            rstSent: form.rstSent, repeatSeconds: config.config.runMode.repeatSeconds,
            stationOperator: station.operator, stationCall: station.call, appVersion: appVersion,
            runtime: EntryTexts.runtimeDescription(), scriptsDir: scriptsDir, loadScript: loadScript ?? { _ in nil },
            tour: contest.tour, now: now(), usesRoverQth: contest.usesRoverQth,
            isKnownLocation: { contest.isKnownLocation($0) })
    }

    /// Applies effects in order; one that waits for the database continues the rest after it (in `commandTask`).
    func perform(effects: ArraySlice<EntryCommandEffect>) {
        var rest: ArraySlice<EntryCommandEffect> = effects
        while let effect = rest.first {
            rest = rest.dropFirst()
            if let work = asyncWork(effect) {
                let remaining: ArraySlice<EntryCommandEffect> = rest
                track { [weak self] in
                    await work()
                    await self?.perform(remaining)
                }
                return
            }
            applyNow(effect)
        }
    }

    /// The async variant used inside a tracked task.
    private func perform(_ effects: ArraySlice<EntryCommandEffect>) async {
        var rest: ArraySlice<EntryCommandEffect> = effects
        while let effect = rest.first {
            rest = rest.dropFirst()
            if let work = asyncWork(effect) {
                await work()
            } else {
                applyNow(effect)
            }
        }
    }

    /// Runs `body` after the command work enqueued before it.
    func track(_ body: @escaping @MainActor () async -> Void) {
        let previous: Task<Void, Never>? = commandTask
        commandTask = Task {
            await previous?.value
            await body()
        }
    }

    /// The effects that wait for the database or the logbook; `nil` = synchronous.
    private func asyncWork(_ effect: EntryCommandEffect) -> (@MainActor () async -> Void)? {
        let contest: ContestModel = self.contest
        switch effect {
        case .wipeLogNow:
            return { [weak self] in await self?.wipeLogNow() }
        case .setTour(let tour, let message):
            return { [weak self] in
                guard await contest.updateSetup({ $0.tour = tour.format() }) else { return }
                contest.setSessionExtras(tour: tour, bonusStations: contest.bonusStations)
                contest.requestRescore()
                self?.show(message)
            }
        case .tourOff(let message):
            return { [weak self] in
                guard await contest.updateSetup({ $0.tour = Tour.off }) else { return }
                contest.setSessionExtras(tour: nil, bonusStations: contest.bonusStations)
                contest.requestRescore()
                self?.show(message)
            }
        case .setBonusStations(let calls, let message):
            return { [weak self] in
                guard await contest.updateSetup({ $0.bonusStations = calls }) else { return }
                contest.setSessionExtras(tour: contest.tour, bonusStations: calls)
                contest.requestRescore()
                self?.show(message)
            }
        case .copyLog:
            return { [weak self] in await self?.copyLog() }
        case .reloadAll:
            return { await contest.reloadAll() }
        case .reopenLog:
            let logbook: LogbookModel = self.logbook
            let status: StatusModel = self.status
            return {
                do {
                    try await logbook.refresh()
                } catch {
                    status.showVerbatim(ErrorText.message(error))
                }
                contest.requestRescore(manual: true)
            }
        default:
            return nil
        }
    }

    private func applyNow(_ effect: EntryCommandEffect) {
        switch effect {
        case .clearCall:
            setCall("")
        case .focusCall:
            focusRequest += 1
        case .setFrequency(let text):
            setFrequencyText(text)
        case .rigQsy(let hz):
            runRigQsy(hz)
        case .rig(let command):
            runRigCommand(command)
        case .setMode(let mode):
            form.mode = mode
            form.applyDefaultRst(mode)
            setMode(mode)
            // N1MM: typing RTTY or PSK switches the digital engine too.
            if digitalReady, let modem = config.config.digital.modem(for: mode) {
                digitalKeyer?.setModem(modem)
            }
        case .rigMode(let mode, let freqHz):
            ports.rig.setMode(mode, freqHz: freqHz)
        case .status(let message):
            show(message)
        case .openDialog(let dialog):
            open(dialog)
        case .menuAction(let id):
            requestMenuAction(id)
        case .openSettingsTab(let key):
            openSettingsTab(key)
        case .setOperator(let op):
            operating.operatorCall = op
        case .rescore(let manual):
            contest.requestRescore(manual: manual)
        case .setEsm(let on):
            operating.applyEsm(on)
        case .setAutoRunSp(let on):
            operating.applyAutoRunSwitch(on)
        case .toggle(let setting, let on):
            toggle(setting, on)
        case .cutNumbers(let style):
            operating.applyCutNumbers(style)
        case .setRoverQth(let qth):
            config.config.station.roverQth = qth
            config.saveSilently()
            updatePreview()
        case .setCountyLine(let counties):
            countyLine = counties
            updatePreview()
        case .exitRequest(let confirm):
            if confirm {
                dialogs.ask(.exit)
            } else {
                dialogs.quitNow()
            }
        case .spotMe(let freqHz, let comment):
            spotMe(freqHz: freqHz, comment: comment)
        case .networkOn:
            cluster?.networkOn()
        case .networkOff:
            cluster?.networkOff()
        case .broadcastLog:
            integrations?.broadcastWholeLog()
        case .unavailable:
            unavailable()
        case .wipeLogNow, .setTour, .tourOff, .setBonusStations, .copyLog, .reloadAll, .reopenLog:
            break
        }
    }

    private func toggle(_ setting: CallFieldCommand.Setting, _ on: Bool) {
        switch setting {
        case .cqRepeat:
            operating.applyCqRepeat(on)
        case .workDupes:
            operating.applyWorkDupes(on)
        case .autoReload:
            operating.applyAutoReload(on)
        case .postContest:
            operating.applyPostContest(on)
        }
    }

    /// The dialogs a command opens; a prompt's answer goes through the same effects as the command with an argument.
    private func open(_ dialog: EntryDialog) {
        switch dialog {
        case .operatorLogin:
            dialogs.openOperator()
        case .wipeLogConfirm:
            dialogs.ask(.wipeLog)
        case .newContest:
            dialogs.setOpen(.newContest, true)
        case .contestBrowser:
            dialogs.setOpen(.contests, true)
        case .bonusStations:
            dialogs.prompt(title: ContestMessage("Bonusové stanice"),
                           hint: ContestMessage("Volačky oddělené čárkou nebo mezerou (W1AW platí i pro W1AW/M)"),
                           initial: contest.bonusStations.joined(separator: ", ")) { [weak self] text in
                let result = CountyLineSetting.bonusStations(text)
                self?.perform(effects: [.setBonusStations(result.calls, status: result.status)][...])
            }
        case .roverQth:
            dialogs.prompt(title: .verbatim("Rover QTH"),
                           hint: ContestMessage("Okres, odkud právě vysíláš (zkratka podle propozic)"),
                           initial: config.config.station.roverQth) { [weak self] text in
                self?.roverQthEntered(text)
            }
        case .countyLine:
            dialogs.prompt(title: .verbatim("County line"),
                           hint: ContestMessage("Okresy oddělené čárkou (prázdné = konec county line)"),
                           initial: countyLine.joined(separator: ", ")) { [weak self] text in
                self?.countyLineEntered(text)
            }
        }
    }

    /// Sets the rover QTH like the ROVERQTH command (the Multipliers window's „Set Rover QTH").
    func setRoverQth(_ text: String) {
        roverQthEntered(text)
    }

    private func roverQthEntered(_ text: String) {
        let qth: String = CountyLineSetting.roverQth(text)
        let known: Bool? = qth.isEmpty ? nil : contest.isKnownLocation(qth)
        let message: EntryStatus = CountyLineSetting.roverQthStatus(qth, usesRoverQth: contest.usesRoverQth,
                                                                     isKnownLocation: known)
        perform(effects: [.setRoverQth(qth), .status(message)][...])
    }

    private func countyLineEntered(_ text: String) {
        let contest: ContestModel = self.contest
        let result = CountyLineSetting.apply(text: text, usesRoverQth: contest.usesRoverQth) { county in
            contest.isKnownLocation(county)
        }
        perform(effects: [.setCountyLine(result.counties), .status(result.status)][...])
    }

    /// Kotlin `openSettingsTab(key)` (`AS:1813-1816`): the Settings window opens on the tab `key` (MSGS, WKEY,
    /// NETCONFIG, the action FUNCTION_KEYS_SETUP) — `pendingSettingsTab` + `pendingMenuAction = "settings.open"`.
    func openSettingsTab(_ key: String) {
        menu.pendingSettingsTab = key
        requestMenuAction("settings.open")
    }

    /// A menu action requested by a command: the main window runs it like the menu item (`pendingMenuAction`); an
    /// action of another subsystem is unavailable.
    func requestMenuAction(_ id: String) {
        if menu.isImplemented(id) {
            menu.pendingMenuAction = id
        } else {
            unavailable()
        }
    }

    /// COPYLOG (`AS:2080-2091`): a backup of the open database next to it, off the main thread.
    func copyLog() async {
        let handle: LogbookHandle = database.handle
        guard !handle.isClosed else {
            show(.tr(EntryTexts.copyLogNoDatabase))
            return
        }
        let name: String = EntryTexts.copyLogFileName(handle.url.lastPathComponent, at: now())
        let target: URL = handle.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            // Through a temporary file renamed into place (as the quit's backup): a cut-short copy never carries
            // the backup's name.
            try await handle.run { access in
                try DatabaseModel.writeBackup(to: target) { partial in
                    try access.repository.backupTo(partial)
                }
            }
            show(EntryTexts.copyLogDone(name))
        } catch {
            show(EntryTexts.copyLogFailed(ErrorText.message(error)))
        }
    }

    /// WIPELOG confirmed / CLEARLOGNOW: the submissions in flight are stored first, then the whole log goes.
    func wipeLogNow() async {
        await settleSubmissions()
        await logbook.wipeLog()
    }

    /// Ctrl+D confirmed: the submissions in flight are stored first, so the QSO just logged is the last one.
    func deleteLastNow() async {
        await settleSubmissions()
        await logbook.deleteLast()
    }

    /// Waits for the submissions only (a command task may itself wait here).
    func settleSubmissions() async {
        while let task = submitTask {
            await task.value
            if task == submitTask {
                return
            }
        }
    }

    // MARK: - helpers

    /// Sets the call field as typing does (the ESM reset on a cleared call included).
    func setCall(_ call: String) {
        callChanged(call)
    }

    func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }

    /// An action of another subsystem (also the Mark / Store / Spot It buttons).
    public func unavailable() {
        status.show(EntryTexts.unavailable)
    }
}
