import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The application. `main()` first handles `--self-check` (resource check without `NSApplication`, for the packaging
/// script and CI), otherwise it starts SwiftUI.
@main
struct MacContestLoggerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let host: AppHost = .shared

    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--self-check") {
            exit(SelfCheck.run())
        }
        // Windows are reopened from `config.openWindows` (Kotlin), not by AppKit's state restoration.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        // The config file is the only geometry store: no frame records of SwiftUI/AppKit are used.
        WindowFrameDefaults.removeFrameRecords(in: UserDefaults.standard)
        startSwiftUI(MacContestLoggerApp.self)
    }

    var body: some Scene {
        Window(Text(verbatim: "MacContestLogger"), id: "main") {
            MainWindowView(host: host)
                .modifier(AppearanceApplier(host: host))
        }
        .windowResizability(.contentSize)
        .commands {
            // One Window menu, menu.json's (`MenuBuilder`): SwiftUI's own loses its window list here and is removed
            // there; its Minimize ⌘M and Close ⌘W move into menu.json's menu.
            CommandGroup(replacing: .windowList) {}
            CommandGroup(replacing: .singleWindowList) {}
        }

        // The scene title (Window menu) follows the language once the model exists; the window title itself is
        // set by `.navigationTitle` in the view.
        Window(Text(verbatim: host.model?.language.tr("Přehled spojení") ?? "Přehled spojení"), id: "log") {
            LogWindowView(host: host)
                .modifier(AppearanceApplier(host: host))
        }
        .defaultSize(width: 900, height: 420)
        // menu.json's „Přehled spojení" opens it; no second entry in the Window menu.
        .commandsRemoved()

        // Kotlin `DefinitionEditorWindow` (`defeditor`) and `ProfilesWindow` (`profiles`): tool windows opened from
        // the menu through `WindowsModel`, not listed in the Window menu.
        Window(Text(verbatim: host.model?.language.tr("Editor definic závodů") ?? "Editor definic závodů"),
               id: "defeditor") {
            DefinitionEditorWindowView(host: host)
                .modifier(AppearanceApplier(host: host))
        }
        .defaultSize(width: 1100, height: 720)
        .commandsRemoved()

        Window(Text(verbatim: host.model?.language.tr("Profily nastavení") ?? "Profily nastavení"), id: "profiles") {
            ProfilesWindowView(host: host)
                .modifier(AppearanceApplier(host: host))
        }
        .defaultSize(width: 480, height: 380)
        .commandsRemoved()

        // The radio tool windows: opened from menu.json's Window menu (`window.*`), Ctrl+K and DEBUGCAT through
        // `WindowsModel`, reopened from `config.openWindows`; not listed in the Window menu.
        toolWindow("CAT log", id: CatLogWindowView.id, size: CGSize(width: 740, height: 440)) {
            CatLogWindowView(host: host)
        }
        toolWindow("Rotátor", id: RotatorWindowView.id, size: CGSize(width: 360, height: 460)) {
            RotatorWindowView(host: host)
        }
        toolWindow("CW z klávesnice", id: CwKeyboardWindowView.id, size: CGSize(width: 560, height: 220)) {
            CwKeyboardWindowView(host: host)
        }
        toolWindow("CW Reader", id: CwReaderWindowView.id, size: CGSize(width: 620, height: 300)) {
            CwReaderWindowView(host: host)
        }
        toolWindow("Digitální rozhraní", id: DigitalInterfaceWindowView.id, size: CGSize(width: 680, height: 340)) {
            DigitalInterfaceWindowView(host: host)
        }
        toolWindow("Vodopád", id: WaterfallWindowView.id, size: CGSize(width: 760, height: 380)) {
            WaterfallWindowView(host: host)
        }

        // The spot windows: the DX Cluster, the Bandmap, the Available Multipliers and the Blacklist, opened from
        // menu.json's Window menu and the DX Cluster shortcut through `WindowsModel`, reopened from
        // `config.openWindows`; not listed in the Window menu.
        toolWindow("DX Cluster", id: DxClusterWindowView.id, size: CGSize(width: 760, height: 560)) {
            DxClusterWindowView(host: host)
        }
        toolWindow("Bandmapa", id: BandmapWindowView.id, size: CGSize(width: 460, height: 640)) {
            BandmapWindowView(host: host)
        }
        toolWindow("Dostupné multiplikátory", id: AvailMultWindowView.id, size: CGSize(width: 720, height: 520)) {
            AvailMultWindowView(host: host)
        }
        toolWindow("Blacklist", id: BlacklistWindowView.id, size: CGSize(width: 640, height: 480)) {
            BlacklistWindowView(host: host)
        }

        // The network and integration windows: Network Status, Chat, Partner, the WSJT-X decodes and the HamQTH
        // log, opened from menu.json's Window menu through `WindowsModel` (Stav sítě also from a PASS), reopened from
        // `config.openWindows`; not listed in the Window menu.
        toolWindow("Stav sítě", id: NetworkStatusWindowView.id, size: CGSize(width: 760, height: 320)) {
            NetworkStatusWindowView(host: host)
        }
        toolWindow("Chat", id: ChatWindowView.id, size: CGSize(width: 560, height: 380)) {
            ChatWindowView(host: host)
        }
        toolWindow("Partner", id: PartnerWindowView.id, size: CGSize(width: 520, height: 280)) {
            PartnerWindowView(host: host)
        }
        toolWindow("WSJT-X dekódy", id: WsjtxDecodesWindowView.id, size: CGSize(width: 640, height: 460)) {
            WsjtxDecodesWindowView(host: host)
        }
        toolWindow("HamQTH log", id: HamQthLogWindowView.id, size: CGSize(width: 760, height: 460)) {
            HamQthLogWindowView(host: host)
        }

        infoToolScenes

        // Kotlin's second entry window (SO2V/SO2R): opened and dismissed by the main window as
        // `twoEntryWindows` changes, not in `openWindows`, not in the Window menu.
        Window(Text(verbatim: host.model.map(EntryVfoBWindowView.title) ?? "Zadávací okno — VFO B"),
               id: EntryVfoBWindowView.id) {
            EntryVfoBWindowView(host: host)
                .modifier(AppearanceApplier(host: host))
        }
        .defaultSize(width: 900, height: 390)
        .commandsRemoved()

        // Kotlin `ConfigurerWindow`: opened by `SettingsModel.open` through `WindowsModel.windowRequest`,
        // 880×1000 by default, no kept geometry, not in the Window menu.
        Window(Text(verbatim: host.model?.language.tr("Nastavení") ?? "Nastavení"), id: SettingsModel.windowId) {
            SettingsWindowView(host: host)
                .modifier(AppearanceApplier(host: host))
        }
        .defaultSize(width: 880, height: 1000)
        .commandsRemoved()

        // The dialogs of the slice: separate windows with the Kotlin ids, opened by the main window
        // from `DialogsModel`; not listed in the Window menu.
        dialog(.startup) { StartupWindowView(host: host) }
        dialog(.newContest) { NewContestWindowView(host: host) }
        dialog(.contests) { ContestBrowserWindowView(host: host) }
        dialog(.databaseNew) { NewDatabaseWindowView(host: host) }
        dialog(.databaseOpen) { OpenDatabaseWindowView(host: host) }
        dialog(.operatorLogin) { OperatorWindowView(host: host) }
        dialog(.callbookResult) { CallbookResultWindowView(host: host) }
    }

    /// The info and tool windows: Info (`rate`), the goal windows, statistics, score, dupesheet, skeds, QTC, the
    /// simulator, band notes, move multipliers, propagation, one multiplier window per kind and the world map. Opened
    /// from menu.json's Window and Multipliers menus through `WindowsModel` (`DialogPresenter`), reopened from
    /// `config.openWindows` (the goal windows and the simulator are never saved); not listed in the Window menu.
    @SceneBuilder private var infoToolScenes: some Scene {
        toolWindow("Info", id: InfoWindowView.id, size: CGSize(width: 760, height: 480)) {
            InfoWindowView(host: host)
        }
        toolWindow("Cíle závodu", id: GoalEditorWindowView.id, size: CGSize(width: 420, height: 560)) {
            GoalEditorWindowView(host: host)
        }
        toolWindow("Cíle z dřívějšího deníku", id: GoalFromLogWindowView.id,
                   size: CGSize(width: 560, height: 460)) {
            GoalFromLogWindowView(host: host)
        }
        toolWindow("Statistiky", id: StatisticsWindowView.id, size: CGSize(width: 820, height: 560)) {
            StatisticsWindowView(host: host)
        }
        toolWindow("Skóre", id: ScoreWindowView.id, size: CGSize(width: 620, height: 420)) {
            ScoreWindowView(host: host)
        }
        toolWindow("Dupesheet", id: DupesheetWindowView.id, size: CGSize(width: 900, height: 420)) {
            DupesheetWindowView(host: host)
        }
        toolWindow("Skedy", id: SkedWindowView.id, size: CGSize(width: 640, height: 420)) {
            SkedWindowView(host: host)
        }
        toolWindow("QTC", id: QtcWindowView.id, size: CGSize(width: 620, height: 560)) {
            QtcWindowView(host: host)
        }
        toolWindow("Simulátor pileupu", id: SimulatorWindowView.id, size: CGSize(width: 620, height: 520)) {
            SimulatorWindowView(host: host)
        }
        toolWindow("Poznámky k pásmům", id: BandNotesWindowView.id, size: CGSize(width: 560, height: 420)) {
            BandNotesWindowView(host: host)
        }
        toolWindow("Přesun násobičů", id: MoveMultsWindowView.id, size: CGSize(width: 640, height: 420)) {
            MoveMultsWindowView(host: host)
        }
        toolWindow("Předpověď šíření", id: PropagationWindowView.id, size: CGSize(width: 720, height: 360)) {
            PropagationWindowView(host: host)
        }
        toolWindow("Mapa", id: WorldMapWindowView.id, size: CGSize(width: 900, height: 520)) {
            WorldMapWindowView(host: host)
        }
        multWindow("dxcc")
        multWindow("grid")
        multWindow("itu")
        multWindow("cq")
        multWindow("districts")
        multWindow("other")
        multWindow("sections")
    }

    /// The window of one multiplier kind (`mult:<kind>`, 980×620).
    private func multWindow(_ kind: String) -> some Scene {
        toolWindow(MultGridLayout.title(kind: kind, translate: .source), id: MultGridWindowView.id(kind),
                   size: CGSize(width: 980, height: 620)) {
            MultGridWindowView(host: host, kind: kind)
        }
    }

    /// A tool window with a translated scene title (the window title itself is set by the view).
    private func toolWindow<Content: View>(_ title: String, id: String, size: CGSize,
                                           @ViewBuilder content: @escaping () -> Content) -> some Scene {
        Window(Text(verbatim: host.model?.language.tr(title) ?? title), id: id) {
            content()
                .modifier(AppearanceApplier(host: host))
        }
        .defaultSize(size)
        .commandsRemoved()
    }

    private func dialog<Content: View>(_ dialog: DialogsModel.Window,
                                       @ViewBuilder content: @escaping () -> Content) -> some Scene {
        Window(Text(verbatim: "MacContestLogger"), id: dialog.rawValue) {
            content()
                .modifier(AppearanceApplier(host: host))
        }
            .defaultSize(dialog.defaultSize)
            .commandsRemoved()
    }
}

/// Starts SwiftUI's own `App.main()`. In a generic context the call resolves to the `App` protocol extension,
/// not to `MacContestLoggerApp.main()` above (which would recurse).
@MainActor
private func startSwiftUI<A: App>(_ app: A.Type) {
    A.main()
}

/// Application delegate: the resource check after launch, then the bootstrap; the quit sequence and the shutdown
/// hooks on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// SIGTERM/SIGINT/SIGHUP → the regular quit: `AppModel.shutdown` releases the transmitter first; a
    /// further signal ends the process (hooks, frame records) once that release is done, after 5 s or on a third one;
    /// a quit that has not released the transmitter 15 s after the first signal ends the same way.
    private lazy var terminationSignals = TerminationSignals(actions: TerminationSignals.Actions(
        // Never `NSApp.terminate` here: the signal source's handler is a main-queue block (see `AppQuit`).
        terminate: { AppQuit.request() },
        isTerminating: { AppHost.shared.isTerminating },
        exitAllowed: { AppHost.shared.model?.signalExitAllowed ?? true },
        transmitReleased: { AppHost.shared.model?.transmitReleased ?? false },
        forceExit: { code in
            QuitTrace.write("force exit \(code)")
            AppDelegate.cleanUpBeforeExit()
            exit(code)
        },
        after: { seconds, body in
            QuitTrace.write("deadline armed \(Int(seconds)) s")
            // A main-queue timer: while `terminate:` waits for the reply (modal panel mode, one of the common modes)
            // the main queue drains, since `AppQuit` keeps that wait out of any main-queue block.
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated {
                    QuitTrace.write("deadline expired")
                    body()
                }
            }
        }))

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything can launch a daemon (its hook registration would otherwise install the hooks' own handler).
        terminationSignals.install()
        AppHost.shared.onQuitMilestone = { [weak self] in
            self?.terminationSignals.milestoneReached()
        }
        if MainThreadWatchdog.isEnabled {
            MainThreadWatchdog.shared.start()
        }
        let problems: [String] = ResourceCheck.verify(bundleURL: Bundle.main.bundleURL)
        guard !problems.isEmpty else {
            // The models are created only now: nothing reads the bundled menu or languages before the check passed.
            AppHost.shared.start()
            return
        }
        // Czech originals: the translation is wired with the language model; when the resources are broken the
        // shipped languages cannot be loaded anyway, and the Czech text is the translation fallback.
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Aplikaci nelze spustit: chybí její zdroje."
        alert.informativeText = problems.joined(separator: "\n")
        alert.addButton(withTitle: "Ukončit")
        alert.runModal()
        AppQuit.request()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        QuitTrace.write("delegate should terminate")
        return AppHost.shared.shouldTerminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        QuitTrace.write("will terminate")
        // Kotlin `App.kt`: on quit the CAT sessions disconnect and launched daemons (`rigctld`) are killed through
        // the shutdown hooks (the rigs were disconnected by `AppModel.shutdown` before the reply).
        Self.cleanUpBeforeExit()
    }

    /// The end of every exit path: the shutdown hooks (launched daemons are killed) and SwiftUI's frame records.
    static func cleanUpBeforeExit() {
        ProcessShutdownHooks.shared.runAll()
        WindowFrameDefaults.removeFrameRecords(in: UserDefaults.standard)
        QuitTrace.write("cleanup done")
    }
}
