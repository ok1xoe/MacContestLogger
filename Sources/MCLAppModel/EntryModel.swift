import Foundation
import MCLCore
import Observation

/// The entry window (Kotlin `EntryPanel.kt` state and `logQso`, `K:EntryPanel.kt:468-567`) over `EntryForm`.
///
/// Typing, the live contest preview, logging (contest, free, forced, post-contest paper time, county line), wiping
/// and unwiping. Call-field commands, shortcuts, F-keys and ESM are in `EntryModel+Commands.swift`; the keyer and the
/// rig are ports (`EntryPorts`, no-ops by default).
@Observable @MainActor
public final class EntryModel {

    /// A focus move of Tab / Shift+Tab / space in the exchange fields (`EntryKeyDecision.focusMove`); the view
    /// resolves it with `EntryFocusOrder`. `id` makes repeated moves distinct.
    public struct FocusMove: Equatable, Sendable {
        public let id: Int
        public let by: Int
        public let skipReports: Bool
    }

    public internal(set) var form = EntryForm()
    /// Raised when the call field should take the focus (Kotlin `callFocus.requestFocus()`).
    public internal(set) var focusRequest: Int = 0
    /// Raised when the exchange field should take the focus (Kotlin `focusExchange()`: space, ESM).
    public internal(set) var exchangeFocusRequest: Int = 0
    /// Raised when the post-contest time field should take the focus (`timeFocus.requestFocus()`).
    public internal(set) var timeFocusRequest: Int = 0
    /// The last requested focus move.
    public internal(set) var focusMoveRequest: FocusMove?
    /// Kotlin `state.countyLine` (COUNTYLINE; not saved, as in N1MM).
    public internal(set) var countyLine: [String] = []
    /// What has been sent in the QSO in progress (Kotlin `esm`).
    public internal(set) var esmProgress: EsmProgress = .empty
    /// Alt+W unwipe memory (Kotlin `lastWiped`).
    public internal(set) var wipeMemory = WipeMemory()
    /// The post-contest time field (Kotlin `paperTime`; `wipe()` does not clear it).
    public var paperTime: String = ""
    /// Kotlin `lastPaperTime`: the time of the previous paper-log QSO (midnight crossing).
    public internal(set) var lastPaperTime: Date?
    /// Kotlin `state.pendingNote`: the Ctrl+N note for the QSO in progress.
    public internal(set) var pendingNote: String?
    /// A held Shift shows the opposite F-key set (Kotlin `shiftHeld`).
    public internal(set) var shiftHeld: Bool = false
    /// The suggestions (check partial) the keys act on: the list shown and its highlight. Wired to the suggestions
    /// model when it joins the app; without it the entry keeps the highlight itself over an empty list.
    public struct SuggestionSource {
        public var list: @MainActor () -> [String]
        public var pick: @MainActor () -> Int
        public var setPick: @MainActor (Int) -> Void

        public init(list: @escaping @MainActor () -> [String], pick: @escaping @MainActor () -> Int,
                    setPick: @escaping @MainActor (Int) -> Void) {
            self.list = list
            self.pick = pick
            self.setPick = setPick
        }
    }

    @ObservationIgnored public var suggestionSource: SuggestionSource?
    private var localPick: Int = -1

    /// The highlighted suggestion (Kotlin `scpPick`, `-1` = none).
    public var scpPick: Int {
        get { suggestionSource?.pick() ?? localPick }
        set {
            if let source = suggestionSource {
                source.setPick(newValue)
            } else {
                localPick = newValue
            }
        }
    }

    /// The suggestions shown.
    public func suggestions() -> [String] {
        suggestionSource?.list() ?? []
    }

    /// The operator at the key (Kotlin `operatorCall`).
    public var operatorCall: String {
        operating.operatorCall
    }

    /// Kotlin `state.runMode`.
    public var runMode: RunMode {
        get { operating.runMode }
        set { operating.runMode = newValue }
    }

    @ObservationIgnored let contest: ContestModel
    @ObservationIgnored let logbook: LogbookModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let database: DatabaseModel
    @ObservationIgnored let operating: OperatingModel
    @ObservationIgnored let dialogs: DialogsModel
    @ObservationIgnored let windows: WindowsModel
    @ObservationIgnored let menu: MenuModel
    @ObservationIgnored let ports: EntryPorts
    /// The entry window's VFO: 0 = rig/VFO A (the main window), 1 = VFO B / rig 2 (`entry-vfob`, SO2V/SO2R).
    public let vfo: Int
    /// The entry window is on screen. The main window's always is; the VFO B window's model outlives its window, so
    /// the view sets this when the window appears and clears it when it closes — a model without a visible window is
    /// never the active panel (no rig follow, no footswitch, no CQ loop, no wheel).
    public var isWindowShown: Bool
    /// The rigs (set by `RigModel.attach`); the active window follows them (`EP:178-196`).
    @ObservationIgnored public internal(set) weak var rig: RigModel?
    @ObservationIgnored let dataDir: URL
    @ObservationIgnored let appVersion: String?
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private(set) var submitTask: Task<Void, Never>?
    /// Command effects that wait for the database (TOUR, BONUS, COPYLOG, WIPELOG…), in order.
    @ObservationIgnored var commandTask: Task<Void, Never>?
    @ObservationIgnored var focusMoveCounter: Int = 0
    /// Kotlin `LaunchedEffect(isDupe)`: the beep sounds when the dupe state turns on.
    @ObservationIgnored private var wasDupe: Bool = false
    /// Whether the entry accepts input now (wired by `AppModel`: not while quitting or switching the database).
    @ObservationIgnored var inputGate: @MainActor () -> Bool = { true }
    /// The self-spot anchor and `callFromSpot` of this window (`EP:150-153`).
    @ObservationIgnored var selfSpot = SelfSpotTracker()
    /// The tuned frequency the tuning effect last ran for (Kotlin `LaunchedEffect(state.tunedFreqHz)` runs once per
    /// new value).
    @ObservationIgnored var selfSpotTunedHz: Int64?
    /// The tuning effect is queued (it runs after the current event, as Compose effects run after recomposition).
    @ObservationIgnored var selfSpotEffectPending = false
    /// The spot actions (Spot It, Store, Mark, the navigation, the self-spot store); wired by the app.
    @ObservationIgnored weak var spotNavigation: SpotNavigation?
    /// Keys bound to plugin actions: called with every key of the entry fields (combination, `true` on the press);
    /// `nil` = not bound, else whether the key keeps its own function too.
    @ObservationIgnored public var pluginKeyHook: ((KeyCombo, Bool) -> Bool?)?
    /// The UDP integrations (BCLOG); wired by the app.
    @ObservationIgnored weak var integrations: IntegrationsModel?
    /// The multi-op messages (Ctrl+Alt+P, Ctrl+Alt+K) and the network log (NETON, NETOFF); wired by the app.
    @ObservationIgnored weak var network: NetworkModel?
    /// Opens the documentation page (Alt+H); wired by the app to the callbook's browser lane.
    @ObservationIgnored var helpOpener: (@MainActor () -> Void)?
    @ObservationIgnored weak var cluster: ClusterSyncModel?

    struct Dependencies {
        let contest: ContestModel
        let logbook: LogbookModel
        let status: StatusModel
        let config: ConfigModel
        let database: DatabaseModel
        let operating: OperatingModel
        let dialogs: DialogsModel
        let windows: WindowsModel
        let menu: MenuModel
        let ports: EntryPorts
        let dataDir: URL
        let appVersion: String?
        let now: @Sendable () -> Date
        var vfo: Int = 0
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        logbook = dependencies.logbook
        status = dependencies.status
        config = dependencies.config
        database = dependencies.database
        operating = dependencies.operating
        dialogs = dependencies.dialogs
        windows = dependencies.windows
        menu = dependencies.menu
        ports = dependencies.ports
        vfo = dependencies.vfo
        isWindowShown = dependencies.vfo == 0
        dataDir = dependencies.dataDir
        appVersion = dependencies.appVersion
        now = dependencies.now
    }

    // MARK: - derived state

    /// `false` while the app quits or switches the database: the fields are disabled and `submit()` does nothing, so
    /// no QSO is typed into (or logged against) a database that is about to close.
    public var acceptsInput: Bool {
        inputGate()
    }

    /// Band of the typed frequency (Kotlin `Band.fromFrequencyHz(parseFreqHz(freqKHz))`).
    public var band: Band? {
        Band.from(frequencyHz: Int(clamping: form.freqHz))
    }

    /// Received fields of the active contest for the typed callsign (empty outside a contest).
    public var fields: [ContestDefinition.ExchangeField] {
        contest.isActive ? contest.exchangeFields(call: form.call) : []
    }

    /// Kotlin `contestReady`.
    public var contestReady: Bool {
        contest.isActive && contest.isComplete(call: form.call, exchange: form.contestExchange)
    }

    /// The contest's dupe. Free logging (no active contest) has none: a repeated call is not flagged.
    public var isDupe: Bool {
        if KotlinStrings.isBlank(form.call) || !contest.isActive {
            return false
        }
        return contest.lastPreview?.dupe == true
    }

    /// Kotlin `modeLocked`: a single-mode contest fixes the mode.
    public var modeLocked: Bool {
        contest.isActive && !contest.isMultiMode
    }

    /// The sent exchange shown in the panel header (`sentExchangeText`).
    public var sentExchangeText: String {
        SentExchange.text(definition: contest.definition, setup: contest.activeSetup, mode: form.mode,
                          serial: logbook.nextSerial, roverQth: config.config.station.roverQth,
                          countyLine: countyLine)
    }

    // MARK: - typing

    /// The call field changed by the operator (typing, a suggestion taken; `EntryTextField` uppercases it): the
    /// contest preview follows, a call cleared to blank starts the ESM sequence again (`EP:176`), and the call is the
    /// operator's again (`callFromSpot = false`, `EP:659, 667, 1105`).
    public func callChanged(_ text: String) {
        selfSpot.typed()
        setCallText(text)
    }

    /// The frequency field changed: the preview, the shared tuned frequency without tuning the rig (typing never
    /// tunes CAT), and Run/S&P by the CQ frequency (`LaunchedEffect(freqKHz)` → `updateTunedFreq` →
    /// `onTunedForRunMode`).
    public func setFrequency(_ text: String) {
        setFrequencyText(text)
        fieldFrequencyChanged()
    }

    /// The field and what follows it on the spot (the preview, Run/S&P), without the shared tuned frequency.
    func setFrequencyText(_ text: String) {
        form.freqKHz = text
        updatePreview()
        reportTuned(form.freqHz)
    }

    /// A mode change (Kotlin `mode = …` then `LaunchedEffect(mode, …)` → `applyContestRst`, `onTunedForRunMode`).
    public func setMode(_ mode: Mode) {
        form.mode = mode
        if contest.isActive {
            form.applyContestRst(mode, rstFieldIds: EntryForm.rstFieldIds(fields))
        }
        updatePreview()
        reportTuned(form.freqHz)
    }

    /// Kotlin `qsy(toKHz, toMode)` from the band × mode grid; the rig half goes to the rig port.
    public func qsy(toKHz kHz: Double, mode: Mode) {
        form.freqKHz = FrequencyText.formatKHz(kHz)
        if !modeLocked {
            form.mode = mode
            form.applyDefaultRst(mode)
            if contest.isActive {
                form.applyContestRst(mode, rstFieldIds: EntryForm.rstFieldIds(fields))
            }
        }
        updatePreview()
        let hz: Int64 = BandStepping.qsyHz(kHz: kHz)
        ports.rig.qsy(hz: hz)
        if hz > 0 {
            ports.rig.setMode(mode, freqHz: hz)
        }
        fieldFrequencyChanged()
        reportTuned(hz)
        focusRequest += 1
    }

    public func editRstSent(_ text: String) {
        form.editRstSent(text)
    }

    public func editRstRcvd(_ text: String) {
        form.rstRcvd = text
    }

    public func editExchange(_ text: String) {
        form.exch = text
    }

    public func editContestField(_ id: String?, _ text: String) {
        form.editContestField(id, text)
        updatePreview()
    }

    /// Kotlin `LaunchedEffect(call, freqKHz, mode, cexch, contest.activeId)`: the preview without writing; then the
    /// dupe beep (`LaunchedEffect(isDupe)`, `config.beepOnDupe`).
    func updatePreview() {
        if contest.isActive, !KotlinStrings.isBlank(form.call) {
            contest.preview(call: form.call, band: band?.adif ?? "", mode: form.mode.rawValue,
                            exchange: form.contestExchange, ownQth: previewQth)
        }
        let dupe: Bool = isDupe
        if dupe && !wasDupe && config.config.beepOnDupe {
            ports.beep()
        }
        wasDupe = dupe
    }

    /// `countyLine.firstOrNull()?.takeIf { usesRoverQth } ?: roverQthForDupe()`.
    private var previewQth: String? {
        let usesRover: Bool = contest.usesRoverQth
        if usesRover, let first = countyLine.first {
            return first
        }
        return QsoAssembly.roverQthForDupe(roverQth: config.config.station.roverQth, usesRoverQth: usesRover)
    }

    /// Kotlin `LaunchedEffect(contestActive, contest.activeId)` and `LaunchedEffect(mode, contestActive, …)`: a
    /// single-mode contest sets its mode (DIGITAL → FT8), the reports are prefilled, the call field takes the focus.
    public func contestActivated() {
        if contest.isActive {
            if modeLocked {
                let primary: Mode = contest.primaryMode
                form.mode = primary == .digital ? .ft8 : primary
            } else if let rigMode = rig?.activeState?.mode {
                // A multi-mode contest takes the rig's mode once (`state.cat.state?.mode()`).
                form.mode = rigMode
            }
            form.applyContestRst(form.mode, rstFieldIds: EntryForm.rstFieldIds(fields))
            updatePreview()
            reportTuned(form.freqHz)
        }
        focusRequest += 1
    }

    // MARK: - wipe and submit

    /// Kotlin `wipe()`: the fields, the ESM progress; the unwipe memory and the paper time stay.
    public func wipe() {
        form = form.wiped(contestActive: contest.isActive, rstFieldIds: EntryForm.rstFieldIds(fields))
        esmProgress = .empty
        wasDupe = isDupe
        selfSpot.typed()
        trackCallForSelfSpot()
        focusRequest += 1
    }

    /// Kotlin `logQso(ctrlEnter, force, comment)` (Enter, Ctrl+Alt+Enter, ESM, `{LOG}`). A command in the call field
    /// runs instead (and is never logged); otherwise the QSO is assembled and the form wiped on the main thread at
    /// once; the insert runs off the main thread, then the row, the dupe index, the count and the contest session
    /// follow in Kotlin order.
    ///
    /// - Parameters:
    ///   - ctrlEnter: the frequency in the call field is the transmit one (split).
    ///   - force: log even with an invalid exchange and past the operating rules (N1MM Ctrl+Alt+Enter).
    ///   - comment: the QSO's note (otherwise the pending Ctrl+N note).
    public func submit(ctrlEnter: Bool = false, force: Bool = false, comment: String? = nil) {
        guard acceptsInput else { return }
        let previous: Task<Void, Never>? = submitTask
        guard let work = prepareSubmission(ctrlEnter: ctrlEnter, force: force, comment: comment) else { return }
        submitTask = Task {
            _ = await previous?.value
            await self.log(work)
        }
    }

    /// Waits for the submissions and command effects in flight (tests, quit).
    func settle() async {
        while true {
            let submit = submitTask
            let command = commandTask
            await submit?.value
            await command?.value
            if submit == submitTask && command == commandTask {
                return
            }
        }
    }

    /// One prepared submission: the QSO copies and what the contest log needs.
    struct Submission {
        let copies: [(qth: String?, qso: Qso)]
        let call: String
        let band: String
        let mode: Mode
        let exchange: JavaLinkedMap<String>
        let contestPath: Bool
        /// The logbook's active contest and the contest session at submit time (the QSO belongs to them even if
        /// another contest is activated before it is stored).
        let activeContestId: String
        let sessionId: String?
        let dxcc: (any DxccLookup)?
        /// The form as submitted (restored when the insert fails).
        let form: EntryForm
        /// The paper-log time (post-contest entry), `nil` = now.
        let at: Date?
        /// The Ctrl+N note this QSO took (given back when the form is restored).
        let consumedNote: String?
        /// `lastPaperTime` and the unwipe memory before the submission (given back when the form is restored).
        let previousPaperTime: Date?
        let previousWipeMemory: WipeMemory
    }

    /// The synchronous part of `logQso`: command, paper time, checks, assembly and wipe. `nil` = nothing to log.
    func prepareSubmission(ctrlEnter: Bool = false, force: Bool = false, comment: String? = nil) -> Submission? {
        let interval: Perf.Interval = Perf.begin("submit-main")
        defer { Perf.end(interval) }
        if KotlinStrings.isBlank(form.call) {
            focusRequest += 1
            return nil
        }
        if let command = EntryCommandPlan.parseForEnter(form.call, currentFreqHz: form.freqHz,
                                                         otherVfoHz: otherVfoHz, ctrlEnter: ctrlEnter) {
            // A text command instead of a callsign (`EP:473-481`): it runs and is never logged.
            runCommand(command)
            return nil
        }
        // Post-contest entry: the QSO time from the time field (`EP:483-492`).
        var at: Date?
        if operating.postContest {
            guard let parsed = PaperTime.parse(paperTime, previous: lastPaperTime, baseDate: paperBaseDate()) else {
                status.show(EntryTexts.paperTimeMissing)
                timeFocusRequest += 1
                return nil
            }
            at = parsed
        }
        let contestPath: Bool = contest.isActive
        let bandAdif: String = band?.adif ?? ""
        let note: String? = comment ?? pendingNote
        let copies: [(qth: String?, qso: Qso)]
        if contestPath {
            if !contestReady && !force {
                return nil
            }
            guard passesOperatingRules(force: force) else { return nil }
            let usesRover: Bool = contest.usesRoverQth
            let units: Int = QsoAssembly.loggingQths(countyLine: countyLine, usesRoverQth: usesRover,
                                                     roverQth: config.config.station.roverQth).count
            copies = contestCopies(serial: logbook.reserveSerial(units: units), note: note, at: at)
        } else {
            let serial: Int = logbook.reserveSerial()
            let qso = QsoAssembly.free(form: form, serial: serial, runMode: runMode, note: note, at: at)
            copies = [(qth: nil, qso: qso)]
        }
        let work = Submission(copies: copies, call: form.call, band: bandAdif, mode: form.mode,
                              exchange: form.contestExchange, contestPath: contestPath,
                              activeContestId: logbook.activeContestId, sessionId: contest.activeId,
                              dxcc: contest.runtime.dxccLookup, form: form, at: at,
                              consumedNote: comment == nil ? pendingNote : nil, previousPaperTime: lastPaperTime,
                              previousWipeMemory: wipeMemory)
        if let at {
            lastPaperTime = at
        }
        pendingNote = nil
        wipeMemory.clear()
        wipe()
        return work
    }

    /// Kotlin `paperBaseDate()`: the contest's start (`setup.startedAt`), else the last QSO, else now.
    func paperBaseDate() -> Date {
        if let started = Self.parseStartedAt(contest.activeSetup?.startedAt ?? "") {
            return started
        }
        return logbook.rows.last?.timestampUtc ?? now()
    }

    /// Kotlin `parseEpoch(startedAt)`: `LocalDateTime.parse(text.trim().replace(" ", "T"))` as UTC. Only the date
    /// matters here (`PaperTime` takes the day), so `yyyy-MM-ddTHH:mm` with optional seconds and fraction is read.
    static func parseStartedAt(_ text: String) -> Date? {
        let trimmed: String = KotlinStrings.trim(text).replacingOccurrences(of: " ", with: "T")
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            return nil
        }
        func group(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
            return Int(trimmed[range])
        }
        var parts = DateComponents()
        parts.year = group(1)
        parts.month = group(2)
        parts.day = group(3)
        parts.hour = group(4)
        parts.minute = group(5)
        parts.second = group(6) ?? 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        guard parts.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: parts)
    }

    /// The operating-rules gate (`K:EntryPanel.kt:495-506`): `false` = blocked (status set). Skipped for a forced
    /// write and in post-contest entry.
    private func passesOperatingRules(force: Bool) -> Bool {
        let cluster: ClusterConfig = config.config.cluster
        let newMultiplier: Bool = contest.lastPreview?.multipliers.contains { $0.countsAsMultiplier && $0.isNew } == true
        let gate = QsoAssembly.operatingGate(force: force, postContest: operating.postContest,
                                             enforcement: cluster.ruleEnforcement) {
            self.operatingViolation(newMultiplier: newMultiplier)
        }
        switch gate {
        case .proceed:
            return true
        case .warn(let violation):
            status.showVerbatim("Pozor: " + violation)
            return true
        case .block(let violation):
            status.show("NEZAPSÁNO — %s (Ctrl+Alt+Enter zapíše i tak)", .string(violation))
            return false
        }
    }

    /// Kotlin `operatingViolation(band, newMultiplier)` (`KA:2722-2733`) over the log model's incremental statistics
    /// of this station (L1): no `ContestStats.of` on the main thread.
    private func operatingViolation(newMultiplier: Bool) -> String? {
        let cluster: ClusterConfig = config.config.cluster
        let interval: Perf.Interval = Perf.begin("operating-rules")
        defer { Perf.end(interval, String(logbook.rows.count) + " qso") }
        let rules = OperatingRules.resolve(contest.definition?.operating, contest.activeSetup?.category)?.bandChange
        let type = QsoAssembly.operatingStationType(networked: cluster.enabled, configured: cluster.stationType)
        return OperatingGuard.check(logbook.statsForRules, rules, band, JavaInstant(date: now()), type, newMultiplier)
    }

    private func contestCopies(serial: Int, note: String?, at: Date?) -> [(qth: String?, qso: Qso)] {
        let fields: [ContestDefinition.ExchangeField] = self.fields
        let definition: ContestDefinition? = contest.definition
        let setup: ContestSetup? = contest.activeSetup
        let mode: Mode = form.mode
        let rstSent: String = form.rstSent
        return QsoAssembly.contestQsos(
            form: form, fields: fields, rstFieldIds: EntryForm.rstFieldIds(fields), serial: serial, runMode: runMode,
            countyLine: countyLine, usesRoverQth: contest.usesRoverQth, roverQth: config.config.station.roverQth,
            note: note, at: at
        ) { qth in
            SentExchange.flat(definition: definition, setup: setup, mode: mode, serial: serial, rstSent: rstSent,
                              ownQth: qth)
        }
    }

    /// The asynchronous part: `state.log(qso)` (pipeline effects) and `contest.log` per copy, with the Kotlin
    /// status texts.
    private func log(_ work: Submission) async {
        for (index, copy) in work.copies.enumerated() {
            let context = QsoLogPipeline.Context(
                activeContestId: KotlinStrings.nilIfBlank(work.activeContestId), operatorCall: operatorCall,
                dxcc: work.dxcc, syncStationId: logbook.syncStationId, reservedSerial: logbook.reservedServerSerial,
                simulatorActive: logbook.simulatorActive(), ritHz: rig?.rit.ritHz ?? 0,
                ritClearAfterLog: config.config.ritClearAfterLog, logToContest: work.contestPath)
            let (prepared, effects) = QsoLogPipeline.plan(qso: copy.qso, isImported: false, context: context)
            do {
                try await logbook.perform(prepared, effects: effects, reserved: true,
                                          contestId: work.activeContestId)
            } catch {
                logbook.releaseReservation(work.copies.count - index - 1)
                if index == 0 {
                    if let serial = copy.qso.serialSent {
                        logbook.withdrawSerial(serial)
                    }
                    restore(work, after: error)
                } else {
                    // L7: the earlier county-line copies are stored. The form is not restored (a re-submit would log
                    // them twice) and their serial stays used.
                    status.showVerbatim(work.call + ": " + ErrorText.message(error))
                }
                return
            }
            for effect in effects {
                if case .status(let key) = effect {
                    status.show(key)
                }
            }
            // Into the live session only while it is still the submitted contest's (a later activation replays it).
            guard effects.contains(.contestLog), contest.activeId == work.sessionId else { continue }
            let logged = contest.log(call: work.call, band: work.band, mode: work.mode.rawValue,
                                     exchange: work.exchange, ownQth: copy.qth, at: work.at ?? now())
            if let logged, logbook.outwardGate(prepared) {
                logbook.onLiveScored?(prepared, logged)
            }
            if let logged, !logged.counted {
                if KotlinStrings.isBlank(work.band) {
                    status.show("%s bez pásma — do skóre se nepočítá", .string(work.call))
                } else {
                    status.show("%s v módu %s — závod ho nemá, nepočítá se", .string(work.call),
                                .string(work.mode.rawValue))
                }
            }
        }
    }

    /// A failed insert must not lose the input (Kotlin would crash instead): the submitted form comes back unless
    /// the operator has already typed a new call — then the failed QSO's call is named in the status line.
    private func restore(_ work: Submission, after error: any Error) {
        let message: String = ErrorText.message(error)
        if KotlinStrings.isBlank(form.call) {
            form = work.form
            if let note = work.consumedNote, pendingNote == nil {
                pendingNote = note
            }
            // Only when no later submission changed them meanwhile.
            if work.at != nil && lastPaperTime == work.at {
                lastPaperTime = work.previousPaperTime
            }
            if wipeMemory.lastWiped == nil {
                wipeMemory = work.previousWipeMemory
            }
            status.showVerbatim(message)
            updatePreview()
            trackCallForSelfSpot()
            focusRequest += 1
        } else {
            status.showVerbatim(work.call + ": " + message)
        }
    }
}

extension EntryModel {

    /// The entry window's frequency or mode changed: Run/S&P follows, and the active window's radio is reported
    /// (the plugins' band, mode and frequency events).
    func reportTuned(_ freqHz: Int64) {
        operating.tuned(freqHz, mode: form.mode)
        if isActivePanel {
            operating.onOperating?(vfo, freqHz, form.mode)
        }
    }
}
