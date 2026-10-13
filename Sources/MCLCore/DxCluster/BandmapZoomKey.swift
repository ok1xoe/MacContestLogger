/// The Bandmap window's zoom keys (N1MM: keypad `+` / `-` zoom the band map). A laptop has no keypad, so Cmd+=
/// (also Cmd++) and Cmd+- do the same. Shift+keypad, N1MM's second band map, has no counterpart: MacContestLogger
/// has one band map, of the active rig.
public enum BandmapZoomKey {

    /// `kVK_ANSI_KeypadPlus` / `kVK_ANSI_KeypadMinus`.
    static let keypadPlus: UInt16 = 69
    static let keypadMinus: UInt16 = 78
    /// `kVK_ANSI_Equal` / `kVK_ANSI_Minus` (the physical keys, whatever the layout prints on them).
    static let equalKey: UInt16 = 24
    static let minusKey: UInt16 = 27
    /// `NSEvent.ModifierFlags` `.shift`, `.control`, `.option`, `.command`.
    static let shift: UInt = 1 << 17
    static let control: UInt = 1 << 18
    static let option: UInt = 1 << 19
    static let command: UInt = 1 << 20

    /// `+1` = zoom in, `-1` = zoom out, `nil` = not a zoom key. Both the press and the release of a zoom key decode
    /// (the caller consumes both and acts on the press only).
    public static func decode(_ event: MacKeyEvent) -> Int? {
        guard event.kind != .flagsChanged else { return nil }
        let flags: UInt = event.modifierFlags
        if flags & (control | option) != 0 {
            return nil
        }
        if event.keyCode == keypadPlus {
            return 1
        }
        if event.keyCode == keypadMinus {
            return -1
        }
        guard flags & command != 0 else { return nil }
        let typed: String = event.charactersIgnoringModifiers ?? ""
        if event.keyCode == equalKey || typed == "=" || typed == "+" {
            return 1
        }
        if event.keyCode == minusKey || typed == "-" {
            return -1
        }
        return nil
    }
}
