import Foundation

/// `MacKeyEvent` → the AWT key event JDK 21 delivers to Compose Desktop (OpenJDK tag `jdk-21+35`):
/// `CPlatformResponder.handleKeyEvent` + `NsCharToJavaVirtualKeyCode` / `NsKeyModifiersToJavaKeyInfo` of
/// `AWTEvent.m`. The facts are pinned by `Fixtures/awt-mac-chars-jdk21.tsv`
/// (maintainer-only probe) and `Fixtures/awt-mac-keycodes-jdk21.tsv`.
///
/// `keyDown`/`keyUp`: the key code comes from the first UTF-16 unit of `charactersIgnoringModifiers`
/// (which on macOS still includes Shift): a dead key (`characters` empty) maps through the dead-key table and
/// is dropped when its character is not there; then a letter maps to `VK_A…VK_Z` or to an extended code
/// `0x01000000 + character`; then a decimal digit to `VK_0…VK_9` (`VK_NUMPAD0…` on the keypad); only then the
/// positional `keyTable` by `kVK`. So on a Czech QWERTZ layout the key typing `y` is `VK_Y` and `ů` (US `;`)
/// has the extended code 0x0100016F.
///
/// Assumption: `tolower` runs in the C locale (an application started from the Finder has no `LANG`), so only
/// A–Z are folded and Shift with a non-ASCII letter gives the code of the upper-case letter. The real fold
/// depends on the JVM launch environment: under a UTF-8 `LANG` the JDK folds non-ASCII letters too.
extension AwtKeyCodes {

    public static let keyLocationUnknown: Int32 = 0
    public static let keyLocationStandard: Int32 = 1
    public static let keyLocationLeft: Int32 = 2
    public static let keyLocationRight: Int32 = 3
    public static let keyLocationNumpad: Int32 = 4

    public static let vkUndefined: Int32 = 0
    public static let vkEnter: Int32 = 10
    public static let vkTab: Int32 = 9
    public static let vkEscape: Int32 = 27
    public static let vkSpace: Int32 = 32
    public static let vkPageUp: Int32 = 33
    public static let vkPageDown: Int32 = 34
    public static let vkUp: Int32 = 38
    public static let vkDown: Int32 = 40
    public static let vkEquals: Int32 = 61
    public static let vkF12: Int32 = 123
    public static let vkCapsLock: Int32 = 20
    public static let vkHelp: Int32 = 156
    static let vkA: Int32 = 65
    static let vk0: Int32 = 48
    static let vkNumpad0: Int32 = 96

    /// `NSEvent.ModifierFlags.capsLock` (`1 << 16`).
    public static let macCapsLockFlag: UInt = 1 << 16
    /// `NSEvent.ModifierFlags.numericPad` (`1 << 21`).
    public static let macNumericPadFlag: UInt = 1 << 21
    /// `NSEvent.ModifierFlags.help` (`1 << 22`).
    public static let macHelpFlag: UInt = 1 << 22

    /// `ExtendedKeyCodes` base of the codes for letters outside A–Z.
    static let extendedLetterBase: Int32 = 0x0100_0000

    /// The AWT event for a macOS key event, or `nil` when JDK 21 delivers none (a dead key whose
    /// character is not in the dead-key table).
    public static func translate(_ event: MacKeyEvent) -> AwtKeyStroke? {
        let modifiers: Int32 = Self.modifiers(fromMacFlags: event.modifierFlags)
        switch event.kind {
        case .flagsChanged:
            return flagsChanged(event, modifiers: modifiers)
        case .keyDown, .keyUp:
            guard let (vk, location) = keyInfo(event) else {
                return nil
            }
            let phase: AwtKeyStroke.Phase = event.kind == .keyDown ? .pressed : .released
            return AwtKeyStroke(vk: vk, location: location, modifiers: modifiers, phase: phase, isRepeat: event.isARepeat)
        }
    }

    /// `NsCharToJavaVirtualKeyCode` with the inputs `CPlatformResponder` gives it.
    static func keyInfo(_ event: MacKeyEvent) -> (Int32, Int32)? {
        // `chars != null && chars.length() == 0`
        let isDeadChar: Bool = event.characters.map { $0.utf16.isEmpty } ?? false
        // A modified key that types nothing and is no dead key (no spacing character) — e.g. Czech Option+M and
        // Option+O — is still a shortcut: it takes its code from the unmodified character like any other key.
        // JDK drops it, which made Alt+M / Alt+O unusable on the Czech layout.
        let shortcutModifiers: UInt = macOptionFlag | macControlFlag | macCommandFlag
        let typesNothing: Bool = isDeadChar && event.deadKeyCharacter == 0
            && event.modifierFlags & shortcutModifiers != 0
        if isDeadChar && !typesNothing {
            guard let vk = deadKeyTable[event.deadKeyCharacter] else {
                // JDK: testChar = deadChar = 0 → `return` without an event.
                return nil
            }
            return (vk, keyLocationUnknown)
        }
        let ch: UInt16 = event.charactersIgnoringModifiers?.utf16.first ?? 0xFFFF
        if let scalar = Unicode.Scalar(ch) {
            if CharacterSet.letters.contains(scalar) {
                let lower: Int32 = asciiLower(ch)
                let offset: Int32 = lower - 97
                if offset >= 0 && offset <= 25 {
                    return (vkA + offset, keyLocationStandard)
                }
                return (vkA + offset + extendedLetterBase + 32, keyLocationStandard)
            }
            if CharacterSet.decimalDigits.contains(scalar) {
                let offset: Int32 = Int32(ch) - 48
                if offset >= 0 && offset <= 9 {
                    let key: UInt16 = event.keyCode
                    let numpad: Bool = event.modifierFlags & macNumericPadFlag != 0 && key > 81 && key < 93
                    if numpad {
                        return (vkNumpad0 + offset, keyLocationNumpad)
                    }
                    return (vk0 + offset, keyLocationStandard)
                }
            }
        }
        let index = Int(event.keyCode)
        guard index < macKeyTable.count else {
            return (vkUndefined, keyLocationUnknown)
        }
        return (macKeyTable[index], macKeyLocation(index))
    }

    /// C `tolower` in the C locale.
    private static func asciiLower(_ ch: UInt16) -> Int32 {
        let value = Int32(ch)
        if value >= 65 && value <= 90 {
            return value + 32
        }
        return value
    }

    /// `keyTable[kVK].javaKeyLocation`.
    static func macKeyLocation(_ index: Int) -> Int32 {
        if macNumpadKeys.contains(index) {
            return keyLocationNumpad
        }
        if macUnknownLocationKeys.contains(index) {
            return keyLocationUnknown
        }
        return keyLocationStandard
    }

    /// `keyTable` entries with `KL_NUMPAD`.
    private static let macNumpadKeys: Set<Int> = [
        0x34, 0x41, 0x43, 0x45, 0x47, 0x4B, 0x4C, 0x4E, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5B, 0x5C, 0x5E, 0x5F,
    ]

    /// `keyTable` entries with `KL_UNKNOWN`; all others are `KL_STANDARD`.
    private static let macUnknownLocationKeys: Set<Int> = [
        0x36, 0x37, 0x38, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x42, 0x44, 0x46, 0x48, 0x49, 0x4A, 0x4D, 0x6C,
        0x6E, 0x70, 0x7F,
    ]

    /// `charToDeadVKTable`: spacing dead-key character → `VK_DEAD_*`.
    static let deadKeyTable: [UInt16: Int32] = [
        0x0060: 128, 0x00B4: 129, 0x0384: 129, 0x005E: 130, 0x007E: 131, 0x02DC: 131, 0x00AF: 132,
        0x02D8: 133, 0x02D9: 134, 0x00A8: 135, 0x02DA: 136, 0x02DD: 137, 0x02C7: 138, 0x00B8: 139,
        0x02DB: 140, 0x037A: 141, 0x309B: 142, 0x309C: 143,
    ]

    /// One row of `nsKeyToJavaModifierTable` (`leftKeyCode`/`rightKeyCode` `0` = none).
    struct ModifierKey: Sendable {
        let mask: UInt
        let left: UInt16
        let right: UInt16
        let vk: Int32
    }

    /// `nsKeyToJavaModifierTable` in source order (Caps Lock, Shift, Control, Command, Option, Help).
    static let modifierKeys: [ModifierKey] = [
        ModifierKey(mask: macCapsLockFlag, left: 0, right: 0, vk: vkCapsLock),
        ModifierKey(mask: macShiftFlag, left: 56, right: 60, vk: vkShift),
        ModifierKey(mask: macControlFlag, left: 59, right: 62, vk: vkControl),
        ModifierKey(mask: macCommandFlag, left: 55, right: 54, vk: vkMeta),
        ModifierKey(mask: macOptionFlag, left: 58, right: 0, vk: vkAlt),
        ModifierKey(mask: macHelpFlag, left: 0, right: 0, vk: vkHelp),
    ]

    /// `NsKeyModifiersToJavaKeyInfo`. The right Option key (kVK 61) has no entry: the loop `continue`s
    /// with `VK_ALT`, `STANDARD` and `KEY_PRESSED` already set, so JDK 21 reports both its press and its
    /// release as a pressed `VK_ALT`.
    static func flagsChanged(_ event: MacKeyEvent, modifiers: Int32) -> AwtKeyStroke {
        let flags: UInt = event.modifierFlags
        let changed: UInt = event.previousModifierFlags ^ flags
        var vk: Int32 = vkUndefined
        var location: Int32 = keyLocationUnknown
        var phase: AwtKeyStroke.Phase = .pressed
        for key in modifierKeys where changed & key.mask != 0 {
            vk = key.vk
            location = keyLocationStandard
            if event.keyCode == key.left {
                location = keyLocationLeft
            } else if event.keyCode == key.right {
                location = keyLocationRight
            } else if key.mask == macOptionFlag {
                continue
            }
            phase = key.mask & flags != 0 ? .pressed : .released
            break
        }
        return AwtKeyStroke(vk: vk, location: location, modifiers: modifiers, phase: phase)
    }
}
