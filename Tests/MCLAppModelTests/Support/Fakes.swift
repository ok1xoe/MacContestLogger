import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// A temporary directory removed at the end of the test.
final class TempDir: @unchecked Sendable {
    let url: URL

    init(_ prefix: String = "mcl-app-model") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func child(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }
}

/// A clock advanced by hand: `schedule` records the action, `advance` fires what became due.
@MainActor
final class ManualClock: RescoreClock {

    private final class Timer: RescoreTimer {
        let due: Int
        let fire: @MainActor @Sendable () -> Void
        var cancelled = false

        init(due: Int, fire: @escaping @MainActor @Sendable () -> Void) {
            self.due = due
            self.fire = fire
        }

        func cancel() {
            cancelled = true
        }
    }

    private(set) var now: Int = 0
    private var timers: [Timer] = []

    func schedule(afterMilliseconds delay: Int, _ fire: @escaping @MainActor @Sendable () -> Void) -> any RescoreTimer {
        let timer = Timer(due: now + delay, fire: fire)
        timers.append(timer)
        return timer
    }

    /// Moves the time forward and fires the due, not cancelled actions in order.
    func advance(by milliseconds: Int) {
        now += milliseconds
        let due: [Timer] = timers.filter { $0.due <= now }
        timers.removeAll { $0.due <= now }
        for timer in due where !timer.cancelled {
            timer.fire()
        }
    }

    var pendingCount: Int {
        timers.filter { !$0.cancelled }.count
    }
}

/// Fixtures of the core tests, read from the source tree (this target has no resources of its own).
enum Fixtures {

    static let coreFixtures: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MCLCoreTests/Fixtures", isDirectory: true)

    /// `contest-data/` (read only).
    static var contestData: URL {
        coreFixtures.appendingPathComponent("contest-data", isDirectory: true)
    }

    static var configV111: URL {
        coreFixtures.appendingPathComponent("config-v1.1.1.json")
    }

    /// A DXCC directory with the test `dxcc.json` in `dir`.
    static func dxccDir(in dir: TempDir) throws -> URL {
        let target: URL = dir.child("dxcc-json")
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: coreFixtures.appendingPathComponent("dxcc-test.json"),
                                         to: target.appendingPathComponent("dxcc.json"))
        return target
    }
}

/// A time a test moves by hand (read off the main thread too).
final class TestNow: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var date: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// An app over a temporary data directory (never the user's).
@MainActor
struct TestApp {
    let dir: TempDir
    let model: AppModel
    let rescoreClock: ManualClock
    let geometryClock: ManualClock
    /// The call history prefill delay.
    let suggestionClock: ManualClock
    /// The periodic automatic backup.
    let backupClock: ManualClock
    /// The definition editor's check delay.
    let editorClock: ManualClock

    var dataDir: URL { dir.child("data") }

    /// Writes `config.json` (after `configure`) and bootstraps.
    static func make(withDxcc: Bool = true, appVersion: String? = nil,
                     fixedNow: Date? = nil, now: TestNow? = nil,
                     definitionSource: DataToolsModel.DefinitionSource? = nil,
                     configure: (inout AppConfig, URL) throws -> Void = { _, _ in },
                     adjust: (inout AppModel.Environment) -> Void = { _ in })
        async throws -> TestApp {
        let dir = try TempDir()
        let dataDir: URL = dir.child("data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        var config = AppConfig()
        config.contestDataDir = Fixtures.contestData.path
        config.station.call = "OK1XOE"
        try configure(&config, dataDir)
        try ConfigWriter.writeFile(config, to: dataDir.appendingPathComponent("config.json"))
        let rescore = ManualClock()
        let geometry = ManualClock()
        let suggestion = ManualClock()
        let backup = ManualClock()
        let editor = ManualClock()
        let clock: @Sendable () -> Date
        if let now {
            clock = { now.date }
        } else if let fixedNow {
            clock = { fixedNow }
        } else {
            clock = { Date() }
        }
        var environment = AppModel.Environment(
            dataDir: dataDir, dxccDir: withDxcc ? try Fixtures.dxccDir(in: dir) : nil, decimalSeparator: ",",
            rescoreClock: rescore, geometryClock: geometry,
            now: clock, appVersion: appVersion, suggestionClock: suggestion, backupClock: backup,
            definitionSource: definitionSource ?? DataToolsModel.DefinitionSource(fetcher: UnreachableFetcher()),
            definitionCheckClock: editor)
        adjust(&environment)
        let model = try await AppModel.bootstrap(environment)
        return TestApp(dir: dir, model: model, rescoreClock: rescore, geometryClock: geometry,
                       suggestionClock: suggestion, backupClock: backup, editorClock: editor)
    }

    /// Creates and starts CQ WW CW.
    func startCqWwCw() async throws {
        var setup = ContestSetup()
        setup.sentExchange = ["zone": "15"]
        let started: Bool = await model.contest.createAndStart(definitionId: "cq-ww-cw", setup: setup)
        try #require(started, "activation failed: \(model.status.message)")
    }

    /// Types and submits one contest QSO, then waits for it to be stored.
    func logContestQso(call: String, zone: String, freqKHz: String = "14025") async {
        let entry: EntryModel = model.entry
        entry.setFrequency(freqKHz)
        entry.callChanged(call)
        entry.editContestField("zone", zone)
        entry.submit()
        await entry.settle()
    }

    /// The config file after the pending writes.
    func savedConfigFlushed() async -> AppConfig {
        await model.config.flush()
        return savedConfig()
    }

    /// The config file as saved.
    func savedConfig() -> AppConfig {
        ConfigStore(file: dataDir.appendingPathComponent("config.json")).load()
    }
}

/// The definition fetcher of tests that do not set one up: it never reaches the network.
struct UnreachableFetcher: DataFetcher {
    func fetch(_ url: URL) async throws -> (status: Int, data: Data) {
        throw URLError(.notConnectedToInternet)
    }
}
