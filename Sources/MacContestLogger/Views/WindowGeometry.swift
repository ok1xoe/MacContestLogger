import AppKit
import MCLAppModel
import SwiftUI

/// Hands the hosting `NSWindow` of a SwiftUI view to `onWindow` as soon as the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    final class AccessorView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: AccessorView, context: Context) {
        view.onWindow = onWindow
        if let window = view.window {
            onWindow(window)
        }
    }
}

/// Binds a window to `config.windowGeometry[id]` through `WindowGeometryStore` (Kotlin
/// `rememberPersistentWindowState`): the saved frame is applied once before the window is shown (the window stays
/// transparent until then), moves and resizes are reported to the store, which saves them after 500 ms.
///
/// The window's delegate belongs to SwiftUI, so the binder listens to the `didMove`/`didResize`/`willClose`
/// notifications (the same events as `NSWindowDelegate.windowDidMove`/`windowDidResize`). State restoration and
/// AppKit's frame autosave are turned off (the autosave name again at every move, resize and key change, since SwiftUI
/// reassigns it): the config file is the only place a frame is kept.
///
/// A window whose size is not persisted (the main window) keeps its top-left corner when its content changes
/// its size, so a bigger font grows the window downwards (AppKit would keep the bottom-left corner).
@MainActor
final class WindowGeometryBinder {

    let id: String
    let persistSize: Bool
    let defaultSize: CGSize
    /// `false` for a window whose geometry is not kept (Kotlin `DialogWindow` with `rememberDialogState`): it opens
    /// centred at its default size and nothing is saved.
    let savesGeometry: Bool
    /// Called when the user closes the window (not while the app quits).
    var onClose: (@MainActor () -> Void)?
    /// `true` while the app quits: closing windows then is not a user's close.
    var isTerminating: @MainActor () -> Bool = { false }

    private weak var window: NSWindow?
    private var store: WindowGeometryStore?
    private var observers: [NSObjectProtocol] = []
    private var applied = false
    private var topLeft: NSPoint?

    init(id: String, persistSize: Bool, defaultSize: CGSize, savesGeometry: Bool = true) {
        self.id = id
        self.persistSize = persistSize
        self.defaultSize = defaultSize
        self.savesGeometry = savesGeometry
    }

    /// The window is known (it may not have a store yet: the app model is still bootstrapping).
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        applied = false
        window.isRestorable = false
        // The config file is the only store; SwiftUI's frame records are also removed at start and
        // on quit (`WindowFrameDefaults`).
        Self.clearAutosave(window)
        if store == nil {
            window.alphaValue = 0
        }
        observe(window)
        applyInitialFrame()
    }

    /// The app model is ready.
    func setStore(_ store: WindowGeometryStore) {
        guard self.store == nil else { return }
        self.store = store
        applyInitialFrame()
    }

    private func applyInitialFrame() {
        guard !applied, let window, let store else { return }
        applied = true
        // SwiftUI may assign the autosave name again after the first attach.
        Self.clearAutosave(window)
        guard savesGeometry else {
            window.center()
            topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.alphaValue = 1
            return
        }
        let screens: [CGRect] = NSScreen.screens.map(\.frame)
        let height: CGFloat = Self.mainScreenHeight()
        if let frame = store.initialFrame(id: id, defaultSize: defaultSize, persistSize: persistSize,
                                          screens: screens, mainScreenHeight: height) {
            if persistSize {
                window.setFrame(frame, display: false)
            } else {
                window.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
            }
        }
        topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.alphaValue = 1
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: window,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        })
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resized() }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameKey() }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closing() }
        })
    }

    private func detach() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    /// SwiftUI assigns its scene's autosave name again after the first attach (the main window's `Window(…, id:
    /// "main")`), and AppKit then writes `NSWindow Frame <name>` into the real defaults domain on the next frame
    /// change — under `.windowResizability(.contentSize)` a content-size change is enough. Every move, resize and key
    /// change (and the close) clears the name again and drops a record already written under it.
    static func clearAutosave(_ window: NSWindow) {
        let name: String = window.frameAutosaveName
        guard !name.isEmpty else { return }
        window.setFrameAutosaveName("")
        WindowFrameDefaults.removeRecord(autosaveName: name, in: UserDefaults.standard)
    }

    private func becameKey() {
        guard let window else { return }
        Self.clearAutosave(window)
    }

    private func moved() {
        guard let window else { return }
        Self.clearAutosave(window)
        guard applied else { return }
        topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        report(window)
    }

    private func resized() {
        guard let window else { return }
        Self.clearAutosave(window)
        guard applied else { return }
        if !persistSize, !window.inLiveResize, let topLeft, window.frame.maxY != topLeft.y {
            window.setFrameTopLeftPoint(topLeft)
        }
        report(window)
    }

    private func report(_ window: NSWindow) {
        guard savesGeometry else { return }
        store?.windowChanged(id: id, frame: window.frame, persistSize: persistSize,
                             mainScreenHeight: Self.mainScreenHeight())
    }

    private func closing() {
        // NSWindow may save its frame on close as well.
        if let window {
            Self.clearAutosave(window)
        }
        detach()
        window = nil
        guard !isTerminating() else { return }
        onClose?()
    }

    /// The main display's height (AWT's origin is its top-left corner): `NSScreen.screens[0]` holds the menu bar.
    static func mainScreenHeight() -> CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }
}

/// Per-window view state that must outlive view updates: the stepper's font size (not persisted) and
/// the geometry binder. Held with `@StateObject`.
@MainActor
final class WindowSession: ObservableObject {
    @Published var fontSize: Int = WindowFont.defaultSize
    let binder: WindowGeometryBinder

    init(id: String, persistSize: Bool, defaultSize: CGSize, savesGeometry: Bool = true) {
        binder = WindowGeometryBinder(id: id, persistSize: persistSize, defaultSize: defaultSize,
                                      savesGeometry: savesGeometry)
    }
}
