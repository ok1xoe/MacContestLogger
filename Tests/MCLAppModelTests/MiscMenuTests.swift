import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The program's View, Tools and Help items (N1MM Show QRZ / Google, Import country list, Program execution logging,
/// Check for new program version, contest rules, the WA7BNM calendar and the error log). Every outward call goes to
/// the fakes of `SpotApp` (an in-memory HTTP getter and a recording browser); nothing reaches the network.
@MainActor @Suite struct MiscMenuTests {

    nonisolated static let release = #"{"tag_name":"v0.9.2","html_url":"https://github.com/ok1xoe/MacContestLogger/releases/tag/v0.9.2"}"#

    @Test func theMenusHoldTheNewItems() async throws {
        let app = try await TestApp.make()
        let entries: [MenuEntry] = app.model.menu.entries()
        func children(_ id: String) -> [String] {
            entries.first { $0.id == id }?.children.filter { !$0.isSeparator }.map(\.id) ?? []
        }
        #expect(children("view") == ["view.unmatchedMark", "view.qrz", "view.google"])
        #expect(children("help") == ["help.docs", "help.shortcuts", "help.commands", "help.contestRules",
                                     "help.contestCalendar", "help.report", "help.errorLog", "help.dataFolder",
                                     "help.checkUpdates"])
        #expect(children("tools").suffix(4) == ["tools.programLogging", "tools.diagnosticsFolder",
                                                "tools.checkVersion", "tools.checkVersionAtStart"])
        for id in MenuActions.miscIds {
            #expect(app.model.menu.isImplemented(id), "\(id)")
        }
    }

    @Test func theCallOfTheEntryWindowOpensItsQrzAndGooglePages() async throws {
        let spot = try await SpotApp.make()
        #expect(MenuActions.perform("view.google", app: spot.model) == nil)
        #expect(spot.model.status.message == spot.model.language.tr("Nejdřív napiš volačku"))
        spot.model.entry.form.call = "ok1xoe"
        #expect(MenuActions.perform("view.qrz", app: spot.model) == nil)
        #expect(MenuActions.perform("view.google", app: spot.model) == nil)
        await spot.model.callbook.settle()
        #expect(spot.opener.urls == ["https://www.qrz.com/db/OK1XOE", "https://www.google.com/search?q=OK1XOE"])
    }

    @Test func theCalendarAndTheRulesOpenOnlyOnTheClick() async throws {
        let spot = try await SpotApp.make(configure: { config, _ in
            config.contestDataDir = try! Self.contestDataWithRules().path
        })
        #expect(MenuActions.perform("help.contestRules", app: spot.model) == nil)
        #expect(spot.model.status.message == spot.model.language.tr("Pravidla závodu: není aktivní závod"))
        try await spot.app.startCqWwCw()
        #expect(MenuActions.perform("help.contestRules", app: spot.model) == nil)
        #expect(MenuActions.perform("help.contestCalendar", app: spot.model) == nil)
        await spot.model.callbook.settle()
        #expect(spot.opener.urls == ["https://www.cqww.com/rules.htm", "https://www.contestcalendar.com/"])
    }

    @Test func aDefinitionWithoutRulesSaysSo() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        #expect(MenuActions.perform("help.contestRules", app: app.model) == nil)
        #expect(app.model.status.message == app.model.language.tr("Definice závodu nemá odkaz na pravidla"))
    }

    // MARK: - the update check

    @Test func aNewerReleaseIsOfferedAndItsPageOpensOnlyOnTheButton() async throws {
        let spot = try await SpotApp.make(adjust: { $0.appVersion = "0.9.1" })
        spot.http.route("api.github.com/repos/ok1xoe/MacContestLogger/releases/latest", Self.release)
        #expect(MenuActions.perform("tools.checkVersion", app: spot.model) == nil)
        await spot.model.updates.settle()
        let release = UpdateCheck.Release(tag: "v0.9.2",
                                          pageUrl: "https://github.com/ok1xoe/MacContestLogger/releases/tag/v0.9.2")
        #expect(spot.model.updates.notice == .newer(release, current: "0.9.1"))
        #expect(spot.http.urls == [UpdateCheck.latestReleaseUrl])
        #expect(spot.opener.urls.isEmpty)
        spot.model.updates.openReleasePage(release)
        await eventually("page") { spot.opener.urls.count == 1 }
        #expect(spot.opener.urls == [release.pageUrl])
        #expect(spot.model.updates.notice == nil)
    }

    @Test func theManualCheckAlwaysAnswers() async throws {
        let spot = try await SpotApp.make(adjust: { $0.appVersion = "0.9.2" })
        spot.http.route("releases/latest", Self.release)
        _ = MenuActions.perform("help.checkUpdates", app: spot.model)
        await spot.model.updates.settle()
        #expect(spot.model.updates.notice == .upToDate(current: "0.9.2"))
        let failing = try await SpotApp.make(adjust: { $0.appVersion = "0.9.2" })
        failing.http.route("releases/latest", "{}", status: 403)
        failing.model.updates.checkNow()
        await failing.model.updates.settle()
        guard case .failed? = failing.model.updates.notice else {
            Issue.record("expected a failure, got \(String(describing: failing.model.updates.notice))")
            return
        }
        #expect(failing.model.status.message.contains("HTTP 403"))
    }

    @Test func theCheckAtStartIsOffByDefaultAndQuietWhenUpToDate() async throws {
        let off = try await SpotApp.make(adjust: { $0.appVersion = "0.9.1" })
        await off.model.updates.settle()
        #expect(off.http.urls.isEmpty, "no outward call without the user's opt-in")
        #expect(!off.model.updates.checksAtStart)
        #expect(MenuActions.perform("tools.checkVersionAtStart", app: off.model) == nil)
        #expect(MenuActions.isChecked("tools.checkVersionAtStart", app: off.model))
        #expect(await off.app.savedConfigFlushed().checkUpdatesAtStart)

        // Opted in: one request at start, and nothing shown while the version is current.
        let http = FakeHttpGetter()
        http.route("releases/latest", Self.release)
        let current = try await SpotApp.make(configure: { config, _ in config.checkUpdatesAtStart = true },
                                             adjust: { $0.appVersion = "0.9.2"; $0.network.http = http })
        await current.model.updates.settle()
        #expect(http.urls == [UpdateCheck.latestReleaseUrl])
        #expect(current.model.updates.notice == nil)
        #expect(!current.model.updates.isChecking)
    }

    @Test func anInertNetworkNeverConnects() async throws {
        let app = try await TestApp.make(configure: { config, _ in config.checkUpdatesAtStart = true })
        app.model.updates.checkNow()
        await app.model.updates.settle()
        #expect(app.model.updates.notice == nil)
        #expect(app.model.status.message == app.model.language.tr("Síť je vypnutá (MCL_INERT_NETWORK)"))
    }

    // MARK: - the country list, the logs

    @Test func anImportedCountryListBecomesTheDxccSourceUntilRemoved() async throws {
        let app = try await TestApp.make()
        let file = app.dir.child("wl_cty.dat")
        try Data("Atlantis:  01:  01:  EU:  10.00:  10.00:  0.0:  ZZ9:\n    OK,ZZ9;\n".utf8).write(to: file)
        #expect(MenuActions.perform("tools.importCountryFile", app: app.model) == .openCountryFile)
        app.model.dataTools.importCountryFile(file)
        await app.model.dataTools.settle()
        #expect(app.model.dataTools.hasImportedCountryFile)
        #expect(app.model.contest.runtime.dxccLookup?.resolve("OK1XOE")?.name == "Atlantis")
        #expect(app.model.status.message.contains("wl_cty.dat"))
        _ = MenuActions.perform("tools.removeCountryFile", app: app.model)
        await app.model.dataTools.settle()
        #expect(!app.model.dataTools.hasImportedCountryFile)
        #expect(app.model.contest.runtime.dxccLookup?.resolve("OK1XOE")?.name != "Atlantis")
    }

    @Test func aFileWithoutCountriesKeepsTheSource() async throws {
        let app = try await TestApp.make()
        let file = app.dir.child("readme.txt")
        try Data("nothing here".utf8).write(to: file)
        app.model.dataTools.importCountryFile(file)
        await app.model.dataTools.settle()
        #expect(!app.model.dataTools.hasImportedCountryFile)
        #expect(app.model.status.message == app.model.language.text(DataToolsModel.countryFileText(.noEntities)))
    }

    @Test func theDiagnosticsFolderIsInTheDataFolder() async throws {
        let app = try await TestApp.make()
        let dir = app.model.dataDir.appendingPathComponent("diagnostics")
        #expect(MenuActions.perform("tools.diagnosticsFolder", app: app.model) == .openDataFolder(dir))
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func programLoggingIsAToggle() async throws {
        let app = try await TestApp.make()
        let log: ProgramLog = .shared
        let was: Bool = log.isEnabled
        defer { log.setEnabled(was) }
        log.setEnabled(false)
        _ = MenuActions.perform("tools.programLogging", app: app.model)
        #expect(log.isEnabled)
        #expect(MenuActions.isChecked("tools.programLogging", app: app.model))
        _ = MenuActions.perform("tools.programLogging", app: app.model)
        #expect(!log.isEnabled)
    }

    /// The fixture contest data with a rules link in CQ WW CW.
    nonisolated static func contestDataWithRules() throws -> URL {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: Fixtures.contestData, to: target)
        let yaml = target.appendingPathComponent("contests/cq-ww-cw.yaml")
        let text = try String(contentsOf: yaml, encoding: .utf8)
            .replacingOccurrences(of: "  organizer: \"CQ Magazine\"\n",
                                  with: "  organizer: \"CQ Magazine\"\n  officialUrl: \"https://www.cqww.com/rules.htm\"\n")
        try text.write(to: yaml, atomically: true, encoding: .utf8)
        return target
    }
}
