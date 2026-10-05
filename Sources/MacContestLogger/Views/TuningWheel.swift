import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The mouse wheel over an entry panel tunes the rig (Kotlin `onPointerEvent(PointerEventType.Scroll)`,
/// `EP:1030-1043`): one step of the mode per wheel event, Option 1 kHz, Control 10 kHz, Control+Option 100 kHz to the
/// next round frequency (`EntryModel.wheel` → `TuningState.wheel` → `RigModel.tuneTo`).
///
/// A local `NSEvent` monitor for the application's own scroll events (never a global one), acting only on events of
/// its window whose location lies inside the panel (`TuningWheelArea`). The event is passed on unchanged, as Compose
/// does not consume it. AWT's wheel rotation is negative for a positive `deltaY` and Compose's `dy < 0` is one step
/// up, so `deltaY > 0` tunes up.
@MainActor
final class TuningWheelMonitor: ObservableObject {

    private var token: Any?
    private weak var window: NSWindow?
    private weak var entry: EntryModel?
    private var accepts: @MainActor () -> Bool = { false }
    private var observer: NSObjectProtocol?
    /// The panel's view (its bounds = the area the wheel tunes in).
    weak var area: NSView?

    /// Installs the monitor for `window` and the window's entry model (once per window).
    func install(window: NSWindow, entry: EntryModel, accepts: @escaping @MainActor () -> Bool) {
        self.entry = entry
        self.accepts = accepts
        guard self.window !== window || token == nil else { return }
        remove()
        self.window = window
        token = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            let deltaY: CGFloat = event.deltaY
            let number: Int = event.windowNumber
            let location: NSPoint = event.locationInWindow
            let flags: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            MainActor.assumeIsolated {
                self?.scrolled(deltaY: deltaY, windowNumber: number, location: location, flags: flags)
            }
            return event
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove() }
        }
    }

    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        token = nil
        observer = nil
        window = nil
    }

    private func scrolled(deltaY: CGFloat, windowNumber: Int, location: NSPoint, flags: NSEvent.ModifierFlags) {
        guard deltaY != 0, let window, window.windowNumber == windowNumber, let area, let entry, accepts() else {
            return
        }
        let point: NSPoint = area.convert(location, from: nil)
        guard area.bounds.contains(point) else { return }
        entry.wheel(direction: deltaY > 0 ? 1 : -1, alt: flags.contains(.option), ctrl: flags.contains(.control))
    }
}

/// A transparent view behind the entry panel that tells `TuningWheelMonitor` where the panel is. It takes no events
/// (`hitTest` returns `nil`), so clicks and scrolls reach the panel's own views.
struct TuningWheelArea: NSViewRepresentable {
    let monitor: TuningWheelMonitor

    final class AreaView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    func makeNSView(context: Context) -> AreaView {
        let view = AreaView()
        monitor.area = view
        return view
    }

    func updateNSView(_ view: AreaView, context: Context) {
        monitor.area = view
    }
}
