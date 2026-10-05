import Foundation
import MCLCore
import Observation
import os

/// The tools of the Settings tabs (`HW:` = `ui/configurer/HardwareTab.kt`, `MT:` = `ModeTabs.kt`, `CT:` =
/// `ContestTab.kt`, `VK:` = `VoiceKeyerTabs.kt` of v1.1.1): the rig list and the rig scan of the „Nastavení TCVR"
/// sheet, the serial ports, the sound devices, the fldigi probe, the counts of the contest tab, the language list
/// and the menu file group of Other.
///
/// - Everything that touches the outside world goes through `SettingsToolPorts`: the rig list, the scan,
///   the device listings and fldigi run on threads of their own; files are read on `BlockingQueue`.
/// - Kotlin lists the ports and the devices and counts the files at every composition; here the ports and devices
///   are listed when a tab or the sheet opens (the view calls the loaders), and the counts follow the draft 300 ms
///   after its last change, with a generation so a late result for an older text is dropped.
/// - The view calls `closeRigSheet()` when the sheet closes and `windowClosed()` when the window closes: a scan in
///   flight is cancelled and its late results are dropped (Kotlin's `DisposableEffect` + the composition's scope).
@Observable @MainActor
public final class SettingsToolsModel {

    /// The scan line of the sheet (Kotlin `scanning`, `scanStatus`).
    public struct ScanState: Equatable, Sendable {
        public var isScanning: Bool
        /// Already in the language of the moment it was set (Kotlin stores the `tr` result).
        public var status: String

        public static let idle = ScanState(isScanning: false, status: "")
    }

    /// Which menu definition applies (`MT:196-221`), read again after every action of the group.
    public struct MenuFileState: Equatable, Sendable {
        /// `<dataDir>/menu.json`.
        public let file: String
        public let source: MenuConfigStore.Source
        /// Why the user's file was not used.
        public let error: String?
    }

    /// The groups of counts that follow one draft field each.
    enum CountGroup: CaseIterable, Sendable {
        case contestData, scp, callHistory
    }

    // MARK: - state

    /// The hamlib models (`HW:209`); empty until the list is read.
    public private(set) var rigModels: [HamlibRigModel] = []
    /// `SerialPorts.available()` as last listed.
    public private(set) var serialPorts: [String] = []
    public private(set) var scanState: ScanState = .idle
    /// A scan thread is still running — also after the sheet closed, until its current candidate ended. No new scan
    /// starts meanwhile, so two `rigctld` never share the rig's serial port (Kotlin allows it after a reopen).
    public private(set) var scanInFlight: Bool = false
    /// The result line under „Vyzkoušet".
    public private(set) var fldigiProbeText: String = ""
    /// `nil` until counted.
    public private(set) var scpCount: Int?
    public private(set) var callHistoryCount: Int?
    public private(set) var contestYamlCount: Int?
    public private(set) var multiplierYamlCount: Int?
    /// `I18n.available()`: Czech first, then the directory's languages.
    public private(set) var languages: [LanguageCatalog.Language] = []
    /// `nil` until read.
    public private(set) var menuFileState: MenuFileState?
    /// The message line of the menu group (`MT:224-252`).
    public private(set) var menuMessage: String = ""

    private var outputDeviceNames: [String] = []
    private var inputDeviceNames: [String] = []

    @ObservationIgnored private let ports: SettingsToolPorts
    @ObservationIgnored private let settings: SettingsModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let menu: MenuModel
    @ObservationIgnored private let dataDir: URL
    @ObservationIgnored private let countsClock: any RescoreClock
    /// Counts one group for one input (`[contests, multipliers]` or `[count]`); tests substitute a held counter.
    @ObservationIgnored var counter: @Sendable (CountGroup, String) -> [Int] = SettingsToolsModel.count
    @ObservationIgnored private var scanListener: ScanListener?
    @ObservationIgnored private var scanGeneration: Int = 0
    @ObservationIgnored private var sheetGeneration: Int = 0
    @ObservationIgnored private var fldigiGeneration: Int = 0
    @ObservationIgnored private var windowGeneration: Int = 0
    @ObservationIgnored private var countSlots: [CountGroup: CountSlot] = [:]
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTaskId: Int = 0

    struct Dependencies {
        let ports: SettingsToolPorts
        let settings: SettingsModel
        let language: LanguageModel
        let status: StatusModel
        let menu: MenuModel
        let dataDir: URL
        let countsClock: any RescoreClock
    }

    init(_ dependencies: Dependencies) {
        ports = dependencies.ports
        settings = dependencies.settings
        language = dependencies.language
        status = dependencies.status
        menu = dependencies.menu
        dataDir = dependencies.dataDir
        countsClock = dependencies.countsClock
    }

    // MARK: - rig list and serial ports

    /// `RigModelFilter.manufacturers(models)`.
    public var manufacturers: [String] {
        RigModelFilter.manufacturers(rigModels)
    }

    /// `RigModelFilter.filter(models, manufacturer, query)`.
    public func filtered(manufacturer: String?, query: String) -> [HamlibRigModel] {
        RigModelFilter.filter(rigModels, manufacturer: manufacturer, query: query)
    }

    /// The OTRSP and footswitch drop-downs (`HW:128, 168`): `"—"` + the ports.
    public var serialPortsWithNone: [String] {
        ["—"] + serialPorts
    }

    /// The sheet opened (`HW:208-210`): the model list, then the serial ports, each off the main thread. The list is
    /// empty until it is read (hamlib missing → its fallback models).
    public func openRigSheet() {
        sheetGeneration += 1
        let generation: Int = sheetGeneration
        rigModels = []
        serialPorts = []
        let port: any RigListPort = ports.rigList
        let devices: any DevicePort = ports.devices
        track { [weak self] in
            let models: [HamlibRigModel] = await OwnThread.run("rig-list") { port.list() }
            guard let self, generation == self.sheetGeneration else { return }
            self.rigModels = models
            let listed: [String] = await OwnThread.run("serial-ports") { devices.serialPorts() }
            guard generation == self.sheetGeneration else { return }
            self.serialPorts = listed
        }
    }

    /// The sheet closed (`HW:211` `DisposableEffect`): a running scan is told to stop at the next candidate and its
    /// late answers are dropped; the scan line is cleared.
    public func closeRigSheet() {
        sheetGeneration += 1
        scanListener?.cancel()
        scanListener = nil
        scanGeneration += 1
        scanState = .idle
    }

    /// A tab with a serial port drop-down opened (Hardware, CW klíč): the ports are listed once.
    public func loadSerialPorts() {
        let generation: Int = windowGeneration
        let devices: any DevicePort = ports.devices
        track { [weak self] in
            let listed: [String] = await OwnThread.run("serial-ports") { devices.serialPorts() }
            guard let self, generation == self.windowGeneration else { return }
            self.serialPorts = listed
        }
    }

    // MARK: - scan (HW:205-250)

    /// The scan button is enabled (`HW:316`): no scan running (nor one still finishing) and a port chosen.
    public func canStartScan(device: String) -> Bool {
        !scanState.isScanning && !scanInFlight && !KotlinStrings.isBlank(device)
    }

    /// „Scan – najít rig" (`startScan`, `HW:217-245`): „Skenuji…", CAT disconnected („scan"), then the candidates
    /// (the chosen model at every baud, then the common models) are probed one by one off the main thread. A found
    /// rig goes into the draft (`rigModel`, `rigModelLabel`, `baud`).
    public func startScan(draft: ConfigurerDraft) {
        guard canStartScan(device: draft.device) else { return }
        scanGeneration += 1
        let generation: Int = scanGeneration
        let listener = ScanListener { [weak self] candidate in
            MainHop.post {
                self?.probed(candidate, generation: generation)
            }
        }
        scanListener = listener
        scanInFlight = true
        scanState = ScanState(isScanning: true, status: SettingsTools.scanning)
        let models: [HamlibRigModel] = rigModels
        let device: String = draft.device
        let model: Int = draft.rigModel
        let label: String = draft.rigModelLabel
        let port: any RigScanPort = ports.rigScan
        track { [weak self] in
            await port.disconnectCat(reason: "scan")
            let outcome: RigScanner.Outcome? = await OwnThread.run("rig-scan") {
                let candidates: [RigScanner.Candidate] = RigScanner.buildCandidates(
                    selectedModel: model, selectedLabel: label, all: models, bauds: SettingsTools.scanBauds)
                return port.scan(device: device, candidates: candidates, listener: listener)
            }
            self?.scanInFlight = false
            self?.scanFinished(outcome, listener: listener, generation: generation)
        }
    }

    /// „Zastavit" (`HW:320`): the scan stops before the next candidate (the one being probed may still answer).
    public func stopScan() {
        scanListener?.cancel()
    }

    private func probed(_ candidate: RigScanner.Candidate, generation: Int) {
        guard generation == scanGeneration, scanState.isScanning else { return }
        scanState.status = language.tr(SettingsTools.probing, .string(candidate.label),
                                       .string(String(candidate.baud)))
    }

    private func scanFinished(_ outcome: RigScanner.Outcome?, listener: ScanListener, generation: Int) {
        guard generation == scanGeneration else { return }
        scanListener = nil
        if let outcome {
            if var draft = settings.draft {
                draft.rigModel = outcome.candidate.model
                draft.rigModelLabel = outcome.candidate.label
                draft.baud = outcome.candidate.baud
                settings.draft = draft
            }
            scanState = ScanState(isScanning: false, status: SettingsTools.found(outcome))
        } else {
            let text: String = listener.isCancelled() ? SettingsTools.scanStopped : SettingsTools.nothingAnswered
            scanState = ScanState(isScanning: false, status: text)
        }
    }

    // MARK: - sound devices (VK:36-46)

    /// The output choices: `tr("Výchozí systémové")`, then the devices without Java's pseudo-mixer.
    public var outputDevices: [String] {
        [language.tr(SettingsTools.systemDefaultDevice)] + outputDeviceNames
    }

    /// The input choices (as `outputDevices`).
    public var inputDevices: [String] {
        [language.tr(SettingsTools.systemDefaultDevice)] + inputDeviceNames
    }

    /// The Audio tab opened: the devices are listed once, off the main thread.
    public func loadAudioDevices() {
        let generation: Int = windowGeneration
        let devices: any DevicePort = ports.devices
        track { [weak self] in
            let lists: [[String]] = await OwnThread.run("audio-devices") {
                [devices.outputDevices(), devices.inputDevices()]
            }
            guard let self, generation == self.windowGeneration else { return }
            self.outputDeviceNames = SettingsTools.deviceChoices(lists[0])
            self.inputDeviceNames = SettingsTools.deviceChoices(lists[1])
        }
    }

    // MARK: - fldigi (MT:86-97)

    /// One probe: `FldigiClient(host.trim(), port.toIntOrNull() ?: 7362)`, `version()` and `modemName()` off the main
    /// thread; `"fldigi <version>, modem <modem>"`, or `tr("nedostupné: %s", message)`. Kotlin builds the client on
    /// the UI thread, where an illegal host throws out of the click; here it is reported like any other failure.
    public func fldigiProbe(host: String, port: String) async -> String {
        let trimmed: String = KotlinStrings.trim(host)
        let number: Int = SettingsTools.fldigiPort(port)
        let probe: any FldigiProbePort = ports.fldigi
        let result: Result<FldigiAnswer, any Error> = await OwnThread.run("fldigi-probe") {
            Result {
                let answer = try probe.probe(host: trimmed, port: number)
                return FldigiAnswer(version: answer.version, modem: answer.modem)
            }
        }
        switch result {
        case .success(let answer):
            return SettingsTools.fldigiAnswer(version: answer.version, modem: answer.modem)
        case .failure(let error):
            return language.tr(SettingsTools.fldigiUnavailable, .string(SettingsTools.fldigiErrorMessage(error)))
        }
    }

    /// „Vyzkoušet": `tr("zkouším…")`, then the answer. A later click wins (an older answer arriving after it is
    /// dropped).
    public func probeFldigi(host: String, port: String) {
        fldigiGeneration += 1
        let generation: Int = fldigiGeneration
        fldigiProbeText = language.tr(SettingsTools.fldigiProbing)
        track { [weak self] in
            guard let self else { return }
            let text: String = await self.fldigiProbe(host: host, port: port)
            guard generation == self.fldigiGeneration else { return }
            self.fldigiProbeText = text
        }
    }

    // MARK: - counts (CT:28-191)

    /// The contest tab shows the draft: the YAML definitions and sets of `contestDataDir`, the calls of `master.scp`
    /// and of the call history. The first request of an opened window counts at once; a change counts 300 ms after
    /// the last change of its field, and a result for an older text is dropped.
    public func updateCounts(_ draft: ConfigurerDraft) {
        request(.contestData, draft.contestDataDir)
        request(.scp, draft.scpFile)
        request(.callHistory, draft.callHistoryFile)
    }

    private func request(_ group: CountGroup, _ input: String) {
        let slot: CountSlot = slot(group)
        guard slot.input != input else { return }
        let first: Bool = slot.input == nil
        slot.input = input
        slot.timer?.cancel()
        slot.timer = nil
        slot.generation += 1
        let generation: Int = slot.generation
        if first {
            runCount(group, input, generation)
        } else {
            slot.timer = countsClock.schedule(afterMilliseconds: 300) { [weak self] in
                self?.runCount(group, input, generation)
            }
        }
    }

    private func runCount(_ group: CountGroup, _ input: String, _ generation: Int) {
        guard slot(group).generation == generation else { return }
        let counter: @Sendable (CountGroup, String) -> [Int] = self.counter
        track { [weak self] in
            let values: [Int] = (try? await BlockingQueue.run { counter(group, input) }) ?? []
            guard let self, self.slot(group).generation == generation else { return }
            self.apply(group, values)
        }
    }

    private func apply(_ group: CountGroup, _ values: [Int]) {
        switch group {
        case .contestData:
            contestYamlCount = values.first ?? 0
            multiplierYamlCount = values.count > 1 ? values[1] : 0
        case .scp:
            scpCount = values.first ?? 0
        case .callHistory:
            callHistoryCount = values.first ?? 0
        }
    }

    private func slot(_ group: CountGroup) -> CountSlot {
        if let existing = countSlots[group] {
            return existing
        }
        let created = CountSlot()
        countSlots[group] = created
        return created
    }

    nonisolated static func count(_ group: CountGroup, _ input: String) -> [Int] {
        switch group {
        case .contestData:
            return [SettingsTools.contestYamlCount(contestDataDir: input),
                    SettingsTools.multiplierYamlCount(contestDataDir: input)]
        case .scp:
            return [SettingsTools.scpCount(input)]
        case .callHistory:
            return [SettingsTools.callHistoryCount(input)]
        }
    }

    // MARK: - languages (MT:127-160)

    /// The Other tab opened (`remember { I18n.available() }`).
    public func loadLanguages() {
        let generation: Int = windowGeneration
        track { [weak self] in
            guard let self else { return }
            let listed: [LanguageCatalog.Language] = await self.language.available()
            guard generation == self.windowGeneration else { return }
            self.languages = listed
        }
    }

    /// „Načíst znovu": `LanguageCatalog.ensureDir` (the shipped languages come back), then the list again.
    public func reloadLanguages() {
        let generation: Int = windowGeneration
        let dir: URL = language.languageDir
        track { [weak self] in
            _ = try? await BlockingQueue.run {
                LanguageCatalog.ensureDir(dir)
            }
            guard let self else { return }
            let listed: [LanguageCatalog.Language] = await self.language.available()
            guard generation == self.windowGeneration else { return }
            self.languages = listed
        }
    }

    // MARK: - menu file (MT:192-258)

    /// The Other tab opened: which definition applies.
    public func refreshMenuFile() {
        track { [weak self] in
            await self?.readMenuFile()
        }
    }

    /// „Vytvořit menu.json k úpravám": the built-in definition is written into the data directory; an existing file
    /// is never overwritten.
    public func createMenuFile() {
        let dir: URL = dataDir
        track { [weak self] in
            let written: MenuWrite = (try? await BlockingQueue.run { Self.writeMenu(dir) })
                ?? MenuWrite(path: nil, existed: false, failure: nil, failed: false)
            guard let self else { return }
            self.menuMessage = self.menuWriteText(written)
            await self.readMenuFile()
        }
    }

    /// „Načíst menu znovu" (`MT:244-249` + `AS:2669-2677`): the menu is read again and the status says which one
    /// applies (a broken file is reported by the menu itself), then the group's state and „Menu načteno znovu.".
    public func reloadMenu() {
        track { [weak self] in
            guard let self else { return }
            await self.menu.reload()
            switch self.menu.source {
            case .user:
                self.status.show(SettingsTools.menuStatusUser)
            case .builtIn:
                self.status.show(SettingsTools.menuStatusBuiltIn)
            case .userInvalid:
                break
            }
            await self.readMenuFile()
            self.menuMessage = self.language.tr(SettingsTools.menuReloaded)
        }
    }

    private func readMenuFile() async {
        let dir: URL = dataDir
        let state: MenuFileState? = try? await BlockingQueue.run {
            let loaded: MenuConfigStore.LoadResult = MenuConfigStore.loadFrom(dataDir: dir)
            return MenuFileState(file: MenuConfigStore.userFile(dataDir: dir).path, source: loaded.source,
                                 error: loaded.error)
        }
        if let state {
            menuFileState = state
        }
    }

    struct MenuWrite: Sendable {
        let path: String?
        let existed: Bool
        let failure: String?
        let failed: Bool
    }

    /// `MT:225-237`: `Files.exists(file)` before the write decides between „already there" and „no directory".
    nonisolated static func writeMenu(_ dir: URL) -> MenuWrite {
        let file: URL = MenuConfigStore.userFile(dataDir: dir)
        let existed: Bool = FileManager.default.fileExists(atPath: file.path)
        do {
            let written: URL? = try MenuConfigStore.writeBuiltIn(dataDir: dir, overwrite: false)
            return MenuWrite(path: written?.path, existed: existed, failure: nil, failed: false)
        } catch {
            return MenuWrite(path: nil, existed: existed, failure: menuWriteMessage(error, dir: dir), failed: true)
        }
    }

    /// Java's message: `Files.createDirectories` over a data directory that is a regular file throws
    /// `FileAlreadyExistsException(<dir>)` (probe row `menu fail`); anything else as `JavaThrowables`.
    nonisolated static func menuWriteMessage(_ error: any Error, dir: URL) -> String? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return dir.path
        }
        return JavaThrowables.describe(error).message
    }

    private func menuWriteText(_ written: MenuWrite) -> String {
        if written.failed {
            return language.tr(SettingsTools.menuWriteFailed, .string(written.failure))
        }
        if let path = written.path {
            return language.tr(SettingsTools.menuCreated, .string(path))
        }
        if written.existed {
            return language.tr(SettingsTools.menuExists)
        }
        return language.tr(SettingsTools.menuNoDataDir)
    }

    // MARK: - lifecycle

    /// The window closed: a scan is cancelled, pending counts and late answers are dropped, the per-window lists and
    /// texts are cleared (Kotlin's tab state lives in the composition).
    public func windowClosed() {
        closeRigSheet()
        windowGeneration += 1
        fldigiGeneration += 1
        fldigiProbeText = ""
        for slot in countSlots.values {
            slot.timer?.cancel()
            slot.generation += 1
        }
        countSlots = [:]
        scpCount = nil
        callHistoryCount = nil
        contestYamlCount = nil
        multiplierYamlCount = nil
        menuMessage = ""
    }

    /// Waits for the work in flight (tests).
    func settle() async {
        while let (id, task) = tasks.first {
            await task.value
            tasks[id] = nil
        }
    }

    private func track(_ body: @escaping @MainActor () async -> Void) {
        nextTaskId += 1
        let id: Int = nextTaskId
        tasks[id] = Task { [weak self] in
            await body()
            self?.tasks[id] = nil
        }
    }
}

/// One debounced count: the input asked for, the pending timer and the generation of the latest request.
@MainActor
final class CountSlot {
    var input: String?
    var timer: (any RescoreTimer)?
    var generation: Int = 0
}

/// The fldigi answer handed back from the probe thread.
struct FldigiAnswer: Sendable {
    let version: String
    let modem: String
}

/// The scan's `RigScanner.Listener`: probes hop to the main actor asynchronously, the cancel flag is shared with the
/// scan thread (Kotlin `AtomicBoolean`).
final class ScanListener: RigScanner.Listener, Sendable {
    private let cancelled = OSAllocatedUnfairLock(initialState: false)
    private let onProbed: @Sendable (RigScanner.Candidate) -> Void

    init(onProbed: @escaping @Sendable (RigScanner.Candidate) -> Void) {
        self.onProbed = onProbed
    }

    func onProbe(_ candidate: RigScanner.Candidate) {
        onProbed(candidate)
    }

    func isCancelled() -> Bool {
        cancelled.withLock { $0 }
    }

    func cancel() {
        cancelled.withLock { $0 = true }
    }
}
