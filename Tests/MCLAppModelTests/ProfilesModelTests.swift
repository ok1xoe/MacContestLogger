import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// Configuration profiles (`PW:1-67`, `AS:2502-2527`): save, load with the Jackson merge (atomic), delete.
@MainActor @Suite struct ProfilesModelTests {

    static func profilesDir(_ app: TestApp) -> URL {
        app.dataDir.appendingPathComponent("profiles")
    }

    static func writeProfile(_ app: TestApp, _ fileName: String, _ json: String) throws {
        let dir: URL = profilesDir(app)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent(fileName))
    }

    @Test func saveTrimsTheNameAndListsIt() async throws {
        let app = try await TestApp.make()
        let profiles: ProfilesModel = app.model.profiles

        await profiles.save(name: "   ")
        #expect(app.model.status.message == "")
        #expect(!FileManager.default.fileExists(atPath: Self.profilesDir(app).path))

        await profiles.save(name: "  Doma ")

        #expect(app.model.status.message == "Profil „Doma“ uložen")
        #expect(profiles.names == ["Doma"])
        let saved: Data = try Data(contentsOf: Self.profilesDir(app).appendingPathComponent("Doma.json"))
        #expect(try JSONDecoder().decode(AppConfig.self, from: saved).station.call == "OK1XOE")
    }

    @Test func saveWithAnInvalidNameShowsJavasMessage() async throws {
        let app = try await TestApp.make()
        await app.model.profiles.save(name: "a/b")
        #expect(app.model.status.message == "Profil: Neplatné jméno profilu: a/b")
        #expect(app.model.profiles.names.isEmpty)
    }

    @Test func loadMergesAppliesAndKeepsTheContestOpen() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try await app.startCqWwCw()
        let activeId: String? = model.contest.activeId
        let gridBefore: String = model.config.config.station.gridSquare
        #expect(model.operating.autoRunSwitch)
        try Self.writeProfile(app, "Expedice.json", #"{"station":{"call":"OK2ABC"},"runMode":{"autoSwitch":false}}"#)

        await model.profiles.load("Expedice")

        #expect(model.status.message
            == "Profil „Expedice“ načten — rig a síťová spojení připoj znovu (nebo restartuj aplikaci)")
        // Jackson merge: the nested object is merged field by field.
        #expect(model.config.config.station.call == "OK2ABC")
        #expect(model.config.config.station.gridSquare == gridBefore)
        #expect(!model.operating.autoRunSwitch)
        #expect(await app.savedConfigFlushed().station.call == "OK2ABC")
        // The contest data reloaded, the contest still open.
        #expect(model.contest.activeId == activeId)
        #expect(!model.contest.isActivating)
        #expect(model.profiles.names == ["Expedice"])
    }

    @Test func loadOfAMissingProfileChangesNothing() async throws {
        let app = try await TestApp.make()
        await app.model.profiles.load("Nikde")
        #expect(app.model.status.message == "Profil: Profil neexistuje: Nikde")
        #expect(app.model.config.config.station.call == "OK1XOE")
    }

    @Test func aRejectedProfileIsNotAppliedHalfway() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        try Self.writeProfile(app, "Rozbity.json", #"{"station":{"call":"OK2ABC"},"bogusKey":1}"#)

        await model.profiles.load("Rozbity")

        #expect(model.status.message.hasPrefix("Profil: Unrecognized field \"bogusKey\""))
        // Jackson would leave the station call applied (the partial state); the load is atomic here.
        #expect(model.config.config.station.call == "OK1XOE")
        #expect(await app.savedConfigFlushed().station.call == "OK1XOE")
    }

    @Test func aDirectoryNamedLikeAProfileGivesJavasError() async throws {
        let app = try await TestApp.make()
        let dir: URL = Self.profilesDir(app).appendingPathComponent("Slozka.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        await app.model.profiles.load("Slozka")

        #expect(app.model.status.message == "Profil: " + dir.path + " (Is a directory)")
    }

    @Test func profileFileNamesAreTrimmedLikeJava() async throws {
        let app = try await TestApp.make()
        try Self.writeProfile(app, "plain.json", #"{"station":{"call":"OK3PL"}}"#)
        try Self.writeProfile(app, "\u{a0}nbsp\u{a0}.json", #"{"station":{"call":"OK4NB"}}"#)

        await app.model.profiles.load("  plain \t")
        #expect(app.model.config.config.station.call == "OK3PL")
        // Java `trim()` keeps a no-break space (probe `profile-files.tsv`).
        await app.model.profiles.load("\u{a0}nbsp\u{a0}")
        #expect(app.model.config.config.station.call == "OK4NB")
        await app.model.profiles.load("nbsp")
        #expect(app.model.status.message == "Profil: Profil neexistuje: nbsp")
    }

    /// The profile load runs `ConfigEffectPlan.profileLoad` through the Settings executor — the inner effects
    /// of `saveConfig`, then mode settings, keys, radio mode, Alt+F11, contest data, revision and the text, which
    /// comes last. `replacesAntennas` follows the file's `antennas` key.
    @Test func loadRunsTheProfilePlanInOrder() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        try Self.writeProfile(harness.app, "Bez.json", #"{"station":{"call":"OK2ABC"}}"#)
        try Self.writeProfile(harness.app, "S.json", #"{"antennas":[{"name":"Yagi"}],"station":{"call":"OK3ABC"}}"#)

        await model.profiles.load("Bez")

        #expect(harness.recorder.effects == ConfigEffectPlan.profileLoad(name: "Bez", replacesAntennas: false))
        #expect(harness.recorder.calls == ["dxMyCall OK2ABC cs"])
        #expect(model.status.message
            == "Profil „Bez“ načten — rig a síťová spojení připoj znovu (nebo restartuj aplikaci)")
        #expect(model.config.revision == 1)

        harness.recorder.effects = []
        await model.profiles.load("S")
        #expect(harness.recorder.effects == ConfigEffectPlan.profileLoad(name: "S", replacesAntennas: true))
        #expect(model.config.config.antennas.map(\.name) == ["Yagi"])
    }

    /// A profile does not switch the language (Kotlin never calls `I18n.use` there), but the look follows it;
    /// ESM is not synced from it.
    @Test func loadKeepsTheLanguageAndAppliesTheLook() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        try Self.writeProfile(harness.app, "Noc.json",
                              #"{"language":"en","themeMode":"DARK","themeAccent":"CONTRAST","esm":{"enabled":true}}"#)
        #expect(model.appearance.appearance == .system)

        await model.profiles.load("Noc")

        #expect(model.config.config.language == "en")
        #expect(model.language.code == "cs")
        #expect(model.appearance.appearance == .dark)
        #expect(model.appearance.isContrast)
        #expect(model.config.config.esm.enabled)
        #expect(!model.operating.esmEnabled)
    }

    /// Atomic profile load: a failed write shows `"Profil: " + message` and changes nothing.
    @Test func failedWriteOfAProfileChangesNothing() async throws {
        let harness = try await SettingsHarness.make()
        let model: AppModel = harness.model
        try Self.writeProfile(harness.app, "P.json", #"{"station":{"call":"OK2ABC"}}"#)
        let before: AppConfig = model.config.config
        harness.writer.setFailing(true)

        await model.profiles.load("P")

        #expect(model.status.message == "Profil: disk full")
        #expect(model.config.config == before)
        #expect(model.config.revision == 0)
        #expect(harness.recorder.effects == [.saveConfig(onFailure: .abortPlan(status: .profileFailed))])
    }

    @Test func antennasKeyDetection() {
        #expect(ProfilesModel.hasAntennasKey(Data(#"{"antennas":[]}"#.utf8)))
        #expect(!ProfilesModel.hasAntennasKey(Data(#"{"station":{"antennas":[]}}"#.utf8)))
        #expect(!ProfilesModel.hasAntennasKey(Data("[1]".utf8)))
        #expect(!ProfilesModel.hasAntennasKey(Data("nonsense".utf8)))
    }

    @Test func deleteIsSilentAndRefreshesTheList() async throws {
        let app = try await TestApp.make()
        let profiles: ProfilesModel = app.model.profiles
        try Self.writeProfile(app, "b.json", "{}")
        try Self.writeProfile(app, "a.json", "{}")
        await profiles.refresh()
        #expect(profiles.names == ["a", "b"])
        app.model.status.showVerbatim("before")

        await profiles.delete("a")
        await profiles.delete("missing")

        #expect(profiles.names == ["b"])
        #expect(app.model.status.message == "before")
    }
}
