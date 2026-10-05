/// Java `LinkedHashMap<String, V>`: first-insertion order, `put` of an existing key
/// overwrites the value **at the original position**, both key and value may be `null`.
///
/// Why not Swift's `Dictionary`: it compares keys **canonically** (`K` and KELVIN SIGN
/// U+212A, `Å` U+00C5 and ANGSTROM SIGN U+212B are one key for it), whereas the Java map compares
/// by UTF-16 units — measured: a `LinkedHashMap` with keys `K` and `K` holds **both**
/// values and the expression `K` / `K` finds each separately (1 / 2). Keys come here from contest
/// definitions (ids of received fields, `mult.<set id>`), so the definition author can write them. And a dictionary
/// literal with two equal keys **crashes** at runtime; here Java's `put` semantics apply.
public struct JavaLinkedMap<Value> {

    /// Key by UTF-16 units (`JavaStringKey`, no allocation on lookup); `nil` = Java
    /// key `null`.
    private typealias Key = JavaStringKey

    /// Keys in first-insertion order.
    public private(set) var keys: [String?] = []
    private var values: [Value?] = []
    private var positions: [Key: Int] = [:]

    public init() {}

    /// Successive Java `put`s in pair order (a later value of the same key wins
    /// and stays at the position of the first occurrence).
    public init(_ pairs: [(String?, Value?)]) {
        for (key, value) in pairs { put(key, value) }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    /// Java `get`: a missing key and a `null` value both give `nil`.
    public subscript(key: String?) -> Value? {
        guard let position = positions[Key(key)] else { return nil }
        return values[position]
    }

    /// Java `get` with a key prepared in advance (e.g. a variable name in a translated expression).
    subscript(key: JavaStringKey) -> Value? {
        guard let position = positions[key] else { return nil }
        return values[position]
    }

    /// Java `containsKey` — true also for a key with a `null` value.
    public func containsKey(_ key: String?) -> Bool {
        positions[Key(key)] != nil
    }

    /// Java `put`.
    public mutating func put(_ key: String?, _ value: Value?) {
        let k = Key(key)
        if let position = positions[k] {
            values[position] = value
        } else {
            positions[k] = keys.count
            keys.append(key)
            values.append(value)
        }
    }

    /// Pairs in insertion order (Java `entrySet()`).
    public var entries: [(key: String?, value: Value?)] {
        Array(zip(keys, values)).map { (key: $0.0, value: $0.1) }
    }
}

extension JavaLinkedMap: Equatable where Value: Equatable {
    /// Java `Map.equals`: same keys (by UTF-16) with the same values, **regardless
    /// of order**.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, value) in lhs.entries {
            guard rhs.containsKey(key), rhs[key] == value else { return false }
        }
        return true
    }
}

extension JavaLinkedMap: Sendable where Value: Sendable {}
