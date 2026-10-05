import Foundation

// MARK: - String.CASE_INSENSITIVE_ORDER

extension JavaText {

    /// Equivalent of Java's `String.CASE_INSENSITIVE_ORDER.compare(left, right)` (JDK 21) —
    /// `RigModelFilter` uses it to sort manufacturers and models and to merge manufacturers in a `TreeSet`.
    /// Returns the same number as Java (the difference of keys, or the difference of lengths in UTF-16 units).
    ///
    /// Java compares by UTF-16 units: equal ones are skipped, otherwise it compares `Character.toUpperCase`
    /// of both and if those differ too, returns the difference of `Character.toLowerCase` of the uppercased ones (`ß` < `É`, because
    /// `ß` < `é`). Neither Swift's `caseInsensitiveCompare` nor `localizedStandardCompare` does that.
    ///
    /// Two paths depending on the compact representation of the Java string (`StringLatin1` / `StringUTF16`):
    /// if **both** strings contain a unit above U+00FF, surrogate pairs are combined into
    /// a code point on mismatch (`compareToCIImpl`: `𐐀` = `𐐨`, `𐐀` > U+FFFF); if at least one is Latin-1, it goes
    /// purely by units (`𐐀` − `é` = 0xD801 − 0xE9). The sign comes out the same in both paths,
    /// the value does not. A lone half of a pair cannot be carried by Swift's `String`, so it cannot be passed here.
    static func caseInsensitiveOrder(_ left: String, _ right: String) -> Int {
        let a: [UInt16] = Array(left.utf16)
        let b: [UInt16] = Array(right.utf16)
        let wide = a.contains { $0 > 0xFF } && b.contains { $0 > 0xFF }
        if !wide {
            for k in 0..<min(a.count, b.count) where a[k] != b[k] {
                let diff = compareCodePointCI(UInt32(a[k]), UInt32(b[k]))
                if diff != 0 { return diff }
            }
            return a.count - b.count
        }
        var k1 = 0
        var k2 = 0
        while k1 < a.count && k2 < b.count {
            var cp1 = UInt32(a[k1])
            var cp2 = UInt32(b[k2])
            if cp1 != cp2 && compareCodePointCI(cp1, cp2) != 0 {
                // Surrogate pair: the high half takes the following one (and advances the index), the low one the preceding one.
                let (first, skip1) = codePointIncluding(a, k1)
                let (second, skip2) = codePointIncluding(b, k2)
                cp1 = first
                cp2 = second
                if skip1 { k1 += 1 }
                if skip2 { k2 += 1 }
                let diff = compareCodePointCI(cp1, cp2)
                if diff != 0 { return diff }
            }
            k1 += 1
            k2 += 1
        }
        return a.count - b.count
    }

    /// The key by which `caseInsensitiveOrder` compares a single character:
    /// `Character.toLowerCase(Character.toUpperCase(cp))`. Two characters are equal exactly when
    /// they have the same key; otherwise the difference of keys decides. For half of a surrogate pair it is the half itself.
    static func caseInsensitiveKey(_ codePoint: UInt32) -> UInt32 {
        lowerCodePointValue(upperCodePointValue(codePoint))
    }

    /// `StringUTF16.compareCodePointCI`.
    private static func compareCodePointCI(_ cp1: UInt32, _ cp2: UInt32) -> Int {
        let upper1 = upperCodePointValue(cp1)
        let upper2 = upperCodePointValue(cp2)
        if upper1 == upper2 { return 0 }
        return Int(lowerCodePointValue(upper1)) - Int(lowerCodePointValue(upper2))
    }

    /// `StringUTF16.codePointIncluding`: the code point from the pair to which the unit at `index` belongs;
    /// `true` = it was the high half and the low one is to be skipped.
    private static func codePointIncluding(_ units: [UInt16], _ index: Int) -> (UInt32, Bool) {
        let unit = units[index]
        if UTF16.isTrailSurrogate(unit) {
            if index > 0 && UTF16.isLeadSurrogate(units[index - 1]) {
                return (combine(units[index - 1], unit), false)
            }
        } else if UTF16.isLeadSurrogate(unit) {
            if index + 1 < units.count && UTF16.isTrailSurrogate(units[index + 1]) {
                return (combine(unit, units[index + 1]), true)
            }
        }
        return (UInt32(unit), false)
    }

    private static func combine(_ high: UInt16, _ low: UInt16) -> UInt32 {
        0x10000 + ((UInt32(high) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
    }

    /// Java `Character.toUpperCase(int)`: simple (1:1) mapping per Unicode 15.0 (JDK 21).
    /// A character or mapping target newer than 15.0 is unknown to Java → unchanged.
    static func upperCodePointValue(_ codePoint: UInt32) -> UInt32 {
        if codePoint < 0x80 {
            return (codePoint >= 0x61 && codePoint <= 0x7A) ? codePoint - 0x20 : codePoint
        }
        if codePoint <= 0xFFFF, let override = JavaChar.simpleUpperOverrides[UInt16(codePoint)] {
            return UInt32(override)
        }
        guard let scalar = Unicode.Scalar(codePoint), isKnownToJava(scalar) else { return codePoint }
        let mapping = scalar.properties.uppercaseMapping.unicodeScalars
        guard mapping.count == 1, let first = mapping.first, isKnownToJava(first) else { return codePoint }
        return first.value
    }

    /// Java `Character.toLowerCase(int)` (U+0130 → `i`), Unicode 15.0.
    static func lowerCodePointValue(_ codePoint: UInt32) -> UInt32 {
        if codePoint < 0x80 {
            return (codePoint >= 0x41 && codePoint <= 0x5A) ? codePoint + 0x20 : codePoint
        }
        guard let scalar = Unicode.Scalar(codePoint) else { return codePoint }
        let lower = lowerCodePoint(scalar)
        return isKnownToJava(lower) ? lower.value : codePoint
    }

    /// The character exists in Unicode 15.0 (the JDK 21 version).
    private static func isKnownToJava(_ scalar: Unicode.Scalar) -> Bool {
        guard let age = scalar.properties.age else { return false }
        return age.major < 15 || (age.major == 15 && age.minor == 0)
    }
}
