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
        config.config.digital.engine != .none
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
                      exchangeValid: exchangeValid, options: operating.esmOptions)
    }

    /// Kotlin `esmStep`: what the next Enter does (the F-keys and "Log It" are highlighted); `nil` without ESM.
    public var esmStep: EsmEngine.Step? {
        EsmFlow.nextStep(esmInput, active: esmActive)
    }

    /// The call field holds a command (`parseCommand() != null`).
    public var hasCommand: Bool {
        EntryCommandPlan.isCommand(form.call, currentFreqHz: form.freqHz, otherVfoHz: otherVfoHz)
    }

    /// What the key router needs at the moment of the event, for the field with the focus.
    public func keyContext(field: EntryKeyField) -> EntryKeyContext {
        EntryKeyContext(bindings: KeyBindings(config.config.keyBindings), field: field, callText: form.call,
                        isCw: form.mode == .cw, esmActive: esmActive, hasLastSent: !operating.lastSentKeys.isEmpty,
                        isSending: ports.keyer.isSending || operating.cqRepeat, scpPick: scpPick,
                        suggestionCount: suggestions().count, hasCommand: hasCommand)
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
            let outcome = FunctionKeyRouter.press(index: index, shift: shift, ctrlShift: ctrlShift,
                                                  context: functionKeyContext())
            apply(outcome, opposite: shift)
        case .cwSpeed(let steps):
            // Kotlin `changeCwSpeed(±config.cwSpeedStep)` on the press (`EP:966-967`).
            if let message = ports.keyer.changeCwSpeed(by: steps * config.config.cwSpeedStep) {
                show(message)
            }
        case .tune(let direction):
            tuneStep(direction)
        case .enter(_, let step):
            enter(step)
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
        // Esc releases a plugin's PTT too (the same key that stops every other transmission).
        let pluginPtt: Bool = rig?.releasePluginPtt() ?? false
        if pluginPtt {
            return true
        }
        let keyer: any KeyerPort = ports.keyer
        if keyer.isTuning {
            _ = keyer.stopSending()
            return true
        }
        let repeating: Bool = operating.cqRepeat
        operating.applyCqRepeat(false)
        return keyer.stopSending() || repeating
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
            network?.popStack()
        default:
            unavailable()
        }
    }

    /// The keyer's shortcuts: Ctrl+K opens the CW keyboard window (`EP:916`) once that window exists.
    private func runKeyerShortcut(_ action: ShortcutAction) {
        if action == .cwKeyboard && WindowsModel.implemented.contains("cwkeyboard") {
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
            windows.findInLog(form.call)
        case .incrementNr:
            incrementNumber()
        default:
            runOperatingShortcut(action)
        }
    }

    private func runOperatingShortcut(_ action: ShortcutAction) {
        switch action {
        case .toggleEsm:
            operating.setEsm(!operating.esmEnabled)
        case .toggleCut:
            operating.toggleCutNumbers()
        case .yankScp:
            if !suggestions().isEmpty {
                takeSuggestion(0)
            }
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
                                           exchangeValid: exchangeValid) {
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
        esmProgress = EsmFlow.jumpToExchange(esmProgress, esmEnabled: operating.esmEnabled, mode: form.mode,
                                             run: operating.isRun, call: form.call)
        exchangeFocusRequest += 1
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

    // MARK: - ESM and F-keys

    /// Enter in ESM (`esmEnter`, `EP:817-835`).
    public func esmEnter() {
        let outcome: EsmFlow.Outcome = EsmFlow.enter(esmInput)
        if let message = outcome.status {
            show(message)
            return
        }
        if !outcome.keys.isEmpty {
            sendKeys(outcome.keys, refocus: false)
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
        let outcome = FunctionKeyRouter.send(indices, opposite: opposite, refocus: refocus,
                                             context: functionKeyContext())
        apply(outcome, opposite: opposite)
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
            keyerStatus = ports.keyer.send(transmission, settings: keyerSettings(opposite: opposite))
        }
        if let key = outcome.recordKey, let message = ports.keyer.toggleRecording(key) {
            show(message)
        }
        for action in outcome.actions {
            macroAction(action)
        }
        if let freqHz = outcome.cqSentFreqHz {
            operating.onCqSent(freqHz)
        }
        if outcome.refocus {
            focusRequest += 1
        }
        if let keyerStatus {
            show(keyerStatus)
        }
    }

    /// `CwMessage.Action` of a sent message (`EP:731-741`).
    private func macroAction(_ action: CwMessage.Action) {
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
        }
    }

    /// The F-key context of this moment (`cwContext` without the per-press values, `AS:1526-1539`).
    public func functionKeyContext() -> FunctionKeyContext {
        let app: AppConfig = config.config
        let station: StationConfig = app.station
        let data = CwMessageBuilder.StationData(name: station.name, grid: station.gridSquare, cqZone: station.cqZone,
                                                ituZone: station.ituZone, state: station.state,
                                                operator: operating.operatorCall)
        let base = CwMessageBuilder.Context(
            myCall: station.call, hisCall: "", lastLogged: logbook.rows.last?.call ?? "", serial: logbook.nextSerial,
            rst: "", exchange: cwExchange(), cutNumbers: app.cwKeyer.cutNumbers, leadingZeros: app.cwKeyer.leadingZeros,
            roverQth: station.roverQth, countyLine: countyLine, cutStyle: app.cwKeyer.cutStyle, station: data,
            functionKeys: [], now: now())
        return FunctionKeyContext(
            mode: form.mode, digitalReady: digitalReady, postContest: operating.postContest, run: operating.isRun,
            call: form.call, rstSent: form.rstSent, freqHz: form.freqHz, progress: esmProgress,
            stationCall: station.call,
            voice: FunctionKeySet(run: app.voiceKeyer.runMessages, sp: app.voiceKeyer.spMessages),
            cw: FunctionKeySet(run: app.cwKeyer.runMessages, sp: app.cwKeyer.spMessages),
            digital: FunctionKeySet(run: app.digital.runMessages, sp: app.digital.spMessages),
            cwBase: base)
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
            guard let id = field.id, let value = station[id] else { continue }
            let trimmed: String = KotlinStrings.trim(value)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }
        return parts.joined(separator: " ")
    }

    private func keyerSettings(opposite: Bool) -> KeyerSettings {
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
