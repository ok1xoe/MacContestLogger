import Foundation
import Testing

@testable import MCLCore

/// Port of `ConfigStoreTest`, `ConfigStoreContestDirTest`, `ConfigStoreFromJsonTest`,
/// `AppConfigDatabaseTest`, `OpenWindowsConfigTest`, `WindowGeometryPersistenceTest`
/// and four previously deferred tests (`InfoWindowConfigTest.survivesConfigRoundTrip`,
/// `StationConfigTest.savesAndReloadsAllStationFields`, `ContestSetupTest.appConfigStoresSetup`,
/// `ConfigProfilesTest.saveListLoadDelete`), plus three new tests securing the behaviour
/// from the Global Constraints (a missing/corrupt file → the default configuration).
@Suite struct ConfigStoreTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
    }

    // MARK: - Brief: missing/corrupt file, round-trip

    @Test func missingFileYieldsDefaults() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(file: dir.appendingPathComponent("config.json"))
        #expect(store.load().station.call == "")
    }

    @Test func corruptedFileYieldsDefaults() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{tohle není JSON".utf8).write(to: file)
        #expect(ConfigStore(file: file).load().station.call == "")
    }

    @Test func roundTripPreservesValues() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ConfigStore(file: file)
        var cfg = AppConfig()
        cfg.station.call = "OK1XOE"
        cfg.scpFile = "/tmp/master.scp"
        store.save(cfg)
        let loaded = store.load()
        #expect(loaded.station.call == "OK1XOE")
        #expect(loaded.scpFile == "/tmp/master.scp")
    }

    @Test func suggestionSwitchesDefaultOnAndRoundTrip() throws {
        #expect(AppConfig().scpSuggestionsEnabled && AppConfig().nPlusOneEnabled)
        // An existing config without the keys keeps the behaviour (both on).
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"scpFile":"/x"}"#.utf8))
        #expect(old.scpSuggestionsEnabled && old.nPlusOneEnabled)
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ConfigStore(file: file)
        var cfg = AppConfig()
        cfg.scpSuggestionsEnabled = false
        store.save(cfg)
        var loaded = store.load()
        #expect(!loaded.scpSuggestionsEnabled && loaded.nPlusOneEnabled)
        cfg.scpSuggestionsEnabled = true
        cfg.nPlusOneEnabled = false
        store.save(cfg)
        loaded = store.load()
        #expect(loaded.scpSuggestionsEnabled && !loaded.nPlusOneEnabled)
    }

    // MARK: - ConfigStoreTest

    @Test func returnsDefaultsWhenFileMissing() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = ConfigStore(file: dir.appendingPathComponent("config.json")).load()
        #expect(config.rig.mode == .launchDaemon)
        #expect(config.rig.port == 4532)
    }

    @Test func savesAndReloadsRigConfig() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ConfigStore(file: file)

        var config = AppConfig()
        config.rig.mode = .connectRunning
        config.rig.model = 2011
        config.rig.modelLabel = "2011 — Kenwood TS-570"
        config.rig.device = "/dev/cu.usbserial-1410"
        config.rig.baud = 57600
        config.rig.host = "192.168.1.50"
        config.rig.port = 4533
        store.save(config)

        let reloaded = ConfigStore(file: file).load().rig
        #expect(reloaded.mode == .connectRunning)
        #expect(reloaded.model == 2011)
        #expect(reloaded.device == "/dev/cu.usbserial-1410")
        #expect(reloaded.baud == 57600)
        #expect(reloaded.host == "192.168.1.50")
        #expect(reloaded.port == 4533)
    }

    @Test func savesAndReloadsSerialParams() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }

        var config = AppConfig()
        config.rig.dataBits = 7
        config.rig.stopBits = 2
        config.rig.parity = .even
        config.rig.flowControl = .hardware
        config.rig.dtr = .on
        config.rig.rts = .off
        ConfigStore(file: file).save(config)

        let reloaded = ConfigStore(file: file).load().rig
        #expect(reloaded.dataBits == 7)
        #expect(reloaded.stopBits == 2)
        #expect(reloaded.parity == .even)
        #expect(reloaded.flowControl == .hardware)
        #expect(reloaded.dtr == .on)
        #expect(reloaded.rts == .off)
    }

    @Test func clusterConfigDefaultsToDisabled() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = ConfigStore(file: dir.appendingPathComponent("config.json")).load()
        #expect(config.cluster.enabled == false)
        #expect(config.cluster.port == 1883)
    }

    @Test func savesAndReloadsClusterConfig() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }

        var config = AppConfig()
        config.cluster.enabled = true
        config.cluster.brokerHost = "cluster.local"
        config.cluster.port = 8883
        config.cluster.username = "OP1"
        config.cluster.password = "secret"
        config.cluster.stationId = "OP1"
        ConfigStore(file: file).save(config)

        let reloaded = ConfigStore(file: file).load().cluster
        #expect(reloaded.enabled == true)
        #expect(reloaded.brokerHost == "cluster.local")
        #expect(reloaded.port == 8883)
        #expect(reloaded.username == "OP1")
        #expect(reloaded.password == "secret")
        #expect(reloaded.stationId == "OP1")
    }

    @Test func savesAndReloadsStationData() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }

        var config = AppConfig()
        config.station.call = "OK1XOE"
        config.station.operator = "OK1ABC"
        config.station.gridSquare = "JO70"
        config.station.name = "Tomáš"
        ConfigStore(file: file).save(config)

        let reloaded = ConfigStore(file: file).load().station
        #expect(reloaded.call == "OK1XOE")
        #expect(reloaded.operator == "OK1ABC")
        #expect(reloaded.gridSquare == "JO70")
        #expect(reloaded.name == "Tomáš")
    }

    // MARK: - ConfigStoreContestDirTest

    @Test func contestDataDirDefaultIsNil() {
        #expect(AppConfig().contestDataDir == nil)
    }

    @Test func persistsContestDataDir() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ConfigStore(file: file)
        var cfg = AppConfig()
        cfg.contestDataDir = "/Users/x/contest-data"
        store.save(cfg)

        #expect(store.load().contestDataDir == "/Users/x/contest-data")
    }

    // MARK: - ConfigStoreFromJsonTest

    @Test func fromJsonRoundTripAndNullSafe() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ConfigStore(file: file)
        var setup = ContestSetup()
        setup.category["OPERATOR"] = "SINGLE-OP"
        setup.category["POWER"] = "LOW"

        let json = store.toJSON(setup)
        let back = store.fromJSON(json, as: ContestSetup.self)
        #expect(back != nil)
        #expect(back?.category["OPERATOR"] == "SINGLE-OP")
        #expect(back?.category["POWER"] == "LOW")

        #expect(store.fromJSON(nil, as: ContestSetup.self) == nil)
        #expect(store.fromJSON("", as: ContestSetup.self) == nil)
        #expect(store.fromJSON("{ garbage", as: ContestSetup.self) == nil)
    }

    // MARK: - AppConfigDatabaseTest

    // The Java test additionally calls `a.setDatabasesDir(null)` and verifies that the getter
    // returns "" — `databasesDir` in Swift is a non-optional `String`, so assigning
    // `nil` does not translate (the same reason as for the tests in the "Not convertible tests" table).
    // The rest of the test (defaults and persistence of `lastDatabase`) unchanged.
    @Test func databaseFieldsDefaultEmpty() {
        var a = AppConfig()
        #expect(a.databasesDir == "")
        #expect(a.lastDatabase == "")
        a.lastDatabase = "Deník"
        #expect(a.databasesDir == "")
        #expect(a.lastDatabase == "Deník")
    }

    // MARK: - OpenWindowsConfigTest

    @Test func freshConfigOpensLogByDefault() {
        #expect(AppConfig().openWindows == ["log"])
    }

    @Test func savesAndReloadsOpenWindows() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        var config = AppConfig()
        config.openWindows = ["bandmap", "dxCluster"]
        ConfigStore(file: file).save(config)

        #expect(ConfigStore(file: file).load().openWindows == ["bandmap", "dxCluster"])
    }

    @Test func emptyOpenWindowsRoundTripsWithoutResettingToDefault() {
        // The user closed all windows → the empty list must survive, not return to ["log"].
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        var config = AppConfig()
        config.openWindows = []
        ConfigStore(file: file).save(config)

        #expect(ConfigStore(file: file).load().openWindows.isEmpty)
    }

    // MARK: - WindowGeometryPersistenceTest

    @Test func freshConfigHasEmptyGeometryMap() {
        #expect(AppConfig().windowGeometry.isEmpty)
    }

    @Test func savesAndReloadsWindowGeometry() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }

        var config = AppConfig()
        config.windowGeometry["bandmap"] = WindowGeometry(x: 300, y: 150, width: 320, height: 640)
        config.windowGeometry["main"] = WindowGeometry(x: 50, y: 60, width: 0, height: 0)
        ConfigStore(file: file).save(config)

        let reloaded = ConfigStore(file: file).load()
        let bandmap = try #require(reloaded.windowGeometry["bandmap"])
        #expect(bandmap.x == 300)
        #expect(bandmap.y == 150)
        #expect(bandmap.width == 320)
        #expect(bandmap.height == 640)
        #expect(bandmap.hasSize())

        let main = try #require(reloaded.windowGeometry["main"])
        #expect(main.x == 50)
        #expect(main.y == 60)
        #expect(!main.hasSize())
    }

    // MARK: - Deferred: InfoWindowConfigTest.survivesConfigRoundTrip

    @Test func infoWindowConfigSurvivesConfigRoundTrip() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ConfigStore(file: file)
        var cfg = AppConfig()
        cfg.infoWindow.trendMinutes = 30
        cfg.infoWindow.offTimeMode = "offTime"
        cfg.infoWindow.showTimers = false
        cfg.infoWindow.showWwv = false
        store.save(cfg)

        let back = store.load()
        #expect(back.infoWindow.trendMinutes == 30)
        #expect(back.infoWindow.offTimeMode == "offTime")
        #expect(back.infoWindow.showTimers == false)
        #expect(back.infoWindow.showWwv == false)
        #expect(back.infoWindow.showCountryInfo) // untouched stays on
    }

    // MARK: - Deferred: StationConfigTest.savesAndReloadsAllStationFields

    @Test func stationConfigSavesAndReloadsAllFields() {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        var config = AppConfig()
        config.station.call = "OK1XOE"
        config.station.operator = "OK1ABC"
        config.station.name = "Tomáš"
        config.station.gridSquare = "JO70"
        config.station.address1 = "Ulice 1"
        config.station.address2 = "2. patro"
        config.station.city = "Praha"
        config.station.state = "ST"
        config.station.zip = "11000"
        config.station.country = "Czech Republic"
        config.station.cqZone = "15"
        config.station.ituZone = "28"
        config.station.license = "HAREC"
        config.station.latitude = "50.08"
        config.station.longitude = "14.42"
        config.station.stationTxRx = "TS-590SG"
        config.station.power = "100 W"
        config.station.antenna = "3el Yagi"
        config.station.antHeight = "12"
        config.station.asl = "300"
        config.station.arrlSection = "DX"
        config.station.roverQth = "JO60"
        config.station.club = "OK1KVK"
        config.station.email = "ok1xoe@example.com"
        ConfigStore(file: file).save(config)

        let r = ConfigStore(file: file).load().station
        #expect(r.call == "OK1XOE")
        #expect(r.operator == "OK1ABC")
        #expect(r.name == "Tomáš")
        #expect(r.gridSquare == "JO70")
        #expect(r.address1 == "Ulice 1")
        #expect(r.address2 == "2. patro")
        #expect(r.city == "Praha")
        #expect(r.state == "ST")
        #expect(r.zip == "11000")
        #expect(r.country == "Czech Republic")
        #expect(r.cqZone == "15")
        #expect(r.ituZone == "28")
        #expect(r.license == "HAREC")
        #expect(r.latitude == "50.08")
        #expect(r.longitude == "14.42")
        #expect(r.stationTxRx == "TS-590SG")
        #expect(r.power == "100 W")
        #expect(r.antenna == "3el Yagi")
        #expect(r.antHeight == "12")
        #expect(r.asl == "300")
        #expect(r.arrlSection == "DX")
        #expect(r.roverQth == "JO60")
        #expect(r.club == "OK1KVK")
        #expect(r.email == "ok1xoe@example.com")
    }

    // MARK: - Deferred: ContestSetupTest.appConfigStoresSetup

    @Test func contestSetupAppConfigStoresSetup() {
        var a = AppConfig()
        var s = ContestSetup()
        s.operators = "OK1XOE"
        s.category = ["OPERATOR": "SINGLE-OP"]
        a.contestSetups["cq-ww-cw"] = s
        #expect(a.contestSetups["cq-ww-cw"]?.operators == "OK1XOE")
        #expect(a.contestSetups["cq-ww-cw"]?.category["OPERATOR"] == "SINGLE-OP")
    }

    // MARK: - Deferred: ConfigProfilesTest.saveListLoadDelete

    @Test func configProfilesSaveListLoadDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let profiles = ConfigProfiles<AppConfig>(dir: dir)

        var home = AppConfig()
        home.station.call = "OK1XOE"
        home.cwSpeedStep = 3
        home.antennas = [AntennaEntry(code: 1, name: "Yagi", bands: "20m", sector: "")]
        try profiles.save("Doma", home)

        var dx = AppConfig()
        dx.station.call = "OK1XOE/P"
        try profiles.save("Expedice 2026", dx)

        #expect(profiles.list() == ["Doma", "Expedice 2026"])

        // The Java test here holds a reference to `current.getStation()` and after `loadInto`
        // verifies `assertSame` — the values are overwritten, but the object stays the same.
        // `AppConfig` is a value type without identity in Swift, so this particular
        // requirement (object identity) has no counterpart (see the doc comment of `ConfigProfiles.swift`).
        //
        // The regression risk that the Java assertion "the list is replaced, not merged"
        // guarded (Jackson's merge-into-instance could leave old items hanging
        // next to the new ones) makes no sense to replicate here by setting `current` before the call
        // — `load` is a pure function returning a new value, there is no receiver to merge
        // into. An equivalent, truly testable assertion:
        // `load` returns exactly what `save` wrote, including `antennas` without leftovers/duplicates.
        let current = try profiles.load("Doma")
        #expect(current.station.call == "OK1XOE")
        #expect(current.cwSpeedStep == 3)
        #expect(current.antennas == home.antennas) // load returns exactly what save stored

        try profiles.delete("Doma")
        #expect(profiles.list() == ["Expedice 2026"])
        #expect(throws: ConfigProfilesError.self) { try profiles.load("Doma") }
        #expect(throws: ConfigProfilesError.self) { try profiles.save("../evil", home) }
        #expect(!ConfigProfiles<AppConfig>.isValidName("a/b"))
        #expect(ConfigProfiles<AppConfig>.isValidName("Multi-op"))
    }
}
