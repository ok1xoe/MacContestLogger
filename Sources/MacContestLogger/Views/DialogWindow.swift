import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The frame of a dialog window of the slice (Kotlin `Window` + `WindowTopBar`): the font stepper on top, the title
/// in the current language, the geometry under the dialog's id, and the window's close button closes
/// the dialog in the model.
struct DialogWindowView<Content: View>: View {
    let host: AppHost
    let dialog: DialogsModel.Window
    let padding: CGFloat
    let title: @MainActor (AppModel) -> String
    @ViewBuilder let content: @MainActor (AppModel) -> Content

    @StateObject private var session: WindowSession

    init(host: AppHost, dialog: DialogsModel.Window, padding: CGFloat,
         title: @escaping @MainActor (AppModel) -> String,
         @ViewBuilder content: @escaping @MainActor (AppModel) -> Content) {
        self.host = host
        self.dialog = dialog
        self.padding = padding
        self.title = title
        self.content = content
        _session = StateObject(wrappedValue: WindowSession(id: dialog.rawValue, persistSize: true,
                                                           defaultSize: dialog.defaultSize,
                                                           savesGeometry: dialog.savesGeometry))
    }

    private var binder: WindowGeometryBinder { session.binder }

    var body: some View {
        Group {
            if let app = host.model {
                VStack(alignment: .leading, spacing: 0) {
                    WindowTopBar(size: $session.fontSize, language: app.language)
                    content(app)
                }
                .windowFont(13)
                .padding(padding)
                .environment(\.windowFontSize, session.fontSize)
                .navigationTitle(title(app))
                .onAppear { binder.setStore(app.geometry) }
                .background(WindowAccessor { window in
                    binder.isTerminating = { host.isTerminating }
                    binder.onClose = { app.dialogs.setOpen(dialog, false) }
                    binder.attach(window)
                })
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 300, minHeight: 150)
    }
}

/// Keeps the dialog windows in step with `DialogsModel` (Kotlin shows a window while its flag is set) and opens a
/// tool window that a menu item marked open. Attached to the main window, which lives as long as the app.
struct DialogPresenter: ViewModifier {
    let app: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                // The start-up offer is made during the bootstrap, before this window has a model.
                for dialog in DialogsModel.Window.allCases where app.dialogs.isOpen(dialog) {
                    openWindow(id: dialog.rawValue)
                }
            }
            .onChange(of: app.dialogs.openDialogs) { old, new in
                for dialog in DialogsModel.Window.allCases {
                    if new.contains(dialog) && !old.contains(dialog) {
                        openWindow(id: dialog.rawValue)
                    } else if old.contains(dialog) && !new.contains(dialog) {
                        dismissWindow(id: dialog.rawValue)
                    }
                }
            }
            .onChange(of: app.windows.openIds) { old, new in
                for id in new where !old.contains(id) && WindowsModel.implemented.contains(id) {
                    openWindow(id: WindowsModel.sceneId(for: id))
                }
                for id in new where !old.contains(id) && PluginCatalog.parseWindowKey(id) != nil {
                    openWindow(id: PluginWindowView.sceneId, value: id)
                }
                // The DX Cluster shortcut toggles its window: an id the model dropped closes the spot window (a
                // window the user closed has already gone).
                for id in old where !new.contains(id) && WindowsModel.spotWindows.contains(id) {
                    dismissWindow(id: id)
                }
            }
    }
}

/// Small layout pieces shared by the dialogs.
struct DialogButtonRow<Buttons: View>: View {
    @ViewBuilder let buttons: () -> Buttons

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            buttons()
        }
    }
}
