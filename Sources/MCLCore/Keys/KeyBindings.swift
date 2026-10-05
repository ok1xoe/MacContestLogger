/// Current key assignment: default action keys + user remapping
/// (N1MM Key Mapper). A remapping is stored as `action id → "Ctrl+Alt+S"`
/// (`AppConfig.keyBindings`); an empty value = action without a key, an invalid or
/// disallowed one = the default key. Mirrors the Java `cz.ok1xoe.maccontestlogger.keys.KeyBindings`.
///
/// Java also carries a `null` value (= no key); `AppConfig.keyBindings` is `[String: String]`,
/// so it cannot occur here — an empty string has the same meaning.
public struct KeyBindings: Sendable {

    /// Java `EnumMap` action → keys (iteration order = `ShortcutAction.allCases`).
    private let byAction: [ShortcutAction: KeyCombo]
    private let byCombo: [KeyCombo: ShortcutAction]

    /// - Parameter overrides: user remapping (action id → keys), may be `nil`.
    ///   The id is looked up with Java equality (by UTF-16 units).
    public init(_ overrides: [String: String]?) {
        var remap: [JavaStringKey: String] = [:]
        for (id, value) in overrides ?? [:] {
            remap[JavaStringKey(id)] = value
        }
        var actions: [ShortcutAction: KeyCombo] = [:]
        var overridden: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            var combo: KeyCombo? = action.defaultCombo()
            if let value = remap[JavaStringKey(action.id)] {
                overridden.insert(action)
                combo = KeyBindings.overrideCombo(value, fallback: combo)
            }
            if let combo {
                actions[action] = combo
            }
        }
        // On a collision the action with a user remapping wins (inserted later it overwrites the default);
        // among themselves the later action in Java order.
        var combos: [KeyCombo: ShortcutAction] = [:]
        for action in ShortcutAction.allCases where !overridden.contains(action) {
            if let combo = actions[action] { combos[combo] = action }
        }
        for action in ShortcutAction.allCases where overridden.contains(action) {
            if let combo = actions[action] { combos[combo] = action }
        }
        byAction = actions
        byCombo = combos
    }

    /// `v.isBlank() ? null : parse(v).filter(isAllowedShortcut).orElse(default)`.
    private static func overrideCombo(_ value: String, fallback: KeyCombo?) -> KeyCombo? {
        if JavaText.isBlank(value) {
            return nil
        }
        guard let parsed = KeyCombo.parse(value), parsed.isAllowedShortcut else {
            return fallback
        }
        return parsed
    }

    /// Action for a keypress, or `nil` (the key is handled normally).
    public func resolve(_ combo: KeyCombo) -> ShortcutAction? {
        byCombo[combo]
    }

    /// Keys of an action; `nil` = the action has no key.
    public func comboFor(_ action: ShortcutAction) -> KeyCombo? {
        byAction[action]
    }

    /// Other actions with the same keys (a collision to warn about in Settings), in Java action order.
    public func conflicts(_ action: ShortcutAction) -> [ShortcutAction] {
        guard let combo = byAction[action] else {
            return []
        }
        return ShortcutAction.allCases.filter { other in
            other != action && byAction[other] == combo
        }
    }
}
