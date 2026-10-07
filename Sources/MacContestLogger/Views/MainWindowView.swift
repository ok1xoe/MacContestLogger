import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The main window (Kotlin `MainScreen`, `KApp:501-514`): the entry panel, a flexible gap, the score strip and the
/// status line. Unlike Kotlin it has the font stepper: its size follows the content
/// (`.windowResizability(.contentSize)`), only its position is saved (`persistSize = false`).
struct MainWindowView: View {
    let host: AppHost

    @StateObject private var session = WindowSession(id: "main", persistSize: false,
                                                     defaultSize: CGSize(width: 820, height: 370))
    @StateObject private var focusHolder = FocusHolder()
    /// The entry window's key monitor, installed with the window once the model exists.
    @StateObject private var keyMonitor = EntryKeyMonitor()
    /// The mouse wheel over the entry panel tunes the rig.
    @StateObject private var wheel = TuningWheelMonitor()
    /// Key window → active VFO with two entry windows; the `\` switch back to this window.
    @StateObject private var activator = EntryWindowActivator()

    private var binder: WindowGeometryBinder { session.binder }
    private var focus: EntryFocusController { focusHolder.controller }
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        content
            .background(WindowAccessor { window in
                binder.isTerminating = { host.isTerminating }
                binder.onClose = { AppQuit.request() }
                binder.attach(window)
                if let app = host.model {
                    keyMonitor.install(window: window, entry: app.entry)
                    wheel.install(window: window, entry: app.entry, accepts: { app.acceptsEntryInput })
                    activator.install(window: window, app: app, vfo: 0)
                }
            })
    }

    @ViewBuilder private var content: some View {
        if let app = host.model {
            loaded(app)
                .environment(\.windowFontSize, session.fontSize)
                .frame(minWidth: 820, minHeight: 330)
                .fixedSize()
                .onAppear {
                    binder.setStore(app.geometry)
                    reopenWindows(app)
                    focus.focus(.call)
                }
                .onChange(of: app.entry.focusRequest) {
                    focus.focus(.call)
                }
                .onChange(of: app.acceptsEntryInput) {
                    // Disabling the panel (database switch, contest activation) resigns the first responder: back to the call field.
                    if app.acceptsEntryInput {
                        focus.focus(.call)
                    }
                }
                .modifier(EntryFocusFollower(app: app, entry: app.entry, focus: focus))
                .modifier(EntryVfoFocus(app: app, vfo: 0, focus: focus, activator: activator))
                .onChange(of: app.rig.vfo.twoEntryWindows, initial: true) {
                    // Kotlin `if (state.twoEntryWindows) Window(…)`: the VFO B window follows SO2V/SO2R.
                    if app.rig.vfo.twoEntryWindows {
                        openWindow(id: EntryVfoBWindowView.id)
                    } else {
                        dismissWindow(id: EntryVfoBWindowView.id)
                    }
                }
                .onChange(of: app.vfoB.entry.isWindowShown) {
                    // The VFO B window closed by some other way than SO1V (the close itself is refused): open it again.
                    if !app.vfoB.entry.isWindowShown && app.rig.vfo.twoEntryWindows && !host.isTerminating {
                        openWindow(id: EntryVfoBWindowView.id)
                    }
                }
                .onChange(of: app.menu.pendingMenuAction) {
                    // Kotlin `LaunchedEffect(state.pendingMenuAction)`: a command asked for a menu action.
                    if let request = MenuActions.performPending(app: app) {
                        ExportPanels.run(request, app: app)
                    }
                }
                .onChange(of: app.exports.pendingRequest) {
                    // A request a model produced after its menu action returned (the print job).
                    if let request = MenuActions.takeModelRequest(app: app) {
                        ExportPanels.run(request, app: app)
                    }
                }
                .modifier(DialogPresenter(app: app))
                .modifier(PluginConsentPresenter(app: app))
                .modifier(WindowRequestPresenter(app: app))
                .modifier(DataToolsDialogPresenter(app: app))
                .modifier(EntryDialogPresenter(app: app))
                .sheet(isPresented: Binding(get: { app.database.needsDatabasesDir }, set: { _ in })) {
                    FirstRunDatabaseDirAlert(app: app)
                }
                .alert(Text(verbatim: app.language.tr("Vlastní menu se nepoužilo")),
                       isPresented: Binding(get: { app.menu.loadError != nil },
                                            set: { if !$0 { app.menu.loadError = nil } })) {
                    Button(app.language.tr("Rozumím")) {
                        app.menu.loadError = nil
                    }
                } message: {
                    Text(verbatim: app.language.tr(
                        "%s\n\nPlatí vestavěné menu. Soubor oprav a v Nastavení → Other → Menu aplikace dej „Načíst menu znovu“.",
                        .string(app.menu.loadError ?? "")))
                }
        } else {
            Color.clear
                .frame(width: 820, height: 370)
        }
    }

    private func loaded(_ app: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: app.language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            EntryPanelView(app: app, panel: app.panel(vfo: 0), focus: focus, wheel: wheel)
            PluginTransmitIndicator(app: app)
            PluginDockArea(app: app)
            Spacer(minLength: 0)
            if app.contest.isActive {
                ScoreBarView(app: app)
                Divider()
            }
            StatusBarView(app: app)
        }
    }

    /// Kotlin restores the tool windows from `config.openWindows` at start (`KApp:153-193`); a window Kotlin never
    /// saves there (`profiles`) is not reopened even when the file names it.
    private func reopenWindows(_ app: AppModel) {
        let ids: [String] = app.windows.openIds.filter { !WindowsModel.notPersisted.contains($0) }
        for id in ids where WindowsModel.implemented.contains(id) {
            openWindow(id: WindowsModel.sceneId(for: id))
        }
        // The plugin windows reopen too; each starts its plugin once the plugins directory was read.
        for id in ids where PluginCatalog.parseWindowKey(id) != nil {
            openWindow(id: PluginWindowView.sceneId, value: id)
        }
    }
}

/// The entry model's focus requests (Kotlin `FocusRequester`s): the exchange (space, ESM), the post-contest time
/// field, and the Tab / Shift+Tab / space moves from the field that has the focus (`EntryFocusOrder`).
struct EntryFocusFollower: ViewModifier {
    let app: AppModel
    let entry: EntryModel
    let focus: EntryFocusController

    private var order: EntryFocusOrder {
        EntryFocusOrder(contestActive: app.contest.isActive, fields: entry.fields)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: entry.exchangeFocusRequest) {
                focus.focus(order.exchangeTarget)
            }
            .onChange(of: entry.timeFocusRequest) {
                focus.focus(.time)
            }
            .onChange(of: entry.focusMoveRequest) {
                guard let move = entry.focusMoveRequest, let from = focus.focusedKey() else { return }
                focus.focus(order.next(from: from, direction: move.by, skipReports: move.skipReports))
            }
    }
}

/// Holds the entry window's focus registry across view updates.
@MainActor
final class FocusHolder: ObservableObject {
    let controller = EntryFocusController()
}

/// Kotlin `ScoreBar` (`K:EntryPanel.kt:1500-1528`).
struct ScoreBarView: View {
    let app: AppModel

    var body: some View {
        if let line = ScoreLine.of(contest: app.contest) {
            bar(line)
        }
    }

    private func bar(_ line: ScoreLine) -> some View {
        HStack(alignment: .center, spacing: 16) {
            cell("QSO", line.qso)
            cell(app.language.tr("Body"), line.points)
            cell("Mult", line.mult)
            Spacer(minLength: 0)
            Text(verbatim: app.language.tr("Skóre:") + " " + line.total)
                .windowFont(16, weight: .bold, design: .monospaced)
        }
        .foregroundStyle(Color(domain: DomainColors.onStrip))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(domain: DomainColors.strip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: app.language.tr("Skóre")))
        .accessibilityValue(Text(verbatim: AccessibilityText.scoreBarValue(
            qso: line.qso, points: line.points, mult: line.mult, total: line.total,
            translator: app.language.translator)))
    }

    private func cell(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: label + ":")
                .windowFont(12)
            Text(verbatim: value)
                .windowFont(14, weight: .bold, design: .monospaced)
        }
    }
}

/// Kotlin `StatusBar` (`KApp:516-541`): the sent exchange on the left, the status (or the CAT state) and the contest
/// name on the right.
struct StatusBarView: View {
    let app: AppModel

    var body: some View {
        let line: StatusLine = StatusLine.of(app)
        HStack(alignment: .center, spacing: 0) {
            if let sent = line.sentExchange {
                Text(verbatim: app.language.tr("Předávaný kód: %s", .string(sent)))
                    .windowFont(12)
            }
            Spacer(minLength: 8)
            // The message must not widen the window (its size follows the content): no ideal width of its own.
            Text(verbatim: line.message)
                .windowFont(12)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .trailing)
            if let name = line.contestName {
                Text(verbatim: name)
                    .windowFont(12, weight: .bold)
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
