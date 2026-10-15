import Foundation
@testable import MCLCore
import Testing

/// N1MM's daily settings backups, the window layouts (Save / Restore Window Positions), the separate data folder,
/// the station per database and the radio mode of the digital modes.
/// Main actor: in a Swift 6.1 debug build these tests' frames hold many `AppConfig` / `ConfigurerDraft` copies
/// (up to ~480 KB), which together with the callees overflows a 512 KB worker thread stack; the main thread has 8 MB.
@MainActor @Suite struct SettingsMaintenanceTests {

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-maint-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 86_400)
    }

    // MARK: - backups

    @Test func dailyBackupOncePerDayAndKeepsSeven() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backups = ConfigBackups(dataDir: dir)
        let file = dir.appendingPathComponent("config.json")
        // No config file yet: nothing to back up.
        #expect(try backups.daily(configFile: file, now: Self.day(0)) == nil)
        try Data(#"{"language":"en"}"#.utf8).write(to: file)
        #expect(try backups.daily(configFile: file, now: Self.day(0)) != nil)
        #expect(try backups.daily(configFile: file, now: Self.day(0).addingTimeInterval(3_600)) == nil)
        for n in 1...9 {
            _ = try backups.daily(configFile: file, now: Self.day(n))
        }
        let listed: [ConfigBackups.Entry] = try backups.list()
        #expect(listed.count == ConfigBackups.keep)
        #expect(listed.first?.label == ConfigBackups.dayStamp(Self.day(9)))
        #expect(listed.last?.label == ConfigBackups.dayStamp(Self.day(3)))
        #expect(try backups.read(listed[0]).language == "en")
    }

    @Test func backupNowWritesTheLiveConfigurationNewestFirst() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backups = ConfigBackups(dataDir: dir)
        var config = AppConfig()
        config.station.call = "OK1ABC"
        try Data("{}".utf8).write(to: dir.appendingPathComponent("config.json"))
        _ = try backups.daily(configFile: dir.appendingPathComponent("config.json"), now: Self.day(0))
        let url: URL = try backups.backupNow(config, now: Self.day(0).addingTimeInterval(60))
        let listed = try backups.list()
        #expect(listed.first?.url.lastPathComponent == url.lastPathComponent)
        #expect(try backups.read(listed[0]).station.call == "OK1ABC")
        #expect(listed.count == 2)
    }

    @Test func preservingKeepsTheLogsTheWindowsAndOptionallyTheStation() {
        var live = AppConfig()
        live.databasesDir = "/db"
        live.lastDatabase = "Contest"
        live.contestDataDir = "/cd"
        live.openWindows = ["log", "bandmap"]
        live.windowGeometry = ["log": WindowGeometry(x: 1, y: 2, width: 3, height: 4)]
        live.station.call = "OK1LIVE"
        live.language = "de"
        var next = AppConfig()
        next.station.call = "OK1OLD"
        let restored = ConfigBackups.preserving(live, into: next, station: false)
        #expect(restored.databasesDir == "/db")
        #expect(restored.lastDatabase == "Contest")
        #expect(restored.contestDataDir == "/cd")
        #expect(restored.openWindows == ["log", "bandmap"])
        #expect(restored.windowGeometry == live.windowGeometry)
        #expect(restored.station.call == "OK1OLD")
        #expect(restored.language == "cs")
        #expect(ConfigBackups.preserving(live, into: next, station: true).station.call == "OK1LIVE")
    }

    // MARK: - window layouts

    @Test func layoutNamesBecomeSafeFileNames() {
        #expect(WindowLayouts.fileName("  OK1ABC ") == "OK1ABC.json")
        #expect(WindowLayouts.fileName("Home/Field") == "Home_Field.json")
        #expect(WindowLayouts.fileName(".hidden") == "_hidden.json")
        #expect(WindowLayouts.fileName("   ") == nil)
    }

    @Test func layoutsSaveLoadAndApply() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layouts = WindowLayouts(dataDir: dir)
        #expect(try layouts.names().isEmpty)
        let saved = WindowLayout(openWindows: ["log", "bandmap"],
                                 windowGeometry: ["bandmap": WindowGeometry(x: 10, y: 20, width: 300, height: 400)])
        try layouts.save(saved, name: "OK1ABC")
        try layouts.save(saved, name: "Club")
        #expect(try layouts.names() == ["Club", "OK1ABC"])
        #expect(try layouts.load(name: "OK1ABC") == saved)
        #expect(try layouts.load(name: "Nobody") == nil)

        var config = AppConfig()
        config.openWindows = ["log", "score"]
        config.windowGeometry = ["score": WindowGeometry(x: 1, y: 1, width: 1, height: 1),
                                 "bandmap": WindowGeometry(x: 0, y: 0, width: 5, height: 5)]
        let applied: AppConfig = saved.applied(to: config)
        #expect(applied.openWindows == ["log", "score", "bandmap"])
        #expect(applied.windowGeometry["bandmap"] == WindowGeometry(x: 10, y: 20, width: 300, height: 400))
        #expect(applied.windowGeometry["score"] == WindowGeometry(x: 1, y: 1, width: 1, height: 1))
        #expect(WindowLayout.of(applied).openWindows == applied.openWindows)
    }

    // MARK: - data folder

    @Test func relaunchPassesThePathsAsParameters() {
        let bundle = URL(fileURLWithPath: "/Applications/Mac Contest Logger.app")
        let other = URL(fileURLWithPath: "/Users/op/MCL club's data", isDirectory: true)
        let command = DataFolderRelaunch.command(bundle: bundle, dataDir: other)
        #expect(command.executable == "/bin/sh")
        #expect(command.arguments.count == 4)
        #expect(command.arguments[0] == "-c")
        #expect(!command.arguments[1].contains("club"))
        #expect(command.arguments[1].contains("open -n -a"))
        #expect(command.arguments[2] == bundle.path)
        #expect(command.arguments[3] == "MCL_DATA_DIR=" + other.path)
        #expect(DataFolderRelaunch.command(bundle: bundle, dataDir: nil).arguments[3] == "MCL_DATA_DIR=")
        #expect(DataFolderRelaunch.differs(other, from: URL(fileURLWithPath: "/tmp/x")))
        #expect(!DataFolderRelaunch.differs(other, from: URL(fileURLWithPath: other.path + "/")))
    }

    // MARK: - station per database

    @Test func stationFollowsTheDatabase() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("Home.sqlite")
        let second = dir.appendingPathComponent("Field.sqlite")
        #expect(DatabaseStation.file(forDatabase: first).lastPathComponent == "Home.station.json")
        var home = StationConfig()
        home.call = "OK1HOME"
        // The new database has no station: it takes the current one, nothing changes.
        #expect(try DatabaseStation.switchDatabase(from: first, to: second, current: home) == nil)
        #expect(try DatabaseStation.read(DatabaseStation.file(forDatabase: second))?.call == "OK1HOME")
        #expect(try DatabaseStation.read(DatabaseStation.file(forDatabase: first))?.call == "OK1HOME")
        // The field station is edited, then the operator goes back home and forth again.
        var field = home
        field.call = "OK1FLD"
        try DatabaseStation.write(field, to: DatabaseStation.file(forDatabase: second))
        #expect(try DatabaseStation.switchDatabase(from: nil, to: first, current: field)?.call == "OK1HOME")
        #expect(try DatabaseStation.switchDatabase(from: first, to: second, current: home)?.call == "OK1FLD")
        // The same station: no change.
        #expect(try DatabaseStation.switchDatabase(from: nil, to: second, current: field) == nil)
    }

    // MARK: - digital radio mode

    @Test func otherDigitalModesUseTheChosenRadioMode() {
        #expect(HamlibModeMapping.default.toHamlib(.ft8, freqHz: 14_074_000) == "PKTUSB")
        let usb = HamlibModeMapping(dataMode: .digital, rttyAfsk: false, digiRadioMode: "usb")
        #expect(usb.digiRadioMode == "USB")
        #expect(usb.toHamlib(.psk, freqHz: 14_070_000) == "USB")
        #expect(usb.toHamlib(.ft8, freqHz: 7_074_000) == "USB")
        #expect(usb.toHamlib(.rtty, freqHz: 14_080_000) == "RTTY")
        #expect(usb.toHamlib(.cw, freqHz: 14_020_000) == "CW")
        #expect(HamlibModeMapping(dataMode: nil, rttyAfsk: true, digiRadioMode: "PKTLSB").toHamlib(.ft4, freqHz: 0)
            == "PKTLSB")
        #expect(HamlibModeMapping.normalizedDigiRadioMode("FM") == "PKTUSB")
        let decoded = try? JSONDecoder().decode(AppConfig.self, from: Data(#"{"digiRadioMode":"lsb"}"#.utf8))
        #expect(decoded?.digiRadioMode == "LSB")
        #expect(AppConfig().digiRadioMode == "PKTUSB")
        #expect(!AppConfig().stationPerDatabase)
    }
}
