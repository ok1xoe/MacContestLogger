import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

// MARK: - fakes

/// A keyer that records what it is handed (nothing is transmitted).
final class RecordingKeyer: KeyerPort, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [FunctionKeyTransmission] = []
    private var stops: Int = 0

    var transmissions: [FunctionKeyTransmission] {
        lock.withLock { sent }
    }

    var stopCount: Int {
        lock.withLock { stops }
    }

    /// The F-keys of the transmissions (CW index = the last key; voice = all keys).
    var keys: [[Int]] {
        transmissions.map { transmission in
            switch transmission {
            case .voice(let indices, _, _, _): return indices
            case .cw(_, let index): return [index]
            case .digital(_, let index): return [index]
            }
        }
    }

    var canSend: Bool { false }
    var isSending: Bool { false }

    func send(_ transmission: FunctionKeyTransmission, settings: KeyerSettings) -> EntryStatus? {
        lock.withLock { sent.append(transmission) }
        return nil
    }

    func stopSending() -> Bool {
        lock.withLock { stops += 1 }
        return false
    }

    func toggleRecording(_ key: Int) -> EntryStatus? {
        nil
    }
}

/// A rig that records the rig half of the actions.
final class RecordingRig: RigPort, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    var log: [String] {
        lock.withLock { calls }
    }

    func qsy(hz: Int64) {
        lock.withLock { calls.append("qsy \(hz)") }
    }

    func setMode(_ mode: Mode, freqHz: Int64) {
        lock.withLock { calls.append("mode \(mode.rawValue) \(freqHz)") }
    }

    func clearRit() -> EntryStatus? {
        lock.withLock { calls.append("clearRit") }
        return nil
    }

    func splitOff() -> EntryStatus? {
        lock.withLock { calls.append("splitOff") }
        return nil
    }
}

/// Counts the dupe beeps.
@MainActor final class BeepCounter {
    var count = 0
}

/// An app over a temporary data directory with fake ports and a contest-data copy that adds a QSO party with a
/// county line (`ROVER_QTH`) checked against the OK/OM districts.
@MainActor
struct PortedApp {
    let dir: TempDir
    let model: AppModel
    let rescoreClock: ManualClock
    let keyer: RecordingKeyer
    let rig: RecordingRig
    let beeps: BeepCounter

    var dataDir: URL { dir.child("data") }

    static let qsoParty = """
        schemaVersion: 1
        id: test-qp
        metadata: { name: "Test QSO Party" }
        bands: [80m, 40m, 20m]
        modes: [CW, SSB]
        exchange:
          sent:
            - { id: rst, type: RST,  source: AUTO_RST }
            - { id: qth, type: TEXT, source: ROVER_QTH }
          received:
            - { id: rst,  type: RST,  required: true }
            - { id: cnty, type: TEXT, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        multipliers:
          - { id: districts, set: ok_om_districts, from: cnty, scope: PER_BAND }
        dupe: { scope: PER_BAND_MODE }
        """

    static func make(fixedNow: Date? = nil, productionKeyer: Bool = false,
                     configure: (inout AppConfig) -> Void = { _ in }) async throws -> PortedApp {
        let dir = try TempDir()
        let dataDir: URL = dir.child("data")
        let fm = FileManager.default
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let contestData: URL = dir.child("contest-data")
        try fm.createDirectory(at: contestData.appendingPathComponent("contests"), withIntermediateDirectories: true)
        try fm.copyItem(at: Fixtures.contestData.appendingPathComponent("multipliers"),
                        to: contestData.appendingPathComponent("multipliers"))
        try fm.copyItem(at: Fixtures.contestData.appendingPathComponent("contests/cq-ww-cw.yaml"),
                        to: contestData.appendingPathComponent("contests/cq-ww-cw.yaml"))
        try qsoParty.write(to: contestData.appendingPathComponent("contests/test-qp.yaml"), atomically: true,
                           encoding: .utf8)
        var config = AppConfig()
        config.contestDataDir = contestData.path
        config.station.call = "OK1XOE"
        configure(&config)
        try ConfigWriter.writeFile(config, to: dataDir.appendingPathComponent("config.json"))
        let rescore = ManualClock()
        let keyer = RecordingKeyer()
        let rig = RecordingRig()
        let beeps = BeepCounter()
        let clock: @Sendable () -> Date
        if let fixedNow {
            clock = { fixedNow }
        } else {
            clock = { Date() }
        }
        let environment = AppModel.Environment(
            dataDir: dataDir, dxccDir: try Fixtures.dxccDir(in: dir), decimalSeparator: ",",
            rescoreClock: rescore, geometryClock: ManualClock(), now: clock, appVersion: "1.2.3",
            ports: EntryPorts(keyer: productionKeyer ? NoKeyer() : keyer, rig: rig, beep: { beeps.count += 1 }),
            backupClock: ManualClock())
        let model = try await AppModel.bootstrap(environment)
        return PortedApp(dir: dir, model: model, rescoreClock: rescore, keyer: keyer, rig: rig, beeps: beeps)
    }

    var entry: EntryModel { model.entry }
    var status: String { model.status.message }

    func start(_ id: String, sent: [String: String] = [:]) async throws {
        var setup = ContestSetup()
        setup.sentExchange = sent
        let started: Bool = await model.contest.createAndStart(definitionId: id, setup: setup)
        try #require(started, "activation failed: \(model.status.message)")
    }

    func startCqWw() async throws {
        try await start("cq-ww-cw", sent: ["zone": "15"])
    }

    /// Types a command (or a call) into the call field and presses Enter; waits for everything it started.
    func enter(_ text: String, ctrl: Bool = false) async {
        entry.callChanged(text)
        entry.handle(.enter(ctrl: ctrl, step: .logQso(ctrlEnter: ctrl)))
        await settle()
    }

    func settle() async {
        await entry.settle()
        await model.logbook.settle()
        await model.logbook.settleMutations()
        await entry.settle()
    }

    func type(call: String, zone: String, freqKHz: String = "14025") {
        entry.setFrequency(freqKHz)
        entry.callChanged(call)
        entry.editContestField("zone", zone)
    }

    func log(call: String, zone: String, freqKHz: String = "14025") async {
        type(call: call, zone: zone, freqKHz: freqKHz)
        entry.submit()
        await settle()
    }
}

// MARK: - commands

/// Call-field commands executed through `EntryCommandPlan` (`EP:368-457`): every local command kind at least once;
/// a command is never logged.
@MainActor @Suite struct EntryCommandTests {

    @Test func qsyFillsTheFieldTellsTheRigAndIsNotLogged() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        app.entry.setFrequency("7025")
        let focus: Int = app.entry.focusRequest
        await app.enter("14030")
        #expect(app.entry.form.freqKHz == "14030.00")
        #expect(app.entry.form.call == "")
        #expect(app.status == "QSY na 14030.00 kHz")
        #expect(app.rig.log == ["qsy 14030000"])
        #expect(app.entry.focusRequest > focus)
        #expect(app.model.logbook.rows.isEmpty)
    }

    @Test func overflowAndInvalidShowTheirTextAndAreNotLogged() async throws {
        let app = try await PortedApp.make()
        await app.enter("99999999999999999")
        #expect(app.status == "99999999999999999 kHz neleží v žádném pásmu")
        await app.enter("SCRIPT")
        #expect(app.status == "SCRIPT: zadej jméno skriptu (soubor scripts/<jméno>.txt)")
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.rig.log.isEmpty)
    }

    @Test func modeCommandOutsideAndInsideALockedContest() async throws {
        let app = try await PortedApp.make()
        app.entry.setFrequency("14025")
        await app.enter("CW")
        #expect(app.entry.form.mode == .cw)
        #expect(app.entry.form.rstSent == "599")
        #expect(app.status == "Mód CW")
        #expect(app.rig.log == ["mode CW 14025000"])
        try await app.startCqWw()
        await app.enter("SSB")
        #expect(app.entry.form.mode == .cw)
        #expect(app.status == "Mód určuje závod (CW)")
    }

    @Test func operatorLoginLogoutAndTheDialog() async throws {
        let app = try await PortedApp.make()
        await app.enter("OPON ok1abc")
        #expect(app.model.operating.operatorCall == "OK1ABC")
        #expect(app.status == "Operátor: OK1ABC")
        await app.enter("LOGOUT")
        #expect(app.model.operating.operatorCall == "OK1XOE")
        await app.enter("OPON")
        #expect(app.model.dialogs.showOperator)
        app.model.dialogs.confirmOperator(call: " ok2x ", persist: true)
        #expect(!app.model.dialogs.showOperator)
        #expect(app.model.operating.operatorCall == "OK2X")
        #expect(app.status == "Operátor: OK2X (uloženo do nastavení stanice)")
        await app.model.config.flush()
        let saved = ConfigStore(file: app.dataDir.appendingPathComponent("config.json")).load()
        #expect(saved.station.operator == "OK2X")
    }

    @Test func versionEsmAutoRunToggleAndCutCommands() async throws {
        let app = try await PortedApp.make()
        await app.enter("VER")
        #expect(app.status.hasPrefix("MacContestLogger 1.2.3 · Swift "))
        await app.enter("ESM")
        #expect(app.model.operating.esmEnabled)
        #expect(app.status == "ESM zapnuto — Enter vysílá zprávy")
        await app.enter("NOESM")
        #expect(!app.model.operating.esmEnabled)
        await app.enter("NOAUTRSP")
        #expect(!app.model.operating.autoRunSwitch)
        #expect(app.status == "Automatické přepínání Run/S&P vypnuto (Alt+F11 zapne)")
        await app.enter("RPT")
        #expect(app.model.operating.cqRepeat)
        #expect(app.status == "Opakování CQ po 2.0 s (Esc nebo psaní volačky zastaví, Ctrl+R změní)")
        await app.enter("POSTCONTEST")
        #expect(app.model.operating.postContest)
        #expect(!app.model.operating.cqRepeat)
        await app.enter("NOPOSTCONTEST")
        #expect(!app.model.operating.postContest)
        await app.enter("NOWORKDUPE")
        #expect(app.status == "Dupe v Run: QSO B4 (NOWORKDUPE)")
        await app.enter("AUTORELOAD")
        #expect(app.status == "Při startu se otevře poslední závod (AUTORELOAD)")
        await app.enter("FULLABBREV")
        await app.model.config.flush()
        let saved = ConfigStore(file: app.dataDir.appendingPathComponent("config.json")).load()
        #expect(saved.esm.enabled == false)
        #expect(saved.esm.workDupes == false)
        #expect(saved.autoReloadLastContest)
        #expect(saved.runMode.autoSwitch == false)
        #expect(saved.cwKeyer.cutNumbers)
        #expect(saved.cwKeyer.cutStyle == .tauedn)
        #expect(app.model.logbook.rows.isEmpty)
    }

    @Test func menuCommandsBecomePendingMenuActionsOrUnavailable() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.enter("EXPORT")
        #expect(app.model.menu.pendingMenuAction == "settings.export")
        #expect(MenuActions.performPending(app: app.model) == .saveAdif(suggestedName: ExportNames.adifDefaultName))
        #expect(app.model.menu.pendingMenuAction == nil)
        await app.enter("WRITELOG")
        #expect(app.model.menu.pendingMenuAction == "settings.exportCabrillo")
        _ = MenuActions.performPending(app: app.model)
        await app.enter("IMPORT")
        #expect(app.model.menu.pendingMenuAction == "settings.import")
        #expect(MenuActions.performPending(app: app.model) == .openImport)
        #expect(app.model.menu.pendingMenuAction == nil)
        await app.enter("SETUP")
        #expect(app.model.menu.pendingMenuAction == "settings.open")
        #expect(app.model.menu.pendingSettingsTab == nil)
        _ = MenuActions.performPending(app: app.model)
        #expect(app.model.settings.isOpen)
        await app.enter("MSGS")
        #expect(app.model.menu.pendingMenuAction == "settings.open")
        #expect(app.model.menu.pendingSettingsTab == "function-keys")
        _ = MenuActions.performPending(app: app.model)
        #expect(app.model.settings.selected == .functionKeys)
        app.model.settings.cancel()
        await app.model.settings.settle()
        await app.enter("CLOSE")
        _ = MenuActions.performPending(app: app.model)
        #expect(!app.model.contest.isActive)
        await app.model.contest.settleActivations()
        await app.enter("NEW")
        #expect(app.model.dialogs.isOpen(.newContest))
        await app.enter("OPEN")
        #expect(app.model.dialogs.isOpen(.contests))
    }

    /// BCLOG: without a broadcast it says so and logs nothing; the call field is cleared.
    @Test func bclogWithoutABroadcastSaysSoAndNeverLogs() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        app.model.status.clear()
        app.entry.editContestField("zone", "14")
        await app.enter("BCLOG")
        #expect(app.status == "BCLOG: UDP broadcast je vypnutý (Nastavení → Broadcast Data)")
        #expect(app.entry.form.call == "")
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.rig.log.isEmpty)
    }

    @Test func rescoreReopenAndExitCommands() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        await app.enter("RESCORE")
        await app.model.contest.settleRescore()
        #expect(app.status.contains("1"))
        await app.enter("REOPEN")
        await app.model.contest.settleRescore()
        #expect(app.model.logbook.rows.count == 1)
        await app.enter("BYE")
        #expect(app.model.dialogs.confirmation == .exit)
        let before: Int = app.model.dialogs.quitRequest
        app.model.dialogs.confirm()
        #expect(app.model.dialogs.quitRequest == before + 1)
        await app.enter("EXITNOW")
        #expect(app.model.dialogs.quitRequest == before + 2)
    }

    @Test func tourCommandsSaveTheSetupBeforeTheirStatus() async throws {
        let app = try await PortedApp.make()
        await app.enter("TOUR 1200/30")
        #expect(app.status == "Není aktivní závod")
        try await app.startCqWw()
        await app.enter("TOUR 1200/30")
        #expect(app.status == "TOUR 1200/30: sezení po 30 min od 1200Z — v každém sezení jde stanice pracovat znovu")
        #expect(app.model.contest.tour?.format() == "1200/30")
        #expect(app.model.contest.activeSetup?.tour == "1200/30")
        await app.enter("TOUR 12")
        #expect(app.status.hasPrefix("TOUR: neplatné „12“"))
        await app.enter("NOTOUR")
        #expect(app.status == "TOUR vypnuto — dupe za celý závod")
        #expect(app.model.contest.tour == nil)
        #expect(app.model.contest.activeSetup?.tour == Tour.off)
        await app.enter("BONUS w1aw, k1abc")
        #expect(app.status == "Bonusové stanice (2): W1AW K1ABC")
        #expect(app.model.contest.bonusStations == ["W1AW", "K1ABC"])
        await app.enter("BONUS")
        let prompt = try #require(app.model.dialogs.textPrompt)
        #expect(prompt.initial == "W1AW, K1ABC")
        app.model.dialogs.submitPrompt("")
        await app.settle()
        #expect(app.status == "Bonusové stanice smazány")
        #expect(app.model.contest.bonusStations.isEmpty)
    }

    @Test func roverQthAndCountyLineCheckTheDistricts() async throws {
        let app = try await PortedApp.make()
        try await app.start("test-qp")
        await app.enter("ROVERQTH apa")
        #expect(app.status == "Rover QTH: APA")
        await app.enter("ROVERQTH XYZ")
        #expect(app.status == "Rover QTH: XYZ — pozor: XYZ není v seznamu okresů závodu")
        await app.enter("COUNTYLINE apa abk xyz")
        #expect(app.entry.countyLine == ["APA", "ABK", "XYZ"])
        #expect(app.status == "County line APA/ABK/XYZ: každé QSO se zapíše 3× — pozor, není v seznamu okresů: XYZ")
        await app.enter("NOCOUNTYLINE")
        #expect(app.entry.countyLine.isEmpty)
        #expect(app.status == "County line vypnuto")
        await app.enter("COUNTYLINE")
        app.model.dialogs.submitPrompt("APA/ABK")
        #expect(app.entry.countyLine == ["APA", "ABK"])
        await app.enter("ROVERQTH")
        #expect(app.model.dialogs.textPrompt?.initial == "XYZ")
        app.model.dialogs.cancelPrompt()
        await app.model.config.flush()
        #expect(ConfigStore(file: app.dataDir.appendingPathComponent("config.json")).load().station.roverQth == "XYZ")
    }

    @Test func scriptRunsItsLinesOffTheMainThread() async throws {
        let app = try await PortedApp.make()
        let scripts: URL = app.dataDir.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "CW\n14030\nSCRIPT other\nHELLO\n".write(to: scripts.appendingPathComponent("setup.txt"), atomically: true,
                                                     encoding: .utf8)
        await app.enter("SCRIPT setup")
        #expect(app.entry.form.mode == .cw)
        #expect(app.entry.form.freqKHz == "14030.00")
        // The parser upper-cases the name (Kotlin `uppercase()`).
        #expect(app.status == "SCRIPT SETUP: provedeno 4 příkazů")
        #expect(app.rig.log == ["mode CW 0", "qsy 14030000"])
        await app.enter("SCRIPT missing")
        #expect(app.status.hasPrefix("SCRIPT: skript „MISSING“ není v "))
    }

    @Test func copyLogBacksUpNextToTheDatabase() async throws {
        let app = try await PortedApp.make(fixedNow: Date(timeIntervalSince1970: 1_790_000_000))
        await app.enter("COPYLOG")
        let url: URL = app.model.database.handle.url
        let name: String = EntryTexts.copyLogFileName(url.lastPathComponent, at: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(app.status == "COPYLOG: záloha " + name)
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(name).path))
    }

    /// COPYLOG goes through a temporary file renamed into place: a stale temporary file of the same name does not
    /// stop it, and none is left; an existing backup of the same name is refused and keeps its bytes.
    @Test func copyLogIsWrittenAtomically() async throws {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let app = try await PortedApp.make(fixedNow: at)
        let url: URL = app.model.database.handle.url
        let dir: URL = url.deletingLastPathComponent()
        let name: String = EntryTexts.copyLogFileName(url.lastPathComponent, at: at)
        let target: URL = dir.appendingPathComponent(name)
        let stale: URL = DatabaseModel.partialName(target)
        try Data("half".utf8).write(to: stale)

        await app.enter("COPYLOG")

        #expect(app.status == "COPYLOG: záloha " + name)
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(!FileManager.default.fileExists(atPath: stale.path))

        // The second one in the same second: refused, the first stays.
        let before: Data = try Data(contentsOf: target)
        await app.enter("COPYLOG")
        #expect(app.status.hasPrefix("COPYLOG: "))
        #expect(!app.status.hasPrefix("COPYLOG: záloha"))
        #expect(try Data(contentsOf: target) == before)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func reloadReopensTheActiveContest() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        let id: String? = app.model.contest.activeId
        await app.enter("RELOAD")
        #expect(app.model.contest.activeId == id)
        #expect(app.status == "Definice závodů znovu načteny a závod otevřen")
    }
}

// MARK: - WIPELOG, delete last, edits

@MainActor @Suite struct LogEditingTests {

    @Test func wipeLogAsksThenDeletesAndTheNextSerialIsOneAgain() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        // A gap: the first insert fails, so serial 1 stays a gap and the next QSOs get 2 and 3.
        try await app.model.database.handle.run { access in
            try access.repository.connection.execute("""
                CREATE TEMP TRIGGER fail_one BEFORE INSERT ON qso WHEN NEW.call = 'GAP'
                BEGIN SELECT RAISE(ABORT, 'disk full'); END
                """)
        }
        app.type(call: "GAP", zone: "14")
        app.entry.submit()
        app.type(call: "DL1ABC", zone: "14")
        app.entry.submit()
        await app.settle()
        app.entry.wipe()
        await app.log(call: "W1AW", zone: "5")
        #expect(app.model.logbook.rows.map(\.serialSent) == [2, 3])
        await app.enter("WIPELOG")
        #expect(app.model.dialogs.confirmation == .wipeLog)
        #expect(app.model.dialogs.confirmationTitle == ContestMessage("Vymazat celý deník (%s QSO)?", .int(2)))
        #expect(app.model.dialogs.confirmationButton == .verbatim("Vymazat"))
        #expect(app.model.logbook.rows.count == 2)
        app.model.dialogs.confirm()
        await app.settle()
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.model.logbook.qsoCount == 0)
        #expect(app.status == "Deník vymazán (2 QSO)")
        #expect(app.model.logbook.nextSerial == 1)
        app.rescoreClock.advance(by: 300)
        await app.model.contest.settleRescore()
        #expect(app.model.contest.score?.qsoCount == 0)
        await app.log(call: "OK1AA", zone: "15")
        #expect(app.model.logbook.rows.map(\.serialSent) == [1])
    }

    /// A submission reserved after WIPELOG settled the submissions but before the wipe job ends (a fake handle
    /// queue holds the job back). The submission keeps its reservation and is stored after the wipe. No serial is
    /// handed out twice, the next serial is at least 1 and the reservations never go negative.
    @Test func submitInsideTheWipeWindowNeverRepeatsASerial() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        #expect(app.model.logbook.rows.map(\.serialSent) == [1])

        // The handle's serial queue is held by a job of the test, so the wipe job waits behind it.
        let gate = DispatchSemaphore(value: 0)
        let held = FlagBox()
        let handle: LogbookHandle = app.model.database.handle
        let blocker = Task {
            try await handle.run { _ in
                held.set()
                gate.wait()
            }
        }
        while !held.isSet { await Task.yield() }

        // The wipe has passed its settle of the submissions in flight (nothing is pending) and queued its job.
        let settled = FlagBox()
        let original = app.model.logbook.settleInserts
        app.model.logbook.settleInserts = {
            await original?()
            settled.set()
        }
        let wipe = Task { await app.model.logbook.wipeLog() }
        while !settled.isSet { await Task.yield() }

        // The submission reserves its serial inside the window; its insert queues behind the wipe job.
        app.type(call: "W1AW", zone: "5")
        app.entry.submit()
        #expect(app.model.logbook.reservedSerials >= 1)
        gate.signal()
        try await blocker.value
        await wipe.value
        await app.settle()

        let serials: [Int] = app.model.logbook.rows.map { $0.serialSent ?? 0 }
        #expect(Set(serials).count == serials.count)
        #expect(app.model.logbook.reservedSerials >= 0)
        #expect(app.model.logbook.nextSerial >= 1)
        #expect(!serials.contains(app.model.logbook.nextSerial))
        await app.log(call: "OK1AA", zone: "15")
        let after: [Int] = app.model.logbook.rows.map { $0.serialSent ?? 0 }
        #expect(Set(after).count == after.count)
        #expect(app.model.logbook.reservedSerials == 0)
    }

    @Test func clearLogNowWipesWithoutAsking() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        await app.enter("CLEARLOGNOW")
        #expect(app.model.dialogs.confirmation == nil)
        #expect(app.model.logbook.rows.isEmpty)
        #expect(app.status == "Deník vymazán (1 QSO)")
    }

    @Test func deleteLastTakesTheQsoJustLogged() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        // Ctrl+D right after Enter: the submission is still in flight when the dialog is confirmed.
        app.type(call: "W1AW", zone: "5")
        app.entry.submit()
        app.entry.runShortcut(.deleteLast)
        #expect(app.model.dialogs.confirmation == .deleteLast)
        app.model.dialogs.confirm()
        await app.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.status == "Smazáno poslední QSO W1AW")
        #expect(!app.model.logbook.isDupe(call: "W1AW", band: .m20))
        app.entry.runShortcut(.deleteLast)
        app.model.dialogs.confirm()
        await app.settle()
        #expect(app.model.logbook.rows.isEmpty)
        app.entry.runShortcut(.deleteLast)
        #expect(app.model.dialogs.confirmationTitle == ContestMessage("Deník je prázdný"))
        #expect(!app.model.dialogs.confirmationEnabled)
        app.model.dialogs.confirm()
        #expect(app.model.dialogs.confirmation == .deleteLast)
        app.model.dialogs.cancelConfirmation()
    }

    @Test func editRescoresAndRecomputesTheMarks() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        await app.log(call: "DL2ABC", zone: "14")
        app.rescoreClock.advance(by: 300)
        await app.model.contest.settleRescore()
        let before: Int64? = app.model.contest.score?.total
        let row: Qso = try #require(app.model.logbook.rows.last)
        let edited: Qso = LogTableEdit.apply(column: .exchange, text: "599 5", to: row)
        let written: Qso? = await app.model.logbook.update(LogbookMutations.Edit(old: row, new: edited))
        #expect(written?.exchangeRcvd == "599 5")
        #expect(app.model.logbook.rows.last?.exchangeRcvd == "599 5")
        await app.model.logbook.settle()
        app.rescoreClock.advance(by: 300)
        await app.model.contest.settleRescore()
        #expect(app.model.contest.score?.total != before)
        let fresh = try #require(app.model.contest.runtime.freshSession())
        #expect(app.model.logbook.marks == QsoMarks.compute(fresh, app.model.logbook.rows))
    }

    /// Important 1: after TOUR the marks are rebuilt over a session with the tour, so the next append is marked as
    /// a full recompute would: a repeat in a new session is not a dupe (a stale tracker would mark it).
    @Test func marksFollowTheSetupExtrasOnTheNextAppend() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.enter("POSTCONTEST")
        app.entry.paperTime = "2026-11-28 1205"
        await app.log(call: "DL1ABC", zone: "14")
        await app.enter("TOUR 1200/30")
        #expect(app.model.contest.tour?.format() == "1200/30")
        await app.model.logbook.settle()
        app.entry.paperTime = "1240"
        await app.log(call: "DL1ABC", zone: "14")
        await app.model.logbook.settle()
        let rows: [Qso] = app.model.logbook.rows
        #expect(rows.count == 2)
        let fresh = try #require(app.model.contest.runtime.freshSession())
        let expected = QsoMarks.compute(fresh, rows)
        #expect(app.model.logbook.marks == expected)
        let second: Int64 = try #require(rows.last?.id)
        #expect(expected[second]?.dupe == false)
    }

    /// Minor 1: a QSO submitted right before the confirmed delete is taken into the snapshot inside the chain.
    @Test func deleteLastWaitsForAQueuedInsertInsideTheChain() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        let delete = Task { await app.model.logbook.deleteLast() }
        app.type(call: "W1AW", zone: "5")
        app.entry.submit()
        await delete.value
        await app.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.model.logbook.qsoCount == 1)
    }

    @Test func noteForTheLastQsoIsSavedAndPendingNoteGoesWithTheNext() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        app.entry.promptNote()
        #expect(app.status == "Ctrl+N: deník je prázdný")
        await app.log(call: "DL1ABC", zone: "14")
        app.entry.promptNote()
        app.model.dialogs.submitPrompt("good signal")
        await app.settle()
        #expect(app.status == "Poznámka uložena k DL1ABC")
        #expect(app.model.logbook.rows.last?.comment == "good signal")
        app.type(call: "W1AW", zone: "5")
        app.entry.promptNote()
        #expect(app.model.dialogs.textPrompt?.title == ContestMessage(EntryTexts.noteTitleCurrent))
        app.model.dialogs.submitPrompt("op Joe")
        #expect(app.entry.pendingNote == "op Joe")
        app.entry.submit()
        await app.settle()
        #expect(app.model.logbook.rows.last?.comment == "op Joe")
        #expect(app.entry.pendingNote == nil)
    }

    @Test func xqsoToggleAndBulkEdit() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        await app.log(call: "W1AW", zone: "5")
        let first: Qso = app.model.logbook.rows[0]
        await app.model.logbook.toggleXqso(first)
        #expect(app.model.logbook.rows[0].xqso)
        #expect(app.status == "DL1ABC: X-QSO, nepočítá se")
        let revision: Int64 = app.model.logbook.revision
        let outcome = BulkAction.xqso.run(text: nil, on: app.model.logbook.rows)
        await app.model.logbook.bulk(outcome)
        await app.model.logbook.settle()
        #expect(app.model.logbook.revision > revision)
        #expect(app.model.logbook.rows.map(\.xqso) == [true, true])
        #expect(app.status.hasPrefix("X-QSO"))
    }
}

// MARK: - logging paths

@MainActor @Suite struct EntryLoggingTests {

    @Test func countyLineLogsOneCopyPerCountyWithOneSerial() async throws {
        let app = try await PortedApp.make()
        try await app.start("test-qp")
        await app.enter("COUNTYLINE APA ABK APB")
        app.entry.setFrequency("14025")
        app.entry.setMode(.cw)
        app.entry.callChanged("K1ABC")
        app.entry.editContestField("cnty", "XX")
        app.entry.submit()
        await app.settle()
        let rows: [Qso] = app.model.logbook.rows
        #expect(rows.map(\.exchangeSent) == ["599 APA", "599 ABK", "599 APB"])
        #expect(rows.map(\.serialSent) == [1, 1, 1])
        #expect(app.model.logbook.nextSerial == 4)
    }

    @Test func failedSecondCountyLineCopyKeepsTheFormWipedAndTheSerialUsed() async throws {
        let app = try await PortedApp.make()
        try await app.start("test-qp")
        await app.enter("COUNTYLINE APA ABK APB")
        try await app.model.database.handle.run { access in
            try access.repository.connection.execute("""
                CREATE TEMP TRIGGER fail_abk BEFORE INSERT ON qso WHEN NEW.exchange_sent LIKE '%ABK%'
                BEGIN SELECT RAISE(ABORT, 'disk full'); END
                """)
        }
        app.entry.setFrequency("14025")
        app.entry.callChanged("K1ABC")
        app.entry.editContestField("cnty", "XX")
        app.entry.submit()
        await app.settle()
        #expect(app.model.logbook.rows.map(\.exchangeSent) == ["59 APA"])
        #expect(app.entry.form.call == "")
        #expect(app.status.hasPrefix("K1ABC: "))
        #expect(app.status.contains("disk full"))
        #expect(app.model.logbook.reservedSerials == 0)
        // Serial 1 went out with the stored APA copy: it is not given back.
        #expect(app.model.logbook.nextSerial == 2)
    }

    /// Minor 3: a failed first insert gives back the paper time and the unwipe memory with the form.
    @Test func failedPaperInsertRestoresThePaperTimeAndTheUnwipeMemory() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.enter("POSTCONTEST")
        app.type(call: "OK1AA", zone: "15")
        app.entry.runShortcut(.wipeUndo)
        #expect(app.entry.wipeMemory.lastWiped?.call == "OK1AA")
        try await app.model.database.handle.run { access in
            try access.repository.connection.execute(
                "CREATE TEMP TRIGGER fail_insert BEFORE INSERT ON qso BEGIN SELECT RAISE(ABORT, 'disk full'); END")
        }
        app.type(call: "DL1ABC", zone: "14")
        app.entry.paperTime = "2026-11-28 2355"
        app.entry.submit()
        #expect(app.entry.lastPaperTime != nil)
        await app.settle()
        #expect(app.entry.form.call == "DL1ABC")
        #expect(app.entry.lastPaperTime == nil)
        #expect(app.entry.wipeMemory.lastWiped?.call == "OK1AA")
    }

    @Test func forcedLogSkipsTheExchangeCheckWithANote() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        app.entry.setFrequency("14025")
        app.entry.callChanged("DL1ABC")
        app.entry.submit()
        await app.settle()
        #expect(app.model.logbook.rows.isEmpty)
        app.entry.runShortcut(.forceLog)
        #expect(app.model.dialogs.textPrompt?.title == ContestMessage(EntryTexts.forcedTitle, .string("DL1ABC")))
        app.model.dialogs.submitPrompt("  ")
        await app.settle()
        #expect(app.model.logbook.rows.map(\.comment) == ["Forced QSO"])
    }

    @Test func paperTimeIsRequiredInPostContestEntry() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.enter("POSTCONTEST")
        let timeFocus: Int = app.entry.timeFocusRequest
        app.type(call: "DL1ABC", zone: "14")
        app.entry.submit()
        #expect(app.status == "Dodatečné zadání: zadej čas QSO (HHmm, nebo 2026-11-28 1432)")
        #expect(app.entry.timeFocusRequest == timeFocus + 1)
        app.entry.paperTime = "2026-11-28 2355"
        app.entry.submit()
        app.type(call: "W1AW", zone: "5")
        app.entry.paperTime = "0005"
        app.entry.submit()
        await app.settle()
        let times: [Date?] = app.model.logbook.rows.map(\.timestampUtc)
        let expected = ISO8601DateFormatter().date(from: "2026-11-28T23:55:00Z")
        #expect(times.first == expected)
        #expect(times.last == expected.map { $0.addingTimeInterval(600) })
        #expect(app.entry.paperTime == "0005")
    }

    @Test func blockingOperatingRulesUseTheIncrementalStatistics() async throws {
        let app = try await PortedApp.make { config in
            config.cluster.ruleEnforcement = .block
        }
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        let mine = ContestStats.of(app.model.logbook.rows)
        await app.model.logbook.settle()
        #expect(app.model.logbook.statsForRules == mine)
    }

    @Test func unwipeIncrementAndFind() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        app.type(call: "DL1ABC", zone: "14")
        app.entry.runShortcut(.wipeUndo)
        #expect(app.entry.form.call == "")
        app.entry.runShortcut(.wipeUndo)
        #expect(app.entry.form.call == "DL1ABC")
        #expect(app.entry.form.contestExchange["zone"] == "14")
        #expect(app.status == "Obnoveno DL1ABC")
        app.entry.runShortcut(.incrementNr)
        #expect(app.entry.form.contestExchange["zone"] == "15")
        app.entry.runShortcut(.find)
        #expect(app.model.windows.isOpen("log"))
        #expect(app.model.windows.logSearchRequest == "call:DL1ABC")
        app.entry.runShortcut(.wipe)
        app.entry.runShortcut(.wipeUndo)
        #expect(app.entry.form.call == "")
    }

    @Test func dupeBeepsOnceWhenConfigured() async throws {
        let app = try await PortedApp.make { config in
            config.beepOnDupe = true
        }
        try await app.startCqWw()
        await app.log(call: "DL1ABC", zone: "14")
        app.entry.callChanged("DL1AB")
        app.entry.callChanged("DL1ABC")
        app.entry.editContestField("zone", "1")
        #expect(app.beeps.count == 1)
    }
}

// MARK: - free logging

@MainActor @Suite struct FreeLoggingDupeBeepTests {

    @Test func repeatedCallNeverBeepsWithoutAContest() async throws {
        let app = try await PortedApp.make { config in
            config.beepOnDupe = true
        }
        app.entry.setFrequency("14025")
        app.entry.callChanged("DL1ABC")
        app.entry.submit()
        await app.entry.settle()
        app.entry.callChanged("DL1AB")
        app.entry.callChanged("DL1ABC")
        #expect(!app.entry.isDupe)
        #expect(app.beeps.count == 0)
        app.entry.submit()
        await app.entry.settle()
        #expect(app.model.logbook.rows.count == 2)
    }
}

// MARK: - keys, Run/S&P, ESM

@MainActor @Suite struct EntryKeysAndRunModeTests {

    @Test func enterAndEscapeDecisions() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        var pick = -1
        app.entry.suggestionSource = EntryModel.SuggestionSource(list: { ["DL1ABC", "DL1ABD"] }, pick: { pick },
                                                                 setPick: { pick = $0 })
        app.type(call: "DL1AB", zone: "14")
        #expect(app.entry.handle(.scpMove(by: 1, to: 1)))
        #expect(app.entry.scpPick == 1)
        app.entry.handle(.escape(.cancelSuggestion))
        #expect(app.entry.scpPick == -1)
        app.entry.handle(.enter(ctrl: false, step: .takeSuggestion(0)))
        #expect(app.entry.form.call == "DL1ABC")
        app.entry.handle(.enter(ctrl: false, step: .logQso(ctrlEnter: false)))
        await app.settle()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        app.type(call: "W1AW", zone: "5")
        app.entry.handle(.escape(.wipe))
        // Kotlin evaluates `stopSending()` on every Esc release before it cancels the suggestion or wipes.
        #expect(app.keyer.stopCount == 2)
        #expect(app.entry.form.call == "")
        #expect(!app.entry.handle(.passThrough))
        #expect(app.entry.handle(.shiftHeld(true, then: .consume)))
        #expect(app.entry.shiftHeld)
        // ↑/↓ without a frequency in the field: nothing (`tuneStep` needs a frequency > 0).
        app.model.status.clear()
        app.entry.handle(.tune(1))
        #expect(app.status == "")
        app.model.operating.applyCqRepeat(true)
        #expect(app.entry.keyContext(field: .call).isSending)
        app.entry.handle(.escape(.stopSending))
        #expect(!app.model.operating.cqRepeat)
        #expect(app.keyer.stopCount == 3)
    }

    @Test func sendAndLogShortcutsAndTheOperatingToggles() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        app.type(call: "DL1ABC", zone: "14")
        app.entry.runShortcut(.sendCallExchange)
        #expect(app.keyer.keys == [[EsmEngine.f2]])
        #expect(app.model.logbook.rows.isEmpty)
        app.entry.runShortcut(.tuAndLog)
        await app.settle()
        #expect(app.keyer.keys.last == [EsmEngine.f3])
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        app.type(call: "W1AW", zone: "5")
        app.entry.runShortcut(.logWithoutSending)
        await app.settle()
        #expect(app.keyer.keys.count == 3)
        app.entry.runShortcut(.toggleEsm)
        #expect(app.model.operating.esmEnabled)
        app.type(call: "OK1AA", zone: "15")
        app.entry.runShortcut(.logWithoutSending)
        await app.settle()
        #expect(app.keyer.keys.count == 3)
        #expect(app.model.logbook.rows.count == 3)
        app.entry.runShortcut(.toggleCut)
        #expect(app.status == "Cut čísla zapnuta (" + CutStyle.tn.label + ")")
        app.entry.runShortcut(.cqRepeat)
        #expect(app.model.operating.cqRepeat)
        app.entry.runShortcut(.autoRunSp)
        #expect(!app.model.operating.autoRunSwitch)
        app.entry.runShortcut(.operator)
        #expect(app.model.dialogs.showOperator)
        app.model.dialogs.closeOperator()
        app.entry.suggestionSource = EntryModel.SuggestionSource(list: { ["DL9ZZ"] }, pick: { -1 }, setPick: { _ in })
        app.entry.runShortcut(.yankScp)
        #expect(app.entry.form.call == "DL9ZZ")
        app.entry.runShortcut(.note)
        #expect(app.model.dialogs.textPrompt?.title == ContestMessage(EntryTexts.noteTitleCurrent))
        app.model.dialogs.cancelPrompt()
        app.entry.runShortcut(.functionKeysSetup)
        #expect(app.model.menu.pendingMenuAction == "settings.open")
        #expect(app.model.menu.pendingSettingsTab == "function-keys")
    }

    /// Kotlin `LaunchedEffect(tunedFreqHz, mode)`: an S&P picked by hand survives a retyped frequency, the same
    /// mode again and a contest activation on the same frequency.
    @Test func handPickedSearchAndPounceSurvivesUnchangedTuning() async throws {
        let app = try await PortedApp.make()
        let operating: OperatingModel = app.model.operating
        app.entry.setFrequency("14025")
        app.entry.setMode(.cw)
        app.entry.runShortcut(.toggleRun)
        #expect(operating.runMode == .run)
        app.entry.runShortcut(.toggleRun)
        #expect(operating.runMode == .searchAndPounce)
        app.entry.setFrequency("14025.0")
        #expect(operating.runMode == .searchAndPounce)
        app.entry.setMode(.cw)
        #expect(operating.runMode == .searchAndPounce)
        await app.enter("14025")
        #expect(operating.runMode == .searchAndPounce)
        try await app.startCqWw()
        #expect(operating.runMode == .searchAndPounce)
        // A real change of the frequency still evaluates: back to the CQ frequency after a QSY → Run.
        app.entry.setFrequency("14030")
        app.entry.setFrequency("14025")
        #expect(operating.runMode == .run)
    }

    @Test func esmWithTheProductionKeyerStillLogsAndShowsTheKeyerTextLast() async throws {
        let app = try await PortedApp.make(productionKeyer: true)
        try await app.startCqWw()
        await app.enter("ESM")
        app.entry.setFrequency("14025")
        app.model.operating.select(.run, freqHz: app.entry.form.freqHz)
        app.type(call: "DL1ABC", zone: "14")
        app.entry.handle(.enter(ctrl: false, step: .esm))
        // The keyer's failure comes from its lane, as Kotlin's `sendCw` failure comes from `cwDispatcher`.
        await app.model.keyer.settle()
        await runMainQueue()
        #expect(app.status == "CW: CW přes CAT: TRX není připojený")
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.settle()
        await app.model.keyer.settle()
        await runMainQueue()
        #expect(app.model.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(app.model.logbook.rows.first?.runMode == .run)
        #expect(app.status == "CW: CW přes CAT: TRX není připojený")
    }

    /// Alt+H is wired (the inert default port opens nothing and says nothing).
    @Test func helpShortcutIsNoLongerUnavailable() async throws {
        let app = try await PortedApp.make()
        app.model.status.clear()
        app.entry.runShortcut(.help)
        #expect(app.status.isEmpty)
    }

    /// Ctrl+K opens the CW keyboard window (`EP:916`).
    @Test func cwKeyboardShortcutOpensItsWindow() async throws {
        let app = try await PortedApp.make()
        app.model.status.clear()
        app.entry.runShortcut(.cwKeyboard)
        #expect(app.model.windows.isOpen("cwkeyboard"))
        #expect(app.status.isEmpty)
    }

    @Test func runAndSearchAndPounceFollowTheCqFrequency() async throws {
        let app = try await PortedApp.make()
        let operating: OperatingModel = app.model.operating
        #expect(operating.runMode == .searchAndPounce)
        app.entry.setFrequency("14025")
        app.entry.runShortcut(.toggleRun)
        #expect(operating.runMode == .run)
        #expect(app.status == "Run (CQ frekvence 14025.0 kHz)")
        #expect(operating.cqFrequency(band: .m20) == 14_025_000)
        // QSY away → S&P; back to the CQ frequency → Run.
        app.entry.setFrequency("14040")
        #expect(operating.runMode == .searchAndPounce)
        app.entry.setFrequency("14025.2")
        #expect(operating.runMode == .run)
        app.entry.setFrequency("7010")
        #expect(operating.runMode == .searchAndPounce)
        // Alt+Q: back to the band's CQ frequency without a rig, Run.
        app.entry.setFrequency("14100")
        app.entry.callChanged("DL1ABC")
        app.entry.runShortcut(.jumpCq)
        #expect(app.entry.form.freqKHz == "14025.00")
        #expect(app.entry.form.call == "")
        #expect(operating.runMode == .run)
        #expect(app.rig.log.last == "qsy 14025000")
        app.entry.setFrequency("3510")
        app.entry.runShortcut(.jumpCq)
        #expect(app.status == "Na pásmu 80m zatím nebylo CQ")
        app.entry.runShortcut(.toggleRun)
        #expect(app.status == "Run (CQ frekvence 3510.0 kHz)")
        app.entry.runShortcut(.toggleRun)
        #expect(app.status == "S&P")
        // The logged QSO carries the run mode.
        try await app.startCqWw()
        operating.select(.run, freqHz: 14_025_000)
        await app.log(call: "DL1ABC", zone: "14")
        #expect(app.model.logbook.rows.last?.runMode == .run)
    }

    @Test func esmInRunSendsCqCallExchangeThenTuAndLogs() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.enter("ESM")
        app.entry.setFrequency("14025")
        app.model.operating.select(.run, freqHz: app.entry.form.freqHz)
        #expect(app.entry.esmStep?.keys == [EsmEngine.f1])
        app.entry.handle(.enter(ctrl: false, step: .esm))
        app.entry.callChanged("DL1ABC")
        #expect(app.entry.esmStep?.keys == [EsmEngine.f5, EsmEngine.f2])
        let exchangeFocus: Int = app.entry.exchangeFocusRequest
        app.entry.handle(.enter(ctrl: false, step: .esm))
        #expect(app.entry.exchangeFocusRequest == exchangeFocus + 1)
        app.entry.editContestField("zone", "14")
        #expect(app.entry.esmStep == EsmEngine.Step(keys: [EsmEngine.f3], log: true, focus: .call))
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.settle()
        #expect(app.keyer.keys == [[EsmEngine.f1], [EsmEngine.f2], [EsmEngine.f3]])
        #expect(app.model.logbook.rows.map(\.runMode) == [.run])
        #expect(app.model.operating.lastSentKeys == [EsmEngine.f3])
        #expect(app.entry.esmProgress == .empty)
        // `=` resends the last keys.
        app.entry.handle(.resendLast)
        #expect(app.keyer.keys.last == [EsmEngine.f3])
    }

    @Test func esmInSearchAndPounceSendsMyCallThenExchangeAndLogs() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.enter("ESM")
        app.type(call: "DL1ABC", zone: "")
        #expect(app.entry.esmStep?.keys == [EsmEngine.f4])
        app.entry.handle(.enter(ctrl: false, step: .esm))
        app.entry.editContestField("zone", "14")
        app.entry.handle(.enter(ctrl: false, step: .esm))
        await app.settle()
        #expect(app.keyer.keys == [[EsmEngine.f4], [EsmEngine.f2]])
        #expect(app.model.logbook.rows.map(\.runMode) == [.searchAndPounce])
        // A dupe in S&P sends nothing.
        app.type(call: "DL1ABC", zone: "")
        app.entry.handle(.enter(ctrl: false, step: .esm))
        #expect(app.status == "DUPE — v S&P ESM nic nevysílá")
        #expect(app.keyer.keys.count == 2)
    }

    @Test func functionKeysUseTheRunOrSearchSetAndF1SwitchesToRun() async throws {
        let app = try await PortedApp.make()
        app.entry.setFrequency("14025")
        app.entry.setMode(.ssb)
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        guard case .voice(let indices, _, let freqHz, let opposite)? = app.keyer.transmissions.last else {
            Issue.record("no voice transmission")
            return
        }
        #expect(indices == [0])
        #expect(freqHz == 14_025_000)
        #expect(!opposite)
        #expect(app.model.operating.runMode == .run)
        #expect(app.model.operating.cqFrequency(band: .m20) == 14_025_000)
        await app.enter("POSTCONTEST")
        app.entry.handle(.functionKey(1, shift: true, ctrlShift: false))
        #expect(app.status == "Dodatečné zadání — nic se nevysílá (NOPOSTCONTEST ukončí)")
        #expect(app.keyer.transmissions.count == 1)
    }

    @Test func noKeyerAnswersWithKotlinsTexts() {
        let keyer = NoKeyer()
        let message = CwMessage(parts: [])
        let off = KeyerSettings(cwMethod: .none, winkeyerPort: "", voiceTexts: [])
        #expect(keyer.send(.cw(message, index: 0), settings: off)?.czech == "CW: CW klíč je vypnutý (Nastavení → CW klíč)")
        let cat = KeyerSettings(cwMethod: .cat, winkeyerPort: "", voiceTexts: [])
        #expect(keyer.send(.cw(message, index: 0), settings: cat)?.czech == "CW: CW přes CAT: TRX není připojený")
        let voice = KeyerSettings(cwMethod: .cat, winkeyerPort: "", voiceTexts: ["", "x"])
        let empty = keyer.send(.voice(indices: [0], hisCall: "", freqHz: 0, opposite: false), settings: voice)
        #expect(empty?.czech == "F1: zpráva je prázdná (Nastavení → Function Keys)")
        #expect(NoRig().clearRit()?.czech == "RIT: připoj TRX (CAT)")
        #expect(!keyer.canSend)
    }

    @Test func repeatTimePromptAcceptsSecondsAndMilliseconds() async throws {
        let app = try await PortedApp.make()
        app.entry.runShortcut(.cqRepeatTime)
        #expect(app.model.dialogs.textPrompt?.initial == "2.0")
        app.model.dialogs.submitPrompt("1800")
        #expect(app.status == "Pauza mezi CQ 1.8 s")
        app.entry.runShortcut(.cqRepeatTime)
        app.model.dialogs.submitPrompt("2,5")
        #expect(app.status == "Pauza mezi CQ 2.5 s")
        app.entry.runShortcut(.cqRepeatTime)
        app.model.dialogs.submitPrompt("-1")
        #expect(app.status == "Opakování CQ: neplatný čas „-1“")
    }

    @Test func postContestMenuActionTogglesTheState() async throws {
        let app = try await PortedApp.make()
        #expect(app.model.menu.isImplemented("contest.postcontest"))
        #expect(app.model.menu.isImplemented("settings.downloadScp"))
        _ = MenuActions.perform("contest.postcontest", app: app.model)
        #expect(app.model.operating.postContest)
        _ = MenuActions.perform("contest.postcontest", app: app.model)
        #expect(!app.model.operating.postContest)
    }
}

// MARK: - termination gate

@Suite struct TerminationGateTests {

    @Test func beforeTheBootstrapTheAppQuitsAtOnce() {
        var gate = TerminationGate()
        let result1 = gate.requestTermination()
        #expect(result1 == .terminateNow)
    }

    @Test func quitDuringTheBootstrapWaitsAndASecondIsCancelled() {
        var gate = TerminationGate()
        gate.bootstrapStarted()
        let result2 = gate.requestTermination()
        #expect(result2 == .terminateLater(startShutdown: false))
        #expect(gate.isTerminating)
        let result3 = gate.requestTermination()
        #expect(result3 == .terminateCancel)
        let result4 = gate.bootstrapSucceeded()
        #expect(result4)
        #expect(gate.phase == .shuttingDown)
        let result5 = gate.requestTermination()
        #expect(result5 == .terminateCancel)
        gate.shutdownFinished()
        let result6 = gate.requestTermination()
        #expect(result6 == .terminateNow)
    }

    @Test func firstQuitStartsTheShutdownOnceSecondAndThirdAreCancelled() {
        var gate = TerminationGate()
        gate.bootstrapStarted()
        let result7 = gate.bootstrapSucceeded()
        #expect(!result7)
        #expect(!gate.isTerminating)
        let result8 = gate.requestTermination()
        #expect(result8 == .terminateLater(startShutdown: true))
        let result9 = gate.requestTermination()
        #expect(result9 == .terminateCancel)
        let result10 = gate.requestTermination()
        #expect(result10 == .terminateCancel)
        gate.shutdownFinished()
        #expect(gate.phase == .finished)
    }

    @Test func failedBootstrapRepliesToAPendingQuitOrQuitsLater() {
        var pending = TerminationGate()
        pending.bootstrapStarted()
        _ = pending.requestTermination()
        let result11 = pending.bootstrapFailed()
        #expect(result11)
        var idle = TerminationGate()
        idle.bootstrapStarted()
        let result12 = idle.bootstrapFailed()
        #expect(!result12)
        #expect(idle.isTerminating)
        let result13 = idle.requestTermination()
        #expect(result13 == .terminateNow)
    }
}

/// A flag set from another thread (a test job on the handle's queue) and polled from the main actor.
final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() {
        lock.withLock { value = true }
    }
}
