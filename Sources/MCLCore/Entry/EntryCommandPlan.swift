import Foundation

/// A dialog a call-field command opens.
public enum EntryDialog: Equatable, Sendable {
    /// `OPON`/`LOGIN` without a call (`showOperatorDialog`).
    case operatorLogin
    /// `WIPELOG`/`CLEARLOG` (`showWipeLogConfirm`).
    case wipeLogConfirm
    /// `NEW` (`showNewContestDialog`).
    case newContest
    /// `OPEN` (`showContestBrowser`).
    case contestBrowser
    /// `BONUS` without calls: prompt with the current list (`AS:3880-3886`).
    case bonusStations
    /// `ROVERQTH` without a county: prompt with the configured rover QTH (`AS:3900-3905`).
    case roverQth
    /// `COUNTYLINE` without counties: prompt with the current county line (`AS:3922-3927`).
    case countyLine
}

/// One step of executing a call-field command, applied by the app in list order (Kotlin `runCommand`,
/// `EP:368-457`). Statuses overwrite each other as in Kotlin — the last one stays.
public enum EntryCommandEffect: Equatable, Sendable {
    /// `call = ""` and `state.typedCall = ""` (before the command runs).
    case clearCall
    /// `callFocus.requestFocus()` (after the command).
    case focusCall
    /// `freqKHz = text`.
    case setFrequency(text: String)
    /// `state.qsy(hz)` — the shared tuning: the tuned and previous frequency follow for any value, the rig is tuned only for a frequency > 0 (a wrapped `long` never reaches CAT, L11).
    case rigQsy(hz: Int64)
    /// `mode = m` and `applyDefaultRst(m)` (both reports to the mode default; the contest reports follow the mode
    /// change).
    case setMode(Mode)
    /// `state.cat.setMode(m, freqHz)` — the rig half.
    case rigMode(Mode, freqHz: Int64)
    case status(EntryStatus)
    case openDialog(EntryDialog)
    /// `state.pendingMenuAction = id` — the menu action; an action `MenuModel` does not implement yet is unavailable.
    case menuAction(String)
    /// `openSettingsTab(key)`: Settings (`settings.open`) on a tab.
    case openSettingsTab(String)
    /// `operatorCall = op` (already Kotlin-trimmed and upper-cased, not blank); the status follows separately.
    case setOperator(String)
    /// `CLEARLOGNOW`: `state.wipeLog()` without asking.
    case wipeLogNow
    case rescore(manual: Bool)
    case setEsm(Bool)
    case setAutoRunSp(Bool)
    /// `CQ_REPEAT` / `WORK_DUPES` / `AUTO_RELOAD` / `POST_CONTEST` (`POSTCONTEST` on also stops the CQ repeat).
    case toggle(CallFieldCommand.Setting, Bool)
    case cutNumbers(CutStyle?)
    /// `setTour(params)` with a valid tour: save to the contest setup, set the session, rescore, then show `status`
    /// (nothing when the setup cannot be saved — the app shows its own text then).
    case setTour(Tour, status: EntryStatus)
    /// `tourOff()`: save `Tour.off`, clear the session, rescore, then `status`.
    case tourOff(status: EntryStatus)
    /// `applyBonusStations`: save, set the session extras, rescore, then `status`.
    case setBonusStations([String], status: EntryStatus)
    /// `applyRoverQth`: `config.station.roverQth = county`, save (the status follows separately).
    case setRoverQth(String)
    /// `applyCountyLine` (not saved, as in N1MM; the status follows separately).
    case setCountyLine([String])
    /// `COPYLOG`: a backup of the database next to it (off the main thread).
    case copyLog
    /// `RELOAD`: reload the contest definitions and reopen the active contest.
    case reloadAll
    /// `REOPEN`: refresh the logbook from the database and rescore (`manual = true`).
    case reopenLog
    /// `BYE`/`EXIT`/`QUIT` (`confirm`) and `EXITNOW`/`QUITNOW`.
    case exitRequest(confirm: Bool)
    /// The rig commands (`EP:404-405, 436-440`): VFO B, split, swap, RIT, the CAT log, the reset.
    case rig(EntryRigCommand)
    /// `SPOTME [comment]`: `state.spotMe(parseFreqHz(freqKHz), comment)` — the station's own spot to the DX cluster
    /// (`AS:3965-3970`).
    case spotMe(freqHz: Int64, comment: String)
    /// `NETON` / `NET`: `state.networkOn()`.
    case networkOn
    /// `NETOFF` / `NONET`: `state.networkOff()`.
    case networkOff
    /// `BCLOG`: `state.broadcastWholeLog()` — the whole log once over the N1MM broadcast.
    case broadcastLog
    /// Another subsystem's command — `tr("Zatím nedostupné")`, nothing logged.
    case unavailable
}

/// A call-field command that goes to the rig model (`EP:404-405, 436-440`).
public enum EntryRigCommand: Equatable, Sendable {
    /// `/14030`: `state.setOtherVfo(freqHz)`.
    case otherVfo(freqHz: Int64)
    /// `SPLIT`, Ctrl+Enter with a frequency: `state.setSplit(txFreqHz)`.
    case split(txFreqHz: Int64)
    /// `NOSPLIT`: `state.splitOff()`.
    case splitOff
    /// `SWAP`: `state.swapVfo()`.
    case swapVfo
    /// `RIT n`: `state.setRit(offsetHz)`.
    case rit(offsetHz: Int)
    /// `DEBUGCAT`: `state.showCatLog = true`.
    case debugCat
    /// `RESET`: `state.resetInterfaces()`.
    case resetInterfaces
}

/// What a command needs from the window, the configuration and the active contest.
public struct EntryCommandContext {
    /// `parseFreqHz(freqKHz)`.
    public var currentFreqHz: Int64
    /// `state.cat.state?.txFreqHz() ?: 0` (no CAT: 0).
    public var otherVfoHz: Int64
    /// A single-mode contest fixes the mode.
    public var modeLocked: Bool
    public var primaryMode: Mode
    /// The sent report (`TOUR` without an argument takes `hhmm/mm` from it).
    public var rstSent: String
    /// `config.runMode.repeatSeconds` (status of `RPT`).
    public var repeatSeconds: Double
    /// `config.station.operator` / `config.station.call` (`LOGOUT`).
    public var stationOperator: String
    public var stationCall: String
    /// The packaged version (`nil` = development build, `tr("vývojová verze")`).
    public var appVersion: String?
    /// `Swift … · macOS …` (`EntryTexts.runtimeDescription()`).
    public var runtime: String
    /// `state.scriptsDir()` and the loader of `SCRIPT name` (`MacroScript.load`).
    public var scriptsDir: String
    public var loadScript: (String) -> [String]?
    /// The active contest's tour and the moment (`TOUR` without an argument shows the session).
    public var tour: Tour?
    public var now: Date
    /// `contest.usesRoverQth()` and `contest.isKnownLocation(c)` (`nil` = no list).
    public var usesRoverQth: Bool
    public var isKnownLocation: (String) -> Bool?

    public init(currentFreqHz: Int64, otherVfoHz: Int64 = 0, modeLocked: Bool = false, primaryMode: Mode = .ssb,
                rstSent: String = "", repeatSeconds: Double = 0, stationOperator: String = "",
                stationCall: String = "", appVersion: String? = nil, runtime: String = "",
                scriptsDir: String = "", loadScript: ((String) -> [String]?)? = nil, tour: Tour? = nil,
                now: Date = Date(), usesRoverQth: Bool = false, isKnownLocation: ((String) -> Bool?)? = nil) {
        self.currentFreqHz = currentFreqHz
        self.otherVfoHz = otherVfoHz
        self.modeLocked = modeLocked
        self.primaryMode = primaryMode
        self.rstSent = rstSent
        self.repeatSeconds = repeatSeconds
        self.stationOperator = stationOperator
        self.stationCall = stationCall
        self.appVersion = appVersion
        self.runtime = runtime
        self.scriptsDir = scriptsDir
        self.loadScript = loadScript ?? { name in MacroScript.load(scriptsDir, name) }
        self.tour = tour
        self.now = now
        self.usesRoverQth = usesRoverQth
        self.isKnownLocation = isKnownLocation ?? { _ in nil }
    }
}

/// Call-field text commands of the entry window (`logQso` command branch `EP:473-481`, `runCommand` `EP:368-457`,
/// `parseCommand` `EP:459-461`).
public enum EntryCommandPlan {

    /// `parseCommand(ctrlEnter)` for Enter. Kotlin does not catch the parser's `ArithmeticException("Overflow")`: in
    /// Compose Desktop 1.7.3 the default window exception handler shows "Error: Overflow" and closes the main window
    /// (the app quits, a maintainer-only probe). Swift shows the entry as invalid instead —
    /// `"<text> kHz neleží v žádném pásmu"` with the entered number (without a leading `/`) — and does not log it (L11,
    /// a documented divergence).
    public static func parseForEnter(_ text: String, currentFreqHz: Int64, otherVfoHz: Int64 = 0,
                                     ctrlEnter: Bool = false) -> CallFieldCommand? {
        do {
            return try CallFieldCommands.parse(text, currentFreqHz: currentFreqHz, otherVfoHz: otherVfoHz,
                                               ctrlEnter: ctrlEnter)
        } catch {
            return .invalid(message: overflowNumber(text) + " kHz neleží v žádném pásmu")
        }
    }

    /// The number as the parser saw it: `trim().toUpperCase()` without a leading `/`.
    static func overflowNumber(_ text: String) -> String {
        let upper: String = JavaText.toUpperCase(JavaText.trim(text))
        if upper.utf16.first == 0x2F {
            return String(upper.unicodeScalars.dropFirst())
        }
        return upper
    }

    /// The text is a command (Enter executes it instead of logging, Store/Spot It refuse it).
    public static func isCommand(_ text: String, currentFreqHz: Int64, otherVfoHz: Int64 = 0) -> Bool {
        parseForEnter(text, currentFreqHz: currentFreqHz, otherVfoHz: otherVfoHz) != nil
    }

    /// The command entered with Enter: clear the call (and the typed call), run it, focus the call field.
    public static func plan(_ command: CallFieldCommand, context: EntryCommandContext) -> [EntryCommandEffect] {
        var ctx = context
        var effects: [EntryCommandEffect] = [.clearCall]
        run(command, &ctx, &effects)
        effects.append(.focusCall)
        return effects
    }

    /// Kotlin `runCommand(command)`. `ctx` follows what the command changed (a script line sees the frequency and
    /// the report set by an earlier line, as the Compose state does).
    private static func run(_ command: CallFieldCommand, _ ctx: inout EntryCommandContext,
                            _ effects: inout [EntryCommandEffect]) {
        if !EntryActionAvailability.isAvailable(EntryActionAvailability.area(of: command))
            && !opensLaterWindow(command) {
            effects.append(.unavailable)
            return
        }
        switch command {
        case .qsy(let hz):
            qsy(hz, &ctx, &effects)
        case .changeMode(let mode):
            changeMode(mode, &ctx, &effects)
        case .login(let op):
            login(op, &effects)
        case .wipeLog:
            effects.append(.openDialog(.wipeLogConfirm))
        case .version:
            effects.append(.status(EntryTexts.version(appVersion: ctx.appVersion, runtime: ctx.runtime)))
        case .exportAdif:
            effects.append(.menuAction("settings.export"))
        case .importLog:
            effects.append(.menuAction("settings.import"))
        case .exportCabrillo:
            effects.append(.menuAction("settings.exportCabrillo"))
        case .openSetup:
            effects.append(.menuAction("settings.open"))
        case .rescore:
            effects.append(.rescore(manual: true))
        case .autoRunSp(let enabled):
            effects.append(contentsOf: [.setAutoRunSp(enabled), .status(EntryTexts.autoRunSwitch(enabled))])
        case .esmOn:
            effects.append(contentsOf: [.setEsm(true), .status(EntryTexts.esm(true))])
        case .esmOff:
            effects.append(contentsOf: [.setEsm(false), .status(EntryTexts.esm(false))])
        case .appAction(let action):
            appAction(action, ctx, &effects)
        case .toggle(let setting, let on):
            effects.append(contentsOf: [.toggle(setting, on), .status(toggleStatus(setting, on, ctx))])
        case .cutNumbers(let style):
            effects.append(contentsOf: [.cutNumbers(style), .status(EntryTexts.cutNumbers(style))])
        case .openSettingsTab(let key):
            effects.append(.openSettingsTab(key))
        case .runScript(let name):
            runScript(name, &ctx, &effects)
        case .invalid(let message):
            effects.append(.status(.verbatim(message)))
        case .otherVfo(let freqHz):
            effects.append(.rig(.otherVfo(freqHz: freqHz)))
        case .split(let txFreqHz):
            effects.append(.rig(.split(txFreqHz: txFreqHz)))
        case .splitOff:
            effects.append(.rig(.splitOff))
        case .swapVfo:
            effects.append(.rig(.swapVfo))
        case .rit(let offsetHz):
            effects.append(.rig(.rit(offsetHz: Int(offsetHz))))
        case .spotMe(let comment):
            effects.append(.spotMe(freqHz: ctx.currentFreqHz, comment: comment))
        case .networkOn:
            effects.append(.networkOn)
        case .networkOff:
            effects.append(.networkOff)
        default:
            qsoParty(command, ctx, &effects)
        }
    }

    /// Commands that open other windows still go to the app (it checks `MenuModel.isImplemented`).
    private static func opensLaterWindow(_ command: CallFieldCommand) -> Bool {
        EntryActionAvailability.area(of: command) == .windows
    }

    private static func qsy(_ hz: Int64, _ ctx: inout EntryCommandContext, _ effects: inout [EntryCommandEffect]) {
        let text: String = FrequencyText.formatHz(hz)
        effects.append(.setFrequency(text: text))
        effects.append(.rigQsy(hz: hz))
        effects.append(.status(.verbatim("QSY na " + text + " kHz")))
        ctx.currentFreqHz = FrequencyText.parseHz(text)
    }

    private static func changeMode(_ mode: Mode, _ ctx: inout EntryCommandContext,
                                   _ effects: inout [EntryCommandEffect]) {
        if ctx.modeLocked {
            effects.append(.status(.tr("Mód určuje závod (%s)", .string(ctx.primaryMode.rawValue))))
            return
        }
        effects.append(contentsOf: [
            .setMode(mode), .rigMode(mode, freqHz: ctx.currentFreqHz), .status(.tr("Mód %s", .string(mode.rawValue))),
        ])
        ctx.rstSent = mode.defaultRst
    }

    /// `OPON call`: blank = the dialog; otherwise `setOperator(call)` (`AS:2156-2166`).
    private static func login(_ op: String, _ effects: inout [EntryCommandEffect]) {
        if KotlinStrings.isBlank(op) {
            effects.append(.openDialog(.operatorLogin))
            return
        }
        effects.append(contentsOf: setOperator(op))
    }

    /// `setOperator(call)` without persisting: Kotlin `trim().uppercase()`, a blank call is ignored.
    public static func setOperator(_ call: String) -> [EntryCommandEffect] {
        let op: String = KotlinStrings.uppercase(KotlinStrings.trim(call))
        if KotlinStrings.isBlank(op) {
            return []
        }
        return [.setOperator(op), .status(EntryTexts.operatorSet(op, persisted: false))]
    }

    private static func appAction(_ action: CallFieldCommand.Action, _ ctx: EntryCommandContext,
                                  _ effects: inout [EntryCommandEffect]) {
        switch action {
        case .exit: effects.append(.exitRequest(confirm: true))
        case .exitNow: effects.append(.exitRequest(confirm: false))
        case .wipeLogNow: effects.append(.wipeLogNow)
        case .closeContest: effects.append(.menuAction("contest.none"))
        case .newContest: effects.append(.openDialog(.newContest))
        case .openContest: effects.append(.openDialog(.contestBrowser))
        case .copyLog: effects.append(.copyLog)
        case .reload: effects.append(.reloadAll)
        case .reopen: effects.append(.reopenLog)
        case .logout:
            // `setOperator(config.station.operator.ifBlank { config.station.call })`.
            let fallback: String = KotlinStrings.isBlank(ctx.stationOperator) ? ctx.stationCall : ctx.stationOperator
            effects.append(contentsOf: setOperator(fallback))
        case .debugCat: effects.append(.rig(.debugCat))
        case .resetInterfaces: effects.append(.rig(.resetInterfaces))
        case .loadBeacons:
            // `state.pendingMenuAction = "beacons.load"` (`EP:413`): the app asks for the file (`App.kt:266`).
            effects.append(.menuAction("beacons.load"))
        case .broadcastLog:
            effects.append(.broadcastLog)
        }
    }

    private static func toggleStatus(_ setting: CallFieldCommand.Setting, _ on: Bool,
                                     _ ctx: EntryCommandContext) -> EntryStatus {
        switch setting {
        case .cqRepeat: EntryTexts.cqRepeat(on, repeatSeconds: ctx.repeatSeconds)
        case .workDupes: EntryTexts.workDupes(on)
        case .autoReload: EntryTexts.autoReload(on)
        case .postContest: EntryTexts.postContest(on)
        }
    }

    /// TOUR, BONUS, ROVERQTH, COUNTYLINE (`EP:426-431`, `AS:3846-3943`).
    private static func qsoParty(_ command: CallFieldCommand, _ ctx: EntryCommandContext,
                                 _ effects: inout [EntryCommandEffect]) {
        switch command {
        case .setTour(let params):
            setTour(params, ctx, &effects)
        case .tourOff:
            effects.append(.tourOff(status: .tr(EntryTexts.tourOff)))
        case .bonusStations(let calls):
            if KotlinStrings.isBlank(calls) {
                effects.append(.openDialog(.bonusStations))
            } else {
                let result = CountyLineSetting.bonusStations(calls)
                effects.append(.setBonusStations(result.calls, status: result.status))
            }
        case .roverQth(let county):
            if KotlinStrings.isBlank(county) {
                effects.append(.openDialog(.roverQth))
            } else {
                let qth: String = CountyLineSetting.roverQth(county)
                let known: Bool? = qth.isEmpty ? nil : ctx.isKnownLocation(qth)
                effects.append(contentsOf: [
                    .setRoverQth(qth),
                    .status(CountyLineSetting.roverQthStatus(qth, usesRoverQth: ctx.usesRoverQth, isKnownLocation: known)),
                ])
            }
        case .countyLine(let counties):
            if KotlinStrings.isBlank(counties) {
                effects.append(.openDialog(.countyLine))
            } else {
                let result = CountyLineSetting.apply(text: counties, usesRoverQth: ctx.usesRoverQth,
                                                     isKnownLocation: ctx.isKnownLocation)
                effects.append(contentsOf: [.setCountyLine(result.counties), .status(result.status)])
            }
        case .countyLineOff:
            let result = CountyLineSetting.off()
            effects.append(contentsOf: [.setCountyLine(result.counties), .status(result.status)])
        default:
            effects.append(.unavailable)
        }
    }

    /// `setTour(params.ifBlank { rstSent.takeIf { it.contains('/') } ?: "" })`.
    private static func setTour(_ params: String, _ ctx: EntryCommandContext, _ effects: inout [EntryCommandEffect]) {
        let fromSnt: String = ctx.rstSent.utf16.contains(0x2F) ? ctx.rstSent : ""
        let text: String = KotlinStrings.isBlank(params) ? fromSnt : params
        if KotlinStrings.isBlank(text) {
            effects.append(.status(EntryTexts.tourState(ctx.tour, now: ctx.now)))
            return
        }
        guard let tour = Tour.parse(text) else {
            effects.append(.status(EntryTexts.tourInvalid(text)))
            return
        }
        effects.append(.setTour(tour, status: EntryTexts.tourSet(tour)))
    }

    /// `SCRIPT name` (`EP:438-454`): the lines as call-field commands; a nested `SCRIPT` is skipped (a loop).
    private static func runScript(_ name: String, _ ctx: inout EntryCommandContext,
                                  _ effects: inout [EntryCommandEffect]) {
        guard let lines = ctx.loadScript(name) else {
            effects.append(.status(.tr("SCRIPT: skript „%s“ není v %s", .string(name), .string(ctx.scriptsDir))))
            return
        }
        for line in lines {
            let command: CallFieldCommand? = parseForEnter(line, currentFreqHz: ctx.currentFreqHz,
                                                           otherVfoHz: ctx.otherVfoHz)
            switch command {
            case nil:
                effects.append(.status(.tr("SCRIPT %s: „%s“ není příkaz", .string(name), .string(line))))
            case .runScript(let nested)?:
                effects.append(.status(.tr("SCRIPT: vnořený skript „%s“ přeskočen", .string(nested))))
            case let command?:
                run(command, &ctx, &effects)
            }
        }
        effects.append(.status(.tr("SCRIPT %s: provedeno %s příkazů", .string(name), .int(lines.count))))
    }
}
