/// Layout-aware key identity for the entry window and the key capture: `AwtKeyCodes.translate` plus the
/// divergence from the JDK 21 behaviour documented as a deliberate divergence from Java v1.1.1 (section 44, "Czech and other
/// layouts"). `translate` itself stays JDK-faithful (it is pinned by the JDK fixtures); this layer is applied on top.
///
/// Why the JDK behaviour was awkward: a key that types a letter is identified by the typed character, any other key
/// by its physical position. On a Czech layout `ů` sits where US has `;` but is a letter (an extended code, so the
/// `;` binding never fired), `§` sits where US has `'` and is not a letter (so the position made it the TU + log key),
/// and `=` sits where US has `-` (so the ESM `=` resolved to `MINUS`). Keypad Enter is `VK_ENTER` at the NUMPAD
/// location, which Compose's key identity (and so `EntryKeyRouter`) does not treat as Enter.
///
/// The rules, in order, for key presses and releases:
/// 1. **Keypad Enter is Return.** `VK_ENTER` at the keypad location becomes the standard-location Enter.
/// 2. **An ASCII punctuation character selects its own key code** (`; ' = \ ` - , . / [ ]`), wherever the layout puts
///    it. On US (and ANSI-like) layouts this is the same as the position; on Czech, `;`, `'` and `=` are reachable
///    by typing them. The keypad keeps its own codes.
/// 3. **A letter outside A-Z on a punctuation position takes the position's US code**: Czech `ů` is the `;` key
///    (N1MM-style, `;` = "Send call + exchange") and `ú` the `[` key. While such a binding is unset the key still
///    types its letter, because the router only consumes what a binding resolves.
/// 4. **A non-ASCII symbol on a punctuation position is no shortcut key** (`VK_UNDEFINED`): `§` no longer logs.
///
/// Digit-row letters (`ě š č ř ž ý á í é`) and every letter A-Z keep the JDK's choice (Y and Z follow the typed
/// character on QWERTZ and QWERTY alike).
extension AwtKeyCodes {

    public static let vkMinus: Int32 = 45
    public static let vkComma: Int32 = 44
    public static let vkPeriod: Int32 = 46
    public static let vkSlash: Int32 = 47
    public static let vkOpenBracket: Int32 = 91
    public static let vkCloseBracket: Int32 = 93

    /// macOS `kVK_Return` and `kVK_ANSI_KeypadEnter`: both confirm like Return.
    public static let macReturnKeyCode: UInt16 = 0x24
    public static let macKeypadEnterKeyCode: UInt16 = 0x4C

    /// Is the macOS key code Return or keypad Enter (the keys that log, submit and confirm)?
    public static func isMacEnterKey(_ keyCode: UInt16) -> Bool {
        keyCode == macReturnKeyCode || keyCode == macKeypadEnterKeyCode
    }

    /// ASCII punctuation → its AWT key code.
    private static let punctuationCodes: [UInt16: Int32] = [
        0x3B: vkSemicolon, 0x27: vkQuote, 0x3D: vkEquals, 0x5C: vkBackSlash, 0x60: vkBackQuote,
        0x2D: vkMinus, 0x2C: vkComma, 0x2E: vkPeriod, 0x2F: vkSlash, 0x5B: vkOpenBracket, 0x5D: vkCloseBracket,
    ]

    private static let punctuationVks: Set<Int32> = Set(punctuationCodes.values)

    /// `translate` with the layout rules above; what the entry window and the key capture use.
    public static func translateForLayout(_ event: MacKeyEvent) -> AwtKeyStroke? {
        guard var stroke = translate(event) else {
            return nil
        }
        guard event.kind != .flagsChanged else {
            return stroke
        }
        if stroke.vk == vkEnter && stroke.location == keyLocationNumpad {
            stroke.location = keyLocationStandard
            return stroke
        }
        guard stroke.location != keyLocationNumpad, event.characters?.isEmpty != true,
              let ch = event.charactersIgnoringModifiers?.utf16.first else {
            return stroke
        }
        if let code = punctuationCodes[ch] {
            stroke.vk = code
            stroke.location = keyLocationStandard
            return stroke
        }
        let index = Int(event.keyCode)
        guard index < macKeyTable.count, punctuationVks.contains(macKeyTable[index]) else {
            return stroke
        }
        let positional: Int32 = macKeyTable[index]
        if stroke.vk >= extendedLetterBase {
            stroke.vk = positional
            stroke.location = keyLocationStandard
        } else if stroke.vk == positional && ch >= 0x80 && !(0xF700...0xF8FF).contains(ch) {
            stroke.vk = vkUndefined
        }
        return stroke
    }
}
