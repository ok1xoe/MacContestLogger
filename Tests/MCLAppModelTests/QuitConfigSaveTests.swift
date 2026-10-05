import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The quit's config save and the atomic writes (data safety): the CW speed (Kotlin `shutdownKeyers` save) is on disk
/// before a second signal may end the process; `config.json` and the forced backup are replaced atomically, never
/// left half-written.
@MainActor @Suite struct QuitConfigSaveTests {

    /// `kill`, then a second `kill` right after the transmit-release milestone: the second one ends the process at
    /// once, and by then the unsaved CW speed is already in `config.json`.
    @Test func aSecondSignalAfterTheMilestoneKeepsTheCwSpeed() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        model.keyer.updateCwSpeed(33)
        #expect(app.savedConfig().cwKeyer.speed == 28)
        let probe = SignalProbe()
        var speedAtExit: Int?
        let signals = TerminationSignals(actions: TerminationSignals.Actions(
            terminate: {
                probe.terminating = true
                probe.quit = Task { await model.shutdown() }
            },
            isTerminating: { probe.terminating },
            exitAllowed: { model.signalExitAllowed },
            transmitReleased: { model.transmitReleased },
            forceExit: { code in
                probe.exits.append(code)
                // What the disk holds when the real exit would end the process.
                speedAtExit = app.savedConfig().cwKeyer.speed
            },
            after: { _, body in probe.deadlines.append(body) }))
        model.onQuitMilestone = { signals.milestoneReached() }
        signals.handle(SIGTERM)
        let shutdown: Task<Void, Never> = try #require(probe.quit)
        signals.handle(SIGTERM)
        await eventually("exit") { !probe.exits.isEmpty }
        #expect(probe.exits == [143])
        #expect(speedAtExit == 33)
        await shutdown.value
    }

    /// `writeFile` replaces the file (a new inode) instead of writing into it: a link to the old file keeps the old
    /// bytes, and no temporary file is left behind.
    @Test func theConfigFileIsReplacedAtomically() throws {
        let dir = try TempDir()
        let file: URL = dir.child("config.json")
        var config = AppConfig()
        config.station.call = "OK1OLD"
        try ConfigWriter.writeFile(config, to: file)
        let link: URL = dir.child("old-link.json")
        try FileManager.default.linkItem(at: file, to: link)
        config.station.call = "OK1NEW"
        try ConfigWriter.writeFile(config, to: file)
        #expect(ConfigStore(file: file).load().station.call == "OK1NEW")
        #expect(ConfigStore(file: link).load().station.call == "OK1OLD")
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names == ["config.json", "old-link.json"])
    }

    /// The forced backup is written under a hidden temporary name and renamed into place; a stale temporary file of an
    /// earlier exit does not stop it, and none is left.
    @Test func theBackupIsRenamedIntoPlace() async throws {
        let app = try await TestApp.make()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let dir: URL = app.dataDir.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let logName: String = app.model.database.handle.url.lastPathComponent
        let target: URL = BackupRotation.target(dir: dir, logName: logName, now: now)
        let stale: URL = DatabaseModel.partialName(target)
        try Data("half".utf8).write(to: stale)
        await app.model.database.backup(force: true, revision: app.model.logbook.revision, now: now)
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == [target.lastPathComponent])
        let size = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int
        #expect((size ?? 0) > 4)
    }

    /// A symbolic link `config.json` (a dotfiles repository, a synced folder) stays a link: the target is replaced,
    /// not the link, and its permissions are kept.
    @Test func aSymbolicLinkIsWrittenThroughAndStaysALink() throws {
        let dir = try TempDir()
        let files = FileManager.default
        let real: URL = dir.child("elsewhere/config.json")
        try files.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = AppConfig()
        config.station.call = "OK1OLD"
        try ConfigWriter.writeFile(config, to: real)
        try files.setAttributes([.posixPermissions: 0o640], ofItemAtPath: real.path)
        let link: URL = dir.child("config.json")
        try files.createSymbolicLink(atPath: link.path, withDestinationPath: "elsewhere/config.json")

        config.station.call = "OK1NEW"
        try ConfigWriter.writeFile(config, to: link)

        #expect((try? files.destinationOfSymbolicLink(atPath: link.path)) == "elsewhere/config.json")
        #expect(ConfigStore(file: real).load().station.call == "OK1NEW")
        let mode = try files.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int
        #expect(mode == 0o640)
    }

    /// A dangling link is followed too: the file it names is created, the link stays.
    @Test func aDanglingLinkCreatesItsTarget() throws {
        let dir = try TempDir()
        let files = FileManager.default
        let link: URL = dir.child("config.json")
        try files.createSymbolicLink(atPath: link.path, withDestinationPath: "later/config.json")
        var config = AppConfig()
        config.station.call = "OK1NEW"

        try ConfigWriter.writeFile(config, to: link)

        #expect((try? files.destinationOfSymbolicLink(atPath: link.path)) == "later/config.json")
        #expect(ConfigStore(file: dir.child("later/config.json")).load().station.call == "OK1NEW")
    }

    /// The replaced file's permissions survive the replacement (a plain file, any mode).
    @Test(arguments: [0o600, 0o640, 0o755])
    func thePermissionsOfTheOldFileAreKept(mode: Int) throws {
        let dir = try TempDir()
        let file: URL = dir.child("config.json")
        try ConfigWriter.writeFile(AppConfig(), to: file)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
        var config = AppConfig()
        config.station.call = "OK1NEW"

        try ConfigWriter.writeFile(config, to: file)

        let after = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(after == mode)
    }

    /// A backup that fails in the middle leaves no partial file under a backup's name, no temporary file, and an
    /// earlier backup untouched (the stub writes half a file under the temporary name, then fails).
    @Test func aFailedBackupKeepsThePreviousOne() throws {
        struct Stop: Error {}
        let dir = try TempDir()
        let previous: URL = dir.child("log-auto-20260101-000000.sqlite")
        try Data("previous backup".utf8).write(to: previous)
        let target: URL = dir.child("log-auto-20260102-000000.sqlite")

        #expect(throws: Stop.self) {
            try DatabaseModel.writeBackup(to: target) { partial in
                try Data("half".utf8).write(to: partial)
                throw Stop()
            }
        }

        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(names == [previous.lastPathComponent])
        #expect(try Data(contentsOf: previous) == Data("previous backup".utf8))
    }

    /// Success renames the temporary file into place; an existing target is refused without calling the writer and
    /// keeps its bytes.
    @Test func aFinishedBackupIsRenamedAndAnExistingOneIsRefused() throws {
        let dir = try TempDir()
        let target: URL = dir.child("log-auto-20260102-000000.sqlite")
        try DatabaseModel.writeBackup(to: target) { partial in
            try Data("whole".utf8).write(to: partial)
        }
        #expect(try Data(contentsOf: target) == Data("whole".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.path) == [target.lastPathComponent])

        var called = false
        #expect(throws: (any Error).self) {
            try DatabaseModel.writeBackup(to: target) { _ in called = true }
        }
        #expect(!called)
        #expect(try Data(contentsOf: target) == Data("whole".utf8))
    }

    /// Temporary files of earlier exits (other times) are removed from the backup directory before a backup; another
    /// logbook's temporary file and the finished backups stay.
    @Test func staleTemporaryBackupsOfEarlierRunsAreCleaned() async throws {
        let app = try await TestApp.make()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let dir: URL = app.dataDir.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logName: String = app.model.database.handle.url.lastPathComponent
        let base: String = String(logName.dropLast(".sqlite".count))
        let stale: URL = dir.appendingPathComponent(".\(base)-auto-20200101-000000.sqlite.part")
        let foreign: URL = dir.appendingPathComponent(".other-auto-20200101-000000.sqlite.part")
        let finished: URL = dir.appendingPathComponent("\(base)-auto-20200101-000000.sqlite")
        for file in [stale, foreign, finished] {
            try Data("x".utf8).write(to: file)
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let target: URL = BackupRotation.target(dir: dir, logName: logName, now: now)

        await app.model.database.backup(force: true, revision: app.model.logbook.revision, now: now)

        let names: Set<String> = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(names == [foreign.lastPathComponent, finished.lastPathComponent, target.lastPathComponent])
    }

    /// The early config save of the quit is skipped while a profile load is in flight (an earlier save would
    /// overwrite the load's write with the old configuration). The held profile write makes the difference
    /// visible: a save enqueued behind it would block `config.flush()`, so the transmit-release milestone would never
    /// be reached while the write is held. The profile's configuration is what ends up on disk.
    @Test func theEarlyQuitSaveIsSkippedDuringAProfileLoad() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        try ProfilesModelTests.writeProfile(harness.app, "Expedice.json", #"{"station":{"call":"OK2ABC"}}"#)
        harness.writer.hold()
        let load = Task { await model.profiles.load("Expedice") }
        await harness.writer.waitUntilHeld()
        #expect(model.profiles.isLoading)

        // The latch opens at the milestone; the bound (failure path only) keeps a regression from hanging.
        let reached = FirstOutcome()
        model.onQuitMilestone = { reached.open(true) }
        let quit = Task {
            await model.shutdown()
            reached.open(false)
        }
        let bound = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            reached.open(false)
        }
        let atTheMilestone: Bool = await reached.value()
        bound.cancel()
        #expect(atTheMilestone, "the quit waited behind the held profile write: its early save was not skipped")
        harness.writer.release()
        await load.value
        await quit.value

        #expect(harness.app.savedConfig().station.call == "OK2ABC")
    }
}
