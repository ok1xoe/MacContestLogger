import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// Lets the main queue run what was posted before (`MainHop.post` of the scan's probes).
@MainActor
private func drainMain() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

/// Waits off the cooperative pool until the semaphore is signalled.
private func waitFor(_ semaphore: DispatchSemaphore) async {
    _ = try? await BlockingQueue.run {
        semaphore.wait()
    }
}

/// A thread-safe log of what the fakes saw.
final class ToolEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func add(_ item: String) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

/// The hamlib list without hamlib: fixed models, and whether it ran off the main thread.
struct FakeRigList: RigListPort {
    let models: [HamlibRigModel]
    let events: ToolEvents

    func list() -> [HamlibRigModel] {
        events.add("list main=" + String(Thread.isMainThread))
        return models
    }
}

/// A scan that touches no rig: it walks the candidates like `RigScanner.scan` (cancel check, `onProbe`), optionally
/// stops at each probe until the test lets it go on, and answers on the candidate `answerAt`.
final class FakeRigScan: RigScanPort, @unchecked Sendable {
    let events: ToolEvents
    let answerAt: Int?
    let gated: Bool
    /// Signalled after each `onProbe`.
    let probing = DispatchSemaphore(value: 0)
    /// Lets a gated probe finish.
    let proceed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var seen: (candidates: [RigScanner.Candidate], listener: (any RigScanner.Listener)?) = ([], nil)

    init(events: ToolEvents, answerAt: Int?, gated: Bool) {
        self.events = events
        self.answerAt = answerAt
        self.gated = gated
    }

    var candidates: [RigScanner.Candidate] {
        lock.lock()
        defer { lock.unlock() }
        return seen.candidates
    }

    var listener: (any RigScanner.Listener)? {
        lock.lock()
        defer { lock.unlock() }
        return seen.listener
    }

    func disconnectCat(reason: String) async {
        events.add("disconnect " + reason)
    }

    func scan(device: String, candidates: [RigScanner.Candidate],
              listener: any RigScanner.Listener) -> RigScanner.Outcome? {
        events.add("scan \(device) main=\(Thread.isMainThread)")
        lock.lock()
        seen = (candidates, listener)
        lock.unlock()
        for (index, candidate) in candidates.enumerated() {
            if listener.isCancelled() {
                events.add("cancelled")
                break
            }
            listener.onProbe(candidate)
            if gated {
                probing.signal()
                proceed.wait()
            }
            if index == answerAt {
                return RigScanner.Outcome(candidate: candidate, freqHz: 14_025_000)
            }
        }
        return nil
    }
}

struct FakeDevices: DevicePort {
    let events: ToolEvents

    func serialPorts() -> [String] {
        events.add("ports main=" + String(Thread.isMainThread))
        return ["/dev/cu.usbserial-1", "/dev/tty.usbserial-1"]
    }

    func outputDevices() -> [String] {
        events.add("outputs main=" + String(Thread.isMainThread))
        return ["Default Audio Device", "MacBook Speakers", "USB Audio CODEC"]
    }

    func inputDevices() -> [String] {
        ["Default Audio Device", "USB Audio CODEC"]
    }
}

/// fldigi without fldigi: answers or fails as told; a host named `slow` waits for `release`.
final class FakeFldigi: FldigiProbePort, @unchecked Sendable {
    let events: ToolEvents
    let failure: (any Error)?
    let release = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)

    init(events: ToolEvents, failure: (any Error)? = nil) {
        self.events = events
        self.failure = failure
    }

    func probe(host: String, port: Int) throws -> (version: String, modem: String) {
        events.add("fldigi \(host):\(port) main=\(Thread.isMainThread)")
        if host == "slow" {
            entered.signal()
            release.wait()
        }
        if let failure {
            throw failure
        }
        return ("4.2.05", host == "slow" ? "OLD" : "BPSK31")
    }
}

/// A counter a test can hold for one input.
final class HeldCounter: @unchecked Sendable {
    let events = ToolEvents()
    let held: String
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    init(held: String) {
        self.held = held
    }

    func count(_ group: SettingsToolsModel.CountGroup, _ input: String) -> [Int] {
        events.add(String(describing: group) + " " + input)
        if input == held {
            entered.signal()
            release.wait()
        }
        return [input.count, input.count + 100]
    }
}

/// The Settings tab tools (`HW:191-260`, `VK:36-46`, `MT:86-97, 127-160, 192-258`, `CT:28-191`) with fake
/// ports only: no rig, serial port, sound device, rigctld or fldigi is touched.
@MainActor @Suite struct SettingsToolsModelTests {

    static let ts590 = HamlibRigModel(number: 2031, mfg: "Kenwood", model: "TS-590S")
    static let ic7300 = HamlibRigModel(number: 3073, mfg: "Icom", model: "IC-7300")

    static func app(scan: FakeRigScan? = nil, fldigi: FakeFldigi? = nil, events: ToolEvents = ToolEvents(),
                    clock: ManualClock? = nil,
                    configure: @escaping (inout AppConfig, URL) throws -> Void = { _, _ in }) async throws -> TestApp {
        try await TestApp.make(configure: configure, adjust: { environment in
            environment.settingsToolPorts = SettingsToolPorts(
                rigList: FakeRigList(models: [ts590, ic7300], events: events),
                rigScan: scan ?? FakeRigScan(events: events, answerAt: nil, gated: false),
                devices: FakeDevices(events: events),
                fldigi: fldigi ?? FakeFldigi(events: events))
            if let clock {
                environment.settingsCountsClock = clock
            }
        })
    }

    /// Opens Settings with a draft whose device is chosen.
    static func draft(_ app: TestApp, device: String = "/dev/cu.usbserial-1") async throws -> ConfigurerDraft {
        app.model.settings.open()
        await app.model.settings.settle()
        var draft: ConfigurerDraft = try #require(app.model.settings.draft)
        draft.device = device
        draft.rigModel = 2014
        draft.rigModelLabel = "Kenwood TS-590SG"
        draft.baud = 4800
        app.model.settings.draft = draft
        return draft
    }

    // MARK: - rig list, ports, devices

    @Test func theSheetListsTheModelsThenThePortsOffTheMainThread() async throws {
        let events = ToolEvents()
        let app = try await Self.app(events: events)
        let tools: SettingsToolsModel = app.model.settingsTools
        #expect(tools.rigModels.isEmpty)

        tools.openRigSheet()
        await tools.settle()

        #expect(tools.rigModels == [Self.ts590, Self.ic7300])
        tools.openRigSheet()
        #expect(tools.serialPorts.isEmpty)
        await tools.settle()
        #expect(tools.serialPorts == ["/dev/cu.usbserial-1", "/dev/tty.usbserial-1"])
        #expect(tools.serialPortsWithNone == ["—", "/dev/cu.usbserial-1", "/dev/tty.usbserial-1"])
        #expect(events.all == ["list main=false", "ports main=false", "list main=false", "ports main=false"])
        #expect(tools.manufacturers == RigModelFilter.manufacturers([Self.ts590, Self.ic7300]))
        #expect(tools.filtered(manufacturer: "Icom", query: "") == [Self.ic7300])
        #expect(tools.filtered(manufacturer: nil, query: "590") == [Self.ts590])
    }

    @Test func audioChoicesStartWithTheSystemDefaultOnce() async throws {
        let events = ToolEvents()
        let app = try await Self.app(events: events)
        let tools: SettingsToolsModel = app.model.settingsTools

        tools.loadAudioDevices()
        await tools.settle()

        #expect(tools.outputDevices == ["Výchozí systémové", "MacBook Speakers", "USB Audio CODEC"])
        #expect(tools.inputDevices == ["Výchozí systémové", "USB Audio CODEC"])
        #expect(events.all == ["outputs main=false"])
    }

    // MARK: - scan

    @Test func scanDisconnectsCatThenProbesAndPutsTheFoundRigIntoTheDraft() async throws {
        let events = ToolEvents()
        let scan = FakeRigScan(events: events, answerAt: 1, gated: true)
        let app = try await Self.app(scan: scan, events: events)
        let tools: SettingsToolsModel = app.model.settingsTools
        tools.openRigSheet()
        await tools.settle()
        let draft: ConfigurerDraft = try await Self.draft(app)
        #expect(tools.canStartScan(device: draft.device))

        tools.startScan(draft: draft)
        #expect(tools.scanState == .init(isScanning: true, status: "Skenuji…"))
        #expect(!tools.canStartScan(device: draft.device))

        await waitFor(scan.probing)
        await drainMain()
        #expect(tools.scanState == .init(isScanning: true, status: "Zkouším Kenwood TS-590SG @ 1200…"))
        scan.proceed.signal()
        await waitFor(scan.probing)
        await drainMain()
        #expect(tools.scanState == .init(isScanning: true, status: "Zkouším Kenwood TS-590SG @ 2400…"))
        scan.proceed.signal()
        await tools.settle()

        #expect(tools.scanState == .init(isScanning: false,
                                         status: "Nalezeno: Kenwood TS-590SG @ 2400 baud (14025.0 kHz)"))
        let after: ConfigurerDraft = try #require(app.model.settings.draft)
        #expect(after.rigModel == 2014)
        #expect(after.rigModelLabel == "Kenwood TS-590SG")
        #expect(after.baud == 2400)
        #expect(events.all.filter { !$0.hasPrefix("list") && !$0.hasPrefix("ports") }
            == ["disconnect scan", "scan /dev/cu.usbserial-1 main=false"])
        #expect(scan.candidates == RigScanner.buildCandidates(
            selectedModel: 2014, selectedLabel: "Kenwood TS-590SG", all: [Self.ts590, Self.ic7300],
            bauds: [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200]))
    }

    @Test func aScanWithoutAnswerSaysSoAndLeavesTheDraft() async throws {
        let scan = FakeRigScan(events: ToolEvents(), answerAt: nil, gated: false)
        let app = try await Self.app(scan: scan)
        let tools: SettingsToolsModel = app.model.settingsTools
        let draft: ConfigurerDraft = try await Self.draft(app)

        tools.startScan(draft: draft)
        await tools.settle()

        #expect(tools.scanState == .init(isScanning: false, status: "Nic se neozvalo"))
        #expect(app.model.settings.draft == draft)
        // Without the model list only the chosen model is tried, at every baud.
        #expect(scan.candidates.count == 8)
    }

    @Test func stopEndsTheScanBeforeTheNextCandidate() async throws {
        let events = ToolEvents()
        let scan = FakeRigScan(events: events, answerAt: nil, gated: true)
        let app = try await Self.app(scan: scan, events: events)
        let tools: SettingsToolsModel = app.model.settingsTools
        let draft: ConfigurerDraft = try await Self.draft(app)

        tools.startScan(draft: draft)
        await waitFor(scan.probing)
        tools.stopScan()
        scan.proceed.signal()
        await tools.settle()

        #expect(tools.scanState == .init(isScanning: false, status: "Scan zastaven"))
        #expect(events.all.last == "cancelled")
        #expect(app.model.settings.draft == draft)
    }

    @Test func closingTheSheetCancelsTheScanAndDropsItsResult() async throws {
        let scan = FakeRigScan(events: ToolEvents(), answerAt: 0, gated: true)
        let app = try await Self.app(scan: scan)
        let tools: SettingsToolsModel = app.model.settingsTools
        let draft: ConfigurerDraft = try await Self.draft(app)

        tools.startScan(draft: draft)
        await waitFor(scan.probing)
        tools.closeRigSheet()
        #expect(tools.scanState == .idle)
        #expect(scan.listener?.isCancelled() == true)
        scan.proceed.signal()
        await tools.settle()
        await drainMain()

        // The candidate being probed answered, but the sheet is gone: nothing reaches the draft or the line.
        #expect(tools.scanState == .idle)
        #expect(app.model.settings.draft == draft)
    }

    @Test func aLateProbeIsDropped() async throws {
        let scan = FakeRigScan(events: ToolEvents(), answerAt: nil, gated: false)
        let app = try await Self.app(scan: scan)
        let tools: SettingsToolsModel = app.model.settingsTools
        let draft: ConfigurerDraft = try await Self.draft(app)
        tools.startScan(draft: draft)
        await tools.settle()
        await drainMain()
        #expect(tools.scanState.status == "Nic se neozvalo")

        let listener: any RigScanner.Listener = try #require(scan.listener)
        let late = RigScanner.Candidate(model: 1, label: "Late", baud: 9600)
        let box = ListenerBox(listener)
        _ = try await BlockingQueue.run {
            box.listener.onProbe(late)
        }
        await drainMain()

        #expect(tools.scanState == .init(isScanning: false, status: "Nic se neozvalo"))
    }

    @Test func noNewScanUntilTheCancelledOneHasEnded() async throws {
        let events = ToolEvents()
        let scan = FakeRigScan(events: events, answerAt: nil, gated: true)
        let app = try await Self.app(scan: scan, events: events)
        let tools: SettingsToolsModel = app.model.settingsTools
        let draft: ConfigurerDraft = try await Self.draft(app)
        tools.startScan(draft: draft)
        await waitFor(scan.probing)

        tools.closeRigSheet()
        tools.openRigSheet()
        #expect(tools.scanInFlight)
        #expect(!tools.canStartScan(device: draft.device))
        tools.startScan(draft: draft)
        #expect(tools.scanState == .idle)

        scan.proceed.signal()
        await tools.settle()
        #expect(!tools.scanInFlight)
        #expect(tools.canStartScan(device: draft.device))
        #expect(events.all.filter { $0.hasPrefix("scan ") }.count == 1)
    }

    @Test func quitCancelsTheScanAndWaitsForItBeforeCat() async throws {
        let events = ToolEvents()
        let scan = FakeRigScan(events: events, answerAt: nil, gated: true)
        let app = try await Self.app(scan: scan, events: events)
        let model: AppModel = app.model
        model.shutdownServices.cat = { events.add("cat") }
        let draft: ConfigurerDraft = try await Self.draft(app)
        model.settingsTools.startScan(draft: draft)
        await waitFor(scan.probing)

        let quit = Task { await model.shutdown() }
        while scan.listener?.isCancelled() != true {
            await drainMain()
        }
        #expect(!events.all.contains("cat"))
        scan.proceed.signal()
        await quit.value

        let tail: [String] = events.all.filter { $0.hasPrefix("disconnect") || $0 == "cancelled" || $0 == "cat" }
        #expect(tail == ["disconnect scan", "cancelled", "cat"])
        #expect(!model.settingsTools.scanInFlight)
    }

    @Test func noScanWithoutAPort() async throws {
        let events = ToolEvents()
        let app = try await Self.app(scan: FakeRigScan(events: events, answerAt: 0, gated: false), events: events)
        let tools: SettingsToolsModel = app.model.settingsTools
        let draft: ConfigurerDraft = try await Self.draft(app, device: "  ")

        #expect(!tools.canStartScan(device: draft.device))
        tools.startScan(draft: draft)
        await tools.settle()

        #expect(tools.scanState == .idle)
        #expect(events.all.isEmpty)
    }

    // MARK: - fldigi

    @Test func fldigiProbeAnswersWithVersionAndModem() async throws {
        let events = ToolEvents()
        let app = try await Self.app(fldigi: FakeFldigi(events: events), events: events)
        let tools: SettingsToolsModel = app.model.settingsTools

        let text: String = await tools.fldigiProbe(host: "  localhost ", port: "")

        #expect(text == "fldigi 4.2.05, modem BPSK31")
        #expect(events.all == ["fldigi localhost:7362 main=false"])
    }

    @Test func fldigiProbeFailureShowsTheJavaMessage() async throws {
        let refused = FakeFldigi(events: ToolEvents(), failure: JavaIOError(nil, javaClass: "java.net.ConnectException"))
        let app = try await Self.app(fldigi: refused)
        #expect(await app.model.settingsTools.fldigiProbe(host: "localhost", port: "7362") == "nedostupné: null")

        let timeout = FakeFldigi(events: ToolEvents(), failure: JavaIOError(
            "HTTP connect timed out", javaClass: "java.net.http.HttpConnectTimeoutException"))
        let other = try await Self.app(fldigi: timeout)
        #expect(await other.model.settingsTools.fldigiProbe(host: "h", port: "1")
            == "nedostupné: HTTP connect timed out")
    }

    @Test func aLaterFldigiClickWins() async throws {
        let fldigi = FakeFldigi(events: ToolEvents())
        let app = try await Self.app(fldigi: fldigi)
        let tools: SettingsToolsModel = app.model.settingsTools

        tools.probeFldigi(host: "slow", port: "7362")
        #expect(tools.fldigiProbeText == "zkouším…")
        await waitFor(fldigi.entered)
        tools.probeFldigi(host: "fast", port: "7362")
        // Only the second probe can finish while the first is held.
        while tools.fldigiProbeText == "zkouším…" {
            await drainMain()
        }
        #expect(tools.fldigiProbeText == "fldigi 4.2.05, modem BPSK31")
        fldigi.release.signal()
        await tools.settle()

        #expect(tools.fldigiProbeText == "fldigi 4.2.05, modem BPSK31")
    }

    // MARK: - counts

    @Test func countsFollowTheDraftAfterTheDelayAndDropStaleResults() async throws {
        let clock = ManualClock()
        let app = try await Self.app(clock: clock)
        let tools: SettingsToolsModel = app.model.settingsTools
        let counter = HeldCounter(held: "slow")
        tools.counter = { group, input in counter.count(group, input) }
        var draft: ConfigurerDraft = try await Self.draft(app)
        draft.contestDataDir = "dir"
        draft.scpFile = "first"
        draft.callHistoryFile = ""

        // The first request counts at once.
        tools.updateCounts(draft)
        await tools.settle()
        #expect(tools.contestYamlCount == 3)
        #expect(tools.multiplierYamlCount == 103)
        #expect(tools.scpCount == 5)
        #expect(tools.callHistoryCount == 0)

        // Changes inside the delay collapse into the last one.
        draft.scpFile = "ab"
        tools.updateCounts(draft)
        draft.scpFile = "abc"
        tools.updateCounts(draft)
        await tools.settle()
        #expect(tools.scpCount == 5)
        clock.advance(by: 299)
        await tools.settle()
        #expect(tools.scpCount == 5)
        clock.advance(by: 1)
        await tools.settle()
        #expect(tools.scpCount == 3)

        // A count still running when the field changes again is dropped.
        draft.scpFile = "slow"
        tools.updateCounts(draft)
        clock.advance(by: 300)
        await waitFor(counter.entered)
        draft.scpFile = "fast!"
        tools.updateCounts(draft)
        counter.release.signal()
        await tools.settle()
        #expect(tools.scpCount == 3)
        clock.advance(by: 300)
        await tools.settle()
        #expect(tools.scpCount == 5)

        #expect(counter.events.all.filter { $0.hasPrefix("scp") } == ["scp first", "scp abc", "scp slow", "scp fast!"])
        #expect(counter.events.all.filter { $0.hasPrefix("contestData") } == ["contestData dir"])
    }

    @Test func countsReadTheFilesOfTheDraft() async throws {
        let app = try await Self.app()
        let tools: SettingsToolsModel = app.model.settingsTools
        var draft: ConfigurerDraft = try await Self.draft(app)
        let scp: URL = app.dir.child("master.scp")
        try Data("OK1XOE\nDL1ABC\n".utf8).write(to: scp)
        draft.scpFile = scp.path
        draft.contestDataDir = Fixtures.contestData.path

        tools.updateCounts(draft)
        await tools.settle()

        #expect(tools.scpCount == 2)
        #expect(tools.callHistoryCount == 0)
        #expect(tools.contestYamlCount == SettingsTools.contestYamlCount(contestDataDir: Fixtures.contestData.path))
        #expect((tools.contestYamlCount ?? 0) > 0)
        #expect((tools.multiplierYamlCount ?? 0) > 0)

        tools.windowClosed()
        #expect(tools.scpCount == nil)
    }

    // MARK: - languages

    @Test func languagesListTheDirectoryAndReloadRestoresTheShippedOnes() async throws {
        let app = try await Self.app()
        let tools: SettingsToolsModel = app.model.settingsTools
        tools.loadLanguages()
        await tools.settle()
        #expect(tools.languages.first?.code == "cs")
        #expect(tools.languages.contains { $0.code == "en" })

        let english: URL = app.model.language.languageDir.appendingPathComponent("lang_en.json")
        try FileManager.default.removeItem(at: english)
        tools.loadLanguages()
        await tools.settle()
        #expect(!tools.languages.contains { $0.code == "en" })

        tools.reloadLanguages()
        await tools.settle()
        #expect(FileManager.default.fileExists(atPath: english.path))
        #expect(tools.languages.contains { $0.code == "en" })
    }

    // MARK: - menu file

    @Test func createMenuFileWritesTheBuiltInMenuOnce() async throws {
        let app = try await Self.app()
        let tools: SettingsToolsModel = app.model.settingsTools
        let file: URL = app.dataDir.appendingPathComponent("menu.json")
        tools.refreshMenuFile()
        await tools.settle()
        #expect(tools.menuFileState == .init(file: file.path, source: .builtIn, error: nil))

        tools.createMenuFile()
        await tools.settle()
        #expect(tools.menuMessage == "Vytvořeno: " + file.path)
        #expect(tools.menuFileState?.source == .user)

        tools.createMenuFile()
        await tools.settle()
        #expect(tools.menuMessage == "Soubor už existuje, nechal jsem ho být. Uprav ho v textovém editoru.")
    }

    @Test func anExistingMenuFileIsNeverOverwritten() async throws {
        let app = try await Self.app()
        let tools: SettingsToolsModel = app.model.settingsTools
        let file: URL = app.dataDir.appendingPathComponent("menu.json")
        let own = Data("{\"menu\": []}".utf8)
        try own.write(to: file)

        tools.createMenuFile()
        await tools.settle()

        #expect(tools.menuMessage == "Soubor už existuje, nechal jsem ho být. Uprav ho v textovém editoru.")
        #expect(try Data(contentsOf: file) == own)
        #expect(tools.menuFileState?.source == .userInvalid)
        #expect(tools.menuFileState?.error == "Soubor " + file.path + " nemá žádnou položku menu.")
    }

    @Test func aFailedMenuWriteCarriesTheJavaMessage() throws {
        let dir = try TempDir()
        let notADirectory: URL = dir.child("plain-file")
        try Data("x".utf8).write(to: notADirectory)

        let written = SettingsToolsModel.writeMenu(notADirectory)

        #expect(written.failed)
        #expect(written.path == nil)
        #expect(!written.existed)
        // Probe `menu fail`: `FileAlreadyExistsException` with the data directory as its message.
        #expect(written.failure == notADirectory.path)
    }

    @Test func reloadMenuReportsWhichMenuApplies() async throws {
        let app = try await Self.app()
        let tools: SettingsToolsModel = app.model.settingsTools
        let model: AppModel = app.model

        tools.reloadMenu()
        await tools.settle()
        #expect(model.status.message == "Menu: vlastní menu.json není, platí vestavěné")
        #expect(tools.menuMessage == "Menu načteno znovu.")
        #expect(model.menu.source == .builtIn)

        tools.createMenuFile()
        await tools.settle()
        tools.reloadMenu()
        await tools.settle()
        #expect(model.status.message == "Menu načteno z menu.json")
        #expect(model.menu.source == .user)
        #expect(tools.menuFileState?.source == .user)

        try Data("not json".utf8).write(to: app.dataDir.appendingPathComponent("menu.json"))
        tools.reloadMenu()
        await tools.settle()
        #expect(model.menu.source == .userInvalid)
        #expect(model.status.message.hasPrefix("Menu: Soubor "))
        #expect(model.status.message.hasSuffix(" Platí vestavěné menu."))
        #expect(tools.menuFileState?.source == .userInvalid)
    }
}

/// Hands a listener to another thread (the scan's listener is used from the scan thread in production).
private final class ListenerBox: @unchecked Sendable {
    let listener: any RigScanner.Listener

    init(_ listener: any RigScanner.Listener) {
        self.listener = listener
    }
}
