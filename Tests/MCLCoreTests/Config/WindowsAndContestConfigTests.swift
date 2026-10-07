import Foundation
import Testing
@testable import MCLCore

/// A small helper structure for the `ConfigProfiles<Profile>` tests — a generic type
/// independent of `AppConfig` (which is a separate type in Swift), see
/// the documentation comment at `ConfigProfiles`.
private struct ProfileFixture: Codable, Equatable, Sendable {
    var call: String = ""
    var speedStep: Int = 0
}

@Suite struct WindowsAndContestConfigTests {

    // MARK: - An empty JSON gives the same values as init()

    @Test func emptyJsonEqualsDefaults() throws {
        let empty = Data("{}".utf8)
        #expect(try JSONDecoder().decode(InfoWindowConfig.self, from: empty) == InfoWindowConfig())
        #expect(try JSONDecoder().decode(MenuConfig.self, from: empty) == MenuConfig())
        #expect(try JSONDecoder().decode(MenuNode.self, from: empty) == MenuNode())
        #expect(try JSONDecoder().decode(StationConfig.self, from: empty) == StationConfig())
        #expect(try JSONDecoder().decode(EsmConfig.self, from: empty) == EsmConfig())
        #expect(try JSONDecoder().decode(RunModeConfig.self, from: empty) == RunModeConfig())
    }

    /// A missing key must give an empty collection, not `nil`.
    @Test func contestSetupDefaultsToEmptyCollections() throws {
        let s = try JSONDecoder().decode(ContestSetup.self, from: Data("{}".utf8))
        #expect(s.category.isEmpty)
        #expect(s.sentExchange.isEmpty)
        #expect(s.skeds.isEmpty)
        #expect(s.bonusStations.isEmpty)
        #expect(s.operators == "")
        #expect(s.tour == "")
    }

    // MARK: - InfoWindowConfigTest

    @Test func defaultsMatchN1mmBehaviour() {
        let c = InfoWindowConfig()
        #expect(c.trendMinutes == 20) // N1MM offers 20/30/60, the default is the shortest
        #expect(c.showTimers)
        #expect(c.offTimeMode == "sinceLastQso")
        // Info rows are on by default — they are the main content of the window.
        #expect(c.showCallframeSpot)
        #expect(c.showCountryInfo)
        #expect(c.showSunTimes)
        #expect(c.showWwv)
        #expect(c.showGoals)
        #expect(c.showMessages)
    }

    @Test func trendMinutesAcceptsOnlyOfferedIntervals() {
        var c = InfoWindowConfig()
        c.trendMinutes = 60
        #expect(c.trendMinutes == 60)
        // A nonsensical value (a hand-edited config) falls back to the default,
        // otherwise the graph would work with an interval that cannot be chosen in the UI.
        c.trendMinutes = 7
        #expect(c.trendMinutes == 20)
    }

    @Test func unknownOffTimeModeFallsBackToDefault() {
        var c = InfoWindowConfig()
        c.offTimeMode = "cumulativeOff"
        #expect(c.offTimeMode == "cumulativeOff")
        c.offTimeMode = "nesmysl"
        #expect(c.offTimeMode == "sinceLastQso")
    }

    // `survivesConfigRoundTrip` (really via `ConfigStore`/`AppConfig`) is
    // ported in `ConfigStoreTests.infoWindowConfigSurvivesConfigRoundTrip`
    // — the temporary replacement directly over `InfoWindowConfig` is no longer needed here.

    // MARK: - MenuConfigJsonTest

    @Test func deserializesNestedTree() throws {
        let json = """
            {"menu":[{"id":"settings","label":"Nastavení","state":"enable",
            "children":[{"id":"settings.open","state":"disable",
            "children":[{"id":"tab.hardware","label":"HW","state":"hidden"}]}]}]}
            """
        let c = try JSONDecoder().decode(MenuConfig.self, from: Data(json.utf8))
        #expect(c.menu.count == 1)
        let settings = c.menu[0]
        #expect(settings.id == "settings")
        #expect(settings.state == .enable)
        let open = settings.children[0]
        #expect(open.state == .disable)
        #expect(open.label == nil)
        #expect(open.children[0].state == .hidden)
        #expect(open.children[0].label == "HW")
    }

    @Test func missingStateDefaultsEnable() throws {
        let c = try JSONDecoder().decode(MenuConfig.self, from: Data(#"{"menu":[{"id":"x"}]}"#.utf8))
        #expect(c.menu[0].state == .enable)
        #expect(c.menu[0].children.isEmpty)
    }

    // MARK: - MenuConfigStoreTest

    private static let validMenuJson = """
        { "menu": [ { "id": "settings", "label": "Moje nastavení", "state": "enable" } ] }
        """

    private func tempMenuFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("menu.json")
    }

    private func tempMenuDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func findMenuNode(id: String, in nodes: [MenuNode]) -> MenuNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findMenuNode(id: id, in: node.children) { return found }
        }
        return nil
    }

    /// A regression pin: the built-in menu must come from the bundled resource
    /// (richer than the code-built `DefaultMenu.tree()`), not from the fallback —
    /// otherwise a fresh installation would have Settings two items poorer than Java.
    @Test func builtInMenuIncludesHamqthAndQrzUnderOnlineLogs() {
        let onlineLogs = findMenuNode(id: "tab.online_logs", in: MenuConfigStore.builtIn().menu)
        #expect(onlineLogs?.children.map(\.id) == ["tab.hamqth", "tab.qrz"])
    }

    @Test func menuConfigStoreMissingFileUsesDefaultTree() {
        let dir = tempMenuDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = MenuConfigStore.loadFrom(dataDir: dir)
        #expect(result.source == .builtIn)
        #expect(result.error == nil)
        #expect(!result.menu.menu.isEmpty)
        #expect(result.menu.menu.first?.id == "settings") // the built-in menu starts with Settings
    }

    @Test func menuConfigStoreUserFileWins() throws {
        let dir = tempMenuDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.validMenuJson.write(to: dir.appendingPathComponent("menu.json"), atomically: true, encoding: .utf8)

        let result = MenuConfigStore.loadFrom(dataDir: dir)

        #expect(result.source == .user)
        #expect(result.error == nil)
        #expect(result.menu.menu.count == 1)
        #expect(result.menu.menu[0].label == "Moje nastavení")
    }

    @Test func menuConfigStoreBrokenFileFallsBackAndReportsWhy() throws {
        let dir = tempMenuDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ \"menu\": [ { \"id\": ".write(
            to: dir.appendingPathComponent("menu.json"), atomically: true, encoding: .utf8)

        let result = MenuConfigStore.loadFrom(dataDir: dir)

        #expect(result.source == .userInvalid)
        #expect(result.error != nil, "the user must learn why their file was not used")
        #expect(!result.menu.menu.isEmpty, "the application must not be left without a menu")
        #expect(result.menu.menu.first?.id == "settings")
    }

    @Test func menuConfigStoreErrorSaysWhereTheProblemIs() throws {
        // The user edits the file in an editor — wants to know the line, not a technical message.
        let dir = tempMenuDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{\n  \"menu\": [\n    { \"id\": \n".write(
            to: dir.appendingPathComponent("menu.json"), atomically: true, encoding: .utf8)

        let error = try #require(MenuConfigStore.loadFrom(dataDir: dir).error)

        #expect(error.contains("řádek"))
        #expect(!error.contains("reference chain"))
    }

    @Test func menuConfigStoreEmptyMenuFallsBack() throws {
        // An empty list = an application without menus; take it as an error, not as a wish.
        let dir = tempMenuDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ \"menu\": [] }".write(to: dir.appendingPathComponent("menu.json"), atomically: true, encoding: .utf8)

        let result = MenuConfigStore.loadFrom(dataDir: dir)

        #expect(result.source == .userInvalid)
        #expect(!result.menu.menu.isEmpty)
    }

    @Test func menuConfigStoreWritesBuiltInCopyForEditing() throws {
        let dir = tempMenuDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try #require(try MenuConfigStore.writeBuiltIn(dataDir: dir, overwrite: false))

        #expect(written == dir.appendingPathComponent("menu.json"))
        let content = try String(contentsOf: written, encoding: .utf8)
        #expect(content.contains("\"menu\""))
        // The written copy must be usable as a user file.
        #expect(MenuConfigStore.loadFrom(dataDir: dir).source == .user)
    }

    @Test func menuConfigStoreDoesNotOverwriteUserFileUnlessAsked() throws {
        let dir = tempMenuDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.validMenuJson.write(to: dir.appendingPathComponent("menu.json"), atomically: true, encoding: .utf8)

        #expect(
            try MenuConfigStore.writeBuiltIn(dataDir: dir, overwrite: false) == nil,
            "edits are not overwritten without permission")
        #expect(MenuConfigStore.loadFrom(dataDir: dir).menu.menu.first?.label == "Moje nastavení")

        #expect(try MenuConfigStore.writeBuiltIn(dataDir: dir, overwrite: true) != nil)
        #expect(MenuConfigStore.loadFrom(dataDir: dir).menu.menu.first?.id == "settings")
    }

    /// `save` has no counterpart in the Java `MenuConfigStore` (the menu is only read there) —
    /// but the interface `save(_:to:)` is wanted, so it is tested
    /// by a new test, not by a port.
    @Test func menuConfigStoreSaveThenLoadRoundTrips() throws {
        let file = tempMenuFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var config = MenuConfig()
        config.menu = [MenuNode(id: "settings", label: "Uložené", state: .enable, children: [])]

        MenuConfigStore.save(config, to: file)
        let loaded = MenuConfigStore.load(from: file)

        #expect(loaded == config)
    }

    // MARK: - DefaultMenuTest

    @Test func topLevelMenusInOrder() {
        let ids = DefaultMenu.tree().menu.map(\.id)
        #expect(ids == ["settings", "contest", "database", "window", "buffer"])
    }

    @Test func settingsOpenHas20Tabs() {
        let settings = DefaultMenu.tree().menu[0]
        let open = settings.children[0]
        #expect(open.id == "settings.open")
        #expect(open.children.count == 21)
        #expect(open.children.allSatisfy { $0.id.hasPrefix("tab.") })
    }

    @Test func bufferIsHidden() {
        let buffer = DefaultMenu.tree().menu[4]
        #expect(buffer.id == "buffer")
        #expect(buffer.state == .hidden)
    }

    @Test func labelForKnownAndUnknown() {
        #expect(DefaultMenu.labelFor("window.log") == "Přehled spojení")
        #expect(DefaultMenu.labelFor("tab.function-keys") == "Function Keys")
        #expect(DefaultMenu.labelFor("nope") == nil)
    }

    // MARK: - StationConfigTest

    @Test func freshConfigHasEmptyNewFields() {
        let s = AppConfig().station
        #expect(s.address1 == "")
        #expect(s.country == "")
        #expect(s.cqZone == "")
        #expect(s.asl == "")
        #expect(s.email == "")
    }

    // `savesAndReloadsAllStationFields` (really via `ConfigStore`/`AppConfig`)
    // is ported in `ConfigStoreTests.stationConfigSavesAndReloadsAllFields`
    // — the temporary replacement directly over `StationConfig` is no longer needed here.

    @Test func stationConfigToStationAndFrom() {
        var s = StationConfig()
        s.call = "OK1XOE"
        s.operator = "OK1ABC"
        s.gridSquare = "JO70"
        s.name = "Tomáš"

        let station = s.toStation()
        #expect(station.call == "OK1XOE")
        #expect(station.operator == "OK1ABC")
        #expect(station.gridSquare == "JO70")
        #expect(station.name == "Tomáš")

        let back = StationConfig.from(station)
        #expect(back.call == "OK1XOE")
        #expect(back.operator == "OK1ABC")

        let empty = StationConfig.from(nil)
        #expect(empty == StationConfig())
    }

    // MARK: - ContestSetupTest
    //
    // `appConfigStoresSetup` is ported as `ConfigStoreTests.contestSetupAppConfigStoresSetup`
    // (it needed `AppConfig`).

    @Test func contestSetupDefaultsAreEmptyNonNull() {
        let s = ContestSetup()
        #expect(s.category.isEmpty)
        #expect(s.sentExchange.isEmpty)
        #expect(s.operators == "")
        #expect(s.soapbox == "")
    }

    /// Replaces the Java `nullSettersCoerced`: in Swift these fields are
    /// non-optional (`[String: String]`/`String`, not `nil`-able), so a "setter
    /// with null" cannot even be written — the equivalent behaviour is an explicit `null`
    /// in the decoded JSON.
    @Test func contestSetupExplicitNullsDecodeToEmptyDefaults() throws {
        let json = #"{"category":null,"sentExchange":null,"operators":null,"soapbox":null}"#
        let s = try JSONDecoder().decode(ContestSetup.self, from: Data(json.utf8))
        #expect(s.category.isEmpty)
        #expect(s.sentExchange.isEmpty)
        #expect(s.operators == "")
        #expect(s.soapbox == "")
    }

    /// Replaces `appConfigContestSetupsNeverNull`: `AppConfig.contestSetups` is
    /// non-optional `[String: ContestSetup]`, so `setContestSetups(null)` from Java
    /// does not translate — the equivalent input is JSON with an explicit `null`. A match with Java:
    /// `setContestSetups(null)` in Java substitutes a new empty `LinkedHashMap`, `{"contestSetups": null}`
    /// in Swift substitutes the declared default `[:]` — both empty.
    @Test func appConfigExplicitNullContestSetupsDecodesToEmptyMap() throws {
        let json = #"{"contestSetups": null}"#
        let a = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(a.contestSetups.isEmpty)
    }

    // MARK: - ContestSetupDatesTest

    @Test func contestSetupDatesDefaultEmpty() {
        let s = ContestSetup()
        #expect(s.startedAt == "")
        #expect(s.endedAt == "")
    }

    /// Replaces the Java `datesDefaultEmptyAndNullSafe` (a setter with `null`) —
    /// see `contestSetupExplicitNullsDecodeToEmptyDefaults`.
    @Test func contestSetupExplicitNullStartedAtDecodesToEmpty() throws {
        let json = #"{"startedAt":null,"endedAt":"2026-11-28 00:00"}"#
        let s = try JSONDecoder().decode(ContestSetup.self, from: Data(json.utf8))
        #expect(s.startedAt == "")
        #expect(s.endedAt == "2026-11-28 00:00")
    }

    // MARK: - ConfigProfilesTest
    //
    // The Java `ConfigProfilesTest.saveListLoadDelete` is one test that
    // verifies both: (a) the file layer (list/save/delete/isValidName) and
    // (b) merging a profile into an existing `AppConfig` instance via Jackson's
    // mergeable `ObjectMapper`. (a) does not depend on `AppConfig` and is ported below.
    // (b) is ported as `ConfigStoreTests.configProfilesSaveListLoadDelete`
    // — `ConfigProfiles<Profile>` stayed unchanged (it is generic,
    // the "wiring" to `AppConfig` is just its use with `Profile == AppConfig`);
    // Jackson's `assertSame` (object identity after merge) has no counterpart for a value
    // type, see the doc comment of `ConfigProfiles.swift` and the comment at
    // of that test.

    @Test func configProfilesIsValidName() {
        #expect(ConfigProfiles<ProfileFixture>.isValidName("Multi-op"))
        #expect(!ConfigProfiles<ProfileFixture>.isValidName("a/b"))
        #expect(!ConfigProfiles<ProfileFixture>.isValidName(""))
        #expect(!ConfigProfiles<ProfileFixture>.isValidName("   "))
        #expect(!ConfigProfiles<ProfileFixture>.isValidName(String(repeating: "a", count: 41)))
    }

    @Test func configProfilesSaveListLoadDeleteRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let profiles = ConfigProfiles<ProfileFixture>(dir: dir)

        try profiles.save("Doma", ProfileFixture(call: "OK1XOE", speedStep: 3))
        try profiles.save("Expedice 2026", ProfileFixture(call: "OK1XOE/P", speedStep: 1))

        #expect(profiles.list() == ["Doma", "Expedice 2026"])
        #expect(try profiles.load("Doma") == ProfileFixture(call: "OK1XOE", speedStep: 3))

        try profiles.delete("Doma")
        #expect(profiles.list() == ["Expedice 2026"])
        #expect(throws: ConfigProfilesError.self) { try profiles.load("Doma") }
    }

    @Test func configProfilesInvalidNameThrowsOnSave() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let profiles = ConfigProfiles<ProfileFixture>(dir: dir)
        #expect(throws: ConfigProfilesError.self) { try profiles.save("../evil", ProfileFixture()) }
    }

    @Test func configProfilesMissingProfileThrowsOnLoad() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let profiles = ConfigProfiles<ProfileFixture>(dir: dir)
        #expect(throws: ConfigProfilesError.self) { try profiles.load("Neexistuje") }
    }

    // MARK: - EsmConfig / RunModeConfig (no Java test, just defaults and clamp)

    @Test func esmConfigDefaults() {
        let e = EsmConfig()
        #expect(!e.enabled)
        #expect(!e.spCallOnce)
        #expect(e.workDupes)
    }

    @Test func runModeConfigDefaultsAndClampsRepeatSeconds() {
        var r = RunModeConfig()
        #expect(r.autoSwitch)
        #expect(r.runOnCqFrequency)
        #expect(r.repeatSeconds == 2.0)

        r.repeatSeconds = 0.01
        #expect(r.repeatSeconds == 0.2)
        r.repeatSeconds = 999
        #expect(r.repeatSeconds == 120.0)
    }
}
