import Foundation
import MCLCore

/// The menu actions implemented so far (Kotlin `buildMenuActions`, `KApp:611-674`; `MenuModel.implementedActions`).
///
/// `settings.profiles`, `contest.updateCallHistory` and `contest.updateDefinitions` run the actions their models
/// register in `AppModel.extraMenuActions` (the default branch).
///
/// Model actions run here; what needs AppKit (a save panel) comes back as a `Request` for the app layer. Opening a
/// window is a flag of a model (`DialogsModel`, `WindowsModel`) that the main window turns into `openWindow`.
@MainActor
public enum MenuActions {

    /// What a directory panel is chosen for (Kotlin `chooseDirectory(title)`).
    public enum DirectoryPurpose: Equatable, Sendable {
        /// `tr("Adresář pro EDI soubory")` → `exportEdi`.
        case edi
        /// `tr("Adresář pro CSV, text a souhrn")` → `exportOther`.
        case other
    }

    /// Work for the app layer.
    public enum Request: Equatable, Sendable {
        /// Kotlin `chooseAdifPath` → `exportAdif`.
        case saveAdif(suggestedName: String)
        /// Kotlin `chooseCabrilloPath(cabrilloFileName())` → `exportCabrillo`.
        case saveCabrillo(suggestedName: String)
        /// Kotlin `chooseImportPath()` (title `"Import QSO (ADIF / Cabrillo)"`, no `tr`) → `importQsos`.
        case openImport
        /// Kotlin `chooseMergePath()` (`tr("Sloučit deník (.sqlite, ADIF, Cabrillo)")`) → `merge`.
        case openMerge
        /// Kotlin `chooseDirectory(title)` → `exportEdi` / `exportOther`.
        case chooseDirectory(DirectoryPurpose)
        /// Kotlin `LogPrinter.print(title, text)`: the print dialog over a prepared job, then `printFinished`.
        case print(ImportExportModel.PrintJob)
        /// Kotlin `showRefillDxccConfirm = true`: the confirmation „Přepočítat DXCC u %s QSO?" (the active contest's
        /// QSOs at the time of the request).
        case confirmRefillDxcc(count: Int)
        /// Kotlin `chooseBeaconsPath()` (`tr("Soubor majáků (Beacons.txt)")`) → `SpotNavigation.loadBeacons` (the
        /// BEACONS command, `App.kt:266`).
        case openBeacons
        /// The data directory in the Finder (`help.dataFolder`; honours `MCL_DATA_DIR`).
        case openDataFolder(URL)
    }

    /// The ids of the file and export items (the first half of `perform`; split so no single `switch` is slow to
    /// type-check).
    private static let fileIds: Set<String> = [
        "settings.export", "settings.exportCabrillo", "settings.exportEdi", "settings.exportOther", "settings.import",
        "settings.merge", "database.refillDxcc",
    ]

    /// The Help items and the documentation page each opens (`nil` = the docs index, `.issues` = the bug tracker).
    private static let helpPages: [String: CallbookModel.DocsPage] = [
        "help.docs": .index, "help.shortcuts": .page("keyboard-shortcuts.md"),
        "help.commands": .page("text-commands.md"), "help.report": .issues,
    ]

    /// Runs the action of a menu item; `nil` = done (or not an action handled here).
    public static func perform(_ id: String, app: AppModel) -> Request? {
        if id == "beacons.load" {
            return .openBeacons
        }
        if id.hasPrefix(MenuModel.recentOpenPrefix) {
            app.contest.openRecent(contestId: String(id.dropFirst(MenuModel.recentOpenPrefix.count)))
            return nil
        }
        if id == "recent.clear" {
            Task { await app.contest.clearRecent() }
            return nil
        }
        if id == "help.dataFolder" {
            return .openDataFolder(app.dataDir)
        }
        if let action = MenuModel.shortcutActions[id], id.hasPrefix("edit.") {
            (app.activeEntry ?? app.entry).runShortcut(action)
            return nil
        }
        if let page = helpPages[id] {
            app.callbook.openDocs(page)
            return nil
        }
        if fileIds.contains(id) {
            return performFile(id, app: app)
        }
        // Kotlin `worldMapStartDxcc = …; showWorldMap = true` (`App.kt:669-673`).
        if id == "window.dxccmap" || id == "mult.map" {
            app.worldMap.startDxcc = id == "window.dxccmap"
            app.windows.setWorldMapOpen(true, dxcc: app.worldMap.startDxcc)
            return nil
        }
        // Kotlin `showXxx = true` (`App.kt:645-677`); the ids Kotlin saves in `openWindows` are camel-cased.
        if let window = WindowsModel.menuWindows[id] {
            app.windows.setOpen(window, true)
            return nil
        }
        performApp(id, app: app)
        return nil
    }

    /// Import, merge and the exports: what the app layer must ask a panel for.
    private static func performFile(_ id: String, app: AppModel) -> Request? {
        switch id {
        case "settings.export":
            return .saveAdif(suggestedName: ExportNames.adifDefaultName)
        case "settings.exportCabrillo":
            guard app.contest.isActive else {
                app.status.show("Cabrillo: není aktivní závod")
                return nil
            }
            return .saveCabrillo(suggestedName: app.exports.cabrilloFileName)
        case "settings.import":
            return .openImport
        case "settings.merge":
            return .openMerge
        case "settings.exportEdi":
            // Kotlin checks the contest before the directory panel; the other checks follow the panel.
            guard app.contest.isActive else {
                app.status.show(IoTexts.ediNoContest)
                return nil
            }
            return .chooseDirectory(.edi)
        case "settings.exportOther":
            return .chooseDirectory(.other)
        case "database.refillDxcc":
            return .confirmRefillDxcc(count: app.logbook.rows.count)
        default:
            return nil
        }
    }

    /// The items that act on a model directly.
    private static func performApp(_ id: String, app: AppModel) {
        switch id {
        case "contest.new":
            app.dialogs.setOpen(.newContest, true)
        case "contest.none":
            app.contest.deactivate()
        case "contest.open":
            app.dialogs.setOpen(.contests, true)
        case "contest.rescore":
            app.contest.requestRescore(manual: true)
        case "database.new":
            app.dialogs.setOpen(.databaseNew, true)
        case "database.open":
            app.dialogs.setOpen(.databaseOpen, true)
        case "window.log":
            app.windows.setOpen("log", true)
        case "contest.postcontest":
            app.operating.setPostContest(!app.operating.postContest)
        case "settings.print":
            // The job is read off the main thread; it comes back as `exports.pendingRequest` (`takeModelRequest`).
            app.exports.startPrint()
        case "settings.keys":
            app.settings.open(tabKey: "keys")
        case "settings.open":
            // Kotlin `openConfigurer(tabSpecs)`; the window follows `windows.windowRequest`.
            app.settings.open()
        case "contest.editor":
            // Kotlin `showDefinitionEditor = true`; the window id is `defeditor` (`config.openWindows`).
            app.windows.setOpen("defeditor", true)
        default:
            if let action = app.extraMenuActions[id] {
                action()
            } else if app.menu.isImplemented(id) {
                // Implemented by a model that is not wired yet.
                app.status.show(EntryTexts.unavailable)
            }
        }
    }

    /// The ✓ of a toggle item („Dodatečné zadání" shows the POSTCONTEST state; Kotlin's menu items carry no
    /// check mark — a UI divergence).
    public static func isChecked(_ id: String, app: AppModel) -> Bool {
        id == "contest.postcontest" && app.operating.postContest
    }

    /// A request a model produced asynchronously after its menu action returned (the print job), cleared; the app
    /// layer observes `app.exports.pendingRequest` and runs what this returns.
    public static func takeModelRequest(app: AppModel) -> Request? {
        app.exports.takePendingRequest()
    }

    /// Kotlin `LaunchedEffect(state.pendingMenuAction)`: runs the action a call-field command requested (and clears
    /// it), then `applyPendingSettingsTab()` — the tab of MSGS/WKEY/NETCONFIG/FUNCTION_KEYS_SETUP (cleared even
    /// when the Settings window is not open, as in Kotlin).
    public static func performPending(app: AppModel) -> Request? {
        guard let id = app.menu.pendingMenuAction else { return nil }
        app.menu.pendingMenuAction = nil
        let request: Request? = perform(id, app: app)
        if let tab = app.menu.pendingSettingsTab {
            app.menu.pendingSettingsTab = nil
            app.settings.applyDeepLink(tab)
        }
        return request
    }
}
