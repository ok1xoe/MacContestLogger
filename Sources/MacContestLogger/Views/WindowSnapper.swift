import AppKit
import MCLAppModel
import MCLCore

/// N1MM „Snap windows to edges" (Nastavení → Přichytávat okna k okrajům, off by default): a window of the app that
/// the user drags and lets go near the edge of the screen or near another of the app's windows snaps to it
/// (`WindowSnap`). Moves the app makes itself (restoring a layout, the snap itself) are left alone: only a move
/// made while the mouse button is held counts, and the snap happens once the button is released.
@MainActor
final class WindowSnapper {

    private weak var app: AppModel?
    private var observer: NSObjectProtocol?
    private var dragged: NSWindow?
    private var timer: Timer?

    func install(app: AppModel) {
        guard observer == nil else { return }
        self.app = app
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil,
                                                          queue: .main) { [weak self] note in
            let window: NSWindow? = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window else { return }
                self?.moved(window)
            }
        }
    }

    private var enabled: Bool {
        app?.config.config.window.flag(.snapWindows) == true
    }

    private func moved(_ window: NSWindow) {
        guard enabled, Self.snaps(window), NSEvent.pressedMouseButtons & 1 != 0 else { return }
        dragged = window
        guard timer == nil else { return }
        // AppKit runs the drag itself; the release is noticed by watching the button.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
    }

    private func poll() {
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        timer?.invalidate()
        timer = nil
        guard let window = dragged else { return }
        dragged = nil
        snap(window)
    }

    private func snap(_ window: NSWindow) {
        guard enabled, let app else { return }
        let others: [CGRect] = NSApp.windows
            .filter { $0 !== window && Self.snaps($0) }
            .map(\.frame)
        let screens: [CGRect] = NSScreen.screens.map(\.visibleFrame)
        let distance = CGFloat(app.config.config.window.snapDistance)
        guard let origin = WindowSnap.snappedOrigin(window.frame, screens: screens, others: others,
                                                    distance: distance) else { return }
        window.setFrameOrigin(origin)
    }

    /// Ordinary visible windows of the app (no sheets, panels or menus).
    private static func snaps(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.styleMask.contains(.titled)
            && !(window is NSPanel) && window.sheetParent == nil
            && !window.styleMask.contains(.fullScreen)
    }
}
