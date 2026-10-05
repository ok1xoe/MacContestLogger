/// Worked multipliers: `bindingId → scopeKey → (key → count)`. A counter because of
/// QSO correction and deletion (a key "lives" while the count is > 0). Port of Java
/// `engine/MultiplierTracker.java`.
///
/// Shape differences versus Java (behaviour is the same):
/// - **`struct`** (a value, `Sendable`): the Java session is created during a background recompute
///   and taken over by the main thread — the value is handed over without locks (baseline 5.8).
/// - Keys of all three levels are compared **by UTF-16** like a Java `HashMap`
///   (`K` ≠ KELVIN SIGN, `A`+U+030A ≠ U+00C5); `bindingId` and the key may be `nil`
///   (Java key `null`). `scopeKey` is non-`nil`: the evaluator always produces it
///   (`MultiplierEvaluator.scopeKey`) and Java would fail with a `null` scope in `weightedForBinding`.
/// - Counts and sums are Java `int` — they wrap around (`JavaMath.addInt`), they do not crash.
/// - `keysForBinding` returns keys **sorted by UTF-16** (`nil` first). The Java version is a
///   `LinkedHashSet` in `HashMap` hash order (unspecified) and the only consumer
///   (`ContestSession.java:157-158`) sorts it right away with `Collections.sort` (UTF-16).
public struct MultiplierTracker: Sendable {

    /// Text as a Java `HashMap` key: match by UTF-16 units, `nil` = `null`.
    private struct Key: Hashable, Sendable {
        let text: String?
        let units: [UInt16]?

        init(_ text: String?) {
            self.text = text
            units = text.map { Array($0.utf16) }
        }

        static func == (left: Key, right: Key) -> Bool { left.units == right.units }

        func hash(into hasher: inout Hasher) { hasher.combine(units) }
    }

    private var counts: [Key: [Key: [Key: Int32]]] = [:]

    public init() {}

    /// Java `isWorked`: the key has a count > 0 in the binding's scope.
    public func isWorked(_ bindingId: String?, _ scopeKey: String, _ key: String?) -> Bool {
        guard let count = counts[Key(bindingId)]?[Key(scopeKey)]?[Key(key)] else { return false }
        return count > 0
    }

    /// Adds an occurrence; `true` if the key newly appeared (0 → 1).
    @discardableResult
    public mutating func add(_ bindingId: String?, _ scopeKey: String, _ key: String?) -> Bool {
        let count = counts[Key(bindingId), default: [:]][Key(scopeKey), default: [:]][Key(key)] ?? 0
        counts[Key(bindingId), default: [:]][Key(scopeKey), default: [:]][Key(key)] = JavaMath.addInt(count, 1)
        return count == 0
    }

    /// Removes an occurrence; `true` if the key disappeared (1 → 0). An unknown binding or scope → `false`
    /// and nothing is created; empty scope maps are not deleted (they contribute zero, as in Java).
    @discardableResult
    public mutating func remove(_ bindingId: String?, _ scopeKey: String, _ key: String?) -> Bool {
        let binding = Key(bindingId), scope = Key(scopeKey), entry = Key(key)
        guard counts[binding]?[scope] != nil else { return false }
        let count = counts[binding]?[scope]?[entry] ?? 0
        if count <= 1 {
            counts[binding]?[scope]?[entry] = nil
            return count == 1
        }
        counts[binding]?[scope]?[entry] = count - 1
        return false
    }

    /// Number of distinct keys across the scopes of one binding (a key on two bands counts
    /// twice — that is a per-band multiplier).
    public func distinctForBinding(_ bindingId: String?) -> Int32 {
        var total: Int32 = 0
        for scope in (counts[Key(bindingId)] ?? [:]).values {
            total = JavaMath.addInt(total, Int32(truncatingIfNeeded: scope.count))
        }
        return total
    }

    /// Number of multipliers of a binding with band weight: the band is the part of `scopeKey` before the first `|`
    /// (or the whole key, so also `*` and `null` literally); a band without a weight has weight 1.
    ///
    /// The weight is looked up **by UTF-16** among the `bandWeights` pairs (Java `HashMap.getOrDefault`),
    /// not by the canonical `subscript` of `YamlOrderedMap`. A present `nil` weight (`{80m: ~}`) makes
    /// Java fail with an NPE only if there is a multiplier on that band — Swift takes it as **1** (a band without
    /// a weight).
    public func weightedForBinding(_ bindingId: String?, _ bandWeights: YamlOrderedMap<Int>) -> Int32 {
        guard let scopes = counts[Key(bindingId)] else { return 0 }
        let weights = bandWeights.pairs.map { (units: Array($0.key.utf16), weight: $0.value) }
        var total: Int32 = 0
        for (scope, keys) in scopes {
            let units = scope.units ?? []
            let band = units.firstIndex(of: 0x7C).map { Array(units[..<$0]) } ?? units
            var weight: Int32 = 1
            if let match = weights.first(where: { $0.units == band }), let value = match.weight {
                weight = Int32(truncatingIfNeeded: value)
            }
            total = JavaMath.addInt(total, JavaMath.multiplyInt(Int32(truncatingIfNeeded: keys.count), weight))
        }
        return total
    }

    /// All worked keys of a binding across scopes (for the grid of non-enumerated sets),
    /// without repeats by UTF-16, sorted by UTF-16 units (`nil` first).
    public func keysForBinding(_ bindingId: String?) -> [String?] {
        var seen: Set<Key> = []
        for scope in (counts[Key(bindingId)] ?? [:]).values {
            for key in scope.keys {
                seen.insert(key)
            }
        }
        return seen.sorted { left, right in
            guard let a = left.units else { return right.units != nil }
            guard let b = right.units else { return false }
            return a.lexicographicallyPrecedes(b)
        }.map(\.text)
    }

    /// Total number of distinct multipliers across all bindings.
    public func totalDistinct() -> Int32 {
        var total: Int32 = 0
        for binding in counts.keys {
            total = JavaMath.addInt(total, distinctForBinding(binding.text))
        }
        return total
    }

    public mutating func reset() {
        counts.removeAll()
    }
}

extension MultiplierTracker: MultiplierCounts {}
