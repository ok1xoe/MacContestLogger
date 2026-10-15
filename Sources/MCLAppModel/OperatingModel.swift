import Foundation
import MCLCore
import Observation

/// How the station operates (Kotlin `AppState`, `AS:1371-1376, 1770-1866, 2150-2235`): the operator at the key,
/// Run / S&P by the CQ frequency (`RunModeTracker`, owned by the main actor), ESM, the CQ repeat flag (its loop is
/// `CqRepeatRunner`: it runs while the call is blank in a keyable mode and stops on the TX lockout, post-contest, a
/// mode that cannot be keyed and a failed send —), post-contest entry and the keyer/ESM settings
/// typed as commands.
///
/// Setters named `apply…` change the state and the config but leave the status line to the caller (the command plan
/// shows its own texts); the others are Kotlin's `update…` with their status texts.
@Observable @MainActor
public final class OperatingModel {

    /// Kotlin `runMode` (S&P by default): the Run/S&P of the entry window with the focus.
    public var runMode: RunMode = .searchAndPounce
    /// N1MM: with two entry windows (SO2V / SO2R) each has its own Run/S&P (Run/S&P, S&P/S&P, Run/Run). The window
    /// with the focus keeps its state in `runMode`; this holds the other window's.
    public private(set) var windowRunModes: [RunMode] = [.searchAndPounce, .searchAndPounce]
    /// The entry window with the focus (0 = VFO A / rig 1, 1 = VFO B / rig 2).
    public private(set) var focusWindow: Int = 0
    /// Raised with every change of a CQ frequency (the CQ marker follows it).
    public private(set) var cqFreqRevision: Int = 0
    /// Alt+F11 / AUTORSP (Kotlin `autoRunSwitch`, from `config.runMode.autoSwitch`).
    public private(set) var autoRunSwitch: Bool
    /// Kotlin `esmEnabled` (from `config.esm.enabled`).
    public private(set) var esmEnabled: Bool
    /// Kotlin `cqRepeat` (RPT).
    public private(set) var cqRepeat: Bool = false
    /// The entry window the CQ repeat was switched on in (0 = VFO A / rig 1, 1 = VFO B / rig 2): in SO2R it keeps
    /// calling CQ on that (run) radio while the entry focus is on the other one (N1MM).
    public internal(set) var cqRepeatWindow: Int = 0
    /// N1MM Dueling CQs (Ctrl+B, SO2R): the CQ alternates between the radios (`So2rAutomation`). Esc ends it.
    public internal(set) var duelingCq: Bool = false
    /// The entry window that sent the last CQ — N1MM's run radio for FocusOther (`nil` = none yet).
    public internal(set) var lastCqWindow: Int?
    /// Kotlin `postContest` (POSTCONTEST): the time field is shown, nothing is sent.
    public private(set) var postContest: Bool = false
    /// The operator at the key (Kotlin `operatorCall`: the configured operator, otherwise the station call). A new
    /// operator resets `{SETWAVDIR}` (N1MM: OPON sets `{WAVDIR}` to the operator).
    public var operatorCall: String {
        didSet {
            if operatorCall != oldValue {
                wavDirName = nil
            }
        }
    }
    /// N1MM `{SETWAVDIR}`: the value of `{WAVDIR}` when it is not the operator's call (`nil`).
    public private(set) var wavDirName: String?
    /// Kotlin `lastSentKeys` (`=` in ESM resends them).
    public var lastSentKeys: [Int] = []
    /// N1MM `{VARYMSG1}` / `{VARYMSG2}`: how many times each was sent (shared by every mode and entry window).
    public private(set) var varyCounts: [Int] = [0, 0]
    /// Kotlin `tunedFreqHz`: the frequency the entry window is on.
    public private(set) var tunedFreqHz: Int64 = 0

    /// The active entry window's radio index, frequency and mode after a change (the plugins' band, mode and
    /// frequency events).
    @ObservationIgnored var onOperating: (@MainActor (_ radio: Int, _ freqHz: Int64, _ mode: Mode) -> Void)?
    @ObservationIgnored private let tracker = RunModeTracker()
    /// The keys of the last tuning effect (Kotlin `LaunchedEffect(state.tunedFreqHz, mode)`, `EP:187`).
    @ObservationIgnored private var lastTuned: [(freqHz: Int64, mode: Mode)?] = [nil, nil]
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel

    init(config: ConfigModel, status: StatusModel) {
        self.config = config
        self.status = status
        let station: StationConfig = config.config.station
        operatorCall = KotlinStrings.isBlank(station.operator) ? station.call : station.operator
        autoRunSwitch = config.config.runMode.autoSwitch
        esmEnabled = config.config.esm.enabled
    }

    /// Kotlin `syncRunModeFromConfig()` (`AS:2357-2359`, after a profile load): Alt+F11 follows
    /// `config.runMode.autoSwitch`.
    public func syncRunModeFromConfig() {
        autoRunSwitch = config.config.runMode.autoSwitch
    }

    /// Kotlin `syncEsmFromConfig()` (`AS:1379-1381`, after a Settings commit): ESM follows `config.esm.enabled`.
    public func syncEsmFromConfig() {
        esmEnabled = config.config.esm.enabled
    }

    public var isRun: Bool {
        runMode == .run
    }

    /// `{SETWAVDIR text}`: `{OPERATOR}` in the text is the operator's call; the operator's own call clears it.
    public func setWavDir(_ text: String) {
        let value: String = KotlinStrings.trim(text.replacingOccurrences(of: "{OPERATOR}", with: operatorCall,
                                                                        options: .caseInsensitive))
        wavDirName = value.isEmpty || value.uppercased() == operatorCall.uppercased() ? nil : value
    }

    /// A sent message used these `{VARYMSGn}` macros (1, 2): their counters move on.
    public func noteVaryUsed(_ numbers: [Int]) {
        for number in numbers where number >= 1 && number <= varyCounts.count {
            varyCounts[number - 1] &+= 1
        }
    }

    // MARK: - Run / S&P

    /// Kotlin `cqFrequencyHz(band)` (reads the revision, so a view follows it).
    public func cqFrequency(band: Band?) -> Int64? {
        _ = cqFreqRevision
        return tracker.cqFrequency(band).map { Int64($0) }
    }

    // MARK: - Run / S&P per entry window

    /// The Run/S&P of entry window `window` (the focused one's is `runMode`).
    public func runMode(window: Int) -> RunMode {
        window == focusWindow || !windowRunModes.indices.contains(window) ? runMode : windowRunModes[window]
    }

    public func isRun(window: Int) -> Bool {
        runMode(window: window) == .run
    }

    /// Sets the Run/S&P of entry window `window`.
    public func setRunMode(_ mode: RunMode, window: Int) {
        if window == focusWindow || !windowRunModes.indices.contains(window) {
            runMode = mode
        } else {
            windowRunModes[window] = mode
        }
    }

    /// The entry focus moved to window `window` (two entry windows): `runMode` becomes that window's.
    public func focusMoved(to window: Int) {
        guard window != focusWindow, windowRunModes.indices.contains(window) else { return }
        windowRunModes[focusWindow] = runMode
        focusWindow = window
        runMode = windowRunModes[window]
    }

    /// Kotlin `onCqSent(freqHz)`: F1 sent — the CQ frequency is remembered, Run (of the window that sent it).
    public func onCqSent(_ freqHz: Int64, window: Int? = nil) {
        setRunMode(tracker.onCq(Int(clamping: freqHz)), window: window ?? focusWindow)
        cqFreqRevision += 1
    }

    /// Kotlin `selectRunMode(mode, freqHz)` (`AS:2196`): Run sets the CQ frequency to the current one.
    public func select(_ mode: RunMode, freqHz: Int64, window: Int? = nil) {
        if mode == .run {
            onCqSent(freqHz, window: window)
        } else {
            setRunMode(.searchAndPounce, window: window ?? focusWindow)
        }
    }

    /// Kotlin `toggleRunMode(freqHz)` (Alt+U); the texts are not translated in Kotlin.
    public func toggleRun(freqHz: Int64, window: Int? = nil) {
        let target: Int = window ?? focusWindow
        select(runMode(window: target) == .run ? .searchAndPounce : .run, freqHz: freqHz, window: target)
        if runMode(window: target) == .run {
            let kHz: String = EntryFormat.oneDecimal(Double(freqHz) / 1000.0)
            status.showVerbatim("Run (CQ frekvence " + kHz + " kHz)")
        } else {
            status.showVerbatim("S&P")
        }
    }

    /// Kotlin `LaunchedEffect(state.tunedFreqHz, mode) { onTunedForRunMode(...) }` and `updateTunedFreq`: the entry
    /// window's frequency or mode changed.
    public func tuned(_ freqHz: Int64, mode: Mode, window: Int? = nil) {
        let target: Int = window ?? focusWindow
        if target == focusWindow {
            tunedFreqHz = freqHz
        }
        // The effect re-runs only when its keys change: a retyped frequency, the same mode again or a contest
        // activation on the same frequency leave a hand-picked S&P alone.
        let slot: Int = lastTuned.indices.contains(target) ? target : 0
        if let last = lastTuned[slot], last.freqHz == freqHz, last.mode == mode {
            return
        }
        lastTuned[slot] = (freqHz: freqHz, mode: mode)
        let next: RunMode? = tracker.onTuned(Int(clamping: freqHz), mode: mode, current: runMode(window: target),
                                             autoSwitch: autoRunSwitch,
                                             runOnCqFreq: config.config.runMode.runOnCqFrequency)
        if let next {
            setRunMode(next, window: target)
        }
    }

    /// Kotlin `jumpToCqFrequency(band)` without a rig: the band's CQ frequency (the caller puts it into the field and
    /// hands it to the rig port) and Run; `nil` with `tr("Na pásmu %s zatím nebylo CQ")` when there was no CQ.
    public func jumpToCqFrequency(band: Band?, window: Int? = nil) -> Int64? {
        guard let cq = cqFrequency(band: band) else {
            status.show("Na pásmu %s zatím nebylo CQ", .string(band?.adif ?? ""))
            return nil
        }
        setRunMode(.run, window: window ?? focusWindow)
        return cq
    }

    /// N1MM Ctrl+Alt+Q: the last CQ frequency on any band and Run; `nil` with a status when there was no CQ yet.
    public func jumpToLastCqFrequency() -> Int64? {
        _ = cqFreqRevision
        guard let cq = tracker.lastCqFrequency else {
            status.show("Zatím nebylo žádné CQ")
            return nil
        }
        runMode = .run
        return Int64(cq)
    }

    /// AUTORSP / NOAUTRSP without a status (the command plan shows it).
    public func applyAutoRunSwitch(_ enabled: Bool) {
        autoRunSwitch = enabled
        config.config.runMode.autoSwitch = enabled
        config.saveSilently()
    }

    /// Kotlin `updateAutoRunSwitch` (Alt+F11).
    public func setAutoRunSwitch(_ enabled: Bool) {
        applyAutoRunSwitch(enabled)
        status.showJoined(EntryTexts.autoRunSwitch(enabled).parts, separator: "")
    }

    // MARK: - ESM, RPT, post-contest

    /// ESM / NOESM without a status.
    public func applyEsm(_ enabled: Bool) {
        esmEnabled = enabled
        config.config.esm.enabled = enabled
        config.saveSilently()
    }

    /// Kotlin `updateEsm` (Ctrl+M).
    public func setEsm(_ enabled: Bool) {
        applyEsm(enabled)
        status.showJoined(EntryTexts.esm(enabled).parts, separator: "")
    }

    /// RPT / NORPT without a status.
    public func applyCqRepeat(_ on: Bool) {
        cqRepeat = on
    }

    /// Kotlin `updateCqRepeat` (Alt+R).
    public func setCqRepeat(_ on: Bool) {
        applyCqRepeat(on)
        let text: EntryStatus = EntryTexts.cqRepeat(on, repeatSeconds: config.config.runMode.repeatSeconds)
        status.showJoined(text.parts, separator: "")
    }

    /// Kotlin `promptRepeatTime` (Ctrl+R): the prompt's initial text `String.format(Locale.US, "%.1f", seconds)`.
    public var repeatTimeText: String {
        EntryFormat.oneDecimal(config.config.runMode.repeatSeconds)
    }

    /// The answer of the Ctrl+R prompt (`AS:1777-1789`): Kotlin `trim().replace(',', '.').toDoubleOrNull()`, ≤ 0 or
    /// not a number → `tr("Opakování CQ: neplatný čas „%s“")`; above 100 = milliseconds.
    public func applyRepeatTime(_ text: String) {
        // Kotlin `v == null || v <= 0`: NaN passes the check.
        guard let value = EntryFormat.repeatSeconds(text), !(value <= 0) else {
            status.show("Opakování CQ: neplatný čas „%s“", .string(text))
            return
        }
        config.config.runMode.repeatSeconds = value > 100 ? value / 1000.0 : value
        config.saveSilently()
        status.showVerbatim("Pauza mezi CQ " + EntryTexts.repeatLabel(config.config.runMode.repeatSeconds))
    }

    /// POSTCONTEST / NOPOSTCONTEST without a status: entering it stops the CQ repeat (`AS:1832-1838`).
    public func applyPostContest(_ on: Bool) {
        postContest = on
        if on {
            cqRepeat = false
        }
    }

    /// Kotlin `updatePostContest` (the menu item `contest.postcontest`).
    public func setPostContest(_ on: Bool) {
        applyPostContest(on)
        status.showJoined(EntryTexts.postContest(on).parts, separator: "")
    }

    // MARK: - keyer settings typed as commands

    /// WORKDUPE / NOWORKDUPE without a status.
    public func applyWorkDupes(_ on: Bool) {
        config.config.esm.workDupes = on
        config.saveSilently()
    }

    /// AUTORELOAD / NOAUTORELOAD without a status.
    public func applyAutoReload(_ on: Bool) {
        config.config.autoReloadLastContest = on
        config.saveSilently()
    }

    /// FULLABBREV… / NOABBREV without a status (`updateCutNumbers`).
    public func applyCutNumbers(_ style: CutStyle?) {
        config.config.cwKeyer.cutNumbers = style != nil
        if let style {
            config.config.cwKeyer.cutStyle = style
        }
        config.saveSilently()
    }

    /// Kotlin `toggleCutNumbers` (Ctrl+G).
    public func toggleCutNumbers() {
        config.config.cwKeyer.cutNumbers.toggle()
        config.saveSilently()
        if config.config.cwKeyer.cutNumbers {
            status.show("Cut čísla zapnuta (%s)", .string(config.config.cwKeyer.cutStyle.label))
        } else {
            status.show("Cut čísla vypnuta")
        }
    }

    /// ESM options (`state.esmOptions()`).
    public var esmOptions: EsmEngine.Options {
        EsmEngine.Options(spCallOnce: config.config.esm.spCallOnce, workDupes: config.config.esm.workDupes)
    }

    // MARK: - operator

    /// Kotlin `setOperator(call, persist)` (`AS:2156-2166`): `trim().uppercase()`, a blank call is ignored; with
    /// `persist` the call is written to the station config. Kotlin's save failure text is overwritten by the
    /// status in the same frame, so the save is silent here too.
    public func setOperator(_ call: String, persist: Bool) {
        let op: String = KotlinStrings.uppercase(KotlinStrings.trim(call))
        if KotlinStrings.isBlank(op) {
            return
        }
        operatorCall = op
        if persist {
            config.config.station.operator = op
            config.saveSilently()
        }
        status.showJoined(EntryTexts.operatorSet(op, persisted: persist).parts, separator: "")
    }
}
