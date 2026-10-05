import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// `AppModel.bootstrap` in the Kotlin order (`KApp:110-144`) and `shutdown` (`KApp:197-207`), over temporary data
/// directories only.
@MainActor @Suite struct AppModelBootstrapTests {

    @Test func firstRunCreatesTheDefaultDatabaseAndLanguages() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        #expect(model.database.currentName == "Deník")
        #expect(model.database.databasesDir.lastPathComponent == "databases")
        #expect(model.database.needsDatabasesDir)
        let dbFile: URL = app.dataDir.appendingPathComponent("databases/Deník.sqlite")
        #expect(FileManager.default.fileExists(atPath: dbFile.path))
        let english: URL = app.dataDir.appendingPathComponent("language/lang_en.json")
        #expect(FileManager.default.fileExists(atPath: english.path))
        #expect(model.language.code == "cs")
        #expect(!model.contest.isActive)
        #expect(!model.contest.showStartupDialog)
        #expect(model.windows.isOpen("log"))
        #expect(model.contest.engineAvailable)
    }

    @Test func languageIsLoadedBeforeTheModels() async throws {
        let app = try await TestApp.make { config, _ in
            config.language = "en"
        }
        #expect(app.model.language.code == "en")
        #expect(app.model.language.tr("Zatím nedostupné") == "Not available yet")
    }

    @Test func missingConfiguredDirectoryFallsBackAndAsksForANewOne() async throws {
        let app = try await TestApp.make { config, dataDir in
            config.databasesDir = dataDir.appendingPathComponent("vanished").path
        }
        #expect(app.model.database.databasesDir == app.dataDir.appendingPathComponent("databases", isDirectory: true))
        #expect(app.model.database.needsDatabasesDir)
    }

    @Test func blankConfiguredDirectoryIsKotlinBlank() {
        let resolved = DatabaseModel.resolveDatabasesDir(configured: "\u{00A0} ", dataDir: URL(fileURLWithPath: "/d"))
        #expect(resolved.needsChoice)
        #expect(resolved.missing == nil)
        #expect(resolved.dir.path == "/d/databases")
    }

    @Test func validDirectoryAndLastDatabaseAreUsed() async throws {
        let app = try await TestApp.make { config, dataDir in
            let dir: URL = dataDir.appendingPathComponent("my-dbs")
            try DatabaseCatalog(databasesDir: dir).create("Závod")
            config.databasesDir = dir.path
            config.lastDatabase = "Závod"
        }
        #expect(!app.model.database.needsDatabasesDir)
        #expect(app.model.database.currentName == "Závod")
    }

    @Test func vanishedLastDatabaseOpensTheDefault() async throws {
        let app = try await TestApp.make { config, dataDir in
            let dir: URL = dataDir.appendingPathComponent("my-dbs")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            config.databasesDir = dir.path
            config.lastDatabase = "Gone"
        }
        #expect(app.model.database.currentName == "Deník")
    }

    @Test func startupDialogIsOfferedWhenTheDatabaseHasAContest() async throws {
        let first = try await TestApp.make { config, dataDir in
            config.databasesDir = dataDir.appendingPathComponent("dbs").path
            try FileManager.default.createDirectory(at: dataDir.appendingPathComponent("dbs"),
                                                    withIntermediateDirectories: true)
        }
        try await first.startCqWwCw()
        await first.model.shutdown()
        let again = AppModel.Environment(dataDir: first.dataDir, dxccDir: try Fixtures.dxccDir(in: first.dir),
                                         rescoreClock: ManualClock(), geometryClock: ManualClock(),
                                         backupClock: ManualClock())
        let second: AppModel = try await AppModel.bootstrap(again)
        #expect(second.contest.showStartupDialog)
        #expect(!second.contest.isActive)
        #expect(await second.contest.lastContestLabel() == "CQ WW DX Contest — CW")
        await second.shutdown()
    }

    @Test func autoReloadOpensTheLastContest() async throws {
        let first = try await TestApp.make()
        try await first.startCqWwCw()
        await first.logContestQso(call: "DL1ABC", zone: "14")
        first.model.config.config.autoReloadLastContest = true
        first.model.config.save(failureKey: "%s")
        await first.model.shutdown()
        let again = AppModel.Environment(dataDir: first.dataDir, dxccDir: try Fixtures.dxccDir(in: first.dir),
                                         rescoreClock: ManualClock(), geometryClock: ManualClock(),
                                         backupClock: ManualClock())
        let second: AppModel = try await AppModel.bootstrap(again)
        #expect(second.contest.isActive)
        #expect(!second.contest.showStartupDialog)
        #expect(second.status.message == "Otevřen poslední závod (AUTORELOAD)")
        #expect(second.logbook.rows.map(\.call) == ["DL1ABC"])
        #expect(second.contest.score?.qsoCount == 1)
        await second.shutdown()
    }

    @Test func brokenMenuHasTheLastWordOverAutoReload() async throws {
        let first = try await TestApp.make()
        try await first.startCqWwCw()
        first.model.config.config.autoReloadLastContest = true
        first.model.config.save(failureKey: "%s")
        await first.model.shutdown()
        try Data("{".utf8).write(to: first.dataDir.appendingPathComponent("menu.json"))
        let again = AppModel.Environment(dataDir: first.dataDir, dxccDir: try Fixtures.dxccDir(in: first.dir),
                                         rescoreClock: ManualClock(), geometryClock: ManualClock(),
                                         backupClock: ManualClock())
        let second: AppModel = try await AppModel.bootstrap(again)
        #expect(second.contest.isActive)
        #expect(second.status.message.hasPrefix("Menu: "))
        await second.shutdown()
    }

    @Test func shutdownRunsInTheKotlinOrder() async throws {
        let app = try await TestApp.make()
        final class Steps: @unchecked Sendable { var names: [String] = [] }
        let steps = Steps()
        var services = AppModel.ShutdownServices()
        services.keyers = { steps.names.append("keyers") }
        services.cat = { steps.names.append("cat") }
        services.dxCluster = { steps.names.append("dxCluster") }
        services.cluster = { steps.names.append("cluster") }
        services.integrations = { steps.names.append("integrations") }
        app.model.shutdownServices = services
        app.model.geometry.windowChanged(id: "main", frame: CGRect(x: 10, y: 10, width: 820, height: 500),
                                         persistSize: false, mainScreenHeight: 1000)
        await app.model.shutdown()
        #expect(steps.names == ["keyers", "cat", "dxCluster", "cluster", "integrations"])
        // closeDatabase: the forced backup exists and the connection is closed.
        let backups: [String] = try FileManager.default.contentsOfDirectory(
            atPath: app.dataDir.appendingPathComponent("backups").path)
        #expect(backups.count == 1)
        #expect(backups.first?.hasPrefix("Deník") == true)
        // The pending geometry was written with the config.
        #expect(app.savedConfig().windowGeometry["main"] == WindowGeometry(x: 10, y: 490, width: 0, height: 0))
    }

    @Test func backupGoesToTheConfiguredDirectory() async throws {
        let app = try await TestApp.make { config, dataDir in
            config.autoBackupDir = dataDir.appendingPathComponent("elsewhere").path
        }
        await app.model.shutdown()
        let files: [String] = try FileManager.default.contentsOfDirectory(
            atPath: app.dataDir.appendingPathComponent("elsewhere").path)
        #expect(files.count == 1)
    }
}
