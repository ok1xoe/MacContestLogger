import AppKit
import MCLAppModel
import SwiftUI

/// The frame every radio tool window shares (Kotlin `Window(title = tr(…), state =
/// rememberPersistentWindowState(state, id, size))`): the translated title, the geometry kept in
/// `config.windowGeometry[id]`, and the window's id leaving `config.openWindows` when the user closes it.
struct RadioWindowChrome: ViewModifier {
    let host: AppHost
    let app: AppModel
    let id: String
    let title: String
    let binder: WindowGeometryBinder

    func body(content: Content) -> some View {
        content
            .navigationTitle(app.language.tr(title))
            .onAppear { binder.setStore(app.geometry) }
            .background(WindowAccessor { window in
                binder.isTerminating = { host.isTerminating }
                binder.onClose = { [weak windows = app.windows, id] in
                    windows?.setOpen(id, false)
                }
                binder.attach(window)
            })
    }
}

/// A window's own model (Kotlin `remember { … }` inside the window): made once from the app model when the window's
/// view first has one, dropped with the window — a reopened window starts afresh.
@MainActor
final class WindowModelHolder<Model: AnyObject>: ObservableObject {
    private var model: Model?

    func model(_ make: () -> Model) -> Model {
        if let model {
            return model
        }
        let made: Model = make()
        model = made
        return made
    }
}

/// A key of a radio tool window, copied out of its `NSEvent`.
struct WindowKey: Sendable {
    let keyCode: UInt16
    let down: Bool
    let shift: Bool
}

/// A tool window's own keys (Kotlin `onPreviewKeyEvent`): a local `NSEvent` monitor — the application's own events
/// only, never a global monitor — that hands key presses and releases of its window, while that window is the key
/// window, to `handler`; a consumed key (`true`) goes no further. Removed when the window closes.
@MainActor
final class WindowKeyMonitor: ObservableObject {
    nonisolated(unsafe) private var token: Any?
    private weak var window: NSWindow?
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    var handler: (@MainActor (WindowKey) -> Bool)?

    func install(window: NSWindow) {
        guard self.window !== window || token == nil else { return }
        remove()
        self.window = window
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let key = WindowKey(keyCode: event.keyCode, down: event.type == .keyDown,
                                shift: event.modifierFlags.contains(.shift))
            let number: Int = event.windowNumber
            let consumed: Bool = MainActor.assumeIsolated {
                self?.handle(key, windowNumber: number) ?? false
            }
            return consumed ? nil : event
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove() }
        }
    }

    deinit {
        if let token {
            NSEvent.removeMonitor(token)
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        window = nil
    }

    private func handle(_ key: WindowKey, windowNumber: Int) -> Bool {
        guard let window, window.isKeyWindow, window.windowNumber == windowNumber, let handler else { return false }
        return handler(key)
    }
}
