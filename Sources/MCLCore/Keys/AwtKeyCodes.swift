/// AWT key codes (`java.awt.event.KeyEvent.VK_*`), on which `KeyCombo` is built.
///
/// Java v1.1.1 builds the table by **reflection** (`J:keys/KeyCombo.java:26-39`): it goes through
/// `KeyEvent.class.getFields()`, takes the static `int` fields with the prefix `VK_` and fills
/// `CODES.put(name, code)` and `NAMES.putIfAbsent(code, name)`. Here the same table is
/// source data (`AwtKeyCodes+Table.swift`, generated from the JDK 21 fixture): 189 names,
/// 188 codes. The only collision is 108 = `SEPARATER` (field 78) and `SEPARATOR` (79) — `name(of:)`
/// returns the first, `SEPARATER`; `code(named:)` accepts both.
///
/// The codes are AWT, not macOS `kVK_*`: converting `NSEvent.keyCode` → VK is UI work.
public enum AwtKeyCodes {

    /// One `VK_*` field: name without the prefix and the value.
    struct Entry: Equatable, Sendable {
        let name: String
        let code: Int32
    }

    public static let vkShift: Int32 = 16
    public static let vkControl: Int32 = 17
    public static let vkAlt: Int32 = 18
    public static let vkMeta: Int32 = 157
    public static let vkAltGraph: Int32 = 65_406
    public static let vkF1: Int32 = 112
    public static let vkF24: Int32 = 61_451
    public static let vkSemicolon: Int32 = 59
    public static let vkQuote: Int32 = 222
    public static let vkBackSlash: Int32 = 92
    public static let vkBackQuote: Int32 = 192

    /// Java `CODES`: name → code. The key with Java equality (by UTF-16 units), so that
    /// `KELVIN SIGN` does not find `K` as Swift canonical `==` would.
    private static let codes: [JavaStringKey: Int32] = {
        var map: [JavaStringKey: Int32] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries {
            map[JavaStringKey(entry.name)] = entry.code
        }
        return map
    }()

    /// Java `NAMES` (`putIfAbsent`): code → first name in `getFields()` order.
    private static let names: [Int32: String] = {
        var map: [Int32: String] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries where map[entry.code] == nil {
            map[entry.code] = entry.name
        }
        return map
    }()

    /// Code of the field `VK_<name>` (exact match by UTF-16), or `nil`.
    public static func code(named name: String) -> Int32? {
        codes[JavaStringKey(name)]
    }

    /// Name of a code without the prefix `VK_` (the first field on a collision), or `nil`.
    public static func name(of code: Int32) -> String? {
        names[code]
    }
}
