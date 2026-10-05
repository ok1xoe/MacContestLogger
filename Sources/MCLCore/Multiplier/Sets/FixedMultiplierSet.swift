import Foundation

/// Fixed multiplier set (enumeration + normalisation from an exchange field).
///
/// Port of Java `multiplier/sets/FixedMultiplierSet.java`. The behaviour is
/// measured (`FixedMultiplierSetTests`) and has several traps
/// that are copied:
/// - keys from the definition are **not normalised** (`" ab "` is never expected),
///   only the query is normalised,
/// - `INTEGER` tries the ASCII `\d+` shape after Java `trim()`, but the canonical
///   key is made by `Integer.parseInt` (`+`, Unicode digits, `int` range) — hence
///   `"+7"` is invalid in `normalize` and expected in `isExpected`,
/// - `enumerable` is **always** `true`, even for an empty set (`grid_fields`),
/// - `keyLength` truncates by UTF-16 units (`substring`).
public final class FixedMultiplierSet: MultiplierSet {

    public let id: String?
    private let keyType: MultiplierSetDefinition.KeyType
    /// Java `LinkedHashMap`: first-occurrence order, last value wins, keys compared
    /// by UTF-16 (`K` and KELVIN SIGN are two values, not one as in a Swift dictionary).
    private let byKey: JavaLinkedMap<MultiplierValue>
    /// Compiled once in the constructor, like Java `Pattern.compile`
    /// (a pattern with `\b` costs ~12 ms).
    private let keyPattern: JavaRegex?
    private let keyLength: Int

    /// - Parameters:
    ///   - keyType: `nil` → `TEXT`.
    ///   - keyPattern: Java regex; the whole value must match (`matches()`).
    ///   - keyLength: if positive, the key is truncated after validation to the first N
    ///     UTF-16 units (a 4-character locator → a 2-character field); `nil`, `0`
    ///     and a negative number mean do not truncate.
    /// - Throws: `MultiplierError.invalidPattern` for a faulty `keyPattern` —
    ///   like the Java constructor (`PatternSyntaxException`), not only on use.
    public init(id: String?, keyType: MultiplierSetDefinition.KeyType?, values: [MultiplierValue],
                keyPattern: String?, keyLength: Int? = nil) throws(MultiplierError) {
        self.id = id
        self.keyType = keyType ?? .TEXT
        if let keyPattern {
            do {
                self.keyPattern = try JavaRegex(keyPattern)
            } catch {
                throw .invalidPattern(pattern: keyPattern, message: error.message)
            }
        } else {
            self.keyPattern = nil
        }
        self.keyLength = keyLength ?? 0
        var byKey = JavaLinkedMap<MultiplierValue>()
        for value in values {
            byKey.put(value.key, value)
        }
        self.byKey = byKey
    }

    public var enumerable: Bool { true }

    public var values: [MultiplierValue] { byKey.entries.compactMap(\.value) }

    public func isExpected(_ key: String?) -> Bool {
        guard let key else { return false }
        return byKey.containsKey(canonical(key))
    }

    public func normalize(_ rawValue: String?) -> Resolution {
        guard let rawValue, !JavaText.isBlank(rawValue) else {
            return .invalid("prázdná hodnota")
        }
        if keyType == .INTEGER && !Self.isAsciiDigits(JavaText.trim(rawValue)) {
            return .invalid("očekáváno číslo: " + rawValue)
        }
        var key = canonical(rawValue)
        if let keyPattern, !keyPattern.matches(key) {
            return .invalid("neodpovídá formátu: " + rawValue)
        }
        if keyLength > 0 && key.utf16.count > keyLength {
            // e.g. locator JO80 → field JO; a split surrogate pair gives U+FFFD
            // (Java keeps a lone half — a deliberate divergence from Java v1.1.1)
            key = String(decoding: Array(key.utf16.prefix(keyLength)), as: UTF16.self)
        }
        return .valid(key)
    }

    public func deriveFromCallsign(_ callsign: String?) -> Resolution {
        .unsupported
    }

    /// Java `canonical`: `trim()`, then for `INTEGER` `Integer.parseInt`
    /// (on error the text stays), otherwise `toUpperCase()`.
    private func canonical(_ raw: String) -> String {
        let trimmed = JavaText.trim(raw)
        if keyType == .INTEGER {
            return JavaInteger.parseInt(trimmed).map { String($0) } ?? trimmed
        }
        // port convention: `uppercased()` = Java `toUpperCase(Locale.ROOT)`
        return trimmed.uppercased()
    }

    /// Java `matches("\\d+")`: at least one digit, ASCII `0`–`9` only
    /// (Java `\d` without `UNICODE_CHARACTER_CLASS`).
    private static func isAsciiDigits(_ text: String) -> Bool {
        !text.isEmpty && text.utf16.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }
}
