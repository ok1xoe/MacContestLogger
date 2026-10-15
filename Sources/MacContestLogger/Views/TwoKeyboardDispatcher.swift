import AppKit
import MCLAppModel
import MCLCore

/// The AppKit half of N1MM „Two Keyboards": every entry window's key monitor asks it first. A key that belongs to
/// the entry window that is not the key window makes that window the key window and is posted again, so it reaches
/// the window it was typed for; `\` only moves the focus there and the Pause key is dropped (`TwoKeyboardModel`).
///
/// Keys stay where they are while a modal dialog or a sheet is open and while another window's text field is being
/// typed in (the cluster command line, a dialog): only keys typed into an entry window or into a window without a
/// text field are moved.
@MainActor
final class TwoKeyboardDispatcher {

    static let shared = TwoKeyboardDispatcher()

    var keyboards: TwoKeyboardModel?
    private var windows: [Int: WeakWindow] = [:]

    private struct WeakWindow {
        weak var window: NSWindow?
    }

    /// The entry window of VFO / radio `vfo`.
    func register(_ window: NSWindow, vfo: Int) {
        windows[vfo] = WeakWindow(window: window)
    }

    /// `nil` = the monitor handles the key as usual; `true` = the key was taken here (moved or dropped).
    func dispatch(_ snapshot: KeyEventSnapshot) -> Bool? {
        guard let keyboards else { return nil }
        if keyboards.isTesting {
            keyboards.drainPresses()
            return nil
        }
        guard keyboards.isActive else { return nil }
        let down: Bool
        switch snapshot.event.kind {
        case .keyDown:
            down = true
        case .keyUp:
            down = false
        case .flagsChanged:
            return nil
        }
        guard NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil, !typingElsewhere else { return nil }
        let key = TwoKeyboardModel.EventKey(timestamp: snapshot.timestamp, keyCode: snapshot.event.keyCode,
                                            down: down)
        switch keyboards.route(key, isRepeat: snapshot.event.isARepeat) {
        case .none:
            return nil
        case .drop:
            return true
        case .focusOnly(let vfo):
            _ = makeKey(vfo)
            return true
        case .window(let vfo):
            guard let window = windows[vfo]?.window, window.isVisible else { return nil }
            if window.isKeyWindow {
                return nil
            }
            guard makeKey(vfo) else { return nil }
            repost(snapshot, to: window)
            return true
        }
    }

    /// Another window than an entry window has a text field being typed in.
    private var typingElsewhere: Bool {
        guard let key = NSApp.keyWindow else { return false }
        if windows.values.contains(where: { $0.window === key }) {
            return false
        }
        return key.firstResponder is NSTextView
    }

    private func makeKey(_ vfo: Int) -> Bool {
        guard let window = windows[vfo]?.window, window.isVisible else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// The key again, for `window` (the same time stamp: the model routes it the same way, now to the key window).
    private func repost(_ snapshot: KeyEventSnapshot, to window: NSWindow) {
        let event: MacKeyEvent = snapshot.event
        guard let copy = NSEvent.keyEvent(with: event.kind == .keyDown ? .keyDown : .keyUp, location: .zero,
                                          modifierFlags: NSEvent.ModifierFlags(rawValue: event.modifierFlags),
                                          timestamp: snapshot.timestamp, windowNumber: window.windowNumber,
                                          context: nil, characters: event.characters ?? "",
                                          charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                                          isARepeat: event.isARepeat, keyCode: event.keyCode) else { return }
        NSApp.postEvent(copy, atStart: true)
    }
}
