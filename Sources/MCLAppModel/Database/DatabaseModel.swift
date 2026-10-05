import Foundation
import MCLCore
import Observation
import os

/// The databases directory and the open logbook (Kotlin `AppState` `KA:95-131, 2679-2694, 3551-3588`): listing,
/// creating and opening named databases. Every SQLite and file operation runs on `BlockingQueue`.
@Observable @MainActor
public final class DatabaseModel {

    /// Where the database files live (Kotlin `databaseCatalog`).
    public private(set) var databasesDir: URL
    /// Name of the open database (Kotlin `currentDatabase`).
    public private(set) var currentName: String
    /// The open database.
    public private(set) var handle: LogbookHandle
    /// No valid databases directory is chosen yet (first run or a vanished directory) — the first-run dialog.
    public private(set) var needsDatabasesDir: Bool
    /// `true` while `open` switches the database (the entry is blocked meanwhile).
    public private(set) var isSwitching: Bool = false

    /// Runs after a database is switched and before „Otevřena databáze %s" (Kotlin `openDatabase`: deactivate the
    /// contest, refresh the log, offer the start-up dialog).
    @ObservationIgnored public var onOpened: (@MainActor () async -> Void)?
    /// Waits for the work in flight on the open database (submissions, activation, recount) before it is closed;
    /// set by the app model.
    @ObservationIgnored public var drain: (@MainActor () async -> Void)?

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let dataDir: URL
    /// Revision of the last successful backup (Kotlin `lastBackupRevision`, initially -1).
    @ObservationIgnored private var lastBackupRevision: Int64 = -1
    /// Time of the last successful backup (Kotlin `lastBackupAt`, initially the start-up).
    @ObservationIgnored private var lastBackupAt: Date
    /// The clock of the backups (the target's time stamp, the interval).
    @ObservationIgnored private let now: @Sendable () -> Date

    init(databasesDir: URL, currentName: String, handle: LogbookHandle, needsDatabasesDir: Bool, dataDir: URL,
         config: ConfigModel, status: StatusModel, now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
        self.lastBackupAt = now()
        self.databasesDir = databasesDir
        self.currentName = currentName
        self.handle = handle
        self.needsDatabasesDir = needsDatabasesDir
        self.dataDir = dataDir
        self.config = config
        self.status = status
    }

    // MARK: - start-up

    /// The start-up choice of the databases directory (`App.kt`): the configured one when it is a directory,
    /// otherwise `dataDir/databases`. `needsChoice` is Kotlin `needsDatabasesDir`; `missing` is the configured
    /// directory that does not exist (Kotlin logs a warning).
    public nonisolated static func resolveDatabasesDir(configured: String, dataDir: URL)
        -> (dir: URL, needsChoice: Bool, missing: String?) {
        let blank: Bool = KotlinStrings.isBlank(configured)
        let exists: Bool = !blank && isDirectory(configured)
        let dir: URL = exists
            ? URL(fileURLWithPath: configured, isDirectory: true)
            : dataDir.appendingPathComponent("databases", isDirectory: true)
        return (dir, blank || !exists, blank || exists ? nil : configured)
    }

    /// Kotlin start-up: `DatabaseCatalog`, the last database when it still exists, otherwise `ensureDefault`, then
    /// the repository. Blocking.
    public nonisolated static func openInitial(databasesDir: URL, lastDatabase: String) throws -> LogbookHandle {
        let catalog = try DatabaseCatalog(databasesDir: databasesDir)
        let name: String
        if let last = KotlinStrings.nilIfBlank(lastDatabase), try catalog.list().contains(last) {
            name = last
        } else {
            name = try catalog.ensureDefault()
        }
        return try LogbookHandle.open(name: name, url: catalog.pathFor(name))
    }

    private nonisolated static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    // MARK: - list, create, open

    /// Database names in the directory (Kotlin `databaseCatalog.list()`).
    public func list() async throws -> [String] {
        let dir: URL = databasesDir
        return try await BlockingQueue.run {
            try DatabaseCatalog(databasesDir: dir).list()
        }
    }

    /// Kotlin `createDatabase(name)`: a trimmed, non-blank name that does not exist yet is created and opened.
    public func create(_ name: String) async {
        let trimmed: String = KotlinStrings.trim(name)
        if KotlinStrings.isBlank(trimmed) {
            return
        }
        let dir: URL = databasesDir
        let exists: Result<Bool, any Error> = await Self.blockingResult {
            try DatabaseCatalog(databasesDir: dir).list().contains(trimmed)
        }
        if case .success(true) = exists {
            status.show("Databáze %s už existuje — použij Otevřít databázi.", .string(trimmed))
            return
        }
        let created: Result<URL, any Error> = await Self.blockingResult {
            if case .failure(let error) = exists {
                throw error
            }
            return try DatabaseCatalog(databasesDir: dir).create(trimmed)
        }
        if case .failure(let error) = created {
            status.show("Nelze založit databázi %s (%s)", .string(trimmed), .string(ErrorText.message(error)))
            return
        }
        await open(trimmed)
    }

    /// Kotlin `openDatabase(name)`: opens the new database first (a failure leaves the old one open), then switches,
    /// remembers it as `lastDatabase`, closes the old connection and lets the owner refresh the state.
    public func open(_ name: String) async {
        isSwitching = true
        defer { isSwitching = false }
        let dir: URL = databasesDir
        let opened: Result<LogbookHandle, any Error> = await Self.blockingResult {
            let catalog = try DatabaseCatalog(databasesDir: dir)
            return try LogbookHandle.open(name: name, url: catalog.pathFor(name))
        }
        let newHandle: LogbookHandle
        switch opened {
        case .success(let value):
            newHandle = value
        case .failure(let error):
            status.show("Nelze otevřít databázi %s (%s)", .string(name), .string(ErrorText.message(error)))
            return
        }
        await drain?()
        let old: LogbookHandle = handle
        handle = newHandle
        currentName = name
        config.config.lastDatabase = name
        config.save(failureKey: "Uložení poslední databáze selhalo (%s)")
        await old.close()
        await onOpened?()
        status.show("Otevřena databáze %s", .string(name))
    }

    /// Kotlin `setDatabasesDir(dir)` (first-run dialog): saves the directory, creates the default database in it and
    /// opens it.
    public func setDatabasesDir(_ dir: URL) async {
        config.config.databasesDir = dir.path
        config.save(failureKey: "Uložení konfigurace selhalo (%s)")
        let created: Result<String, any Error> = await Self.blockingResult {
            try DatabaseCatalog(databasesDir: dir).ensureDefault()
        }
        switch created {
        case .success(let name):
            databasesDir = dir
            needsDatabasesDir = false
            await open(name)
        case .failure(let error):
            // Kotlin lets the exception escape; the status line keeps the dialog open with a reason.
            status.showVerbatim(ErrorText.message(error))
        }
    }

    // MARK: - backup and close

    /// Kotlin `autoBackupIfDue(force)` (`AS:2060-2078`): the forced backup on quit and the periodic one
    /// (`AutoBackupLoop`). A backup is made when the log changed since the last one (`revision`) and — unless
    /// forced — `autoBackupMinutes` > 0 and at least that many whole minutes (Java `Duration.toMinutes()`) passed
    /// since the last successful backup (or the start-up); into `autoBackupDir` (blank → `dataDir/backups`) with
    /// rotation by `autoBackupKeep`. A failure goes to the status line. The copy is one job on the handle's serial
    /// queue, so it never sees a half-written database.
    public func backup(force: Bool, revision: Int64, now at: Date? = nil) async {
        let now: Date = at ?? self.now()
        let settings: AppConfig = config.config
        if settings.autoBackupMinutes <= 0 && !force {
            return
        }
        if revision == lastBackupRevision {
            return
        }
        if !force && Self.wholeMinutes(from: lastBackupAt, to: now) < Int64(settings.autoBackupMinutes) {
            return
        }
        let dir: URL = KotlinStrings.nilIfBlank(settings.autoBackupDir).map { URL(fileURLWithPath: $0) }
            ?? dataDir.appendingPathComponent("backups", isDirectory: true)
        let open: LogbookHandle = handle
        let logName: String = open.url.lastPathComponent
        let keep: Int = settings.autoBackupKeep
        do {
            try await open.run { access in
                let target: URL = BackupRotation.target(dir: dir, logName: logName, now: now)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                Self.removeStalePartials(dir: dir, logName: logName)
                try Self.writeBackup(to: target) { partial in
                    try access.repository.backupTo(partial)
                }
                _ = try BackupRotation.prune(dir: dir, logName: logName, keep: keep)
            }
            lastBackupRevision = revision
            lastBackupAt = now
        } catch {
            status.show("Automatická záloha selhala: %s", .string(ErrorText.message(error)))
        }
    }

    /// Kotlin `closeDatabase()`: the forced backup, then the connection is closed. The caller drains the work in
    /// flight first (`AppModel.shutdown`).
    public func close(revision: Int64) async {
        await backup(force: true, revision: revision)
        await handle.close()
    }

    // MARK: - helpers

    /// The temporary name of a backup being written: hidden and without the `.sqlite` suffix, so the rotation never
    /// counts it.
    nonisolated static func partialName(_ target: URL) -> URL {
        target.deletingLastPathComponent().appendingPathComponent("." + target.lastPathComponent + ".part")
    }

    /// Removes the temporary files an earlier exit left behind in the backup directory (a forced backup cut short):
    /// the hidden `.<log>-auto-<time>.sqlite.part` files of this logbook. Other logbooks' files and the finished
    /// backups are not touched.
    nonisolated static func removeStalePartials(dir: URL, logName: String) {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: dir.path) else { return }
        let prefix: String = "." + BackupRotation.autoPrefix(logName)
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".sqlite.part") {
            try? files.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// A backup written by `write` through a temporary file renamed into place (the forced backup of the quit, ledger
    /// also COPYLOG): an exit or a failure in the middle leaves no partial backup under a backup's name
    /// and an earlier backup is never touched. An existing target is refused as by `backupTo`; a stale temporary file
    /// of the same name is replaced.
    nonisolated static func writeBackup(to target: URL, write: (URL) throws -> Void) throws {
        let files = FileManager.default
        if files.fileExists(atPath: target.path) {
            throw LogbookError("Záloha deníku: soubor už existuje: \(target.path)")
        }
        let partial: URL = partialName(target)
        if files.fileExists(atPath: partial.path) {
            try files.removeItem(at: partial)
        }
        do {
            try write(partial)
            try files.moveItem(at: partial, to: target)
        } catch {
            try? files.removeItem(at: partial)
            throw error
        }
    }

    /// Java `Duration.between(from, to).toMinutes()`: the seconds rounded down (the nanos are non-negative), then
    /// divided by 60 toward zero.
    nonisolated static func wholeMinutes(from: Date, to: Date) -> Int64 {
        let seconds: Double = (to.timeIntervalSince(from)).rounded(.down)
        guard seconds.isFinite, abs(seconds) < 9.0e15 else { return seconds < 0 ? Int64.min / 60 : Int64.max / 60 }
        return Int64(seconds) / 60
    }

    nonisolated static func blockingResult<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async
        -> Result<T, any Error> {
        do {
            return .success(try await BlockingQueue.run(body))
        } catch {
            return .failure(error)
        }
    }
}

/// Logger of the app models (warnings Kotlin writes through `System.getLogger`).
let appLog = Logger(subsystem: "cz.ok1xoe.maccontestlogger", category: "app")
