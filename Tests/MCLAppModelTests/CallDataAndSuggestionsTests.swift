import Foundation
import MCLCore
import Observation
import Testing
@testable import MCLAppModel

/// Lets the main queue run what was posted before (`MainHop.post`, observation re-arming).
@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

/// Set from `withObservationTracking`'s `onChange` (any thread).
private final class FiredFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func set() {
        lock.lock()
        fired = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
    }
}

extension Trait where Self == TimeLimitTrait {
    /// A guard against hangs for the gate tests, not a speed measure. `timeLimit` runs from the start of the test and
    /// counts the wait for the main actor: Swift Testing starts all tests at once and the main-actor tests run one after
    /// another, so on CI (3 vCPUs) a test that is not hung takes as long as the whole run (up to ~6.5 min, 5 min was exceeded
    /// with no hang). The bound is therefore above the length of the whole run.
    static var mainActorSafetyNet: Self { .timeLimit(.minutes(30)) }
}

/// `CallDataModel`: `master.scp` and the call history loaded off the main thread, the `master.scp` download
/// (`AS:168-253`) against a local server only.
@MainActor @Suite struct CallDataModelTests {

    private struct Fixture {
        let dir: TempDir
        let config: ConfigModel
        let status: StatusModel
        let model: CallDataModel

        var dataDir: URL { dir.child("data") }
    }

    private static func fixture(scpSource: String = "http://127.0.0.1:9/none",
                                configure: (inout AppConfig, TempDir) throws -> Void = { _, _ in }) throws -> Fixture {
        let dir = try TempDir("mcl-call-data")
        var config = AppConfig()
        try configure(&config, dir)
        try FileManager.default.createDirectory(at: dir.child("data"), withIntermediateDirectories: true)
        let language = LanguageModel(translator: .source, languageDir: dir.child("language"))
        let status = StatusModel(language: language)
        let file: URL = dir.child("data/config.json")
        let configModel = ConfigModel(config: config, store: ConfigStore(file: file), writer: ConfigWriter(file: file),
                                      status: status)
        let model = CallDataModel(config: configModel, status: status, dataDir: dir.child("data"),
                                  scpSource: scpSource)
        return Fixture(dir: dir, config: configModel, status: status, model: model)
    }

    private static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// A `master.scp` the downloader accepts (≥ 1,000 calls).
    private static func masterScp(_ count: Int) -> String {
        var text = "# master.scp test\n"
        for i in 0..<count {
            text += "OK\(i % 10)A\(i)\n"
        }
        return text
    }

    @Test func loadsBothFilesFromTheConfiguredPaths() async throws {
        let fixture = try Self.fixture { config, dir in
            try Self.write("# comment\nok1abc\n DL1XYZ \nOK1ABC\n", to: dir.child("MASTER.SCP"))
            try Self.write("!!Order!!,Call,Name,CQZone\nOK1ABC,Pavel,15\n", to: dir.child("ch.txt"))
            // Kotlin trims the configured paths.
            config.scpFile = " " + dir.child("MASTER.SCP").path + " "
            config.callHistoryFile = dir.child("ch.txt").path
        }
        let model: CallDataModel = fixture.model
        var loaded = 0
        model.onLoaded = { loaded += 1 }
        model.reload()
        await model.settle()
        #expect(model.scp.size == 2)
        #expect(model.scp.contains("DL1XYZ"))
        #expect(model.callHistory.size == 1)
        #expect(model.callHistory.lookup("ok1abc")?["name"] == "Pavel")
        #expect(model.scpRevision == 1)
        #expect(model.callHistoryRevision == 1)
        #expect(loaded == 2)
        #expect(fixture.status.current == nil)
    }

    @Test func missingFilesGiveEmptyDatabases() async throws {
        let fixture = try Self.fixture { config, dir in
            config.scpFile = dir.child("missing.scp").path
            // A directory in place of the file.
            config.callHistoryFile = dir.url.path
        }
        let model: CallDataModel = fixture.model
        model.reload()
        await model.settle()
        #expect(model.scp.size == 0)
        #expect(model.callHistory.size == 0)
        #expect(model.scpRevision == 1)
        #expect(model.callHistoryRevision == 1)
        #expect(fixture.status.current == nil)
    }

    @Test func blankPathsGiveEmptyDatabases() async throws {
        let fixture = try Self.fixture()
        fixture.model.reload()
        await fixture.model.settle()
        #expect(fixture.model.scp.size == 0)
        #expect(fixture.model.callHistory.size == 0)
    }

    /// A UTF-8 BOM keeps the Java defect (the BOM header becomes a call record) and no warning is shown.
    @Test func callHistoryWithBomKeepsTheJavaDefectWithoutWarning() async throws {
        let fixture = try Self.fixture { config, dir in
            let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("!!Order!!,Call,Name,Exch1\r\nok1abc,Pavel,15\r\n".utf8)
            try Data(bytes).write(to: dir.child("bom.txt"))
            config.callHistoryFile = dir.child("bom.txt").path
        }
        let model: CallDataModel = fixture.model
        model.reloadCallHistory()
        await model.settle()
        #expect(model.callHistory.size == 2)
        #expect(model.callHistory.lookup("\u{FEFF}!!order!!")?["name"] == "Call")
        // The default column order stays: Pavel lands in `name`, 15 in `loc1`.
        #expect(model.callHistory.lookup("OK1ABC")?["loc1"] == "15")
        #expect(fixture.status.current == nil)
    }

    /// The last started load wins even when an older one finishes later.
    @Test func newerLoadWins() async throws {
        let fixture = try Self.fixture { config, dir in
            try Self.write("OK1AAA\n", to: dir.child("a.scp"))
            try Self.write("OK1BBB\nOK1CCC\n", to: dir.child("b.scp"))
            config.scpFile = dir.child("a.scp").path
        }
        let model: CallDataModel = fixture.model
        model.reloadScp()
        fixture.config.config.scpFile = fixture.dir.child("b.scp").path
        model.reloadScp()
        await model.settle()
        #expect(model.scp.size == 2)
        #expect(model.scp.contains("OK1BBB"))
        #expect(model.scpRevision == 1)
    }

    @Test func pathChangeReloads() async throws {
        let fixture = try Self.fixture { config, dir in
            try Self.write("OK1AAA\n", to: dir.child("a.scp"))
            try Self.write("OK1BBB\nOK1CCC\n", to: dir.child("b.scp"))
            try Self.write("OK1ABC,Pavel\n", to: dir.child("ch.txt"))
            config.scpFile = dir.child("a.scp").path
        }
        let model: CallDataModel = fixture.model
        model.reload()
        model.observePaths()
        await model.settle()
        #expect(model.scp.size == 1)
        // Another config change (not a path) reloads nothing.
        fixture.config.config.station.call = "OK1XOE"
        await drainMainQueue()
        await model.settle()
        #expect(model.scpRevision == 1)
        #expect(model.callHistoryRevision == 1)
        fixture.config.config.scpFile = fixture.dir.child("b.scp").path
        await drainMainQueue()
        await model.settle()
        #expect(model.scp.size == 2)
        #expect(model.scpRevision == 2)
        #expect(model.callHistoryRevision == 1)
        // The observation is re-armed.
        fixture.config.config.callHistoryFile = fixture.dir.child("ch.txt").path
        await drainMainQueue()
        await model.settle()
        #expect(model.callHistory.size == 1)
        #expect(model.callHistoryRevision == 2)
    }

    @Test func downloadWithoutConfiguredFileUsesTheDataDirectory() async throws {
        let server = try LocalHttpServer(routes: ["/MASTER.SCP": .init(body: Self.masterScp(1500))])
        defer { server.stop() }
        let fixture = try Self.fixture(scpSource: server.url("/MASTER.SCP"))
        let model: CallDataModel = fixture.model
        model.downloadScp()
        #expect(fixture.status.message == "Stahuji master.scp…")
        await model.settle()
        let target: String = fixture.dataDir.appendingPathComponent("MASTER.SCP").path
        #expect(fixture.status.message == "master.scp stažen: 1500 volaček → " + target)
        #expect(fixture.config.config.scpFile == target)
        #expect(model.scp.size == 1500)
        #expect(model.scp.contains("OK3A3"))
        #expect(server.requestedPaths == ["/MASTER.SCP"])
        await fixture.config.flush()
        let saved = ConfigStore(file: fixture.dataDir.appendingPathComponent("config.json")).load()
        #expect(saved.scpFile == target)
    }

    @Test func downloadIntoTheConfiguredFile() async throws {
        let server = try LocalHttpServer(routes: ["/MASTER.SCP": .init(body: Self.masterScp(1200))])
        defer { server.stop() }
        let fixture = try Self.fixture(scpSource: server.url("/MASTER.SCP")) { config, dir in
            try Self.write("OLD1\n", to: dir.child("my.scp"))
            config.scpFile = dir.child("my.scp").path
        }
        let model: CallDataModel = fixture.model
        model.reload()
        await model.settle()
        #expect(model.scp.size == 1)
        model.downloadScp()
        await model.settle()
        let target: String = fixture.dir.child("my.scp").path
        #expect(fixture.status.message == "master.scp stažen: 1200 volaček → " + target)
        #expect(fixture.config.config.scpFile == target)
        #expect(model.scp.size == 1200)
    }

    @Test func failedDownloadKeepsTheOldFile() async throws {
        let server = try LocalHttpServer(routes: ["/error.html": .init(body: "<html><body>Not here</body></html>")])
        defer { server.stop() }
        let fixture = try Self.fixture(scpSource: server.url("/MASTER.SCP")) { config, dir in
            try Self.write("OLD1\n", to: dir.child("my.scp"))
            config.scpFile = dir.child("my.scp").path
        }
        let model: CallDataModel = fixture.model
        model.reload()
        await model.settle()
        model.downloadScp()
        await model.settle()
        #expect(fixture.status.message == "Stažení master.scp selhalo: Server vrátil HTTP 404")
        #expect(model.scp.size == 1)
        #expect(model.scpRevision == 1)
        let old = try String(contentsOf: fixture.dir.child("my.scp"), encoding: .utf8)
        #expect(old == "OLD1\n")
    }

    @Test func downloadOfSomethingElseIsRejected() async throws {
        let server = try LocalHttpServer(routes: ["/MASTER.SCP": .init(body: "<html><body>Not here</body></html>")])
        defer { server.stop() }
        let fixture = try Self.fixture(scpSource: server.url("/MASTER.SCP"))
        fixture.model.downloadScp()
        await fixture.model.settle()
        #expect(fixture.status.message == "Stažení master.scp selhalo: "
            + "Stažený soubor nevypadá jako master.scp (0 volaček, 1 jiných řádků) — ponechávám původní")
        #expect(fixture.config.config.scpFile == "")
        #expect(!FileManager.default.fileExists(atPath: fixture.dataDir.appendingPathComponent("MASTER.SCP").path))
    }
}

/// `SuggestionsModel` over a running CQ WW CW contest (`EP:271-295, 623-669, 1193-1246`).
@MainActor @Suite struct SuggestionsModelTests {

    /// The entry form the model reads and the prefill writes (stands in for the entry window).
    @MainActor private final class FormBox {
        var form = EntryForm()
        var sinks = 0
    }

    private struct Fixture {
        let app: TestApp
        let callData: CallDataModel
        let model: SuggestionsModel
        let clock: ManualClock
        let box: FormBox
    }

    private static func fixture(scp: String = "", callHistory: String = "", contest: Bool = true) async throws
        -> Fixture {
        let app = try await TestApp.make { config, dataDir in
            if !scp.isEmpty {
                let url: URL = dataDir.appendingPathComponent("MASTER.SCP")
                try Data(scp.utf8).write(to: url)
                config.scpFile = url.path
            }
            if !callHistory.isEmpty {
                let url: URL = dataDir.appendingPathComponent("CALLHISTORY.txt")
                try Data(callHistory.utf8).write(to: url)
                config.callHistoryFile = url.path
            }
        }
        if contest {
            try await app.startCqWwCw()
        }
        let model: AppModel = app.model
        let callData = CallDataModel(config: model.config, status: model.status, dataDir: app.dataDir)
        callData.reload()
        await callData.settle()
        let clock = ManualClock()
        let suggestions = SuggestionsModel(callData: callData, logbook: model.logbook, contest: model.contest,
                                           clock: clock)
        let box = FormBox()
        suggestions.formSource = { box.form }
        suggestions.formSink = { form in
            box.form = form
            box.sinks += 1
        }
        return Fixture(app: app, callData: callData, model: suggestions, clock: clock, box: box)
    }

    private static let scpCalls = "OK1ABC\nOK1ABD\nOK1XYZ\nDL1ABC\nOK2ABC\n"

    private func type(_ call: String, _ fixture: Fixture) async {
        fixture.box.form.call = call
        fixture.model.refresh()
        await fixture.model.settle()
    }

    @Test func partialAndNPlusOneMatchTheCore() async throws {
        let fixture = try await Self.fixture(scp: Self.scpCalls)
        await fixture.app.logContestQso(call: "OK1ABE", zone: "15")
        await type("OK1AB", fixture)
        let scp: ScpDatabase = fixture.callData.scp
        let expected = EntrySuggestions.partial(query: "OK1AB", logCalls: ["OK1ABE"], spotCalls: [], scp: scp)
        #expect(fixture.model.partial == expected)
        #expect(fixture.model.suggestions == ["OK1ABE", "OK1ABC", "OK1ABD"])
        #expect(fixture.model.partial.first?.source == .LOG)
        await type("OK1ABX", fixture)
        #expect(fixture.model.nPlusOne == ["OK1ABC", "OK1ABD", "OK1ABE"])
        #expect(fixture.model.isLogged("OK1ABE"))
        #expect(!fixture.model.isLogged("OK1ABC"))
        // Too short: nothing.
        await type("O", fixture)
        #expect(fixture.model.partial.isEmpty)
        #expect(fixture.model.nPlusOne.isEmpty)
    }

    /// The Settings switches: an off function is not computed (so its keys find nothing to pick), its row is
    /// hidden, and the other one keeps working.
    @Test func switchesTurnTheFunctionsOffIndependently() async throws {
        let fixture = try await Self.fixture(scp: Self.scpCalls)
        let model: SuggestionsModel = fixture.model
        #expect(model.showsScpRow && model.showsNPlusOneRow)
        fixture.app.model.config.config.scpSuggestionsEnabled = false
        #expect(!model.showsScpRow && model.showsNPlusOneRow)
        await type("OK1ABX", fixture)
        #expect(model.partial.isEmpty && model.suggestions.isEmpty)
        #expect(!model.moveScpPick(1))
        #expect(model.takeSuggestion(0) == nil)
        #expect(model.nPlusOne == ["OK1ABC", "OK1ABD"])
        // Back on: Check partial returns, the highlight works; N+1 off now.
        fixture.app.model.config.config.scpSuggestionsEnabled = true
        fixture.app.model.config.config.nPlusOneEnabled = false
        #expect(model.showsScpRow && !model.showsNPlusOneRow)
        await type("OK1AB", fixture)
        #expect(model.suggestions == ["OK1ABC", "OK1ABD"])
        #expect(model.moveScpPick(1))
        #expect(model.nPlusOne.isEmpty)
        await type("OK1ABX", fixture)
        #expect(model.nPlusOne.isEmpty)
    }

    /// The keyboard goes through `suggestions()` of the entry: with Check partial off, Alt+Y has nothing to take.
    @Test func switchingOffClearsShownSuggestionsAtOnce() async throws {
        let fixture = try await Self.fixture(scp: Self.scpCalls)
        await type("OK1AB", fixture)
        #expect(!fixture.model.suggestions.isEmpty)
        fixture.app.model.config.config.scpSuggestionsEnabled = false
        fixture.model.refresh()
        await fixture.model.settle()
        #expect(fixture.model.suggestions.isEmpty)
        #expect(fixture.model.scpPick == -1)
    }

    /// Records which background jobs reached the main thread and parks the chosen ones until released — waits are
    /// event-based (no polling); the time limit only turns a regression into a failure instead of a hang.
    @MainActor private final class JobGate {
        private let held: [SuggestionsModel.Job]
        private var reached: [SuggestionsModel.Job] = []
        private var waiters: [(job: SuggestionsModel.Job, continuation: CheckedContinuation<Void, Never>)] = []
        private var parked: [(job: SuggestionsModel.Job, continuation: CheckedContinuation<Void, Never>)] = []

        init(holding held: [SuggestionsModel.Job]) {
            self.held = held
        }

        func hook(_ job: SuggestionsModel.Job) async {
            reached.append(job)
            let ready = waiters.filter { $0.job == job }
            waiters.removeAll { $0.job == job }
            for waiter in ready {
                waiter.continuation.resume()
            }
            if held.contains(job) {
                await withCheckedContinuation { parked.append((job, $0)) }
            }
        }

        /// Returns once `job` reached the main thread (a held job is parked by then, another one adopted).
        func reached(_ job: SuggestionsModel.Job) async {
            if reached.contains(job) {
                return
            }
            await withCheckedContinuation { waiters.append((job, $0)) }
        }

        func release(_ job: SuggestionsModel.Job) {
            let ready = parked.filter { $0.job == job }
            parked.removeAll { $0.job == job }
            for entry in ready {
                entry.continuation.resume()
            }
        }
    }

    /// A late result for an older call is dropped (generation).
    @Test(.mainActorSafetyNet) func staleGenerationIsDropped() async throws {
        let fixture = try await Self.fixture(scp: Self.scpCalls)
        let model: SuggestionsModel = fixture.model
        let gate = JobGate(holding: [.partial(generation: 1)])
        model.beforeAdopt = { await gate.hook($0) }
        fixture.box.form.call = "OK1"
        model.refresh()
        await gate.reached(.partial(generation: 1))
        fixture.box.form.call = "DL1"
        model.refresh()
        await gate.reached(.partial(generation: 2))
        #expect(model.suggestions == ["DL1ABC"])
        gate.release(.partial(generation: 1))
        await model.settle()
        #expect(model.partialGeneration == 2)
        #expect(model.suggestions == ["DL1ABC"])
    }

    /// Worked-before has its own generation: a late result for an older call is dropped.
    @Test(.mainActorSafetyNet) func staleWorkedBeforeIsDropped() async throws {
        let fixture = try await Self.fixture()
        await fixture.app.logContestQso(call: "DL1ABC", zone: "14")
        let model: SuggestionsModel = fixture.model
        let gate = JobGate(holding: [.workedBefore(generation: 1)])
        model.beforeAdopt = { await gate.hook($0) }
        fixture.box.form.call = "DL1ABC"
        model.refresh()
        await gate.reached(.workedBefore(generation: 1))
        fixture.box.form.call = "OK1XYZ"
        model.refresh()
        await gate.reached(.workedBefore(generation: 2))
        #expect(model.workedBefore == nil)
        gate.release(.workedBefore(generation: 1))
        await model.settle()
        #expect(model.workedGeneration == 2)
        #expect(model.workedBefore == nil)
        // The same call again is computed and adopted.
        await type("DL1ABC", fixture)
        #expect(model.workedBefore?.count == 1)
    }

    /// Adopting results inside `observe()`'s tracking does not register the model's own outputs as inputs.
    @Test func adoptingDoesNotObserveTheOutputs() async throws {
        let fixture = try await Self.fixture(scp: Self.scpCalls,
                                             callHistory: "!!Order!!,Call,CQZone\nDL1ABC,14\n")
        let model: SuggestionsModel = fixture.model
        fixture.box.form.editContestField("zone", "14")
        await type("OK1AB", fixture)
        await type("DL1ABC", fixture)
        #expect(!model.suggestions.isEmpty)
        #expect(model.workedBefore == nil)
        // A short call adopts empty suggestions and the reverse lookup synchronously, within the tracking (the
        // observers are installed after it, so only reads there count).
        fixture.box.form.call = ""
        let fired = FiredFlag()
        withObservationTracking {
            model.refresh()
        } onChange: {
            fired.set()
        }
        #expect(model.suggestions.isEmpty)
        #expect(model.reverse == ["DL1ABC"])
        // Later adoptions write the outputs again; they were not read as inputs, so the tracking stays quiet.
        await type("OK1AB", fixture)
        #expect(!model.suggestions.isEmpty)
        #expect(model.reverse.isEmpty)
        #expect(!fired.value)
    }

    /// A contest activation (`contest.activeId`, a Kotlin key) restarts the prefill delay.
    @Test func contestChangeRetriggersTheFill() async throws {
        let fixture = try await Self.fixture(callHistory: "!!Order!!,Call,CQZone\nDL1ABC,14\n", contest: false)
        let model: SuggestionsModel = fixture.model
        fixture.box.form.call = "DL1ABC"
        model.refresh()
        // Past the callbook pause too (700 ms, its own timer).
        fixture.clock.advance(by: 700)
        #expect(fixture.box.sinks == 0)
        model.refresh()
        #expect(fixture.clock.pendingCount == 0)
        try await fixture.app.startCqWwCw()
        model.refresh()
        #expect(fixture.clock.pendingCount == 1)
        fixture.clock.advance(by: 250)
        #expect(fixture.box.form.contestExchange["zone"] == "14")
        #expect(model.chFilled["zone"] == "14")
    }

    @Test func pickFollowsTheKotlinKeys() async throws {
        let fixture = try await Self.fixture(scp: Self.scpCalls)
        let model: SuggestionsModel = fixture.model
        #expect(!model.moveScpPick(1))
        await type("OK1AB", fixture)
        #expect(model.suggestions == ["OK1ABC", "OK1ABD"])
        #expect(model.moveScpPick(1))
        #expect(model.moveScpPick(1))
        #expect(model.moveScpPick(1))
        #expect(model.scpPick == 1)
        #expect(model.moveScpPick(-1))
        #expect(model.scpPick == 0)
        // The same list again keeps the highlight.
        fixture.callData.reloadScp()
        await fixture.callData.settle()
        model.refresh()
        await model.settle()
        #expect(model.scpPick == 0)
        // A changed list drops it.
        await type("OK1ABD", fixture)
        #expect(model.suggestions == ["OK1ABD"])
        #expect(model.scpPick == -1)
        #expect(model.moveScpPick(1))
        #expect(model.takeSuggestion(0) == "OK1ABD")
        #expect(model.scpPick == -1)
        #expect(model.takeSuggestion(5) == nil)
        #expect(model.moveScpPick(1))
        #expect(model.clearScpPick())
        #expect(!model.clearScpPick())
        #expect(model.moveScpPick(-1))
        #expect(model.scpPick == -1)
    }

    /// `LaunchedEffect(call, …) { delay(250) … }`: only the last call within 250 ms fills.
    @Test func callHistoryFillIsDebounced() async throws {
        let fixture = try await Self.fixture(callHistory: "!!Order!!,Call,CQZone\nDL1ABC,14\nDL1ABD,28\n")
        let model: SuggestionsModel = fixture.model
        fixture.box.form.call = "DL1ABC"
        model.refresh()
        fixture.clock.advance(by: 249)
        #expect(fixture.box.form.contestExchange["zone"] == nil)
        // A new call restarts the delay.
        fixture.box.form.call = "DL1ABD"
        model.refresh()
        fixture.clock.advance(by: 249)
        #expect(fixture.box.sinks == 0)
        // An unchanged call does not.
        model.refresh()
        fixture.clock.advance(by: 1)
        #expect(fixture.box.form.contestExchange["zone"] == "28")
        #expect(model.chFilled["zone"] == "28")
        #expect(fixture.box.sinks == 1)
        // Only the callbook pause of the last call is left.
        #expect(fixture.clock.pendingCount == 1)
        fixture.clock.advance(by: 700)
        #expect(fixture.clock.pendingCount == 0)
    }

    /// What the call history filled goes away with the call; what the operator overwrote stays.
    @Test func filledValuesAreTakenBack() async throws {
        let fixture = try await Self.fixture(callHistory: "!!Order!!,Call,CQZone\nDL1ABC,14\nDL1ABD,14\n")
        let model: SuggestionsModel = fixture.model
        fixture.box.form.call = "DL1ABC"
        model.refresh()
        fixture.clock.advance(by: 250)
        #expect(fixture.box.form.contestExchange["zone"] == "14")
        // The same value for the next call stays filled.
        fixture.box.form.call = "DL1ABD"
        model.refresh()
        fixture.clock.advance(by: 250)
        #expect(fixture.box.form.contestExchange["zone"] == "14")
        #expect(model.chFilled["zone"] == "14")
        // A call without a record: the value is taken back.
        fixture.box.form.call = "DL1ZZZ"
        model.refresh()
        fixture.clock.advance(by: 250)
        #expect(fixture.box.form.contestExchange["zone"] == nil)
        #expect(model.chFilled.isEmpty)
        // Overwritten by the operator: kept, but forgotten.
        fixture.box.form.call = "DL1ABC"
        model.refresh()
        fixture.clock.advance(by: 250)
        fixture.box.form.editContestField("zone", "15")
        fixture.box.form.call = ""
        model.refresh()
        fixture.clock.advance(by: 250)
        #expect(fixture.box.form.contestExchange["zone"] == "15")
        #expect(model.chFilled.isEmpty)
    }

    @Test func noFillOutsideAContestOrForShortCalls() async throws {
        let fixture = try await Self.fixture(callHistory: "!!Order!!,Call,CQZone\nDL1,14\n", contest: false)
        fixture.box.form.call = "DL1"
        fixture.model.refresh()
        fixture.clock.advance(by: 250)
        #expect(fixture.box.sinks == 0)
        #expect(fixture.box.form.contestExchange.isEmpty)
    }

    /// A reloaded call history restarts the delay (Kotlin key `state.callHistory`).
    @Test func reloadedCallHistoryRefills() async throws {
        let fixture = try await Self.fixture(callHistory: "!!Order!!,Call,CQZone\nDL1ABC,14\n")
        let model: SuggestionsModel = fixture.model
        fixture.box.form.call = "DL1ABC"
        model.refresh()
        // Past the callbook pause too (700 ms, its own timer).
        fixture.clock.advance(by: 700)
        #expect(fixture.box.sinks == 1)
        fixture.callData.reloadCallHistory()
        await fixture.callData.settle()
        model.refresh()
        #expect(fixture.clock.pendingCount == 1)
        fixture.clock.advance(by: 250)
        #expect(fixture.box.sinks == 2)
    }

    @Test func reverseLookupNeedsABlankCallAndAnExchange() async throws {
        let fixture = try await Self.fixture(callHistory: "!!Order!!,Call,CQZone\nDL1ABC,14\nDL2XYZ,14\nOK1ABC,15\n")
        let model: SuggestionsModel = fixture.model
        model.refresh()
        #expect(model.reverse.isEmpty)
        fixture.box.form.editContestField("zone", "14")
        model.refresh()
        #expect(model.reverse == CallHistoryFill.reverse(callHistory: fixture.callData.callHistory,
                                                         form: fixture.box.form,
                                                         fields: fixture.app.model.contest.exchangeFields(call: ""),
                                                         contestActive: true))
        #expect(model.reverse == ["DL1ABC", "DL2XYZ"])
        fixture.box.form.call = "D"
        model.refresh()
        #expect(model.reverse.isEmpty)
    }

    @Test func workedBeforeOverTheLog() async throws {
        let fixture = try await Self.fixture()
        await fixture.app.logContestQso(call: "DL1ABC", zone: "14", freqKHz: "14025")
        await fixture.app.logContestQso(call: "DL1ABC", zone: "14", freqKHz: "7025")
        await type("DL", fixture)
        #expect(fixture.model.workedBefore == nil)
        await type("DL1ABC", fixture)
        let result: WorkedBefore.Result = try #require(fixture.model.workedBefore)
        #expect(result.count == 2)
        let order: [String] = fixture.app.model.contest.runtime.bandOrder.compactMap { $0 }
        #expect(result == WorkedBefore.of(qsos: fixture.app.model.logbook.rows, call: "DL1ABC", bandOrder: order))
        #expect(result.bands.filter(\.worked).map(\.band) == ["40m", "20m"])
        await type("DL1ABD", fixture)
        #expect(fixture.model.workedBefore == nil)
    }

    /// Kotlin `remember(state.qsos.size)`: the log calls follow the QSO count.
    @Test func newQsoRefreshesSuggestions() async throws {
        let fixture = try await Self.fixture()
        await type("DL1AB", fixture)
        #expect(fixture.model.suggestions.isEmpty)
        await fixture.app.logContestQso(call: "DL1ABC", zone: "14")
        fixture.model.refresh()
        await fixture.model.settle()
        #expect(fixture.model.suggestions == ["DL1ABC"])
    }

    @Test func observationFollowsTheInputs() async throws {
        let fixture = try await Self.fixture()
        fixture.model.observe()
        await fixture.model.settle()
        #expect(fixture.model.suggestions.isEmpty)
        // A QSO logged elsewhere: the observed log rows change.
        fixture.box.form.call = "DL1AB"
        await fixture.app.logContestQso(call: "DL1ABC", zone: "14")
        await drainMainQueue()
        await fixture.model.settle()
        #expect(fixture.model.suggestions == ["DL1ABC"])
    }
}

/// The values the info strip's sources read: a lock-guarded box, so the `@Sendable` source closures capture a
/// reference instead of mutable locals.
private final class InfoStripState: @unchecked Sendable {
    private let lock = NSLock()
    private var values: (county: [String], repeating: Bool, post: Bool)

    init(county: [String], repeating: Bool, post: Bool) {
        values = (county, repeating, post)
    }

    var county: [String] { lock.withLock { values.county } }
    var repeating: Bool { lock.withLock { values.repeating } }
    var post: Bool { lock.withLock { values.post } }

    func set(county: [String], repeating: Bool, post: Bool) {
        lock.withLock { values = (county, repeating, post) }
    }
}

/// `InfoStripModel` (`EP:1271-1307`) from the local states.
@MainActor @Suite struct InfoStripModelTests {

    @Test func emptyWithoutItems() async throws {
        let app = try await TestApp.make()
        let strip = InfoStripModel(contest: app.model.contest, config: app.model.config, language: app.model.language)
        #expect(strip.items.isEmpty)
        #expect(strip.text == "")
    }

    @Test func itemsInKotlinOrder() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let strip = InfoStripModel(contest: app.model.contest, config: app.model.config, language: app.model.language)
        let state = InfoStripState(county: ["ABC", "DEF"], repeating: true, post: true)
        strip.sources.countyLine = { state.county }
        strip.sources.cqRepeat = { state.repeating }
        strip.sources.postContest = { state.post }
        app.model.config.config.runMode.repeatSeconds = 2.5
        #expect(strip.text == " County line ABC/DEF · RPT 2.5 s · DODATEČNÉ ZADÁNÍ")
        #expect(strip.input.tour == nil)
        #expect(strip.input.recording == nil)
        #expect(strip.input.snsWaiting == nil)
        state.set(county: [], repeating: false, post: false)
        #expect(strip.text == "")
    }

    @Test func tourAndBonusFromTheContestRuntime() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        // 2026-11-28 12:10Z: inside the 1200/30 session, which ends at 12:30Z.
        let now = Date(timeIntervalSince1970: 1_795_867_800)
        let strip = InfoStripModel(contest: app.model.contest, config: app.model.config, language: app.model.language,
                                   now: { now })
        let tour: Tour = try #require(Tour.parse("1200/30"))
        app.model.contest.runtime.setSessionExtras(tour: tour, bonusStations: ["W1AW", "K1ABC"])
        #expect(strip.text == " TOUR " + tour.format() + " do 1230Z · Bonus 2")
        // The rover QTH only for a contest that uses it (CQ WW does not).
        app.model.config.config.station.roverQth = "ABC"
        #expect(strip.text == " TOUR " + tour.format() + " do 1230Z · Bonus 2")
        #expect(!strip.input.usesRoverQth)
        #expect(strip.input.roverQth == "ABC")
    }

    @Test func translatedItemsFollowTheLanguage() async throws {
        let app = try await TestApp.make()
        let strip = InfoStripModel(contest: app.model.contest, config: app.model.config, language: app.model.language)
        strip.sources.postContest = { true }
        #expect(strip.text == " DODATEČNÉ ZADÁNÍ")
        let file: URL = app.dir.child("lang_en.json")
        try Data(#"{"DODATEČNÉ ZADÁNÍ": "POST-CONTEST ENTRY"}"#.utf8).write(to: file)
        app.model.language.apply(Translator(language: "en", translations: LanguageCatalog.load(file)))
        #expect(strip.text == " POST-CONTEST ENTRY")
    }
}
