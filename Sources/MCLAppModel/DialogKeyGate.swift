import Foundation

/// Enter and Esc of the entry dialogs (the text prompt, the confirmations, the operator window) in Kotlin's phases:
/// - Enter acts on its **release** (`onPreviewKeyEvent` on `KeyUp`, `TextPromptDialog.kt`, `OperatorDialog.kt`); a
///   confirmation has no Enter action (Compose `AlertDialog`).
/// - Esc: the operator window (a Kotlin `Window`) closes on the release (`OperatorDialog.kt`, `KeyUp`). The text
///   prompt and the confirmations are Compose `Dialog` layers, which dismiss on the Esc **press** (Compose 1.7.3
///   `Dialog.skiko.kt`: `isDismissRequest() = type == KeyDown && key == Escape`, the field's `KeyUp` handler comes
///   too late).
/// - A press while the field holds marked text belongs to the input system (it commits the composition): it passes on
///   and is not recorded, so its release does nothing either.
/// - A release whose press the dialog did not see does nothing.
public struct DialogKeyGate: Sendable {

    public enum Key: Hashable, Sendable {
        case enter
        case escape
    }

    public enum Action: Equatable, Sendable {
        case submit
        case cancel
    }

    /// What the dialog does with a key event.
    public struct Outcome: Equatable, Sendable {
        /// The event is dropped (the field never sees it).
        public let consumed: Bool
        public let action: Action?

        public init(consumed: Bool, action: Action?) {
            self.consumed = consumed
            self.action = action
        }
    }

    /// Enter submits (the prompt, the operator window); `false` = a confirmation.
    public var enterSubmits: Bool
    /// Esc cancels on its press (Compose `Dialog`); `false` = on its release (the operator `Window`).
    public var escapeOnPress: Bool
    private var pressed: Set<Key> = []

    public init(enterSubmits: Bool, escapeOnPress: Bool) {
        self.enterSubmits = enterSubmits
        self.escapeOnPress = escapeOnPress
    }

    /// The Settings window (Kotlin `ConfigurerWindow` `onKeyEvent`, `CW:67-74`): Esc cancels on its release, Enter
    /// does nothing; an Esc that aborts a composition (a dead key, an input method) does not cancel.
    public static func settingsWindow() -> DialogKeyGate {
        DialogKeyGate(enterSubmits: false, escapeOnPress: false)
    }

    public mutating func press(_ key: Key, composing: Bool) -> Outcome {
        if composing {
            pressed.remove(key)
            return Outcome(consumed: false, action: nil)
        }
        if key == .escape && escapeOnPress {
            pressed.remove(key)
            return Outcome(consumed: true, action: .cancel)
        }
        pressed.insert(key)
        return Outcome(consumed: true, action: nil)
    }

    public mutating func release(_ key: Key) -> Outcome {
        guard pressed.remove(key) != nil else {
            return Outcome(consumed: false, action: nil)
        }
        switch key {
        case .enter:
            return Outcome(consumed: true, action: enterSubmits ? .submit : nil)
        case .escape:
            return Outcome(consumed: true, action: escapeOnPress ? nil : .cancel)
        }
    }

    /// The dialog's window stopped being key: the keys held now are released elsewhere.
    public mutating func reset() {
        pressed.removeAll()
    }
}
