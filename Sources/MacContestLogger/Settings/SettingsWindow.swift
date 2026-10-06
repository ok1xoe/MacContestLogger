import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ConfigurerWindow` (`CW:55-140`): the Settings window, 880×1000 by default (fitted to the screen),
/// resizable, without a kept geometry and not reopened after a restart. The font stepper is on top,
/// the tabs are a sidebar (instead of Kotlin's tab strip), the selected tab scrolls, and OK / „Zrušit" sit centred
/// at the bottom.
///
/// - OK commits the draft (`SettingsModel.confirm`) and the window closes after a successful save; a failed save
///   keeps it open with the draft.
/// - „Zrušit", Esc on its release and the close button drop the draft (`SettingsModel.cancel`).
/// - While a commit runs the window cannot be closed or cancelled (OK, „Zrušit", Esc and the close button are off),
///   so reopening it meanwhile only brings it to the front with the same draft.
struct SettingsWindowView: View {
    let host: AppHost

    @StateObject private var session = WindowSession(id: SettingsModel.windowId, persistSize: false,
                                                     defaultSize: CGSize(width: 880, height: 1000),
                                                     savesGeometry: false)
    @StateObject private var chrome = SettingsWindowChrome()
    @Environment(\.dismissWindow) private var dismissWindow

    private var binder: WindowGeometryBinder { session.binder }

    var body: some View {
        Group {
            if let app = host.model {
                loaded(app)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 780, minHeight: 420)
    }

    private func loaded(_ app: AppModel) -> some View {
        let settings: SettingsModel = app.settings
        let saving: Bool = settings.isSaving
        let keys: KeyCaptureMonitor = chrome.keys
        return VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: app.language)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                SettingsSidebar(app: app)
                    .frame(width: 210)
                Divider()
                SettingsContent(app: app)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            SettingsFooter(app: app)
        }
        .windowFont(13)
        .environment(\.windowFontSize, session.fontSize)
        .environmentObject(keys)
        .navigationTitle(app.language.tr("Nastavení"))
        .onAppear {
            binder.setStore(app.geometry)
            // A window shown without the model's request (SwiftUI) gets a draft like a regular opening.
            if !settings.isOpen {
                settings.open()
            }
        }
        .onChange(of: settings.isOpen) {
            if !settings.isOpen {
                dismissWindow(id: SettingsModel.windowId)
            }
        }
        .background(WindowAccessor { window in
            binder.isTerminating = { host.isTerminating }
            binder.onClose = {
                keys.remove()
                settings.cancel()
                app.settingsTools.windowClosed()
            }
            binder.attach(window)
            chrome.fit(window)
            window.standardWindowButton(.closeButton)?.isEnabled = !saving
            keys.install(window: window) {
                // Kotlin `onKeyEvent`: Esc on its release closes the window (= Zrušit).
                guard !settings.isSaving else { return }
                settings.cancel()
            }
        })
    }
}

/// Per-window AppKit helpers held with `@StateObject`: the key monitor (Esc, key capture) and the fitting of the
/// default size to the screen.
@MainActor
final class SettingsWindowChrome: ObservableObject {
    let keys = KeyCaptureMonitor()
    private weak var fitted: NSWindow?

    /// Kotlin `rememberDialogState(880, 1000)` on a smaller screen: the window is cut to the visible frame once.
    func fit(_ window: NSWindow) {
        guard fitted !== window else { return }
        fitted = window
        guard let visible: CGRect = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame: CGRect = window.frame
        guard frame.width > visible.width || frame.height > visible.height else { return }
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = visible.minX + (visible.width - frame.width) / 2
        frame.origin.y = visible.minY + (visible.height - frame.height) / 2
        window.setFrame(frame, display: false)
    }
}

/// The selected tab in a scroll view: „Žádný dostupný tab." when the menu leaves no enabled tab, a progress view
/// while the draft is being read.
struct SettingsContent: View {
    let app: AppModel

    var body: some View {
        let settings: SettingsModel = app.settings
        let anyEnabled: Bool = settings.specs.contains { $0.state == .enable }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !anyEnabled {
                    Text(verbatim: app.language.tr("Žádný dostupný tab."))
                        .foregroundStyle(.secondary)
                } else if let draft = settings.draft {
                    SettingsTabView(tab: settings.selected, app: app, draft: binding(settings, current: draft))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Edits typed during a write would be dropped when the commit closes the window.
            .disabled(settings.isSaving)
        }
    }

    /// The draft as a binding; a write after the window closed (a late field edit) is dropped.
    private func binding(_ settings: SettingsModel, current: ConfigurerDraft) -> Binding<ConfigurerDraft> {
        Binding(
            get: { settings.draft ?? current },
            set: { value in
                guard settings.isOpen, settings.draft != nil else { return }
                settings.draft = value
            })
    }
}

/// OK and „Zrušit", centred (`CW:127-135`).
struct SettingsFooter: View {
    let app: AppModel

    var body: some View {
        let settings: SettingsModel = app.settings
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                Task { await settings.confirm() }
            } label: {
                Text(verbatim: "OK")
                    .frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .disabled(settings.isSaving || settings.draft == nil)
            Button {
                settings.cancel()
            } label: {
                Text(verbatim: app.language.tr("Zrušit"))
                    .frame(minWidth: 60)
            }
            .disabled(settings.isSaving)
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

/// The tab bodies (`CW:94-124`).
struct SettingsTabView: View {
    let tab: ConfigurerTab
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        switch tab {
        case .hardware, .functionKeys, .keys, .digitalModes, .other, .winkey, .modeControl, .antennas,
             .scoreReporting, .broadcast:
            firstHalf
        case .wsjt, .audio, .station, .contest, .cluster, .dxCluster, .onlineCallbooks, .bandplan, .digiFreq,
             .map:
            secondHalf
        }
    }

    @ViewBuilder private var firstHalf: some View {
        switch tab {
        case .hardware:
            HardwareTab(app: app, draft: $draft)
        case .functionKeys:
            FunctionKeysTab(app: app, draft: $draft)
        case .keys:
            KeysTab(app: app, draft: $draft)
        case .digitalModes:
            DigitalModesTab(app: app, draft: $draft)
        case .other:
            OtherTab(app: app, draft: $draft)
        case .winkey:
            CwKeyerTab(app: app, draft: $draft)
        case .modeControl:
            ModeControlTab(app: app, draft: $draft)
        case .antennas:
            AntennasTab(app: app, draft: $draft)
        case .scoreReporting:
            ScoreReportingTab(app: app, draft: $draft)
        default:
            BroadcastTab(app: app, draft: $draft)
        }
    }

    @ViewBuilder private var secondHalf: some View {
        switch tab {
        case .wsjt:
            WsjtTab(app: app, draft: $draft)
        case .audio:
            AudioTab(app: app, draft: $draft)
        case .station:
            StationTab(app: app, draft: $draft)
        case .contest:
            ContestTab(app: app, draft: $draft)
        case .cluster:
            ClusterTab(app: app, draft: $draft)
        case .dxCluster:
            DxClusterTab(app: app, draft: $draft)
        case .onlineCallbooks:
            OnlineCallbooksTab(app: app, draft: $draft)
        case .bandplan:
            BandPlanTab(app: app, draft: $draft)
        case .digiFreq:
            DigiFreqTab(app: app, draft: $draft)
        default:
            MapTab(app: app, draft: $draft)
        }
    }
}

/// Opens the windows a model asks for by id (`WindowsModel.windowRequest`: the Settings window) or brings them to
/// the front. Attached to the main window, which lives as long as the app.
struct WindowRequestPresenter: ViewModifier {
    let app: AppModel

    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onChange(of: app.windows.windowRequest) {
                guard let request = app.windows.windowRequest else { return }
                openWindow(id: request.id)
            }
    }
}
