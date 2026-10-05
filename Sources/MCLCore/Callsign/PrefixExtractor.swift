import Foundation

/// Derivation of the WPX prefix from a callsign (CQ WPX rules). Prefix = the leading part up to the
/// **last** digit; without a digit `0` is appended. Portable indicators via `/`
/// are taken into account: a single digit = area change, another shorter part = prefix override
/// (append `0` if it has no digit), suffixes (`/P`, `/MM`…) are ignored.
///
/// Examples: `OK1XOE→OK1`, `W3ABC→W3`, `2E0ABC→2E0`, `K1ABC/7→K7`,
/// `DL/W1ABC→DL0`, `W1/OK1XOE→W1`, `G3ABC/P→G3`, `RAEM→RA0`.
///
/// Port of Java `callsign/PrefixExtractor.java`. In CQ WPX the prefix is the
/// **multiplier**, so a deviation directly changes the final score — which is why Java
/// semantics are kept here down to the last detail:
///
/// - emptiness is tested by Java `isBlank()` and the edges are dropped by Java
///   `trim()` (`JavaText`) — these are **two different** whitespace sets and Swift
///   `.whitespacesAndNewlines` matches neither. The no-break space
///   U+00A0 is non-empty for `isBlank()` and `trim()` does not drop it, so
///   `wpx("\u{00A0}OK1XOE")` is `"\u{00A0}OK1"`, not `"OK1"` (measured in Java);
/// - the string is indexed and sliced by **UTF-16 units** like Java
///   `charAt`/`substring`, not by graphemes (see `JavaChar`);
/// - a "digit" is Java `Character.isDigit(char)`, i.e. the whole category `Nd`,
///   not just ASCII (`wpx("OK\u{0661}XOE")` = `"OK\u{0661}"`).
///
/// KG4 / Guantánamo is **not** here and must not be: DXCC special cases are handled by
/// `DxccSpecialCases`. The WPX prefix of `KG4XX` comes out normally as `KG4`.
public enum PrefixExtractor {

    /// Suffixes that are completely ignored when looking for the prefix.
    ///
    /// In Java it is a private `Set<String>` and `DxccResolver.SUFFIXES` has a value-wise
    /// identical set too — the original does **not** unify them, they are two
    /// independent copies in two packages. The port leaves it that way so that
    /// any future drift of one does not carry over to the other.
    ///
    /// Compared by UTF-16 units, because Java `String.equals` is
    /// exact, whereas Swift string equality is canonical.
    private static let suffixes: Set<[UInt16]> = Set(
        ["P", "M", "MM", "AM", "QRP", "A", "R", "LH", "B", "J"].map { Array($0.utf16) }
    )

    private static let slash: UInt16 = 0x2F
    private static let zero: UInt16 = 0x30

    /// WPX prefix of a callsign. `nil` or blank input gives `""` (never `nil`).
    public static func wpx(_ callsign: String?) -> String {
        guard let callsign, !JavaText.isBlank(callsign) else {
            return ""
        }
        let up = Array(JavaText.trim(callsign).uppercased().utf16)
        guard up.contains(slash) else {
            return JavaChar.string(prefixOf(up))
        }

        var singleDigit: UInt16?
        var parts: [[UInt16]] = []
        for token in split(up) {
            if token.isEmpty || suffixes.contains(token) {
                continue
            }
            // Java `t.matches("\\d")` without UNICODE_CHARACTER_CLASS = exactly
            // one **ASCII** digit. The Arabic digit `\u{0661}` is therefore not an area
            // indicator, even though `Character.isDigit` considers it a digit.
            if token.count == 1, token[0] >= zero, token[0] <= 0x39 {
                singleDigit = token[0]
                continue
            }
            parts.append(token)
        }

        if let singleDigit, !parts.isEmpty {
            let main = longest(parts)
            return JavaChar.string(replaceLastDigit(prefixOf(main), singleDigit))
        }
        if parts.isEmpty {
            return JavaChar.string(prefixOf(up.filter { $0 != slash }))
        }
        if parts.count == 1 {
            return JavaChar.string(prefixOf(parts[0]))
        }
        return JavaChar.string(normalizePortable(shortest(parts)))
    }

    /// Java `up.split("/")`. Java drops trailing empty elements, here they are
    /// kept — it changes nothing in the result, because the caller skips empty tokens
    /// anyway.
    private static func split(_ units: [UInt16]) -> [[UInt16]] {
        var out: [[UInt16]] = []
        var current: [UInt16] = []
        for unit in units {
            if unit == slash {
                out.append(current)
                current = []
            } else {
                current.append(unit)
            }
        }
        out.append(current)
        return out
    }

    /// The leading part up to (and including) the **last** digit. Without a digit: the first two
    /// units (or the whole input if shorter) plus `"0"` — hence `RAEM → RA0`.
    private static func prefixOf(_ call: [UInt16]) -> [UInt16] {
        var lastDigit = -1
        for index in call.indices where JavaChar.isDigit(call[index]) {
            lastDigit = index
        }
        if lastDigit < 0 {
            let letters = call.count >= 2 ? Array(call[0..<2]) : call
            return letters + [zero]
        }
        return Array(call[0...lastDigit])
    }

    /// Portable prefix override: if the part has a digit, the prefix is taken; if not,
    /// `0` is appended (a WPX prefix must have a digit).
    private static func normalizePortable(_ part: [UInt16]) -> [UInt16] {
        part.contains(where: JavaChar.isDigit) ? prefixOf(part) : part + [zero]
    }

    /// Replaces the **last** digit in the already computed prefix with a single-digit
    /// area indicator. If the prefix has no digit, the indicator is appended at the end.
    private static func replaceLastDigit(_ prefix: [UInt16], _ digit: UInt16) -> [UInt16] {
        var out = prefix
        var index = out.count - 1
        while index >= 0 {
            if JavaChar.isDigit(out[index]) {
                out[index] = digit
                return out
            }
            index -= 1
        }
        return prefix + [digit]
    }

    /// The longest part; on equal length the first wins (strict `>` as in Java).
    /// The length is in UTF-16 units, like Java `String.length()`.
    private static func longest(_ parts: [[UInt16]]) -> [UInt16] {
        var result = parts[0]
        for part in parts where part.count > result.count {
            result = part
        }
        return result
    }

    /// The shortest part; on equal length the first wins (strict `<` as in Java).
    private static func shortest(_ parts: [[UInt16]]) -> [UInt16] {
        var result = parts[0]
        for part in parts where part.count < result.count {
            result = part
        }
        return result
    }
}
