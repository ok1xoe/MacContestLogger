import Foundation

/// The Keys tab of Settings (N1MM Key Mapper, `KT:` = `ui/configurer/KeysTab.kt` of v1.1.1, lines 46-109): the
/// rows of all `ShortcutAction`s, the capture of a new combination and the three edits of the remapping.
/// The remapping is the draft's `action id → "Ctrl+Alt+S"` map (`""` = the action has no key).
public enum KeyCaptureRules {

    /// The outcome of one key event while "Změnit" waits for a combination (`KT:66-80`).
    public enum Capture: Equatable, Sendable {
        /// Esc (any modifiers, `e.key == Key.Escape`): capturing ends, the hint is cleared, nothing changes.
        case cancelled
        /// A bare modifier: consumed, capturing goes on.
        case ignored
        /// Store `text` (`KeyCombo.format()`) as the action's remapping; capturing ends, the hint is cleared.
        case accepted(String)
        /// Not allowed: show `tr(hintKey, args…)`, capturing goes on.
        case rejected(hintKey: String, args: [String])
    }

    /// One row of the table (`KT:55-95`).
    public struct Row: Equatable, Sendable {
        public let action: ShortcutAction
        /// `comboFor(action).format()` or `"—"` when the action has no key.
        public let keys: String
        /// Bold = the remapping contains the action id; also enables "Výchozí".
        public let isCustom: Bool
        /// The other actions on the same keys, in Java action order (non-empty = shown in the error colour).
        public let conflicts: [ShortcutAction]

        /// `"koliduje: " + conflicts.joinToString { it.label() }` — neither part goes through `tr` in Kotlin; `nil`
        /// without a conflict.
        public var conflictText: String? {
            guard !conflicts.isEmpty else { return nil }
            let labels: [String] = conflicts.map(\.label)
            return SettingsTexts.conflictPrefix + labels.joined(separator: ", ")
        }
    }

    /// The rows of every `ShortcutAction` in Java order, over `KeyBindings(overrides)`.
    public static func rows(overrides: [String: String]) -> [Row] {
        let bindings = KeyBindings(overrides)
        return ShortcutAction.allCases.map { action in
            let keys: String = bindings.comboFor(action)?.format() ?? SettingsTexts.noKey
            return Row(
                action: action, keys: keys, isCustom: isCustom(action, overrides: overrides),
                conflicts: bindings.conflicts(action))
        }
    }

    /// One key press (Kotlin consumes every non-press event without effect; the caller passes presses only).
    public static func capture(_ combo: KeyCombo) -> Capture {
        if combo.keyCode == AwtKeyCodes.vkEscape {
            return .cancelled
        }
        if KeyCombo.isModifierKey(combo.keyCode) {
            return .ignored
        }
        let text: String = combo.format()
        if combo.isAllowedShortcut {
            return .accepted(text)
        }
        return .rejected(hintKey: SettingsTexts.keyNotAllowed, args: [text])
    }

    /// `keyOverrides.containsKey(action.id())`. The ids are lower-case ASCII, which no other string is canonically
    /// equal to, so Swift `String` keys match exactly as Java's.
    public static func isCustom(_ action: ShortcutAction, overrides: [String: String]) -> Bool {
        overrides[action.id] != nil
    }

    /// An accepted capture: `keyOverrides[action.id()] = text`.
    public static func assign(_ text: String, to action: ShortcutAction, in overrides: inout [String: String]) {
        overrides[action.id] = text
    }

    /// "Výchozí" (`KT:88`, enabled only when `isCustom`): `keyOverrides.remove(action.id())`.
    public static func resetToDefault(_ action: ShortcutAction, in overrides: inout [String: String]) {
        overrides.removeValue(forKey: action.id)
    }

    /// "Žádná" (`KT:89`): `keyOverrides[action.id()] = ""` — the action has no key.
    public static func setNone(_ action: ShortcutAction, in overrides: inout [String: String]) {
        overrides[action.id] = ""
    }

    /// "Vše na výchozí (N1MM)" (`KT:100`): `keyOverrides.clear()`.
    public static func resetAll(_ overrides: inout [String: String]) {
        overrides.removeAll()
    }
}
