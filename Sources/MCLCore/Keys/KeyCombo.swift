/// Key combination for remapping shortcuts (N1MM Key Mapper): modifiers + a key
/// as an **AWT code** (`KeyEvent.VK_*`, see `AwtKeyCodes`). Text form
/// `Ctrl+Alt+Shift+Cmd+PAGE_UP`; Alt is Option on the Mac. Mirrors the Java
/// `cz.ok1xoe.maccontestlogger.keys.KeyCombo` (a record — equality and hash by components).
public struct KeyCombo: Hashable, Sendable {
    public let ctrl: Bool
    public let alt: Bool
    public let shift: Bool
    public let meta: Bool
    public let keyCode: Int32

    public init(ctrl: Bool, alt: Bool, shift: Bool, meta: Bool, keyCode: Int32) {
        self.ctrl = ctrl
        self.alt = alt
        self.shift = shift
        self.meta = meta
        self.keyCode = keyCode
    }

    /// Java `ALIASES` (`J:keys/KeyCombo.java:20-24`), keys with Java equality: `;` must not
    /// find the canonically equal GREEK QUESTION MARK U+037E.
    private static let aliases: [JavaStringKey: String] = {
        let pairs: [(String, String)] = [
            ("PGUP", "PAGE_UP"), ("PGDN", "PAGE_DOWN"), ("PGDOWN", "PAGE_DOWN"),
            ("DEL", "DELETE"), ("ESC", "ESCAPE"), ("INS", "INSERT"),
            ("RETURN", "ENTER"), (";", "SEMICOLON"), ("'", "QUOTE"),
            ("APOSTROPHE", "QUOTE"), ("=", "EQUALS"), ("-", "MINUS"),
        ]
        var map: [JavaStringKey: String] = [:]
        for (alias, name) in pairs {
            map[JavaStringKey(alias)] = name
        }
        return map
    }()

    private enum Modifier { case ctrl, alt, shift, meta }

    /// Java `switch (p)` over modifiers (equality by UTF-16).
    private static let modifiers: [JavaStringKey: Modifier] = {
        let pairs: [(String, Modifier)] = [
            ("CTRL", .ctrl), ("CONTROL", .ctrl),
            ("ALT", .alt), ("OPTION", .alt), ("OPT", .alt), ("\u{2325}", .alt),
            ("SHIFT", .shift), ("\u{21E7}", .shift),
            ("CMD", .meta), ("COMMAND", .meta), ("META", .meta), ("\u{2318}", .meta),
        ]
        var map: [JavaStringKey: Modifier] = [:]
        for (text, modifier) in pairs {
            map[JavaStringKey(text)] = modifier
        }
        return map
    }()

    /// `\s*\+\s*(?=.)` — the Java dialect: `\s` ASCII only, `.` does not match a line terminator.
    private static let separator: JavaRegex = {
        do {
            return try JavaRegex("\\s*\\+\\s*(?=.)")
        } catch {
            preconditionFailure("pevný vzor oddělovače kláves musí jít zkompilovat: \(error)")
        }
    }()

    /// Parses "Ctrl+Alt+S", "Alt+F7", "Cmd+Down", "PgUp"…; `nil` if it does not know the key
    /// (Java `Optional.empty()`). The last non-modifier wins (`a+b` → `B`).
    public static func parse(_ text: String?) -> KeyCombo? {
        guard let text, !JavaText.isBlank(text) else {
            return nil
        }
        var ctrl = false
        var alt = false
        var shift = false
        var meta = false
        var key: String?
        let parts: [String] = JavaText.split(JavaText.trim(text), regex: separator, limit: 0)
        for part in parts {
            let p: String = JavaText.toUpperCase(JavaText.trim(part))
            switch modifiers[JavaStringKey(p)] {
            case .ctrl?: ctrl = true
            case .alt?: alt = true
            case .shift?: shift = true
            case .meta?: meta = true
            case nil: key = p
            }
        }
        guard let key else {
            return nil
        }
        let name: String = aliases[JavaStringKey(key)] ?? key
        guard let code = AwtKeyCodes.code(named: name) else {
            return nil
        }
        return KeyCombo(ctrl: ctrl, alt: alt, shift: shift, meta: meta, keyCode: code)
    }

    /// Text form for saving and display; an unknown code as `0x` + Java
    /// `Integer.toHexString` (negative as 32-bit two's complement: `0xfffffffb`).
    public func format() -> String {
        var out = ""
        if ctrl { out += "Ctrl+" }
        if alt { out += "Alt+" }
        if shift { out += "Shift+" }
        if meta { out += "Cmd+" }
        if let name = AwtKeyCodes.name(of: keyCode) {
            out += name
        } else {
            let hex: String = String(UInt32(bitPattern: keyCode), radix: 16)
            out += "0x\(hex)"
        }
        return out
    }

    /// Is it only a modifier (Shift, Ctrl…) without a key of its own?
    public static func isModifierKey(_ keyCode: Int32) -> Bool {
        keyCode == AwtKeyCodes.vkShift || keyCode == AwtKeyCodes.vkControl || keyCode == AwtKeyCodes.vkAlt
            || keyCode == AwtKeyCodes.vkMeta || keyCode == AwtKeyCodes.vkAltGraph
    }

    /// May this combination be a shortcut? Without Ctrl/Alt/Cmd it would override typing into fields —
    /// exceptions are F-keys, ";", "'", "\\" and "`" (N1MM uses them without modifiers).
    public var isAllowedShortcut: Bool {
        if KeyCombo.isModifierKey(keyCode) {
            return false
        }
        if ctrl || alt || meta {
            return true
        }
        let fKey: Bool = keyCode >= AwtKeyCodes.vkF1 && keyCode <= AwtKeyCodes.vkF24
        if fKey {
            return true
        }
        return keyCode == AwtKeyCodes.vkSemicolon || keyCode == AwtKeyCodes.vkQuote
            || keyCode == AwtKeyCodes.vkBackSlash || keyCode == AwtKeyCodes.vkBackQuote
    }
}
