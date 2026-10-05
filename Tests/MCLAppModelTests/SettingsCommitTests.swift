import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The Settings commit (`CD:554-614`, atomic, with ports) and the executor of the effect plans.
@MainActor @Suite struct SettingsCommitTests {

    /// The plan of a commit that changed only the station call, executed in order; the app's own effects and the
    /// ports interleave as in Kotlin: the configuration and the language are live before the inner effects, the
    /// status is set before the CW speed.
    @Test func commitWritesAppliesAndRunsThePlanInOrder() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        draft.language = "en"
        harness.settings.draft = draft

        let saved: Bool = await harness.settings.confirm()

        #expect(saved)
        #expect(!harness.settings.isOpen)
        let expected: [ConfigEffect] = ConfigEffectPlan.commit(ConfigChanges(scoringStation: true),
                                                              reconnectRig: false, catConnected: false)
        #expect(harness.recorder.effects == expected)
        #expect(harness.recorder.calls == ["dxMyCall OK9ZZZ en", "cwSpeed after Settings saved", "checkClock"])
        #expect(model.config.config.station.call == "OK9ZZZ")
        #expect(model.config.config.language == "en")
        #expect(model.language.code == "en")
        #expect(model.status.message == "Settings saved")
        #expect(model.config.revision == 1)
        #expect(harness.app.savedConfig().station.call == "OK9ZZZ")
        #expect(harness.recorder.reconnects.isEmpty)
    }

    /// A failed write shows the error in the old language, returns `false`, keeps the window and the
    /// draft and changes neither the configuration nor the language; no effect after the write runs.
    @Test func failedWriteChangesNothing() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        draft.language = "en"
        draft.esmEnabled = !model.config.config.esm.enabled
        harness.settings.draft = draft
        let before: AppConfig = model.config.config
        harness.writer.setFailing(true)

        let saved: Bool = await harness.settings.confirm()

        #expect(!saved)
        #expect(harness.settings.isOpen)
        #expect(harness.settings.draft == draft)
        #expect(!harness.settings.isSaving)
        #expect(model.status.message == "Uložení nastavení selhalo: disk full")
        #expect(model.config.config == before)
        #expect(model.language.code == "cs")
        #expect(model.operating.esmEnabled == before.esm.enabled)
        #expect(model.config.revision == 0)
        #expect(harness.recorder.effects == [.saveConfig(onFailure: .abortPlan(status: .settingsSaveFailed))])
        #expect(harness.recorder.calls.isEmpty)
        #expect(harness.app.savedConfig().station.call == "OK1XOE")

        // The write works again: the same draft is saved.
        harness.writer.setFailing(false)
        #expect(await harness.settings.confirm())
        #expect(model.config.config.station.call == "OK9ZZZ")
        #expect(model.language.code == "en")
    }

    /// A change made outside the window while it is open is overwritten by the draft on OK (Kotlin parity);
    /// fields the draft does not have are kept.
    @Test func externalChangesWhileOpenAreOverwrittenOnOk() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        _ = try await harness.openWithDraft()
        #expect(!model.operating.esmEnabled)

        model.operating.setEsm(true)
        model.operating.applyAutoRunSwitch(!model.config.config.runMode.autoSwitch)
        let autoSwitch: Bool = model.config.config.runMode.autoSwitch
        model.windows.setOpen("defeditor", true)

        #expect(await harness.settings.confirm())

        #expect(!model.config.config.esm.enabled)
        #expect(!model.operating.esmEnabled)
        #expect(model.config.config.runMode.autoSwitch == !autoSwitch)
        #expect(model.operating.autoRunSwitch == !autoSwitch)
        #expect(model.config.config.openWindows.contains("defeditor"))
        let file: AppConfig = await harness.app.savedConfigFlushed()
        #expect(!file.esm.enabled)
        #expect(file.openWindows.contains("defeditor"))
    }

    /// A change of a field the draft does not have, made while the file is being written, is kept: the value is
    /// built again over the live configuration and written once more.
    @Test func aChangeDuringTheWriteIsKept() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        harness.settings.draft = draft
        harness.writer.hold()

        let commit = Task { await harness.settings.confirm() }
        await harness.writer.waitUntilHeld()
        model.windows.setOpen("defeditor", true)
        harness.writer.release()

        #expect(await commit.value)
        #expect(model.config.config.station.call == "OK9ZZZ")
        #expect(model.config.config.openWindows.contains("defeditor"))
        let file: AppConfig = await harness.app.savedConfigFlushed()
        #expect(file.station.call == "OK9ZZZ")
        #expect(file.openWindows.contains("defeditor"))
    }

    /// The second write of a rebased value reports its failure (the commit's own write succeeded).
    @Test func aFailedRewriteAfterARebaseIsShown() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        harness.settings.draft = draft
        harness.writer.hold()

        let commit = Task { await harness.settings.confirm() }
        await harness.writer.waitUntilHeld()
        model.windows.setOpen("defeditor", true)
        // The held write already passed its check; every later write fails.
        harness.writer.setFailing(true)
        harness.writer.release()

        #expect(await commit.value)
        await model.config.flush()
        await Self.drainMainQueue()
        #expect(model.status.message == "Uložení nastavení selhalo: disk full")
        #expect(model.config.config.openWindows.contains("defeditor"))
        // The next save writes the file again and the two agree.
        harness.writer.setFailing(false)
        _ = try await harness.openWithDraft()
        #expect(await harness.settings.confirm())
        let file: AppConfig = await harness.app.savedConfigFlushed()
        #expect(file.openWindows.contains("defeditor"))
        #expect(file == model.config.config)
    }

    /// Critical fix: a blank or whitespace `contestDataDir` reads and writes the band data in the default directory
    /// (`<data>/contest-data`, as `reloadBandData` and the contest data do), never relative to the process
    /// directory — Kotlin's `Path.of("")` would read nothing there and then overwrite the default tables with empty
    /// ones.
    @Test(arguments: ["", "  "])
    func blankContestDataDirUsesTheDefaultDirectory(_ blank: String) async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cwdFiles: [URL] = [cwd.appendingPathComponent("bandplan.yaml"),
                               cwd.appendingPathComponent("digi_frequencies.yaml")]
        let existedBefore: [Bool] = cwdFiles.map { FileManager.default.fileExists(atPath: $0.path) }
        let harness = try await SettingsHarness.make { config, dataDir in
            try FileManager.default.copyItem(at: Fixtures.contestData,
                                             to: dataDir.appendingPathComponent("contest-data"))
            config.contestDataDir = blank
        }
        let defaultDir: URL = harness.app.dataDir.appendingPathComponent("contest-data")
        let segments: [BandPlanFile.Segment] = BandPlanFile.read(defaultDir)
        let table: DigiFreqFile.Table = DigiFreqFile.read(defaultDir)
        #expect(!segments.isEmpty)
        #expect(!table.channels.isEmpty)

        let draft: ConfigurerDraft = try await harness.openWithDraft()
        #expect(draft.bandData().segments == segments)
        #expect(draft.bandData().table == table)
        #expect(draft.contestDataDir == blank)
        #expect(await harness.settings.confirm())

        #expect(harness.model.status.message == "Nastavení uloženo")
        #expect(BandPlanFile.read(defaultDir) == segments)
        #expect(DigiFreqFile.read(defaultDir) == table)
        #expect(cwdFiles.map { FileManager.default.fileExists(atPath: $0.path) } == existedBefore)
        #expect(harness.model.contest.environment.bandPlan.modeAt(1_820_000, .r1) == .cw)
    }

    /// Lets the main queue run what was posted before (`MainHop.post` of a failed write).
    static func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    /// `reloadContestData` only when the directory changed (`contestDirDiffers`), `rescore` only when a scoring
    /// field of the station changed, `callData.reload` after every write.
    @Test func conditionalEffectsFollowThePredicates() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        let scp: Int = model.callData.scpRevision
        let history: Int = model.callData.callHistoryRevision

        _ = try await harness.openWithDraft()
        #expect(await harness.settings.confirm())
        await model.callData.settle()
        #expect(harness.recorder.effects == ConfigEffectPlan.commit(.none, reconnectRig: false, catConnected: false))
        #expect(!harness.recorder.effects.contains(.reloadContestData))
        #expect(!harness.recorder.effects.contains(.rescore))
        #expect(harness.recorder.effects.contains(.saveInner(.callData)))
        #expect(model.callData.scpRevision == scp + 1)
        #expect(model.callData.callHistoryRevision == history + 1)

        let other: URL = harness.app.dataDir.appendingPathComponent("other-data")
        try FileManager.default.copyItem(at: Fixtures.contestData, to: other)
        harness.recorder.effects = []
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.contestDataDir = " " + other.path + " "
        draft.grid = "JN79AA"
        harness.settings.draft = draft
        #expect(await harness.settings.confirm())
        let changes = ConfigChanges(contestDir: true, scoringStation: true)
        #expect(harness.recorder.effects == ConfigEffectPlan.commit(changes, reconnectRig: false, catConnected: false))
        #expect(model.config.config.contestDataDir == other.path)
        #expect(model.contest.environment.dataRoot.path == other.path)
        #expect(model.status.message == "Nastavení uloženo")
    }

    /// The active contest survives the commit (the band data reload keeps it; a changed directory reopens it).
    @Test func theContestStaysOpenAcrossACommit() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        try await harness.app.startCqWwCw()
        let active: String? = model.contest.activeId
        let other: URL = harness.app.dataDir.appendingPathComponent("other-data")
        try FileManager.default.copyItem(at: Fixtures.contestData, to: other)

        _ = try await harness.openWithDraft()
        #expect(await harness.settings.confirm())
        #expect(model.contest.activeId == active)

        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.contestDataDir = other.path
        harness.settings.draft = draft
        #expect(await harness.settings.confirm())
        #expect(model.contest.activeId == active)
        #expect(!model.contest.isActivating)
    }

    /// `writeBandData` into the draft's (new) directory, then `reloadBandData` into the environment; a failed write
    /// overwrites the „saved" status and the plan goes on.
    @Test func bandDataAreWrittenAndReloaded() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        // The first row is R1 CW 1810-1838 kHz.
        #expect(model.contest.environment.bandPlan.modeAt(1_820_000, .r1) == .cw)
        draft.bandSegments.removeFirst()
        harness.settings.draft = draft

        #expect(await harness.settings.confirm())

        #expect(BandPlanFile.read(harness.contestDir) == draft.bandData().segments)
        #expect(DigiFreqFile.read(harness.contestDir) == draft.bandData().table)
        #expect(model.contest.environment.bandPlan.modeAt(1_820_000, .r1) == nil)
        #expect(model.contest.environment.bandPlan.modeAt(1_839_000, .r1) == .digi)

        let blocked: URL = harness.app.dataDir.appendingPathComponent("blocked")
        try Data("x".utf8).write(to: blocked)
        harness.recorder.effects = []
        draft = try await harness.openWithDraft()
        draft.contestDataDir = blocked.path
        harness.settings.draft = draft
        #expect(await harness.settings.confirm())
        #expect(model.status.message.hasPrefix("Uložení bandplánu/digi selhalo: "))
        #expect(harness.recorder.effects.last == .reloadBandData)
    }

    /// Reconnect only with „Uložit a připojit" or a changed rig while CAT is connected; `disconnectFirst` is read
    /// again when the effect runs (the plan sampled it when it was built).
    @Test func reconnectFollowsTheRigAndTheCatState() async throws {
        let harness = try await SettingsHarness.make()
        let recorder: EffectRecorder = harness.recorder

        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.host = "rig.example"
        harness.settings.draft = draft
        #expect(await harness.settings.confirm())
        #expect(recorder.reconnects.isEmpty)

        recorder.catConnected = true
        draft = try await harness.openWithDraft()
        draft.host = "rig2.example"
        harness.settings.draft = draft
        recorder.effects = []
        #expect(await harness.settings.confirm())
        #expect(recorder.effects.last == .reconnectCat(disconnectFirst: true))
        #expect(recorder.reconnects == [true])

        recorder.catConnected = false
        _ = try await harness.openWithDraft()
        #expect(await harness.settings.confirm(reconnectRig: true))
        #expect(recorder.reconnects == [true, false])

        // A changed rig without „Uložit a připojit": decided when the step runs (`CD:609`). CAT drops in the
        // middle of the plan → no reconnect; CAT comes up in the middle of the plan → reconnect with a disconnect.
        recorder.catConnected = true
        recorder.duringCheckClock = { recorder.catConnected = false }
        draft = try await harness.openWithDraft()
        draft.host = "rig3.example"
        harness.settings.draft = draft
        #expect(await harness.settings.confirm())
        #expect(recorder.reconnects == [true, false])
        recorder.catConnected = false
        recorder.duringCheckClock = { recorder.catConnected = true }
        draft = try await harness.openWithDraft()
        draft.host = "rig4.example"
        harness.settings.draft = draft
        #expect(await harness.settings.confirm())
        #expect(recorder.reconnects == [true, false, true])

        // „Uložit a připojit" and CAT drops in the middle of the plan: the disconnect is skipped.
        recorder.catConnected = true
        recorder.duringCheckClock = { recorder.catConnected = false }
        _ = try await harness.openWithDraft()
        #expect(await harness.settings.confirm(reconnectRig: true))
        #expect(recorder.reconnects == [true, false, true, false])
    }

    /// „Odeslat teď" commits and then reports through the port; the window stays open.
    @Test func sendScoreNowCommitsThenReports() async throws {
        let harness = try await SettingsHarness.make()
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        harness.settings.draft = draft

        await harness.settings.sendScoreNow()

        #expect(harness.model.config.config.station.call == "OK9ZZZ")
        #expect(harness.recorder.calls.last == "reportScoreNow")
        #expect(harness.recorder.scoreReports == 1)
        #expect(harness.settings.isOpen)
        #expect(harness.settings.draft != nil)
    }

    /// A close asked while the commit runs (OK, then ⌘Q or the close button) does not drop the accepted OK: the
    /// configuration and the language are written, and the window closes when the commit ends.
    @Test func cancelWhileSavingKeepsTheCommit() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        draft.language = "en"
        harness.settings.draft = draft
        harness.writer.hold()

        let commit = Task { await harness.settings.confirm() }
        await harness.writer.waitUntilHeld()
        harness.settings.cancel()
        #expect(harness.settings.isOpen)
        #expect(harness.settings.draft != nil)
        harness.writer.release()

        #expect(await commit.value)
        #expect(!harness.settings.isOpen)
        #expect(!harness.settings.isSaving)
        #expect(model.config.config.station.call == "OK9ZZZ")
        #expect(model.language.code == "en")
        #expect(harness.app.savedConfig().station.call == "OK9ZZZ")
    }

    /// The close arrives before the language read ended (the window of the old `guard isOpen`).
    @Test func cancelDuringTheLanguageReadKeepsTheCommit() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        draft.language = "en"
        harness.settings.draft = draft

        let commit = Task { await harness.settings.confirm() }
        while !harness.settings.isSaving {
            await Task.yield()
        }
        harness.settings.cancel()

        #expect(await commit.value)
        #expect(!harness.settings.isOpen)
        #expect(model.config.config.station.call == "OK9ZZZ")
        #expect(model.language.code == "en")
        #expect(harness.app.savedConfig().station.call == "OK9ZZZ")
    }

    /// Quitting right after OK waits for the commit and its write. A regression pin: the earlier code already
    /// passed it (`shutdown` awaited the commit task then too); it keeps that wait from being lost later. The write is
    /// held until the quit waits in `settings.settle()`, so a config save the quit enqueues anywhere before that (the
    /// old keyer-shutdown save) lands after the commit's write with the old call — deterministically.
    @Test func shutdownWaitsForTheCommit() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.call = "OK9ZZZ"
        draft.language = "en"
        harness.settings.draft = draft
        harness.writer.hold()

        let commit = Task { await harness.settings.confirm() }
        await harness.writer.waitUntilHeld()
        harness.settings.cancel()
        // No busy wait: the quit reaching `settings.settle()` (or ending, or a bound on the failure path only — the
        // quit blocked behind the held write before the settle) opens the latch; the held write is released either
        // way, so a regression fails instead of spinning forever.
        let reached = FirstOutcome()
        model.beforeSettingsSettle = { reached.open(true) }
        let quit = Task {
            await model.shutdown()
            reached.open(false)
        }
        let bound = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            reached.open(false)
        }
        let atTheSettle: Bool = await reached.value()
        bound.cancel()
        #expect(atTheSettle, "the quit did not wait in settings.settle() while the commit's write was held")
        // The quit is suspended in `settings.settle()` (this test runs only while it waits).
        harness.writer.release()
        await quit.value

        #expect(await commit.value)
        #expect(model.config.config.station.call == "OK9ZZZ")
        #expect(model.language.code == "en")
        #expect(harness.app.savedConfig().station.call == "OK9ZZZ")
    }

    /// An unreadable `bandplan.yaml` reads as an empty plan, so OK overwrites the user's broken file
    /// with an empty table; an empty table means the built-in plan on load.
    @Test func aBrokenBandFileIsOverwrittenWithAnEmptyTable() async throws {
        let harness = try await SettingsHarness.make()
        let file: URL = harness.contestDir.appendingPathComponent("bandplan.yaml")
        let broken = "regions: [unclosed\n\t- : :"
        try Data(broken.utf8).write(to: file)
        #expect(BandPlanFile.read(harness.contestDir).isEmpty)

        let draft: ConfigurerDraft = try await harness.openWithDraft()
        #expect(draft.bandSegments.isEmpty)
        #expect(await harness.settings.confirm())

        let after: String = try String(contentsOf: file, encoding: .utf8)
        #expect(after != broken)
        #expect(BandPlanFile.read(harness.contestDir).isEmpty)
        #expect(harness.model.contest.environment.bandPlan.modeAt(1_820_000, .r1) == .cw)
    }

    /// A second OK while a commit runs is ignored; without a draft there is nothing to commit.
    @Test func overlappingCommitsAreRefused() async throws {
        let harness = try await SettingsHarness.make()
        #expect(await harness.settings.commit(reconnectRig: false) == false)
        _ = try await harness.openWithDraft()
        async let first: Bool = harness.settings.commit(reconnectRig: false)
        let second: Bool = await harness.settings.commit(reconnectRig: false)
        let results: [Bool] = [await first, second]
        #expect(results.filter { $0 }.count == 1)
        #expect(harness.recorder.effects.filter { $0 == .configRevision }.count == 1)
    }

    /// The periodic backup reads `autoBackupMinutes` live, so a committed interval applies without a restart.
    @Test func autoBackupFollowsTheCommittedInterval() async throws {
        let now = TestNow(AutoBackupTests.start)
        let recorder = EffectRecorder()
        let app = try await TestApp.make(now: now, configure: { config, dataDir in
            let copy: URL = dataDir.appendingPathComponent("copied-data")
            try FileManager.default.copyItem(at: Fixtures.contestData, to: copy)
            config.contestDataDir = copy.path
            config.autoBackupMinutes = 0
            config.autoBackupDir = dataDir.appendingPathComponent("auto").path
        }, adjust: { environment in
            environment.settingsServices = recorder.services { nil }
        })
        let dir: URL = app.dataDir.appendingPathComponent("auto")
        now.advance(seconds: 120)
        app.backupClock.advance(by: 60_000)
        await app.model.autoBackup.settle()
        #expect(AutoBackupTests.backups(dir).isEmpty)

        app.model.settings.open()
        await app.model.settings.settle()
        var draft: ConfigurerDraft = try #require(app.model.settings.draft)
        draft.autoBackupMinutes = "1"
        app.model.settings.draft = draft
        #expect(await app.model.settings.confirm())

        now.advance(seconds: 60)
        app.backupClock.advance(by: 60_000)
        await app.model.autoBackup.settle()
        #expect(AutoBackupTests.backups(dir).count == 1)
    }
}

/// The first of several outcomes, awaited without polling: `open` resumes the waiter once; later calls are ignored.
@MainActor
final class FirstOutcome {
    private var result: Bool?
    private var waiter: CheckedContinuation<Bool, Never>?

    func open(_ value: Bool) {
        guard result == nil else { return }
        result = value
        waiter?.resume(returning: value)
        waiter = nil
    }

    func value() async -> Bool {
        if let result {
            return result
        }
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}
