import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The periodic automatic backup (Kotlin `AS:2041-2078`).
@MainActor @Suite struct AutoBackupTests {

    /// What the loop looked like inside the switch.
    @MainActor final class SwitchState {
        var running: Bool?
        var pending: Int?
    }

    static let start = Date(timeIntervalSince1970: 1_764_417_600)

    static func backups(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".sqlite") }
    }

    /// The loop ticks every 60 s of its clock, the next tick only after the previous one finished; `stop` ends it.
    @Test func loopTicksEveryMinuteUntilStopped() async {
        let clock = ManualClock()
        var ticks: Int = 0
        let loop = AutoBackupLoop(clock: clock) {
            ticks += 1
        }
        loop.start()
        loop.start()
        #expect(clock.pendingCount == 1)
        clock.advance(by: 59_999)
        await loop.settle()
        #expect(ticks == 0)
        clock.advance(by: 1)
        await loop.settle()
        #expect(ticks == 1)
        #expect(clock.pendingCount == 1)
        clock.advance(by: 60_000)
        await loop.settle()
        #expect(ticks == 2)
        await loop.stop()
        #expect(!loop.isRunning)
        #expect(clock.pendingCount == 0)
        clock.advance(by: 600_000)
        await loop.settle()
        #expect(ticks == 2)
        loop.start()
        clock.advance(by: 60_000)
        await loop.settle()
        #expect(ticks == 3)
        await loop.stop()
    }

    /// `stop` waits for a tick in flight and no tick follows it.
    @Test func stopWaitsForTheTickInFlight() async {
        let clock = ManualClock()
        var finished: Bool = false
        var gate: CheckedContinuation<Void, Never>?
        let loop = AutoBackupLoop(clock: clock) {
            await withCheckedContinuation { gate = $0 }
            finished = true
        }
        loop.start()
        clock.advance(by: 60_000)
        while gate == nil {
            await Task.yield()
        }
        let stopping = Task { @MainActor in
            await loop.stop()
            return finished
        }
        gate?.resume()
        #expect(await stopping.value)
        #expect(clock.pendingCount == 0)
    }

    @Test func backsUpWhenTheLogChangedAndTheIntervalPassed() async throws {
        let now = TestNow(Self.start)
        let app = try await TestApp.make(now: now) { config, dataDir in
            config.autoBackupMinutes = 2
            config.autoBackupDir = dataDir.appendingPathComponent("auto").path
        }
        let model: AppModel = app.model
        let dir: URL = app.dataDir.appendingPathComponent("auto")
        #expect(model.autoBackup.isRunning)

        // One minute: the interval of two minutes has not passed.
        now.advance(seconds: 60)
        app.backupClock.advance(by: 60_000)
        await model.autoBackup.settle()
        #expect(Self.backups(dir).isEmpty)

        now.advance(seconds: 60)
        app.backupClock.advance(by: 60_000)
        await model.autoBackup.settle()
        #expect(Self.backups(dir).count == 1)

        // No change of the log: no backup however long it waits.
        now.advance(seconds: 600)
        app.backupClock.advance(by: 60_000)
        await model.autoBackup.settle()
        #expect(Self.backups(dir).count == 1)

        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        now.advance(seconds: 60)
        app.backupClock.advance(by: 60_000)
        await model.autoBackup.settle()
        #expect(Self.backups(dir).count == 2)
        #expect(model.status.message != "")
        #expect(!model.status.message.hasPrefix("Automatická záloha selhala"))
    }

    @Test func disabledIntervalMakesNoPeriodicBackup() async throws {
        let now = TestNow(Self.start)
        let app = try await TestApp.make(now: now) { config, dataDir in
            config.autoBackupMinutes = 0
            config.autoBackupDir = dataDir.appendingPathComponent("auto").path
        }
        now.advance(seconds: 3_600)
        app.backupClock.advance(by: 60_000)
        await app.model.autoBackup.settle()
        #expect(Self.backups(app.dataDir.appendingPathComponent("auto")).isEmpty)
    }

    @Test func failureGoesToTheStatusLine() async throws {
        let now = TestNow(Self.start)
        let app = try await TestApp.make(now: now) { config, dataDir in
            config.autoBackupMinutes = 1
            config.autoBackupDir = dataDir.appendingPathComponent("blocked").path
        }
        try Data("x".utf8).write(to: app.dataDir.appendingPathComponent("blocked"))
        now.advance(seconds: 60)
        app.backupClock.advance(by: 60_000)
        await app.model.autoBackup.settle()
        #expect(app.model.status.message.hasPrefix("Automatická záloha selhala: "))
        #expect(app.model.autoBackup.isRunning)
        #expect(app.backupClock.pendingCount == 1)
    }

    /// The loop stops on quit before the forced backup, and around a database switch (restarted afterwards).
    @Test func stopsOnQuitAndAroundADatabaseSwitch() async throws {
        let app = try await TestApp.make { config, dataDir in
            config.autoBackupDir = dataDir.appendingPathComponent("auto").path
        }
        let model: AppModel = app.model
        // Between the drain and `onOpened` the loop is stopped (falsifiable without the `stop()` in the drain).
        let duringSwitch = SwitchState()
        let drain = model.database.drain
        let clock: ManualClock = app.backupClock
        model.database.drain = {
            await drain?()
            duringSwitch.running = model.autoBackup.isRunning
            duringSwitch.pending = clock.pendingCount
        }
        #expect(app.backupClock.pendingCount == 1)
        await model.database.create("second")
        #expect(duringSwitch.running == false)
        #expect(duringSwitch.pending == 0)
        #expect(model.database.currentName == "second")
        #expect(model.autoBackup.isRunning)
        #expect(app.backupClock.pendingCount == 1)

        await model.shutdown()
        #expect(!model.autoBackup.isRunning)
        #expect(app.backupClock.pendingCount == 0)
        // The forced backup of the quit.
        #expect(Self.backups(app.dataDir.appendingPathComponent("auto")).count == 1)
    }

    /// The forced backup on quit is named after the injected clock.
    @Test func forcedBackupUsesTheAppClock() async throws {
        let now = TestNow(Self.start)
        let app = try await TestApp.make(now: now) { config, dataDir in
            config.autoBackupDir = dataDir.appendingPathComponent("auto").path
        }
        let logName: String = app.model.database.handle.url.lastPathComponent
        now.advance(seconds: 3_600)
        await app.model.shutdown()
        let dir: URL = app.dataDir.appendingPathComponent("auto")
        let expected: String = BackupRotation.target(dir: dir, logName: logName, now: now.date).lastPathComponent
        #expect(Self.backups(dir) == [expected])
    }

    @Test func wholeMinutesTruncateLikeJava() {
        let base = Self.start
        #expect(DatabaseModel.wholeMinutes(from: base, to: base.addingTimeInterval(59.999)) == 0)
        #expect(DatabaseModel.wholeMinutes(from: base, to: base.addingTimeInterval(60)) == 1)
        #expect(DatabaseModel.wholeMinutes(from: base, to: base.addingTimeInterval(-59)) == 0)
        #expect(DatabaseModel.wholeMinutes(from: base, to: base.addingTimeInterval(-60.5)) == -1)
    }
}
