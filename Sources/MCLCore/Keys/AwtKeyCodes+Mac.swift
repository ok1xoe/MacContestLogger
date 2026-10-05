/// macOS virtual key codes (`NSEvent.keyCode`, Carbon `kVK_*`) → AWT `KeyEvent.VK_*` and
/// `NSEvent.ModifierFlags` → AWT extended modifier masks (`InputEvent.*_DOWN_MASK`).
///
/// Compose Desktop's `nativeKeyCode` is the AWT `KeyEvent.keyCode` that JDK 21 derives from the
/// native table `keyTable` in `AWTEvent.m` (OpenJDK tag `jdk-21+35`). The table below holds the same
/// numeric mapping (128 entries indexed by `kVK`, `0` = `VK_UNDEFINED`); `AwtKeyCodesMacTests` checks it
/// against `Fixtures/awt-mac-keycodes-jdk21.tsv` (maintainer-only probe).
///
/// The table is the last step of the JDK's key-code choice: keys that type a letter or a decimal digit are
/// mapped by the typed character first (`NsCharToJavaVirtualKeyCode`; non-Latin letters get extended codes),
/// and modifier keys arrive as `flagsChanged` (`NsKeyModifiersToJavaKeyInfo`, kVK 56/60, 59/62, 55/54, 58 with
/// a left/right location). The whole choice is `AwtKeyCodes.translate` (`AwtKeyCodes+Translate.swift`);
/// `fromMac` alone is only the positional part (it returns `nil` for the right Command 0x36, for example).
/// The core has no AppKit, so it works with raw numbers only.
extension AwtKeyCodes {

    /// AWT `InputEvent.SHIFT_DOWN_MASK` (JDK 21, measured: 64).
    public static let shiftDownMask: Int32 = 64
    /// AWT `InputEvent.CTRL_DOWN_MASK` (128).
    public static let ctrlDownMask: Int32 = 128
    /// AWT `InputEvent.META_DOWN_MASK` (256).
    public static let metaDownMask: Int32 = 256
    /// AWT `InputEvent.ALT_DOWN_MASK` (512).
    public static let altDownMask: Int32 = 512

    /// `NSEvent.ModifierFlags.shift.rawValue` (`1 << 17`).
    public static let macShiftFlag: UInt = 1 << 17
    /// `NSEvent.ModifierFlags.control.rawValue` (`1 << 18`).
    public static let macControlFlag: UInt = 1 << 18
    /// `NSEvent.ModifierFlags.option.rawValue` (`1 << 19`).
    public static let macOptionFlag: UInt = 1 << 19
    /// `NSEvent.ModifierFlags.command.rawValue` (`1 << 20`).
    public static let macCommandFlag: UInt = 1 << 20

    /// AWT key code for a macOS `kVK` value; `nil` for `VK_UNDEFINED` and for codes outside the table (≥ 128).
    public static func fromMac(keyCode: UInt16) -> Int32? {
        let index = Int(keyCode)
        guard index < macKeyTable.count else {
            return nil
        }
        let code: Int32 = macKeyTable[index]
        return code == 0 ? nil : code
    }

    /// AWT extended modifiers from raw `NSEvent.ModifierFlags` bits: Control → Ctrl, Option → Alt,
    /// Shift → Shift, Command → Meta. Other bits (Caps Lock, Fn, numeric pad…) are ignored.
    public static func modifiers(fromMacFlags flags: UInt) -> Int32 {
        var mask: Int32 = 0
        if flags & macShiftFlag != 0 { mask |= shiftDownMask }
        if flags & macControlFlag != 0 { mask |= ctrlDownMask }
        if flags & macCommandFlag != 0 { mask |= metaDownMask }
        if flags & macOptionFlag != 0 { mask |= altDownMask }
        return mask
    }

    /// `keyTable[kVK].javaKeyCode` of JDK 21 `AWTEvent.m`, index = `kVK`.
    static let macKeyTable: [Int32] = [
        65, // 0x00 A
        83, // 0x01 S
        68, // 0x02 D
        70, // 0x03 F
        72, // 0x04 H
        71, // 0x05 G
        90, // 0x06 Z
        88, // 0x07 X
        67, // 0x08 C
        86, // 0x09 V
        192, // 0x0A BACK_QUOTE
        66, // 0x0B B
        81, // 0x0C Q
        87, // 0x0D W
        69, // 0x0E E
        82, // 0x0F R
        89, // 0x10 Y
        84, // 0x11 T
        49, // 0x12 1
        50, // 0x13 2
        51, // 0x14 3
        52, // 0x15 4
        54, // 0x16 6
        53, // 0x17 5
        61, // 0x18 EQUALS
        57, // 0x19 9
        55, // 0x1A 7
        45, // 0x1B MINUS
        56, // 0x1C 8
        48, // 0x1D 0
        93, // 0x1E CLOSE_BRACKET
        79, // 0x1F O
        85, // 0x20 U
        91, // 0x21 OPEN_BRACKET
        73, // 0x22 I
        80, // 0x23 P
        10, // 0x24 ENTER
        76, // 0x25 L
        74, // 0x26 J
        222, // 0x27 QUOTE
        75, // 0x28 K
        59, // 0x29 SEMICOLON
        92, // 0x2A BACK_SLASH
        44, // 0x2B COMMA
        47, // 0x2C SLASH
        78, // 0x2D N
        77, // 0x2E M
        46, // 0x2F PERIOD
        9, // 0x30 TAB
        32, // 0x31 SPACE
        192, // 0x32 BACK_QUOTE
        8, // 0x33 BACK_SPACE
        10, // 0x34 ENTER
        27, // 0x35 ESCAPE
        0, // 0x36 UNDEFINED
        157, // 0x37 META
        16, // 0x38 SHIFT
        20, // 0x39 CAPS_LOCK
        18, // 0x3A ALT
        17, // 0x3B CONTROL
        0, // 0x3C UNDEFINED
        65406, // 0x3D ALT_GRAPH
        0, // 0x3E UNDEFINED
        0, // 0x3F UNDEFINED
        61444, // 0x40 F17
        110, // 0x41 DECIMAL
        0, // 0x42 UNDEFINED
        106, // 0x43 MULTIPLY
        0, // 0x44 UNDEFINED
        107, // 0x45 ADD
        0, // 0x46 UNDEFINED
        12, // 0x47 CLEAR
        0, // 0x48 UNDEFINED
        0, // 0x49 UNDEFINED
        0, // 0x4A UNDEFINED
        111, // 0x4B DIVIDE
        10, // 0x4C ENTER
        0, // 0x4D UNDEFINED
        109, // 0x4E SUBTRACT
        61445, // 0x4F F18
        61446, // 0x50 F19
        61, // 0x51 EQUALS
        96, // 0x52 NUMPAD0
        97, // 0x53 NUMPAD1
        98, // 0x54 NUMPAD2
        99, // 0x55 NUMPAD3
        100, // 0x56 NUMPAD4
        101, // 0x57 NUMPAD5
        102, // 0x58 NUMPAD6
        103, // 0x59 NUMPAD7
        61447, // 0x5A F20
        104, // 0x5B NUMPAD8
        105, // 0x5C NUMPAD9
        92, // 0x5D BACK_SLASH
        523, // 0x5E UNDERSCORE
        44, // 0x5F COMMA
        116, // 0x60 F5
        117, // 0x61 F6
        118, // 0x62 F7
        114, // 0x63 F3
        119, // 0x64 F8
        120, // 0x65 F9
        240, // 0x66 ALPHANUMERIC
        122, // 0x67 F11
        241, // 0x68 KATAKANA
        61440, // 0x69 F13
        61443, // 0x6A F16
        61441, // 0x6B F14
        0, // 0x6C UNDEFINED
        121, // 0x6D F10
        0, // 0x6E UNDEFINED
        123, // 0x6F F12
        0, // 0x70 UNDEFINED
        61442, // 0x71 F15
        156, // 0x72 HELP
        36, // 0x73 HOME
        33, // 0x74 PAGE_UP
        127, // 0x75 DELETE
        115, // 0x76 F4
        35, // 0x77 END
        113, // 0x78 F2
        34, // 0x79 PAGE_DOWN
        112, // 0x7A F1
        37, // 0x7B LEFT
        39, // 0x7C RIGHT
        40, // 0x7D DOWN
        38, // 0x7E UP
        0, // 0x7F UNDEFINED
    ]
}
