import Foundation
import MCLCore
import Observation
import os

/// The rigs of v1.1.1 (`AppState.cat1`/`cat2`/`cat`, `CatConnection`; `AS:130-143`, `CC:32-172`) and what the entry
/// windows do with them: tuning (`RigModel+Tuning.swift`), VFO B, split, RIT, SO2V/SO2R and antennas
/// (`RigModel+Vfo.swift`).
///
/// The state (`tuning`, `rit`, `vfo`, the antenna, the status) changes synchronously on the main actor in
/// Kotlin's order; every CAT call goes to the rig's `RigLane` (one serial thread per rig, so commands keep their
/// order) and its result comes back asynchronously. The main actor never calls a `CatSession` getter: it reads
/// `cat1`/`cat2`, the mirrors that `onChange` fills (posted to the main queue in order).
@Observable @MainActor
public final class RigModel {

    /// The mirror of rig 1's session (Kotlin `cat1.state`/`status`/`connected`).
    public private(set) var cat1 = CatSession.Snapshot()
    /// The mirror of rig 2's session (SO2R).
    public private(set) var cat2 = CatSession.Snapshot()
    /// `tunedFreqHz`, `previousFreqHz`, `lastFreqOnBand`, `antennaBand`.
    public internal(set) var tuning = TuningState()
    /// `ritHz` (the last value the rig accepted).
    public internal(set) var rit = RitState()
    /// SO1V / SO2V / SO2R, the active VFO, the VFOs' frequencies, SO2R stereo.
    public internal(set) var vfo: VfoState
    /// `currentAntenna` and its identity (rules (a)–(c)).
    public internal(set) var antenna = AntennaApply()
    /// Kotlin `focusVfoRequest`: the entry window `vfo` takes the focus (the view clears it).
    public var focusVfoRequest: Int?

    /// The shared live mode mapping of both rigs.
    @ObservationIgnored public let modeStore = HamlibModeStore()
    @ObservationIgnored let lanes: [RigLane]
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let language: LanguageModel
    @ObservationIgnored let contest: ContestModel
    @ObservationIgnored let dialogs: DialogsModel
    @ObservationIgnored let windows: WindowsModel
    @ObservationIgnored let peripherals: PeripheralsModel
    @ObservationIgnored public let rotator: RotatorModel
    @ObservationIgnored let catLog: CatTrafficLog
    /// The language and the transverters for the sessions' threads.
    @ObservationIgnored private let shared: SharedRigSettings
    /// The entry windows that follow the rig (weak; the VFO B window joins later).
    @ObservationIgnored private var entries: [WeakEntry] = []
    /// The call typed in the active entry window (Kotlin `typedCall`, the antenna's azimuth).
    @ObservationIgnored var typedCall: @MainActor () -> String = { "" }
    /// `cwKeyer?.close(); cwKeyer = null` of `resetInterfaces` (the keyer).
    @ObservationIgnored public var resetKeyer: @MainActor () -> Void = {}
    /// The keyer's release before a user disconnect of rig `index` (a CAT carrier, a voice message's PTT).
    @ObservationIgnored var keyerRelease: @MainActor (Int) -> Void = { _ in }
    /// Run on a rig's connect thread with every fresh connection, before its first poll (wired by the app to the
    /// keyer: a PTT release still owed to that rig goes out first).
    @ObservationIgnored let connectRelease = ConnectReleaseHook()
    /// Kotlin `autoSplitActive`: the split was turned on by a spot (only such a split is turned off by the next).
    @ObservationIgnored var autoSplitActive = false
    /// The rig that got the footswitch PTT on (the release goes to the same rig even after a VFO switch).
    @ObservationIgnored var footswitchPttRig: Int?
    /// Set when the quit starts releasing the transmitter: a footswitch press is refused from then on (a release
    /// edge still releases), so nothing keys a rig after the transmit-release milestone.
    @ObservationIgnored var transmitClosed = false
    /// The pileup simulator refuses the footswitch PTT while it starts or runs (a status text; a
    /// release is never gated); wired by the app model to `TxPorts.rigKeyingGate`.
    @ObservationIgnored var keyingGate: @MainActor () -> EntryStatus? = { nil }
    /// The spot buffer and the exchange prediction of `tuneToSpot` (wired by the app).
    @ObservationIgnored var spotSources = SpotSources()

    struct Dependencies {
        let hardware: HardwarePorts
        let catLog: CatTrafficLog
        let config: ConfigModel
        let status: StatusModel
        let language: LanguageModel
        let contest: ContestModel
        let dialogs: DialogsModel
        let windows: WindowsModel
        let peripherals: PeripheralsModel
        let rotator: RotatorModel
    }

    init(_ dependencies: Dependencies) {
        config = dependencies.config
        status = dependencies.status
        language = dependencies.language
        contest = dependencies.contest
        dialogs = dependencies.dialogs
        windows = dependencies.windows
        peripherals = dependencies.peripherals
        rotator = dependencies.rotator
        catLog = dependencies.catLog
        vfo = VfoState(radioMode: dependencies.config.config.radioMode)
        let shared = SharedRigSettings(translator: dependencies.language.translator,
                                       transverters: dependencies.config.config.transverters)
        self.shared = shared
        let mirror = MirrorSink()
        var built: [RigLane] = []
        for index in 0..<2 {
            let transverters: @Sendable () -> [TransverterEntry]
            if index == 0 {
                transverters = { shared.transverters }
            } else {
                transverters = { [] }
            }
            let provider: HamlibModeProvider = modeStore.provider
            let hooks = CatHooks(
                index: index, transverters: transverters, modes: provider, log: dependencies.catLog,
                translate: { key in shared.translate(key) },
                onChange: { snapshot in mirror.post(index, snapshot) },
                onUnexpectedError: { error in mirror.unexpected(index, error) })
            let cat: any CatPort = dependencies.hardware.makeCat(hooks)
            let connectRelease: ConnectReleaseHook = self.connectRelease
            cat.setOnConnected { rig in
                connectRelease.run(index, rig)
            }
            built.append(RigLane(cat: cat, name: "rig-\(index + 1)"))
        }
        lanes = built
        mirror.model = self
        observeShared()
    }

    // MARK: - the mirrors

    /// The snapshot of the rig the entry window `vfo` works with (Kotlin `catFor(vfo)`).
    public func snapshot(vfo index: Int) -> CatSession.Snapshot {
        vfo.catIndex(for: index) == 1 ? cat2 : cat1
    }

    /// The active rig's snapshot (Kotlin `cat`).
    public var active: CatSession.Snapshot {
        vfo.activeCatIndex == 1 ? cat2 : cat1
    }

    /// Kotlin `cat.state`.
    public var activeState: RigState? {
        active.state
    }

    /// Kotlin `catFor(vfo).connected`.
    public func connected(vfo index: Int) -> Bool {
        snapshot(vfo: index).connected
    }

    /// Kotlin `state.cat.connected` (`SettingsServices.catConnected`).
    public var catConnected: Bool {
        active.connected
    }

    /// Kotlin `catFor(vfo).status`: the message, or `tr("TRX odpojen")` translated when shown.
    public func status(vfo index: Int) -> String {
        snapshot(vfo: index).statusMessage ?? language.tr(CatSession.disconnectedText)
    }

    /// The active rig's status (the status line's fallback, Kotlin `state.cat.status`).
    public var activeStatus: String {
        status(vfo: vfo.activeVfo)
    }

    /// The lane of the active rig (Kotlin `cat`).
    var activeLane: RigLane {
        lanes[vfo.activeCatIndex]
    }

    fileprivate func applySnapshot(_ index: Int, _ snapshot: CatSession.Snapshot) {
        let previous: RigState? = index == 0 ? cat1.state : cat2.state
        if index == 0 {
            cat1 = snapshot
        } else {
            cat2 = snapshot
        }
        // Kotlin `LaunchedEffect(state.cat.state, …)`: only a different state of the active rig is followed.
        if index == vfo.activeCatIndex && previous != snapshot.state {
            notifyEntries { $0.followRig() }
        }
    }

    /// An error Kotlin does not catch in `connect` (it escapes the coroutine): shown and written to the CAT log.
    fileprivate func unexpected(_ message: String) {
        status.showVerbatim(message)
        try? catLog.info(message)
    }

    // MARK: - connection

    /// Kotlin `rigConfigFor(vfo)`: rig 2's configuration only for VFO B in SO2R.
    public func rigConfig(vfo index: Int) -> RigConfig {
        vfo.catIndex(for: index) == 1 ? config.config.rig2 : config.config.rig
    }

    /// The LED / „TRX" of an entry window: `catFor(vfo).toggle(rigConfigFor(vfo))`. Pressed again during
    /// „Připojuji…" it cancels that connect and waits for it (Kotlin could start a second daemon then).
    public func toggle(vfo index: Int) {
        let rc: RigConfig = rigConfig(vfo: index)
        let rig: Int = vfo.catIndex(for: index)
        releaseBeforeUserDisconnect(onRig: rig)
        lanes[rig].run { cat in
            if cat.isConnecting {
                cat.disconnectCancellingConnect(nil)
            } else {
                cat.toggle(rc)
            }
        }
    }

    /// The reconnect after Settings (`CD:609-611`, `SettingsServices.reconnectCat`): the **active** rig with
    /// `config.rig` (in SO2R with rig 2 active, rig 2 gets rig 1's configuration, as in Kotlin).
    public func reconnect(disconnectFirst: Bool) {
        let rc: RigConfig = config.config.rig
        let message: String = language.tr("překonfigurováno")
        releaseBeforeUserDisconnect(onRig: vfo.activeCatIndex)
        activeLane.run { cat in
            if disconnectFirst {
                cat.disconnectCancellingConnect(message)
            } else if cat.isConnecting {
                // A connect still running would otherwise race the new one (and its daemon).
                cat.disconnectCancellingConnect(nil)
            }
            cat.connect(rc)
        }
    }

    /// `cat.disconnect("scan")` before a rig scan (`HW:221`): the active rig, awaited — the scan opens the serial
    /// port itself, so a connect in flight is cancelled and waited for too.
    public func disconnectForScan(reason: String) async {
        let lane: RigLane = activeLane
        releaseBeforeUserDisconnect(onRig: vfo.activeCatIndex)
        lane.run { cat in
            cat.disconnectCancellingConnect(reason)
        }
        await lane.settle()
    }

    /// Kotlin `resetInterfaces()` (`AS:2106-2115`): only rig 1 reconnects (not rig 2, not OTRSP) and the CW
    /// keyer is dropped; `"reset"` is the verbatim disconnect message.
    public func resetInterfaces() {
        let wasConnected: Bool = cat1.connected
        let rc: RigConfig = config.config.rig
        if wasConnected {
            releaseBeforeUserDisconnect(onRig: 0)
            lanes[0].run { cat in
                cat.disconnectCancellingConnect(RigTexts.resetDisconnect)
            }
        }
        resetKeyer()
        if wasConnected {
            lanes[0].run { cat in
                cat.connect(rc)
            }
        }
        show(RigTexts.interfacesReset(wasConnected: wasConnected))
    }

    /// Kotlin `applyModeSettings()` (`AS:2362-2364`): Digital Modes / RTTY AFSK into the shared mapping.
    public func applyModeSettings() {
        modeStore.configure(dataMode: Mode.from(adif: config.config.dataMode), rttyAfsk: config.config.rttyAfsk)
    }

    /// Kotlin `loggedMode(radio, freqHz)` (`AS:2366-2370`): the mode to log by Mode Control.
    public func loggedMode(_ radio: Mode?, freqHz: Int64) -> Mode? {
        let app: AppConfig = config.config
        let rule: ModeControl.Rule = ModeControl.Rule(rawValue: app.modeRule) ?? .radio
        return ModeControl.loggedMode(rule, radio: radio, bandplan: bandPlanCategory(freqHz),
                                      always: Mode.from(adif: app.modeAlways))
    }

    /// Kotlin `contest.bandPlanCategory(freqHz)`: the band plan of my region (by my call's continent).
    func bandPlanCategory(_ freqHz: Int64) -> BandPlan.ModeCategory? {
        let continent: String? = contest.runtime.dxccLookup?.resolve(config.config.station.call)?.primaryContinent
        let region = BandPlan.IaruRegion.forContinent(continent)
        return contest.environment.bandPlan.modeAt(freqHz, region)
    }

    /// Kotlin `tuneStepHz(mode)` (`AS:2373-2376`).
    public func tuneStepHz(_ mode: Mode) -> Int64 {
        TuningState.tuneStepHz(mode, cwHz: config.config.tuneStepCwHz, ssbHz: config.config.tuneStepSsbHz)
    }

    /// Before a user-initiated disconnect of rig `index` (the LED, a reconnect, the reset, a scan): the keyer's carrier
    /// or voice PTT and a held footswitch PTT on that rig are released — `T 0` is queued on its lane ahead of the
    /// disconnect, so the rig never stays keyed.
    func releaseBeforeUserDisconnect(onRig index: Int) {
        keyerRelease(index)
        releaseFootswitchPtt(onRig: index)
    }

    // MARK: - the entry windows

    private struct WeakEntry {
        weak var entry: EntryModel?
    }

    /// An entry window follows the rig (the main entry at start-up, the VFO B window when it is created).
    public func attach(_ entry: EntryModel) {
        entries.removeAll { $0.entry == nil || $0.entry === entry }
        entries.append(WeakEntry(entry: entry))
        entry.rig = self
    }

    func notifyEntries(_ body: (EntryModel) -> Void) {
        for holder in entries {
            if let entry = holder.entry {
                body(entry)
            }
        }
    }

    // MARK: - shutdown

    /// Waits for the work queued on both lanes (tests).
    func settle() async {
        for lane in lanes {
            await lane.settle()
        }
    }

    /// Quit: a footswitch PTT still held is released first, then **both** rigs disconnect with
    /// `tr("ukončeno")` (Kotlin only the active one), cancelling a connect in flight and waiting for it, so no
    /// `rigctld` or poller survives the quit.
    func shutdown() async {
        releaseFootswitchPtt()
        let message: String = language.tr("ukončeno")
        for lane in lanes {
            lane.run { cat in
                cat.disconnectCancellingConnect(message)
            }
        }
        await settle()
    }

    // MARK: - helpers

    func show(_ message: EntryStatus) {
        status.showJoined(message.parts, separator: "")
    }

    /// The translator and the transverter table follow the app (the sessions read them on their own threads).
    private func observeShared() {
        withObservationTracking {
            _ = language.translator
            _ = config.config.transverters
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                self.shared.update(translator: self.language.translator,
                                   transverters: self.config.config.transverters)
                self.observeShared()
            }
        }
    }
}

/// What the CAT sessions read on their own threads: the UI language (`tr` of their texts) and rig 1's transverters.
final class SharedRigSettings: Sendable {
    private struct State {
        var translator: Translator
        var transverters: [TransverterEntry]
    }

    private let state: OSAllocatedUnfairLock<State>

    init(translator: Translator, transverters: [TransverterEntry]) {
        state = OSAllocatedUnfairLock(initialState: State(translator: translator, transverters: transverters))
    }

    func update(translator: Translator, transverters: [TransverterEntry]) {
        state.withLock { $0 = State(translator: translator, transverters: transverters) }
    }

    func translate(_ key: String) -> String {
        state.withLock { $0.translator }.translate(key)
    }

    var transverters: [TransverterEntry] {
        state.withLock { $0.transverters }
    }
}

/// The sessions' callbacks → the main actor, in the order they came (`MainHop.post` = the main queue's FIFO).
private final class MirrorSink: @unchecked Sendable {
    private let lock = NSLock()
    private weak var target: RigModel?

    var model: RigModel? {
        get { lock.withLock { target } }
        set { lock.withLock { target = newValue } }
    }

    func post(_ index: Int, _ snapshot: CatSession.Snapshot) {
        let model: RigModel? = self.model
        MainHop.post {
            model?.applySnapshot(index, snapshot)
        }
    }

    func unexpected(_ index: Int, _ error: any Error) {
        let model: RigModel? = self.model
        let message: String = ErrorText.message(error)
        MainHop.post {
            model?.unexpected(message)
        }
    }
}

/// The hook a rig's connect thread runs with a fresh connection (rig index, the new rig), set once by the app.
final class ConnectReleaseHook: Sendable {
    private let hook = OSAllocatedUnfairLock<(@Sendable (Int, any RigController) -> Void)?>(initialState: nil)

    func set(_ body: @escaping @Sendable (Int, any RigController) -> Void) {
        hook.withLock { $0 = body }
    }

    func run(_ index: Int, _ rig: any RigController) {
        hook.withLock { $0 }?(index, rig)
    }
}
