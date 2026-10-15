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
        /// N1MM's transaction file: a `.trn` file → `recoverFromJournal`.
        case openJournal
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
        /// The ADIF of the QSOs in `range` (Export → ADIF by date) → `exportAdif(to:range:)`.
        case saveAdifRange(suggestedName: String, range: AdifDateRange, allContests: Bool = false, station: String = "")
        /// N1MM „Export to file (generic) sorted by band" → `exportTextByBand(to:)`.
        case saveTextByBand(suggestedName: String)
        /// N1MM's generic text output in the contest's layout → `exportFormattedText(to:)`.
        case saveFormattedText(suggestedName: String)
        /// The loaded call history → `exportCallHistory(to:format:)`.
        case saveCallHistory(format: DataToolsModel.CallHistoryFormat, suggestedName: String)
        /// N1MM Export Function Keys to file: the message set the entry window's keys send now, as an `.mc` file.
        case saveFunctionKeys(kind: FunctionKeyKind, suggestedName: String)
        /// N1MM Import Call History: one or more files (multiple selection) → `importCallHistoryFiles`.
        case openCallHistoryImport
        /// N1MM Config → Change Exchange Abbreviations: the table file (created with a short header when missing) in
        /// the text editor; it is read again whenever it changes.
        case openFile(URL)
        /// N1MM's recovery of a lost window: every window off the connected displays moves onto the main one.
        case gatherWindows
    }

    /// The ids of the file and export items (the first half of `perform`; split so no single `switch` is slow to
    /// type-check).
    private static let fileIds: Set<String> = [
        "settings.export", "settings.exportCabrillo", "settings.exportEdi", "settings.exportOther", "settings.exportByBand",
        "settings.exportFormatted", "settings.import",
        "settings.merge", "database.refillDxcc", "callhistory.exportN1mm", "callhistory.exportCsv",
        "callhistory.import", "fkeys.export", "file.recoverJournal",
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
        if id == "layout.gather" {
            return .gatherWindows
        }
        if id == "layout.save" || id == "layout.restore" {
            promptLayout(save: id == "layout.save", app: app)
            return nil
        }
        if id == "settings.exchangeAbbreviations" {
            let url: URL = app.dataDir.appendingPathComponent(ExchangeAbbreviations.fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try Data(ExchangeAbbreviations.template.utf8).write(to: url, options: .atomic)
                } catch {
                    app.status.show("Soubor zkratek nejde založit: %s", .string(ErrorText.message(error)))
                    return nil
                }
            }
            return .openFile(url)
        }
        if id == "edit.editCurrent" {
            (app.activeEntry ?? app.entry).editCurrentContact()
            return nil
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
        case "file.recoverJournal":
            guard app.contest.isActive else {
                app.status.show("Obnova z transakčního souboru: není otevřený závod")
                return nil
            }
            return .openJournal
        case "settings.exportEdi":
            // Kotlin checks the contest before the directory panel; the other checks follow the panel.
            guard app.contest.isActive else {
                app.status.show(IoTexts.ediNoContest)
                return nil
            }
            return .chooseDirectory(.edi)
        case "settings.exportOther":
            return .chooseDirectory(.other)
        case "settings.exportByBand":
            return .saveTextByBand(suggestedName: ExportNames.otherBase(call: app.config.config.station.call) + "-by-band.txt")
        case "settings.exportFormatted":
            return .saveFormattedText(suggestedName: ExportNames.otherBase(call: app.config.config.station.call) + ".txt")
        case "database.refillDxcc":
            return .confirmRefillDxcc(count: app.logbook.rows.count)
        case "callhistory.import":
            return .openCallHistoryImport
        case "callhistory.exportN1mm", "callhistory.exportCsv":
            guard app.dataTools.hasCallHistory else {
                app.status.show("Call history je prázdná")
                return nil
            }
            let format: DataToolsModel.CallHistoryFormat = id == "callhistory.exportCsv" ? .csv : .n1mm
            return .saveCallHistory(format: format, suggestedName: app.dataTools.callHistoryFileName(format))
        case "fkeys.export":
            let kind: FunctionKeyKind = app.entry.currentKeyKind
            return .saveFunctionKeys(kind: kind, suggestedName: kind.rawValue + " Messages.mc")
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
        case "contest.setup":
            app.dialogs.openContestSetup()
        case "contest.rescore":
            app.contest.requestRescore(manual: true)
        case "file.copyContest":
            app.dialogs.setOpen(.copyContest, true)
        case "file.post3830":
            if app.contest.isActive {
                app.dialogs.setOpen(.score3830, true)
            } else {
                app.status.show("Odeslat výsledek: není aktivní závod")
            }
        case "settings.exportAdifRange":
            app.dialogs.setOpen(.adifRange, true)
        case "tools.addCallToCountry":
            app.dialogs.setOpen(.dxccOverrides, true)
        case "callhistory.clear":
            if app.dataTools.hasCallHistory {
                app.dialogs.ask(.clearCallHistory)
            } else {
                app.status.show("Call history je prázdná")
            }
        case "contest.rescoreHours":
            promptRescoreHours(app: app)
        case "settings.callHistoryLookup":
            app.callData.toggleLookup()
        case "database.new":
            app.dialogs.setOpen(.databaseNew, true)
        case "database.open":
            app.dialogs.setOpen(.databaseOpen, true)
        case "window.log":
            app.windows.setOpen("log", true)
        case "contest.postcontest":
            app.operating.setPostContest(!app.operating.postContest)
        case "view.unmatchedMark":
            app.check.setShowsUnmatchedMark(!app.check.showsUnmatchedMark)
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

    /// „Přepočítat posledních N hodin…": asks for N, then rescores the QSOs of that window (`RescoreWindow`).
    /// Tools › Save / Restore window layout (N1MM Save / Restore Window Positions): the name prompt, the operator's
    /// call by default (a layout per operator); the restore opens the layout's windows too.
    private static func promptLayout(save: Bool, app: AppModel) {
        let profiles: ProfilesModel = app.profiles
        let windows: WindowsModel = app.windows
        let dialogs: DialogsModel = app.dialogs
        let operatorCall: String = KotlinStrings.nilIfBlank(app.operating.operatorCall) ?? "MCL"
        Task {
            let names: [String] = await profiles.layoutNames()
            let list: String = names.isEmpty ? "—" : names.joined(separator: ", ")
            if save {
                dialogs.prompt(title: ContestMessage("Uložit rozložení oken"),
                               hint: ContestMessage("Jméno rozložení (třeba volačka operátora). Uložená: %s", .string(list)),
                               initial: operatorCall) { name in
                    Task { await profiles.saveLayout(name: name) }
                }
            } else {
                let initial: String = names.contains(operatorCall) ? operatorCall : names.first ?? operatorCall
                dialogs.prompt(title: ContestMessage("Obnovit rozložení oken"),
                               hint: ContestMessage("Jméno rozložení. Uložená: %s", .string(list)),
                               initial: initial) { name in
                    Task {
                        guard let ids = await profiles.restoreLayout(name: name) else { return }
                        for id in ids where WindowsModel.implemented.contains(id) {
                            windows.setOpen(id, true)
                        }
                    }
                }
            }
        }
    }

    private static func promptRescoreHours(app: AppModel) {
        let contest: ContestModel = app.contest
        let status: StatusModel = app.status
        app.dialogs.prompt(
            title: ContestMessage("Přepočet skóre"),
            hint: ContestMessage("Kolik posledních hodin přepočítat (celé číslo 1–%s)", .int(RescoreWindow.maxHours)),
            initial: "24") { text in
            guard let hours = RescoreWindow.parseHours(text) else {
                status.show("Neplatný počet hodin (1–%s)", .int(RescoreWindow.maxHours))
                return
            }
            contest.requestRescore(manual: true, lastHours: hours)
        }
    }

    /// The ✓ of a toggle item („Dodatečné zadání" shows the POSTCONTEST state, „Zapnout dohledávání v call history"
    /// N1MM's Enable Call History Lookup; Kotlin's menu items carry no check mark — a UI divergence).
    public static func isChecked(_ id: String, app: AppModel) -> Bool {
        switch id {
        case "contest.postcontest":
            return app.operating.postContest
        case "settings.callHistoryLookup":
            return app.callData.callHistoryLookupEnabled
        case "view.unmatchedMark":
            return app.check.showsUnmatchedMark
        default:
            return false
        }
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
