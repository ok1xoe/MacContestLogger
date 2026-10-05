import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// `MenuModel` (`KApp:543-608`): the source of the menu, a broken `menu.json`, labels and enabling.
@MainActor @Suite struct MenuModelTests {

    private static func node(_ id: String, in nodes: [MenuNode]) -> MenuNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let found = Self.node(id, in: node.children) {
                return found
            }
        }
        return nil
    }

    @Test func builtInMenuWithoutUserFile() async throws {
        let app = try await TestApp.make()
        let menu: MenuModel = app.model.menu
        #expect(menu.source == .builtIn)
        #expect(!menu.tree.isEmpty)
        #expect(menu.loadError == nil)
        #expect(menu.revision == 0)
    }

    @Test func brokenMenuJsonIsReported() async throws {
        let app = try await TestApp.make { _, dataDir in
            try Data("{ \"menu\": [".utf8).write(to: dataDir.appendingPathComponent("menu.json"))
        }
        let menu: MenuModel = app.model.menu
        #expect(menu.source == .userInvalid)
        let error: String = try #require(menu.loadError)
        #expect(error.contains("menu.json"))
        #expect(app.model.status.message == "Menu: " + error + " Platí vestavěné menu.")
        #expect(!menu.tree.isEmpty)

        // A reload reports in the status line only (no dialog after start-up).
        menu.loadError = nil
        await menu.reload()
        #expect(menu.revision == 1)
        #expect(menu.loadError == nil)
        #expect(app.model.status.message.hasPrefix("Menu: "))
    }

    @Test func emptyUserMenuIsReported() async throws {
        let app = try await TestApp.make { _, dataDir in
            try Data(#"{"menu":[]}"#.utf8).write(to: dataDir.appendingPathComponent("menu.json"))
        }
        #expect(app.model.menu.source == .userInvalid)
        #expect(app.model.menu.loadError?.contains("nemá žádnou položku menu") == true)
    }

    @Test func labelsFollowTheLanguage() async throws {
        let app = try await TestApp.make()
        let menu: MenuModel = app.model.menu
        let newContest: MenuNode = try #require(Self.node("contest.new", in: menu.tree))
        let czech: String = menu.label(newContest)
        await app.model.language.switchTo("en")
        let english: String = menu.label(newContest)
        #expect(czech != english)
        #expect(english == app.model.language.translator.translate(newContest.label
            ?? DefaultMenu.labelFor("contest.new") ?? "contest.new"))
        let unknown = MenuNode(id: "x.unknown")
        #expect(menu.label(unknown) == "x.unknown")
    }

    @Test func enablingFollowsContestAndImplementation() async throws {
        let app = try await TestApp.make()
        let menu: MenuModel = app.model.menu
        let rescore: MenuNode = try #require(Self.node("contest.rescore", in: menu.tree))
        let new: MenuNode = try #require(Self.node("contest.new", in: menu.tree))
        // Every item of the shipped menu is implemented; an item of a user menu that nothing knows is not.
        let future = MenuNode(id: "x.future")
        #expect(!menu.isEnabled(rescore))
        #expect(menu.isEnabled(new))
        #expect(!menu.isEnabled(future))
        #expect(menu.unavailableHint(future) == "Zatím nedostupné")
        #expect(menu.unavailableHint(new) == nil)
        try await app.startCqWwCw()
        #expect(menu.isEnabled(rescore))
        var disabled = new
        disabled.state = .disable
        #expect(!menu.isEnabled(disabled))
    }

    /// An item of a user menu that nothing implements shows the hint in the current language.
    @Test func anUnknownItemShowsTheHintInTheLanguage() async throws {
        let json = #"{"menu":[{"id":"window","children":[{"id":"x.future"}]}]}"#
        let app = try await TestApp.make { _, dataDir in
            try Data(json.utf8).write(to: dataDir.appendingPathComponent("menu.json"))
        }
        let menu: MenuModel = app.model.menu
        let czech: MenuEntry = try #require(Self.entry("x.future", in: menu.entries()))
        #expect(czech.toolTip == "Zatím nedostupné")
        #expect(!czech.enabled)
        await app.model.language.switchTo("en")
        let english: MenuEntry = try #require(Self.entry("x.future", in: menu.entries()))
        #expect(english.toolTip == "Not available yet")
        await app.model.language.switchTo("cs")
    }

    @Test func contestNewNeedsTheEngine() async throws {
        let app = try await TestApp.make(withDxcc: false)
        #expect(!app.model.menu.runtimeEnabled("contest.new"))
        #expect(!app.model.menu.runtimeEnabled("contest.none"))
        #expect(app.model.menu.runtimeEnabled("contest.open"))
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

    /// The menu bar is rebuilt from `entries()`; after a language switch every title and hint is in the new
    /// language.
    @Test func entriesFollowTheLanguageSwitch() async throws {
        let app = try await TestApp.make()
        let menu: MenuModel = app.model.menu
        let czech: [MenuEntry] = menu.entries()
        #expect(czech.map(\.title) == ["Nastavení", "Závod", "Databáze", "Okno"])
        let refill: MenuEntry = try #require(Self.entry("window.simulator", in: czech))
        #expect(refill.toolTip == nil)
        #expect(refill.enabled)
        #expect(refill.isItem)

        await app.model.language.switchTo("en")
        let english: [MenuEntry] = menu.entries()
        #expect(english.map(\.title) == ["Settings", "Contest", "Database", "Window"])
        let translated: MenuEntry = try #require(Self.entry("window.simulator", in: english))
        #expect(translated.toolTip == nil)
        #expect(translated.title != refill.title)
        let newContest: MenuEntry = try #require(Self.entry("contest.new", in: english))
        #expect(newContest.title == app.model.language.tr("Nový závod…"))
        #expect(newContest.title != "Nový závod…")

        await app.model.language.switchTo("cs")
        #expect(menu.entries() == czech)
    }

    /// Kotlin `topLevelMenu` / `renderMenuNode`: hidden nodes are left out, `tab.*` children are not menu entries
    /// (their host is an item), disabled nodes stay visible but disabled, a top-level node is always a menu.
    @Test func entriesKeepTheKotlinRendering() async throws {
        let json = #"""
        {"menu":[
          {"id":"settings","children":[
            {"id":"settings.open","children":[{"id":"tab.hardware"},{"id":"tab.other"}]},
            {"id":"settings.export","state":"disable"},
            {"id":"settings.print","state":"hidden"},
            {"id":"group","label":"Skupina","children":[{"id":"window.log"}]}
          ]},
          {"id":"contest"},
          {"id":"buffer","state":"hidden","children":[{"id":"window.chat"}]}
        ]}
        """#
        let app = try await TestApp.make { _, dataDir in
            try Data(json.utf8).write(to: dataDir.appendingPathComponent("menu.json"))
        }
        let entries: [MenuEntry] = app.model.menu.entries()
        #expect(entries.map(\.id) == ["settings", "contest"])
        let settings: MenuEntry = try #require(entries.first)
        #expect(!settings.isItem)
        #expect(settings.children.map(\.id) == ["settings.open", "settings.export", "group"])
        let host: MenuEntry = settings.children[0]
        #expect(host.isItem)
        #expect(host.children.isEmpty)
        // The Settings host is implemented.
        #expect(host.enabled)
        #expect(host.toolTip == nil)
        let export: MenuEntry = settings.children[1]
        #expect(!export.enabled)
        #expect(export.toolTip == nil)
        let group: MenuEntry = settings.children[2]
        #expect(!group.isItem)
        #expect(group.title == "Skupina")
        #expect(group.enabled)
        #expect(group.children.map(\.id) == ["window.log"])
        #expect(group.children.first?.enabled == true)
        let contest: MenuEntry = entries[1]
        #expect(!contest.isItem)
        #expect(contest.children.isEmpty)
    }

    /// Kotlin `Menu(enabled = false)` (`App.kt:548,563`) disables the whole submenu: nothing below a disabled menu
    /// node is enabled, at any depth.
    @Test func disabledMenuDisablesEverythingBelow() async throws {
        let json = #"""
        {"menu":[
          {"id":"database","state":"disable","children":[{"id":"database.new"},{"id":"database.open"}]},
          {"id":"contest","children":[
            {"id":"group","state":"disable","children":[{"id":"contest.open"},
              {"id":"inner","children":[{"id":"contest.new"}]}]},
            {"id":"contest.none"}
          ]}
        ]}
        """#
        let app = try await TestApp.make { _, dataDir in
            try Data(json.utf8).write(to: dataDir.appendingPathComponent("menu.json"))
        }
        let menu: MenuModel = app.model.menu
        let entries: [MenuEntry] = menu.entries()
        let database: MenuEntry = try #require(Self.entry("database", in: entries))
        #expect(!database.enabled)
        let new: MenuEntry = try #require(Self.entry("database.new", in: entries))
        #expect(new.ancestors.map(\.id) == ["database"])
        #expect(!new.enabled)
        #expect(menu.isEnabled(new.node))
        #expect(!menu.isEnabled(new.node, ancestors: new.ancestors))
        let open: MenuEntry = try #require(Self.entry("contest.open", in: entries))
        #expect(!open.enabled)
        let deep: MenuEntry = try #require(Self.entry("contest.new", in: entries))
        #expect(deep.ancestors.map(\.id) == ["contest", "group", "inner"])
        #expect(!deep.enabled)
        let inner: MenuEntry = try #require(Self.entry("inner", in: entries))
        #expect(!inner.enabled)
        let none: MenuEntry = try #require(Self.entry("contest.none", in: entries))
        #expect(none.enabled)
        #expect(menu.isEnabled(none.node, ancestors: none.ancestors))
    }

    /// The menu bar is updated in place when only titles or states change (language, contest), rebuilt when the
    /// structure changes.
    @Test func shapeIgnoresTitlesAndStates() async throws {
        let app = try await TestApp.make()
        let menu: MenuModel = app.model.menu
        let before = MenuShape(menu.entries())
        await app.model.language.switchTo("en")
        try await app.startCqWwCw()
        #expect(MenuShape(menu.entries()) == before)
        var tree: [MenuNode] = menu.tree
        tree[0].children.removeLast()
        let shorter: [MenuEntry] = tree.map { node in
            MenuEntry(node: node, ancestors: [], title: node.id, enabled: true, toolTip: nil, isItem: false,
                      children: [])
        }
        #expect(MenuShape(shorter) != before)
    }
}
