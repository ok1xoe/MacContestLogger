import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// Records the effects a plan ran and what the other subsystems' ports saw.
@MainActor
final class EffectRecorder {
    var effects: [ConfigEffect] = []
    /// Port name and a note taken when it ran.
    var calls: [String] = []
    var catConnected: Bool = false
    var reconnects: [Bool] = []
    var scoreReports: Int = 0
    /// Runs inside the `checkClock` port (a test changes state in the middle of a plan).
    var duringCheckClock: (@MainActor () -> Void)?

    func services(_ app: @escaping @MainActor () -> AppModel?) -> SettingsServices {
        var services = SettingsServices()
        services.trace = { [unowned self] effect in self.effects.append(effect) }
        services.dxMyCall = { [unowned self] in
            // What the inner effects see: the new configuration live, the new language switched to.
            let model: AppModel? = app()
            self.calls.append("dxMyCall " + (model?.config.config.station.call ?? "") + " "
                              + (model?.language.code ?? ""))
        }
        services.cwSpeed = { [unowned self] in
            self.calls.append("cwSpeed after " + (app()?.status.message ?? ""))
        }
        services.checkClock = { [unowned self] in
            self.calls.append("checkClock")
            self.duringCheckClock?()
        }
        services.restartCluster = { [unowned self] in self.calls.append("restartCluster") }
        services.catConnected = { [unowned self] in self.catConnected }
        services.reconnectCat = { [unowned self] disconnectFirst in self.reconnects.append(disconnectFirst) }
        services.reportScoreNow = { [unowned self] in
            self.calls.append("reportScoreNow")
            self.scoreReports += 1
        }
        return services
    }

    /// The bootstrap wires the rig's live CAT ports over the injected ones; a test that records the CAT state
    /// and the reconnects puts its own back afterwards.
    func installCatPorts(on settings: SettingsModel) {
        settings.services.catConnected = { [unowned self] in self.catConnected }
        settings.services.reconnectCat = { [unowned self] disconnectFirst in self.reconnects.append(disconnectFirst) }
    }
}

/// A `config.json` writer a test can make fail.
final class SwitchableWriter: @unchecked Sendable {
    struct Refused: Error, CustomStringConvertible {
        var description: String { "disk full" }
    }

    private let lock = NSLock()
    private var failing: Bool = false
    private(set) var writes: Int = 0

    func setFailing(_ value: Bool) {
        lock.lock()
        failing = value
        lock.unlock()
    }

    private var gate: DispatchSemaphore?
    /// Signalled when a held write started.
    let entered = DispatchSemaphore(value: 0)

    /// The next write waits for `release()`.
    func hold() {
        lock.lock()
        gate = DispatchSemaphore(value: 0)
        lock.unlock()
    }

    func release() {
        lock.lock()
        let held: DispatchSemaphore? = gate
        gate = nil
        lock.unlock()
        held?.signal()
    }

    /// Waits off the cooperative pool until a held write started.
    func waitUntilHeld() async {
        let entered: DispatchSemaphore = self.entered
        _ = try? await BlockingQueue.run {
            entered.wait()
        }
    }

    func writer(_ file: URL) -> ConfigWriter {
        ConfigWriter { [self] config in
            lock.lock()
            let fail: Bool = failing
            let held: DispatchSemaphore? = gate
            writes += 1
            lock.unlock()
            if let held {
                entered.signal()
                held.wait()
                held.signal()
            }
            if fail {
                throw Refused()
            }
            try ConfigWriter.writeFile(config, to: file)
        }
    }
}

/// An app with recording Settings ports, a switchable writer and a writable copy of the contest data (a commit
/// writes the band plan and the digi frequencies into `contestDataDir`).
@MainActor
struct SettingsHarness {
    let app: TestApp
    let recorder: EffectRecorder
    let writer: SwitchableWriter
    /// The copy of the fixture contest data the configuration points at.
    let contestDir: URL

    var model: AppModel { app.model }
    var settings: SettingsModel { app.model.settings }

    static func make(configure: @escaping (inout AppConfig, URL) throws -> Void = { _, _ in })
        async throws -> SettingsHarness {
        let recorder = EffectRecorder()
        let writer = SwitchableWriter()
        final class Box { var model: AppModel? }
        let box = Box()
        let app = try await TestApp.make(configure: { config, dataDir in
            let copy: URL = dataDir.appendingPathComponent("copied-data")
            try FileManager.default.copyItem(at: Fixtures.contestData, to: copy)
            config.contestDataDir = copy.path
            try configure(&config, dataDir)
        }, adjust: { environment in
            environment.settingsServices = recorder.services { box.model }
            environment.configWriter = writer.writer(environment.dataDir.appendingPathComponent("config.json"))
        })
        box.model = app.model
        recorder.installCatPorts(on: app.model.settings)
        return SettingsHarness(app: app, recorder: recorder, writer: writer,
                               contestDir: app.dataDir.appendingPathComponent("copied-data"))
    }

    /// Opens the window and waits for the draft.
    func openWithDraft(tabKey: String? = nil) async throws -> ConfigurerDraft {
        settings.open(tabKey: tabKey)
        await settings.settle()
        return try #require(settings.draft)
    }
}

/// The Settings window model (`CW:55-140`, `AS:1810-1823, 2697-2714`): tabs, the draft, Cancel, reopening
/// and deep links.
@MainActor @Suite struct SettingsModelTests {

    static let menuWithDisabledTab = #"""
    {"menu":[
      {"id":"settings","children":[
        {"id":"settings.open","children":[
          {"id":"tab.hardware","state":"disable"},
          {"id":"tab.station"},
          {"id":"tab.function-keys","state":"disable"},
          {"id":"tab.audio","state":"hidden"},
          {"id":"tab.other"}
        ]}
      ]}
    ]}
    """#

    static func enter(_ model: AppModel, _ text: String) async {
        model.entry.callChanged(text)
        model.entry.handle(.enter(ctrl: false, step: .logQso(ctrlEnter: false)))
        await model.entry.settle()
    }

    @Test func openBuildsTheSpecsAndReadsTheDraftOffTheMainThread() async throws {
        let harness = try await SettingsHarness.make()
        let settings: SettingsModel = harness.settings
        #expect(!settings.isOpen)

        settings.open()

        #expect(settings.isOpen)
        #expect(settings.specs.count == 21)
        #expect(settings.selected == .hardware)
        #expect(harness.model.windows.windowRequest?.id == "settings")
        await settings.settle()
        let draft: ConfigurerDraft = try #require(settings.draft)
        let config: AppConfig = harness.model.config.config
        let expected = ConfigurerDraft(config: config, bandSegments: BandPlanFile.read(harness.contestDir),
                                       digi: DigiFreqFile.read(harness.contestDir),
                                       defaultContestDataDir: harness.app.dataDir
                                           .appendingPathComponent("contest-data").path)
        #expect(draft == expected)
        #expect(!draft.bandSegments.isEmpty)
    }

    @Test func cancelDropsTheDraftAndChangesNothing() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        let before: AppConfig = model.config.config
        let writesBefore: Int = harness.writer.writes
        draft.call = "OK9ZZZ"
        draft.language = "en"
        harness.settings.draft = draft

        harness.settings.cancel()

        #expect(!harness.settings.isOpen)
        #expect(harness.settings.draft == nil)
        #expect(model.config.config == before)
        #expect(model.language.code == "cs")
        await model.config.flush()
        #expect(harness.writer.writes == writesBefore)
        #expect(harness.recorder.effects.isEmpty)
        // Opened again: a new draft from the configuration.
        let fresh: ConfigurerDraft = try await harness.openWithDraft()
        #expect(fresh.call == "OK1XOE")
    }

    @Test func closingBeforeTheDraftIsReadDropsTheLateDraft() async throws {
        let harness = try await SettingsHarness.make()
        let settings: SettingsModel = harness.settings
        settings.open()
        settings.cancel()
        await settings.settle()
        #expect(settings.draft == nil)
        #expect(!settings.isOpen)
    }

    @Test func switchingTabsKeepsTheDraft() async throws {
        let harness = try await SettingsHarness.make()
        let settings: SettingsModel = harness.settings
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        settings.draft = draft

        settings.select(.station)
        #expect(settings.selected == .station)
        settings.select(.bandplan)
        #expect(settings.selected == .bandplan)

        #expect(settings.draft?.call == "OK9ZZZ")
    }

    @Test func reopeningWhileOpenKeepsTheDraftAndSelectsTheFirstEnabledTab() async throws {
        let harness = try await SettingsHarness.make()
        let settings: SettingsModel = harness.settings
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        settings.draft = draft
        settings.select(.station)
        let request: WindowsModel.WindowRequest? = harness.model.windows.windowRequest

        settings.open()
        await settings.settle()

        #expect(settings.selected == .hardware)
        #expect(settings.draft?.call == "OK9ZZZ")
        #expect(harness.model.windows.windowRequest?.serial == (request?.serial ?? 0) + 1)
    }

    /// The deep link may select a disabled tab (Kotlin `firstOrNull { it.tab.key == key }`); a click may not.
    @Test func deepLinkSelectsADisabledTabAClickDoesNot() async throws {
        let harness = try await SettingsHarness.make { _, dataDir in
            try Data(Self.menuWithDisabledTab.utf8).write(to: dataDir.appendingPathComponent("menu.json"))
        }
        let settings: SettingsModel = harness.settings

        settings.open()
        #expect(settings.specs.map(\.tab) == [.hardware, .station, .functionKeys, .other])
        #expect(settings.selected == .station)
        settings.select(.hardware)
        #expect(settings.selected == .station)

        settings.open(tabKey: "function-keys")
        #expect(settings.selected == .functionKeys)
        // A hidden or unknown tab: the first enabled one stays.
        settings.open(tabKey: "audio")
        #expect(settings.selected == .station)
        settings.applyDeepLink("bogus")
        #expect(settings.selected == .station)
        settings.cancel()
        settings.applyDeepLink("function-keys")
        #expect(settings.selected == .station)
    }

    /// SETUP, MSGS/WKEY/NETCONFIG and the action FUNCTION_KEYS_SETUP open the Settings through
    /// `pendingMenuAction`; the pending tab is applied after the action (`applyPendingSettingsTab`).
    @Test func commandsOpenTheSettingsOnTheirTab() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        #expect(model.menu.isImplemented("settings.open"))

        await Self.enter(model, "WKEY")
        #expect(model.menu.pendingMenuAction == "settings.open")
        #expect(model.menu.pendingSettingsTab == "winkey")
        #expect(MenuActions.performPending(app: model) == nil)
        #expect(model.settings.isOpen)
        #expect(model.settings.selected == .winkey)
        #expect(model.menu.pendingSettingsTab == nil)

        model.entry.runShortcut(.functionKeysSetup)
        _ = MenuActions.performPending(app: model)
        #expect(model.settings.selected == .functionKeys)

        await Self.enter(model, "SETUP")
        _ = MenuActions.performPending(app: model)
        #expect(model.settings.selected == .hardware)

        model.settings.cancel()
        #expect(MenuActions.perform("settings.open", app: model) == nil)
        #expect(model.settings.isOpen)
    }
}
