import AppKit
import Carbon.HIToolbox
import MCLAppModel
import MCLCore

/// A key event copied out of an `NSEvent` (plain values, safe to hand to the main actor) with the number of the window
/// it belongs to.
struct KeyEventSnapshot: Sendable {
    let event: MacKeyEvent
    let windowNumber: Int
}

/// `NSEvent` → `MacKeyEvent` (podklad 4.3): the fields `CPlatformResponder.handleKeyEvent` reads. The previous
/// modifier flags are filled in by `EntryKeyFlow`; the dead-key character is computed like JDK `NsGetDeadKeyChar`.
enum KeyEventBridge {

    /// `nil` for an event type the monitor does not handle.
    static func snapshot(_ event: NSEvent) -> KeyEventSnapshot? {
        let kind: MacKeyEvent.Kind
        switch event.type {
        case .keyDown:
            kind = .keyDown
        case .keyUp:
            kind = .keyUp
        case .flagsChanged:
            kind = .flagsChanged
        default:
            return nil
        }
        var copy = MacKeyEvent(kind: kind, keyCode: event.keyCode, modifierFlags: event.modifierFlags.rawValue)
        if kind != .flagsChanged {
            // `characters`, `charactersIgnoringModifiers` and `isARepeat` raise for `flagsChanged`.
            let characters: String? = event.characters
            copy.characters = characters
            copy.charactersIgnoringModifiers = event.charactersIgnoringModifiers
            copy.isARepeat = event.isARepeat
            if characters?.isEmpty == true {
                copy.deadKeyCharacter = deadKeyCharacter(keyCode: event.keyCode)
            }
        }
        return KeyEventSnapshot(event: copy, windowNumber: event.windowNumber)
    }

    /// JDK 21 `NsGetDeadKeyChar` (`AWTEvent.m`): the key translated with the current Carbon modifiers
    /// (`GetCurrentEventKeyModifiers() >> 8`) and the option `kUCKeyTranslateNoDeadKeysBit` — the bit's index, 0, as
    /// JDK passes it, so the dead-key state is kept — then Space; the first character, `0` when there is none.
    static func deadKeyCharacter(keyCode: UInt16) -> UInt16 {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return 0
        }
        let data: CFData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return 0 }
        let modifierKeyState = UInt32((GetCurrentEventKeyModifiers() >> 8) & 0xFF)
        let keyboardType = UInt32(LMGetKbdType())
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout -> UInt16 in
            var deadKeyState: UInt32 = 0
            var length: Int = 0
            var chars = [UniChar](repeating: 0, count: 255)
            var status: OSStatus = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifierKeyState,
                                                  keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                                  &deadKeyState, 255, &length, &chars)
            guard status == noErr, deadKeyState != 0 else { return 0 }
            status = UCKeyTranslate(layout, UInt16(kVK_Space), UInt16(kUCKeyActionDown), 0, keyboardType, 0,
                                    &deadKeyState, 255, &length, &chars)
            guard status == noErr, length > 0 else { return 0 }
            return chars[0]
        }
    }
}

/// The entry window's key monitor: `NSEvent.addLocalMonitorForEvents` for key presses, releases and modifier
/// changes — the application's own events only, never a global monitor. Installed with the main window and removed
/// when it closes.
///
/// Every `flagsChanged` goes to `EntryKeyFlow` (the JDK keeps the previous flags of every one). The other events are
/// routed only while the main window is the key window and an entry field's editor is its first responder; the
/// frequency field and other windows get their keys untouched. A consumed event is dropped (`nil`).
@MainActor
final class EntryKeyMonitor: ObservableObject {

    private var token: Any?
    private weak var window: NSWindow?
    private var flow: EntryKeyFlow?
    private var observers: [NSObjectProtocol] = []

    /// Installs the monitor for `window` (once; a later call with the same window does nothing). The flow keeps the
    /// `EntryModel` it is given for the window's lifetime: `AppHost` creates the app model once and never replaces it
    /// (a failed bootstrap ends the app), so the main window's entry model is fixed.
    func install(window: NSWindow, entry: EntryModel) {
        guard self.window !== window || token == nil else { return }
        remove()
        self.window = window
        flow = EntryKeyFlow(entry: entry)
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let snapshot = KeyEventBridge.snapshot(event) else { return event }
            let consumed: Bool = MainActor.assumeIsolated {
                self?.handle(snapshot) ?? false
            }
            return consumed ? nil : event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flow?.reset() }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove() }
        })
    }

    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        flow = nil
        window = nil
    }

    private func handle(_ snapshot: KeyEventSnapshot) -> Bool {
        guard let flow else { return false }
        return flow.process(snapshot.event, target: target(windowNumber: snapshot.windowNumber))
    }

    /// The entry field with the focus, when the event belongs to the key main window; `.composing` while its editor
    /// holds marked text (the key belongs to the input system, as in JDK `AWTView keyDown`).
    private func target(windowNumber: Int) -> EntryKeyFlow.Target {
        guard let window, window.isKeyWindow, window.windowNumber == windowNumber,
              let editor = window.firstResponder as? EntryFieldEditor,
              let key = editor.owner?.entryKey else {
            return .elsewhere
        }
        let field: EntryKeyField
        switch key {
        case .call:
            field = .call
        case .time:
            field = .time
        case .rstSent, .rstRcvd, .exchange, .contest:
            field = .exchange
        }
        return editor.hasMarkedText() ? .composing(field) : .entry(field)
    }
}
