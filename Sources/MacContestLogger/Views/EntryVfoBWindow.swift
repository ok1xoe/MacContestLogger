import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin's second entry window (`App.kt:336-357`): `entry-vfob`, 900×360, the font stepper and
/// `EntryPanel(state, vfo = 1)`. Shown only while `twoEntryWindows` (SO2V/SO2R; the main window opens and dismisses
/// it), titled `tr("Zadávací okno — rig 2")` in SO2R, `tr("Zadávací okno — VFO B")` otherwise. The user cannot close
/// it: a close sets the status `tr("Okno VFO B zavře přepnutí na SO1V v Nastavení → Hardware")`. It is not part of
/// `openWindows`; its geometry is kept like every window's.
struct EntryVfoBWindowView: View {
    let host: AppHost

    static let id = "entry-vfob"

    @StateObject private var session = WindowSession(id: EntryVfoBWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 900, height: 390))
    @StateObject private var focusHolder = FocusHolder()
    @StateObject private var keyMonitor = EntryKeyMonitor()
    @StateObject private var wheel = TuningWheelMonitor()
    @StateObject private var activator = EntryWindowActivator()
    @StateObject private var closeGuard = WindowCloseGuard()

    private var binder: WindowGeometryBinder { session.binder }
    private var focus: EntryFocusController { focusHolder.controller }

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .navigationTitle(Self.title(app))
                    .onAppear {
                        binder.setStore(app.geometry)
                        focus.focus(.call)
                    }
                    .background(WindowAccessor { window in
                        binder.isTerminating = { host.isTerminating }
                        binder.attach(window)
                        let panel: EntryPanel = app.vfoB
                        keyMonitor.install(window: window, entry: panel.entry)
                        wheel.install(window: window, entry: panel.entry, accepts: { app.acceptsEntryInput })
                        activator.install(window: window, app: app, vfo: panel.vfo,
                                          isTerminating: { host.isTerminating })
                        closeGuard.install(window: window, allowsClose: {
                            host.isTerminating || !app.rig.vfo.twoEntryWindows
                        }, refused: {
                            app.status.show("Okno VFO B zavře přepnutí na SO1V v Nastavení → Hardware")
                        })
                    })
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 600, minHeight: 330)
    }

    static func title(_ app: AppModel) -> String {
        app.rig.vfo.so2r ? app.language.tr("Zadávací okno — rig 2") : app.language.tr("Zadávací okno — VFO B")
    }

    private func content(_ app: AppModel) -> some View {
        let panel: EntryPanel = app.vfoB
        return VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: app.language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            // Kotlin's column does not scroll: what does not fit the window is cut off.
            EntryPanelView(app: app, panel: panel, focus: focus, wheel: wheel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .environment(\.windowFontSize, session.fontSize)
        .onChange(of: panel.entry.focusRequest) {
            focus.focus(.call)
        }
        .modifier(EntryFocusFollower(app: app, entry: panel.entry, focus: focus))
        .modifier(EntryVfoFocus(app: app, vfo: panel.vfo, focus: focus, activator: activator))
    }
}

/// Kotlin `onFocusChanged { if (it.hasFocus && state.twoEntryWindows) state.activateVfo(vfo) }` (`EP:1028`): the
/// window that becomes the key window makes its VFO (or rig) the active one — only with two entry windows. And
/// `focusVfoRequest` (`\`, `EP:198-203`): the requested window becomes the key window with its call field focused.
///
/// For the VFO B window it also keeps `EntryModel.isWindowShown`: set when the window is there, cleared when it
/// closes; a close while it was the active window (not while quitting) hands the activity back to VFO A, so no
/// invisible window stays active.
@MainActor
final class EntryWindowActivator: ObservableObject {

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func install(window: NSWindow, app: AppModel, vfo: Int,
                 isTerminating: @escaping @MainActor () -> Bool = { false }) {
        guard self.window !== window else { return }
        remove()
        self.window = window
        let entry: EntryModel = app.panel(vfo: vfo).entry
        if vfo != 0 {
            entry.isWindowShown = true
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                            queue: .main) { [weak app] _ in
            MainActor.assumeIsolated {
                guard let app, app.rig.vfo.twoEntryWindows else { return }
                app.rig.activateVfo(vfo)
            }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                            queue: .main) { [weak self, weak app] _ in
            MainActor.assumeIsolated {
                self?.remove()
                guard vfo != 0, let app else { return }
                app.panel(vfo: vfo).entry.isWindowShown = false
                if !isTerminating() && app.rig.vfo.twoEntryWindows && app.rig.vfo.activeVfo == vfo {
                    app.rig.activateVfo(0)
                }
            }
        })
    }

    private func remove() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        window = nil
    }

    /// Brings the window forward as the key window (the `\` switch).
    func makeKey() {
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The `focusVfoRequest` of the window's VFO: key window, call field, request cleared.
struct EntryVfoFocus: ViewModifier {
    let app: AppModel
    let vfo: Int
    let focus: EntryFocusController
    let activator: EntryWindowActivator

    func body(content: Content) -> some View {
        content
            .onChange(of: app.rig.focusVfoRequest, initial: true) {
                guard app.rig.focusVfoRequest == vfo else { return }
                app.rig.focusVfoRequest = nil
                activator.makeKey()
                focus.focus(.call)
            }
    }
}

/// Refuses the user's close of a window that only a setting may close (the close button and Close ⌘W both ask the
/// delegate's `windowShouldClose`). SwiftUI owns the window's delegate, so the guard puts a forwarding proxy in front
/// of it: every other delegate message reaches SwiftUI's delegate unchanged.
@MainActor
final class WindowCloseGuard: ObservableObject {

    private var proxy: CloseGuardProxy?

    func install(window: NSWindow, allowsClose: @escaping @MainActor () -> Bool,
                 refused: @escaping @MainActor () -> Void) {
        if let proxy, window.delegate === proxy {
            proxy.allowsClose = allowsClose
            proxy.refused = refused
            return
        }
        let next = CloseGuardProxy(inner: window.delegate, allowsClose: allowsClose, refused: refused)
        proxy = next
        window.delegate = next
    }
}

/// The delegate proxy of `WindowCloseGuard`.
@MainActor
final class CloseGuardProxy: NSObject, NSWindowDelegate {

    /// Read by the nonisolated `NSObject` overrides below; AppKit calls a window's delegate on the main thread only.
    nonisolated(unsafe) weak var inner: (any NSWindowDelegate)?
    var allowsClose: @MainActor () -> Bool
    var refused: @MainActor () -> Void

    init(inner: (any NSWindowDelegate)?, allowsClose: @escaping @MainActor () -> Bool,
         refused: @escaping @MainActor () -> Void) {
        self.inner = inner
        self.allowsClose = allowsClose
        self.refused = refused
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard allowsClose() else {
            refused()
            return false
        }
        return inner?.windowShouldClose?(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) {
            return true
        }
        return inner?.responds(to: selector) ?? false
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if let inner, inner.responds(to: selector) {
            return inner
        }
        return super.forwardingTarget(for: selector)
    }
}
