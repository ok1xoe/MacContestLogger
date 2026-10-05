// MARK: - toUpperCase and compareTo

extension JavaText {

    /// Java `String.toUpperCase()` under the default locale `en_US`/`cs_CZ` (= `Locale.ROOT`).
    ///
    /// By code points the **full** mapping (`SpecialCasing` without conditions): `ß` → `SS`,
    /// `ŉ` → `ʼN`, `ﬃ` → `FFI`, `ΐ` → three points… (102 expanding points), otherwise the simple
    /// `Character.toUpperCase`. Latin-1 can escape (`ÿ` → U+0178, `µ` → U+039C).
    /// The result length may therefore differ from the input — do not carry indices over from the uppercased copy.
    ///
    /// JDK 21 knows Unicode 15.0: points added later and mappings whose target was added
    /// later (`ƛ` → U+A7DC, `ɤ` → U+A7CB in Unicode 16.0) Java leaves unchanged —
    /// measured over all code points (`JavaTextUpperCaseTests.codePointSweepMatchesJava`).
    /// Turkish/Azerbaijani/Lithuanian behavior (other default locales) is not emulated.
    static func toUpperCase(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value: UInt32 = scalar.value
            if value < 0x80 {
                out.append((value >= 0x61 && value <= 0x7A) ? Unicode.Scalar(value - 0x20)! : scalar)
            } else {
                out.append(contentsOf: upperCodePoints(scalar))
            }
        }
        return String(out)
    }

    /// Java uppercase of a single code point (one or more points), limited to Unicode 15.0.
    static func upperCodePoints(_ scalar: Unicode.Scalar) -> [Unicode.Scalar] {
        if isAfterUnicode15(scalar) { return [scalar] }
        let mapping: [Unicode.Scalar] = Array(scalar.properties.uppercaseMapping.unicodeScalars)
        for mapped in mapping where isAfterUnicode15(mapped) {
            return [scalar]
        }
        return mapping
    }

    private static func isAfterUnicode15(_ scalar: Unicode.Scalar) -> Bool {
        guard let age = scalar.properties.age else { return false }
        return age.major > 15 || (age.major == 15 && age.minor > 0)
    }

    /// Java `a.compareTo(b)`: the difference of the first differing UTF-16 unit, otherwise the difference of lengths
    /// (in UTF-16 units). Sorts like Java's `sorted()`/`TreeMap`/`TreeSet` over strings —
    /// not canonically like Swift's `<` (`é` vs. `e` + U+0301) and not by scalars
    /// (`😀` D83D… is **before** `ａ` FF41).
    static func compare(_ a: String, _ b: String) -> Int {
        var left = a.utf16.makeIterator()
        var right = b.utf16.makeIterator()
        var common = 0
        while true {
            switch (left.next(), right.next()) {
            case (nil, nil):
                return 0
            case (nil, _?):
                return common - b.utf16.count
            case (_?, nil):
                return a.utf16.count - common
            case let (x?, y?):
                if x != y { return Int(x) - Int(y) }
                common += 1
            }
        }
    }
}
