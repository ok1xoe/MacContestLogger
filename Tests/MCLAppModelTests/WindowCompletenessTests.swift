import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// No menu item of the shipped `menu.json` is left without its window or action, so no item says „Zatím
/// nedostupné"; every window the model lists has its scene in the app layer. The windows themselves are views and are
/// not unit-tested (the models behind them are, in `InfoTools*Tests`, `ToolWindowsTests`).
@MainActor @Suite struct WindowCompletenessTests {

    /// The items (leaves a user can choose) of a menu, recursively.
    private static func items(_ entries: [MenuEntry]) -> [MenuEntry] {
        var out: [MenuEntry] = []
        for entry in entries {
            if entry.isItem {
                out.append(entry)
            }
            out.append(contentsOf: items(entry.children))
        }
        return out
    }

    /// Every item of the shipped menu is implemented and carries no „not available yet" hint, in both languages.
    @Test func noMenuItemSaysNotAvailableYet() async throws {
        let app = try await TestApp.make()
        let menu: MenuModel = app.model.menu
        let entries: [MenuEntry] = Self.items(menu.entries())
        // The menu is not a stub: the settings host, the contest, the database and the window items are there.
        #expect(entries.count > 50)
        for language in ["cs", "en"] {
            await app.model.language.switchTo(language)
            for entry in Self.items(menu.entries()) {
                #expect(menu.isImplemented(entry.id), "\(entry.id) is not implemented")
                #expect(entry.toolTip == nil, "\(entry.id) shows \(entry.toolTip ?? "") in \(language)")
            }
        }
        await app.model.language.switchTo("cs")
        for id in ["window.rate", "window.skeds", "window.score", "window.movemults", "window.dupesheet",
                   "window.statistics", "window.qtc", "window.propagation", "window.bandnotes", "window.simulator",
                   "window.dxccmap", "mult.dxcc", "mult.grid", "mult.map", "mult.itu", "mult.cq", "mult.districts",
                   "mult.other", "mult.sections"] {
            #expect(entries.contains { $0.id == id }, "\(id) is missing from the menu")
        }
    }

    /// The window an item opens (`App.kt:645-677`): the saved id of its window.
    private static func window(of menuId: String) -> String? {
        switch menuId {
        case "window.log": return "log"
        case "window.dxccmap": return "worldmap-dxcc"
        case "mult.map": return "worldmap"
        default: return WindowsModel.menuWindows[menuId]
        }
    }

    /// Choosing every window item opens its window and never says „Zatím nedostupné".
    @Test func everyWindowItemOpensItsWindow() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let ids: [String] = Self.items(model.menu.entries()).map(\.id).filter {
            $0.hasPrefix("window.") || $0.hasPrefix("mult.")
        }
        #expect(ids.count >= 30)
        for id in ids {
            let window: String = try #require(Self.window(of: id), "\(id) opens no window")
            #expect(MenuActions.perform(id, app: model) == nil)
            #expect(model.windows.isOpen(window), "\(id) did not open \(window)")
            #expect(WindowsModel.implemented.contains(window), "\(window) is not implemented")
            #expect(model.status.message != EntryTexts.unavailable, "\(id) says it is unavailable")
        }
    }

    /// Every window id Kotlin saves is implemented, and so is every item that names one.
    @Test func everyKotlinWindowIdIsImplemented() {
        #expect(Set(WindowsModel.kotlinOrder).isSubset(of: WindowsModel.implemented))
        #expect(Set(WindowsModel.menuWindows.values).isSubset(of: WindowsModel.implemented))
        #expect(WindowsModel.multWindowIds == ["mult:dxcc", "mult:grid", "mult:itu", "mult:cq", "mult:districts",
                                               "mult:other", "mult:sections"])
        #expect(WindowsModel.sceneId(for: "worldmap-dxcc") == "worldmap")
        #expect(WindowsModel.sceneId(for: "worldmap") == "worldmap")
        #expect(WindowsModel.sceneId(for: "mult:cq") == "mult:cq")
    }

    /// Every implemented window id has a scene in the app layer: a `Window(id:)` with that id (the multiplier windows
    /// are built from their kind, the DXCC map is the same scene as the map).
    @Test func everyImplementedIdHasASceneInTheApp() throws {
        let root: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MacContestLogger")
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var source = ""
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            source += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }
        try #require(source.contains("MacContestLoggerApp"), "the app sources were not found at \(root.path)")
        for id in WindowsModel.implemented {
            let scene: String = WindowsModel.sceneId(for: id)
            let needle: String = scene.hasPrefix("mult:") ? "\"mult:\"" : "\"\(scene)\""
            #expect(source.contains(needle), "no scene for \(id)")
        }
        // Every window view of the info and tool windows is registered by a real `toolWindow(…, id: <View>.id)` call
        // (not just named somewhere), once; the multiplier windows by `multWindow("<kind>")` calls, once per kind.
        let appFile: URL = root.appendingPathComponent("MacContestLoggerApp.swift")
        let app: String = try String(contentsOf: appFile, encoding: .utf8)
        func captures(_ pattern: String, in text: String) throws -> [String] {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            }
        }
        let tools: [URL] = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Tools"),
                                                                       includingPropertiesForKeys: nil)
        var views: [String] = []
        for file in tools where file.pathExtension == "swift" {
            views += try captures("struct (\\w+WindowView): View", in: try String(contentsOf: file, encoding: .utf8))
        }
        #expect(views.count == 14, "found \(views.sorted())")
        let registered: [String] = try captures("toolWindow\\(\\s*[^,]+,\\s*id:\\s*(\\w+)\\.id[,)]", in: app)
        #expect(Set(registered).count == registered.count, "a window is registered twice: \(registered)")
        // `MultGridWindowView` is registered once through `multWindow`, by `MultGridWindowView.id(kind)`.
        let direct: Set<String> = Set(views).subtracting(["MultGridWindowView"])
        #expect(direct.isSubset(of: Set(registered)), "scenes \(registered.sorted()) for views \(direct.sorted())")
        #expect(app.contains("MultGridWindowView.id(kind)"))
        // The plugin windows (`plugin:<plugin>/<window>`) are one window group keyed by the window key.
        #expect(app.contains("WindowGroup(id: PluginWindowView.sceneId, for: String.self)"))
        let kinds: [String] = try captures("multWindow\\(\"(\\w+)\"\\)", in: app)
        #expect(kinds.sorted() == MultGridLayout.kinds.sorted(), "multiplier scenes: \(kinds)")
    }
}
