/// A macOS key event as plain values (the core has no AppKit): what the entry window's key monitor
/// copies out of an `NSEvent` of type `.keyDown`, `.keyUp` or `.flagsChanged`.
public struct MacKeyEvent: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public var kind: Kind
    /// `NSEvent.keyCode` (Carbon `kVK_*`).
    public var keyCode: UInt16
    /// `NSEvent.characters`; an empty (not `nil`) string marks a dead key, as in JDK 21.
    public var characters: String?
    /// `NSEvent.charactersIgnoringModifiers`; its first UTF-16 unit selects the AWT key code.
    public var charactersIgnoringModifiers: String?
    /// Raw `NSEvent.modifierFlags.rawValue`.
    public var modifierFlags: UInt
    /// `NSEvent.isARepeat` (only meaningful for `.keyDown`).
    public var isARepeat: Bool
    /// For `.flagsChanged`: the `modifierFlags` of the previous `.flagsChanged` event the application saw
    /// (`0` at start). JDK 21 keeps the same value in a static (`sPreviousNSFlags`) and derives the changed
    /// modifier from `previous ^ current`.
    public var previousModifierFlags: UInt
    /// For a dead key: the spacing character the keyboard layout produces for it (JDK `NsGetDeadKeyChar`:
    /// `UCKeyTranslate` of the key with the current modifiers, then Space), `0` if there is none. AppKit
    /// side computes it only when `characters` is empty.
    public var deadKeyCharacter: UInt16

    public init(
        kind: Kind,
        keyCode: UInt16,
        characters: String? = nil,
        charactersIgnoringModifiers: String? = nil,
        modifierFlags: UInt = 0,
        isARepeat: Bool = false,
        previousModifierFlags: UInt = 0,
        deadKeyCharacter: UInt16 = 0
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifierFlags = modifierFlags
        self.isARepeat = isARepeat
        self.previousModifierFlags = previousModifierFlags
        self.deadKeyCharacter = deadKeyCharacter
    }
}

/// The AWT `KEY_PRESSED`/`KEY_RELEASED` event JDK 21 would deliver for a `MacKeyEvent`: `KeyEvent.keyCode`,
/// `keyLocation` and the extended modifiers (`getModifiersEx()`).
public struct AwtKeyStroke: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case pressed
        case released
    }

    /// `KeyEvent.VK_*` (or an extended code `0x01000000 + Unicode` for letters outside A–Z).
    public var vk: Int32
    /// `KeyEvent.KEY_LOCATION_*`.
    public var location: Int32
    /// `InputEvent.*_DOWN_MASK` bits.
    public var modifiers: Int32
    public var phase: Phase
    /// `NSEvent.isARepeat` of the source event (AWT repeats `KEY_PRESSED` and sends one `KEY_RELEASED`).
    public var isRepeat: Bool

    public init(vk: Int32, location: Int32, modifiers: Int32, phase: Phase, isRepeat: Bool = false) {
        self.vk = vk
        self.location = location
        self.modifiers = modifiers
        self.phase = phase
        self.isRepeat = isRepeat
    }

    public var isShiftDown: Bool { modifiers & AwtKeyCodes.shiftDownMask != 0 }
    public var isControlDown: Bool { modifiers & AwtKeyCodes.ctrlDownMask != 0 }
    public var isAltDown: Bool { modifiers & AwtKeyCodes.altDownMask != 0 }
    public var isMetaDown: Bool { modifiers & AwtKeyCodes.metaDownMask != 0 }

    /// Compose Desktop's key location (`keyLocationForCompose`): `UNKNOWN` becomes `STANDARD`.
    public var composeLocation: Int32 {
        location == AwtKeyCodes.keyLocationUnknown ? AwtKeyCodes.keyLocationStandard : location
    }

    /// Compose `Key` equality: the same key code and the same (Compose) location.
    public func isKey(_ vk: Int32, location: Int32 = AwtKeyCodes.keyLocationStandard) -> Bool {
        self.vk == vk && composeLocation == location
    }
}
