import AppKit
import Carbon.HIToolbox
import MCLAppModel
import MCLCore

/// The Settings window's key monitor: `NSEvent.addLocalMonitorForEvents` for presses and releases —
/// the application's own events only, and only those of the Settings window itself (not of the transceiver sheet or
/// another window).
///
/// - Esc on its **release** cancels the window (Kotlin `onKeyEvent`, `CW:67-74`) through `DialogKeyGate`: only when
///   its press reached the window too, and not when the press aborted a composition (marked text); a press consumed
///   by the key capture does not close the window on its release.
/// - While „Změnit" waits for a combination every key event is consumed (Kotlin `onPreviewKeyEvent` returns
///   `true`); a press is converted like the entry window's keys (`KeyEventBridge` + `AwtKeyCodes.translate`, the
///   character branch for letters of the layout) and judged by `KeyCaptureRules.capture`.
@MainActor
final class KeyCaptureMonitor: ObservableObject {

    private var token: Any?
    private weak var window: NSWindow?
    private var onEscapeRelease: (@MainActor () -> Void)?
    private var capture: (@MainActor (KeyCaptureRules.Capture) -> Void)?
    private var gate = DialogKeyGate.settingsWindow()

    /// Installs the monitor for the Settings window (once per window; later calls only update the Esc action).
    func install(window: NSWindow, onEscapeRelease: @escaping @MainActor () -> Void) {
        self.onEscapeRelease = onEscapeRelease
        guard self.window !== window || token == nil else { return }
        remove()
        self.window = window
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let snapshot = KeyEventBridge.snapshot(event) else { return event }
            let consumed: Bool = MainActor.assumeIsolated {
                self?.handle(snapshot) ?? false
            }
            return consumed ? nil : event
        }
    }

    /// The window closed.
    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        window = nil
        capture = nil
        gate.reset()
    }

    /// „Změnit": the next key presses go to `handler` until `stopCapture`.
    func startCapture(_ handler: @escaping @MainActor (KeyCaptureRules.Capture) -> Void) {
        capture = handler
        gate.reset()
    }

    func stopCapture() {
        capture = nil
    }

    private func handle(_ snapshot: KeyEventSnapshot) -> Bool {
        guard let window, snapshot.windowNumber == window.windowNumber else { return false }
        let event: MacKeyEvent = snapshot.event
        if let capture {
            // Kotlin consumes every event of the capturing text; only a press is judged.
            guard event.kind == .keyDown,
                  let stroke = AwtKeyCodes.translateForLayout(event), stroke.phase == .pressed else {
                return true
            }
            let combo = KeyCombo(ctrl: stroke.isControlDown, alt: stroke.isAltDown, shift: stroke.isShiftDown,
                                 meta: stroke.isMetaDown, keyCode: stroke.vk)
            capture(KeyCaptureRules.capture(combo))
            return true
        }
        guard event.keyCode == UInt16(kVK_Escape) else { return false }
        let outcome: DialogKeyGate.Outcome
        if event.kind == .keyDown {
            // Esc that aborts a composition (dead key, input method) belongs to the input system.
            let composing: Bool = (window.firstResponder as? NSTextView)?.hasMarkedText() ?? false
            outcome = gate.press(.escape, composing: composing)
        } else {
            outcome = gate.release(.escape)
        }
        if outcome.action == .cancel {
            onEscapeRelease?()
        }
        return outcome.consumed
    }
}
