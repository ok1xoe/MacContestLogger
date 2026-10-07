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

    /// Kotlin `runMode` (S&P by default).
    public var runMode: RunMode = .searchAndPounce
    /// Raised with every change of a CQ frequency (the CQ marker follows it).
    public private(set) var cqFreqRevision: Int = 0
    /// Alt+F11 / AUTORSP (Kotlin `autoRunSwitch`, from `config.runMode.autoSwitch`).
    public private(set) var autoRunSwitch: Bool
    /// Kotlin `esmEnabled` (from `config.esm.enabled`).
    public private(set) var esmEnabled: Bool
    /// Kotlin `cqRepeat` (RPT).
    public private(set) var cqRepeat: Bool = false
    /// Kotlin `postContest` (POSTCONTEST): the time field is shown, nothing is sent.
    public private(set) var postContest: Bool = false
    /// The operator at the key (Kotlin `operatorCall`: the configured operator, otherwise the station call).
    public var operatorCall: String
    /// Kotlin `lastSentKeys` (`=` in ESM resends them).
    public var lastSentKeys: [Int] = []
    /// Kotlin `tunedFreqHz`: the frequency the entry window is on.
    public private(set) var tunedFreqHz: Int64 = 0

    /// The active entry window's radio index, frequency and mode after a change (the plugins' band, mode and
    /// frequency events).
    @ObservationIgnored var onOperating: (@MainActor (_ radio: Int, _ freqHz: Int64, _ mode: Mode) -> Void)?
    @ObservationIgnored private let tracker = RunModeTracker()
    /// The keys of the last tuning effect (Kotlin `LaunchedEffect(state.tunedFreqHz, mode)`, `EP:187`).
    @ObservationIgnored private var lastTuned: (freqHz: Int64, mode: Mode)?
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

    // MARK: - Run / S&P

    /// Kotlin `cqFrequencyHz(band)` (reads the revision, so a view follows it).
    public func cqFrequency(band: Band?) -> Int64? {
        _ = cqFreqRevision
        return tracker.cqFrequency(band).map { Int64($0) }
    }

    /// Kotlin `onCqSent(freqHz)`: F1 sent — the CQ frequency is remembered, Run.
    public func onCqSent(_ freqHz: Int64) {
        runMode = tracker.onCq(Int(clamping: freqHz))
        cqFreqRevision += 1
    }

    /// Kotlin `selectRunMode(mode, freqHz)` (`AS:2196`): Run sets the CQ frequency to the current one.
    public func select(_ mode: RunMode, freqHz: Int64) {
        if mode == .run {
            onCqSent(freqHz)
        } else {
            runMode = .searchAndPounce
        }
    }

    /// Kotlin `toggleRunMode(freqHz)` (Alt+U); the texts are not translated in Kotlin.
    public func toggleRun(freqHz: Int64) {
        select(runMode == .run ? .searchAndPounce : .run, freqHz: freqHz)
        if runMode == .run {
            let kHz: String = EntryFormat.oneDecimal(Double(freqHz) / 1000.0)
            status.showVerbatim("Run (CQ frekvence " + kHz + " kHz)")
        } else {
            status.showVerbatim("S&P")
        }
    }

    /// Kotlin `LaunchedEffect(state.tunedFreqHz, mode) { onTunedForRunMode(...) }` and `updateTunedFreq`: the entry
    /// window's frequency or mode changed.
    public func tuned(_ freqHz: Int64, mode: Mode) {
        tunedFreqHz = freqHz
        // The effect re-runs only when its keys change: a retyped frequency, the same mode again or a contest
        // activation on the same frequency leave a hand-picked S&P alone.
        if let last = lastTuned, last.freqHz == freqHz, last.mode == mode {
            return
        }
        lastTuned = (freqHz: freqHz, mode: mode)
        let next: RunMode? = tracker.onTuned(Int(clamping: freqHz), mode: mode, current: runMode,
                                             autoSwitch: autoRunSwitch,
                                             runOnCqFreq: config.config.runMode.runOnCqFrequency)
        if let next {
            runMode = next
        }
    }

    /// Kotlin `jumpToCqFrequency(band)` without a rig: the band's CQ frequency (the caller puts it into the field and
    /// hands it to the rig port) and Run; `nil` with `tr("Na pásmu %s zatím nebylo CQ")` when there was no CQ.
    public func jumpToCqFrequency(band: Band?) -> Int64? {
        guard let cq = cqFrequency(band: band) else {
            status.show("Na pásmu %s zatím nebylo CQ", .string(band?.adif ?? ""))
            return nil
        }
        runMode = .run
        return cq
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
