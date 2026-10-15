import CoreGraphics
import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The settings backups and their restore, the reset to the defaults, the window layouts, the lost-window gather and
/// the station per database (N1MM Clear INI, daily `.bak`, Save / Restore Window Positions, UserDir neighbours).
@MainActor @Suite struct SettingsMaintenanceModelTests {

    @Test func startUpMakesTheDailyBackup() async throws {
        let app = try await TestApp.make()
        await app.model.profiles.refreshBackups()
        #expect(app.model.profiles.backups.count == 1)
        let backup: AppConfig = try ConfigBackups(dataDir: app.dataDir).read(try #require(app.model.profiles.backups.first))
        #expect(backup.station.call == "OK1XOE")
    }

    @Test func resetKeepsTheStationTheLogsAndTheWindowsAndBacksUpFirst() async throws {
        let app = try await TestApp.make { config, _ in
            config.ntpServer = "ntp.example"
            config.beepOnDupe = true
            config.openWindows = ["log", "bandmap"]
        }
        let model: AppModel = app.model
        let before: Int = try ConfigBackups(dataDir: app.dataDir).list().count

        await model.profiles.resetToDefaults(now: Date(timeIntervalSince1970: 1_790_000_000))

        let config: AppConfig = model.config.config
        #expect(!config.beepOnDupe)
        #expect(config.ntpServer == AppConfig().ntpServer)
        #expect(config.station.call == "OK1XOE")
        #expect(config.openWindows == ["log", "bandmap"])
        #expect(config.contestDataDir == Fixtures.contestData.path)
        #expect(model.profiles.backups.count == before + 1)
        #expect(model.status.message.hasPrefix("Nastavení vráceno na výchozí"))
        #expect(await app.savedConfigFlushed().beepOnDupe == false)
        // The newest backup holds the settings before the reset.
        let newest: ConfigBackups.Entry = try #require(model.profiles.backups.first)
        #expect(try ConfigBackups(dataDir: app.dataDir).read(newest).beepOnDupe)
    }

    @Test func restoreTakesTheBackupButKeepsTheLogsAndTheWindows() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        var old = AppConfig()
        old.station.call = "OK2OLD"
        old.beepOnDupe = true
        old.databasesDir = "/elsewhere"
        let backups = ConfigBackups(dataDir: app.dataDir)
        let written: URL = try backups.backupNow(old, now: Date(timeIntervalSince1970: 1_000))
        let entry: ConfigBackups.Entry = try #require(try backups.list().first { $0.url == written })
        let databasesDir: String = model.config.config.databasesDir

        await model.profiles.restoreBackup(entry, now: Date(timeIntervalSince1970: 2_000))

        #expect(model.config.config.station.call == "OK2OLD")
        #expect(model.config.config.beepOnDupe)
        #expect(model.config.config.databasesDir == databasesDir)
        #expect(model.status.message.hasPrefix("Nastavení obnoveno ze zálohy"))
    }

    @Test func layoutsAreSavedAndRestoredByName() async throws {
        let app = try await TestApp.make { config, _ in
            config.openWindows = ["log", "bandmap"]
            config.windowGeometry = ["bandmap": WindowGeometry(x: 10, y: 20, width: 300, height: 400)]
        }
        let profiles: ProfilesModel = app.model.profiles
        await profiles.saveLayout(name: " OK1ABC ")
        #expect(app.model.status.message == "Rozložení oken „OK1ABC“ uloženo")
        #expect(await profiles.layoutNames() == ["OK1ABC"])

        app.model.config.config.windowGeometry["bandmap"] = WindowGeometry(x: 1, y: 1, width: 1, height: 1)
        var restored = false
        let observer = NotificationCenter.default.addObserver(forName: WindowGeometryStore.layoutRestored,
                                                              object: nil, queue: nil) { _ in restored = true }
        defer { NotificationCenter.default.removeObserver(observer) }
        let ids: [String]? = await profiles.restoreLayout(name: "OK1ABC")

        #expect(ids == ["log", "bandmap"])
        #expect(restored)
        #expect(app.model.config.config.windowGeometry["bandmap"] == WindowGeometry(x: 10, y: 20, width: 300, height: 400))
        #expect(await profiles.restoreLayout(name: "Nikdo") == nil)
        #expect(app.model.status.message == "Rozložení oken „Nikdo“ neexistuje")
    }

    @Test func layoutMenuItemsAskForAName() async throws {
        let app = try await TestApp.make()
        #expect(MenuActions.perform("layout.gather", app: app.model) == .gatherWindows)
        #expect(MenuActions.perform("layout.save", app: app.model) == nil)
        for _ in 0..<50 where app.model.dialogs.textPrompt == nil {
            await Task.yield()
        }
        let prompt = try #require(app.model.dialogs.textPrompt)
        #expect(prompt.initial == "OK1XOE")
        app.model.dialogs.submitPrompt("Club")
        for _ in 0..<200 where await app.model.profiles.layoutNames().isEmpty {
            await Task.yield()
        }
        #expect(await app.model.profiles.layoutNames() == ["Club"])
    }

    @Test func gatherMovesOnlyLostWindows() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frames: [CGRect] = [
            CGRect(x: 100, y: 100, width: 400, height: 300),
            CGRect(x: 3000, y: 100, width: 400, height: 300),
            CGRect(x: -2000, y: -2000, width: 200, height: 100),
        ]
        let moves = WindowGather.moves(frames: frames, screens: [main], main: main)
        #expect(moves[0] == nil)
        #expect(moves[1] == CGPoint(x: 20, y: 900 - 20 - 300))
        #expect(moves[2] == CGPoint(x: 20 + WindowGather.step, y: 900 - 20 - WindowGather.step - 100))
    }

    @Test func stationFollowsTheDatabaseWhenOn() async throws {
        let app = try await TestApp.make { config, _ in
            config.stationPerDatabase = true
        }
        let model: AppModel = app.model
        let first: String = model.database.currentName
        await model.database.create("Polní den")
        // The new database takes the current station.
        #expect(model.config.config.station.call == "OK1XOE")
        model.config.config.station.call = "OK1FLD"
        await model.database.open(first)
        #expect(model.config.config.station.call == "OK1XOE")
        #expect(model.status.message.contains("údaje stanice z databáze"))
        await model.database.open("Polní den")
        #expect(model.config.config.station.call == "OK1FLD")
    }

    @Test func stationStaysWhenOff() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let first: String = model.database.currentName
        await model.database.create("Druhá")
        model.config.config.station.call = "OK1NEW"
        await model.database.open(first)
        #expect(model.config.config.station.call == "OK1NEW")
        #expect(!FileManager.default.fileExists(atPath: model.database.databasesDir
            .appendingPathComponent("Druhá.station.json").path))
    }
}
