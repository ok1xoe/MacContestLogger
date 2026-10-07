import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The menu bar after the restructure: File, Edit, Contest, Tools, Settings, Window, Help (N1MM-like), every action
/// still reachable, the Edit items running the entry shortcuts and showing the user's keys, the Help items opening the
/// public repository's pages.
@MainActor @Suite struct MenuRestructureTests {

    private static func ids(_ entries: [MenuEntry]) -> [String] {
        entries.flatMap { [$0.id] + ids($0.children) }
    }

    private static func entry(_ id: String, in entries: [MenuEntry]) -> MenuEntry? {
        for entry in entries {
            if entry.id == id {
                return entry
            }
            if let found = Self.entry(id, in: entry.children) {
                return found
            }
        }
        return nil
    }

    @Test func theMenuBarHasOneOfEachInNOneMmOrder() async throws {
        let app = try await TestApp.make()
        let entries: [MenuEntry] = app.model.menu.entries()
        #expect(entries.map(\.id) == ["file", "edit", "contest", "tools", "settings", "window", "help"])
        #expect(entries.map(\.title) == ["Soubor", "Úpravy", "Závod", "Nástroje", "Nastavení", "Okno", "Nápověda"])
        await app.model.language.switchTo("en")
        #expect(app.model.menu.entries().map(\.title) == ["File", "Edit", "Contest", "Tools", "Settings", "Window",
                                                          "Help"])
        await app.model.language.switchTo("cs")
    }

    /// Every action the model implements is in the shipped tree (nothing became unreachable), once.
    @Test func everyImplementedActionIsInTheTree() async throws {
        let app = try await TestApp.make()
        let ids: [String] = Self.ids(app.model.menu.entries())
        // „Vymazat seznam" is only in the menu while there is something to clear (`OpenRecentTests`).
        for action in MenuModel.implementedActions.subtracting(["recent.clear"]) {
            #expect(ids.filter { $0 == action }.count == 1, "\(action) is not exactly once in the menu")
        }
        #expect(Set(ids).count == ids.count, "an id is in the menu twice")
    }

    @Test func fileToolsAndSettingsHoldTheMovedItems() async throws {
        let app = try await TestApp.make()
        let entries: [MenuEntry] = app.model.menu.entries()
        func children(_ id: String) throws -> [String] {
            try #require(Self.entry(id, in: entries)).children.filter { !$0.isSeparator }.map(\.id)
        }
        #expect(try children("file") == ["contest.new", "contest.open", "file.openRecent", "database.new",
                                         "database.open", "file.copyContest", "file.import", "file.export",
                                         "file.post3830", "settings.print"])
        #expect(try children("file.import") == ["settings.import", "settings.merge"])
        #expect(try children("file.export") == ["settings.export", "settings.exportAdifRange",
                                                "settings.exportCabrillo", "settings.exportEdi",
                                                "settings.exportOther", "callhistory.exportN1mm",
                                                "callhistory.exportCsv"])
        #expect(try children("tools") == ["contest.rescore", "contest.rescoreHours", "database.refillDxcc",
                                          "tools.addCallToCountry", "settings.downloadScp",
                                          "contest.updateDefinitions", "database.updateClubLogDxcc",
                                          "contest.updateCallHistory", "callhistory.clear", "beacons.load",
                                          "contest.editor"])
        #expect(try children("settings") == ["settings.open", "settings.keys", "settings.profiles"])
        #expect(try children("contest") == ["contest.postcontest", "contest.record", "contest.none"])
        #expect(try children("help") == ["help.docs", "help.shortcuts", "help.commands", "help.report",
                                         "help.dataFolder"])
        let file: MenuEntry = try #require(Self.entry("file", in: entries))
        #expect(file.children.filter(\.isSeparator).count == 3)
        #expect(MenuShape(entries) == MenuShape(entries))
    }

    @Test func editItemsShowTheUsersKeys() async throws {
        let app = try await TestApp.make()
        let menu: MenuModel = app.model.menu
        func hint(_ id: String) -> String? {
            Self.entry(id, in: menu.entries())?.shortcut
        }
        #expect(hint("edit.wipe") == "Ctrl+W")
        #expect(hint("edit.wipeUndo") == "Alt+W")
        #expect(hint("edit.note") == "Ctrl+N")
        #expect(hint("edit.find") == "Ctrl+F")
        #expect(hint("edit.deleteLast") == "Ctrl+D")
        #expect(hint("edit.incrementNr") == "Ctrl+U")
        #expect(hint("help.docs") == "Alt+H")
        #expect(hint("settings.keys") == nil)
        // A remapped key shows up, an action without a key shows none.
        app.model.config.config.keyBindings = [ShortcutAction.wipe.id: "Ctrl+Alt+X", ShortcutAction.find.id: ""]
        #expect(hint("edit.wipe") == "Ctrl+Alt+X")
        #expect(hint("edit.find") == nil)
        #expect(hint("edit.note") == "Ctrl+N")
    }

    @Test func editItemsRunTheEntryShortcuts() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        model.entry.form.call = "OK1ABC"
        #expect(MenuActions.perform("edit.wipe", app: model) == nil)
        #expect(model.entry.form.call.isEmpty)
        model.entry.form.call = "OK2XYZ"
        #expect(MenuActions.perform("edit.wipe", app: model) == nil)
        #expect(MenuActions.perform("edit.wipeUndo", app: model) == nil)
        #expect(model.status.message != EntryTexts.unavailable)
    }

    @Test func settingsKeysOpensTheKeysTab() async throws {
        let app = try await TestApp.make()
        #expect(MenuActions.perform("settings.keys", app: app.model) == nil)
        #expect(app.model.settings.isOpen)
        #expect(app.model.settings.selected == .keys)
    }

    @Test func helpItemsOpenThePublicPages() async throws {
        let spot = try await SpotApp.make()
        for id in ["help.docs", "help.shortcuts", "help.commands", "help.report"] {
            #expect(MenuActions.perform(id, app: spot.model) == nil)
        }
        await spot.model.callbook.settle()
        #expect(spot.opener.urls == [
            "https://github.com/ok1xoe/MacContestLogger/tree/main/docs",
            "https://github.com/ok1xoe/MacContestLogger/blob/main/docs/keyboard-shortcuts.md",
            "https://github.com/ok1xoe/MacContestLogger/blob/main/docs/text-commands.md",
            "https://github.com/ok1xoe/MacContestLogger/issues",
        ])
    }

    @Test func dataFolderRequestHonoursTheDataDirectory() async throws {
        let app = try await TestApp.make()
        #expect(MenuActions.perform("help.dataFolder", app: app.model) == .openDataFolder(app.model.dataDir))
    }

    /// The docs the Help items point at exist in the repository.
    @Test func theLinkedDocsExist() throws {
        let docs: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs")
        for name in ["keyboard-shortcuts.md", "text-commands.md"] {
            #expect(FileManager.default.fileExists(atPath: docs.appendingPathComponent(name).path), "\(name)")
        }
    }
}
