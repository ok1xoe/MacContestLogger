import Foundation

// MARK: - Value tree

/// A value read from YAML. Matches what Jackson's `ObjectMapper.readTree`
/// (`JsonNode`) returns in Java — including how Jackson types unquoted scalars
/// (`48` number, `160m` text, `yes` boolean).
///
/// Numeric values are split into `int` and `double` exactly as in Jackson
/// (`IntNode`/`LongNode` vs `DoubleNode`) — merging them would lose the
/// difference between `48` and `48.0`, which the canonical dump in the gate
/// against Java relies on.
///
/// Scalars whose spelling in the file may differ from the computed value carry
/// the **original spelling** in `raw`. Java returns it verbatim when filling
/// `String` fields (measured: `1e3` -> "1e3", `007` -> "007", `2.50` -> "2.50",
/// `yes` -> "yes"), so without it a user definition with `power: 1e3` would
/// behave differently from Java. `contest-data/` is a user-configurable
/// directory (`AppConfig.contestDataDir`), so the content of our files cannot
/// be relied upon.
public enum YamlValue: Sendable, Hashable {
    case null
    case bool(Bool, raw: String)
    case int(Int, raw: String)
    case double(Double, raw: String)
    case string(String)
    case sequence([YamlValue])
    case mapping(YamlMapping)
}

public extension YamlValue {
    /// A scalar without a special spelling — `raw` is derived from the value.
    /// Used by literals and by callers who build the tree in code, not from a file.
    static func bool(_ value: Bool) -> YamlValue { .bool(value, raw: value ? "true" : "false") }
    static func int(_ value: Int) -> YamlValue { .int(value, raw: String(value)) }
    static func double(_ value: Double) -> YamlValue { .double(value, raw: String(value)) }
}

extension YamlValue {
    /// Equality **ignores the original spelling** and compares only the value,
    /// like Jackson's `JsonNode.equals` (its tree does not keep the original
    /// spelling at all — `asText()` on `1e3` returns "1000.0"). `raw` is thus the
    /// origin of the value, not part of its identity: `.int(7, raw: "007") == .int(7)`.
    ///
    /// If `raw` counted towards equality, the `parse(write(v)) == v` round-trip
    /// would fail, because the writer writes canonically.
    /// `hash(into:)` ignores `raw` too, so the `Hashable` contract holds.
    public static func == (lhs: YamlValue, rhs: YamlValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a, _), .bool(b, _)): return a == b
        case let (.int(a, _), .int(b, _)): return a == b
        case let (.double(a, _), .double(b, _)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.sequence(a), .sequence(b)): return a == b
        case let (.mapping(a), .mapping(b)): return a == b
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null: hasher.combine(0)
        case .bool(let v, _): hasher.combine(1); hasher.combine(v)
        case .int(let v, _): hasher.combine(2); hasher.combine(v)
        case .double(let v, _): hasher.combine(3); hasher.combine(v)
        case .string(let v): hasher.combine(4); hasher.combine(v)
        case .sequence(let v): hasher.combine(5); hasher.combine(v)
        case .mapping(let v): hasher.combine(6); hasher.combine(v)
        }
    }
}

/// A YAML mapping. Keeps the **key order from the document** (Jackson uses
/// `LinkedHashMap`, so it behaves the same).
///
/// Duplicate key: the **last** value wins, but the key keeps its **original
/// position** — measured on Java, `a: 1 / b: 2 / a: 3` gives `{a:3, b:2}`.
///
/// Equality is sensitive to key order and compares values via `YamlValue.==`,
/// so the original scalar spelling (`YamlValue.raw`) does not enter into it.
public struct YamlMapping: Sendable, Hashable {

    private var order: [String]
    private var values: [String: YamlValue]

    public init() {
        order = []
        values = [:]
    }

    /// Builds a mapping from pairs in the given order; a duplicate key is handled as in Java.
    public init(_ pairs: [(String, YamlValue)]) {
        self.init()
        for (key, value) in pairs { set(key, value) }
    }

    /// Keys in the order they appeared in the document.
    public var keys: [String] { order }
    public var count: Int { order.count }
    public var isEmpty: Bool { order.isEmpty }

    /// The value for the key, or `nil` when the key is missing. For walking the
    /// tree `YamlValue.subscript(_:)` is more convenient; it returns a missing
    /// key as `.null`.
    public subscript(key: String) -> YamlValue? { values[key] }

    public func contains(_ key: String) -> Bool { values[key] != nil }

    /// Inserts or overwrites a key. An existing key keeps its position.
    public mutating func set(_ key: String, _ value: YamlValue) {
        if values.updateValue(value, forKey: key) == nil {
            order.append(key)
        }
    }

    /// Pairs in document order.
    public var pairs: [(key: String, value: YamlValue)] {
        order.map { (key: $0, value: values[$0] ?? .null) }
    }
}

extension YamlMapping: Sequence {
    public func makeIterator() -> Array<(key: String, value: YamlValue)>.Iterator {
        pairs.makeIterator()
    }
}

extension YamlMapping: ExpressibleByDictionaryLiteral {
    /// A literal keeps the order in which it is written.
    public init(dictionaryLiteral elements: (String, YamlValue)...) {
        self.init(elements)
    }
}

// MARK: - Literals (mainly for tests and for the writer)

extension YamlValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension YamlValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension YamlValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension YamlValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension YamlValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: YamlValue...) { self = .sequence(elements) }
}

extension YamlValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, YamlValue)...) {
        self = .mapping(YamlMapping(elements))
    }
}

// MARK: - Strict reading (own case only)

public extension YamlValue {

    var isNull: Bool { if case .null = self { return true } else { return false } }

    /// Boolean — only from `.bool`, no conversions.
    var bool: Bool? { if case .bool(let v, _) = self { return v } else { return nil } }

    /// Integer — only from `.int`, no conversions.
    var int: Int? { if case .int(let v, _) = self { return v } else { return nil } }

    /// Floating-point number — only from `.double`, no conversions.
    var double: Double? { if case .double(let v, _) = self { return v } else { return nil } }

    /// The original spelling of a scalar from the file — exactly what Java puts
    /// into a `String` field. For `.string` it is the value itself (after escape
    /// expansion); for a mapping, sequence and `null` it is `nil`.
    var rawText: String? {
        switch self {
        case .bool(_, let raw), .int(_, let raw), .double(_, let raw): return raw
        case .string(let value): return value
        case .null, .sequence, .mapping: return nil
        }
    }

    /// Text — only from `.string`, no conversions.
    var string: String? { if case .string(let v) = self { return v } else { return nil } }

    var sequence: [YamlValue]? { if case .sequence(let v) = self { return v } else { return nil } }

    var mapping: YamlMapping? { if case .mapping(let v) = self { return v } else { return nil } }

    /// Mapping keys, or empty when this is not a mapping.
    var keys: [String] { mapping?.keys ?? [] }

    func has(_ key: String) -> Bool { mapping?.contains(key) ?? false }

    /// Navigation through a mapping. A missing key and "this is not a mapping"
    /// both give `.null`, so calls can be chained
    /// (`doc["scoring"]["qsoPoints"]["mode"]`) without a cascade of `switch`
    /// and without crashing.
    subscript(key: String) -> YamlValue { mapping?[key] ?? .null }

    /// Navigation through a sequence. Out of range and "this is not a sequence" give `.null`.
    subscript(index: Int) -> YamlValue {
        guard case .sequence(let items) = self, index >= 0, index < items.count else { return .null }
        return items[index]
    }
}

// MARK: - Reading with a default value

/// A type that can be read from a YAML node.
///
/// The conversions copy Jackson (measured on Java): `"48"` -> `48`, `3.7` -> `3`,
/// `48` -> `"48"`, `1` -> `true`, `"true"` -> `true`, but `"yes"` -> **no**.
public protocol YamlReadable {
    /// Returns `nil` when the node cannot be turned into a value of this type.
    init?(yaml value: YamlValue)
}

public extension YamlValue {

    /// Reads the value, or returns the default. A missing key, `null` and a wrong
    /// type all end with the default value — never with an error.
    ///
    /// This is the same contract as `KeyedDecodingContainer.value(_:default:)`:
    /// Java has `FAIL_ON_UNKNOWN_PROPERTIES` turned off, so it
    /// ignores an unknown key and leaves a missing one at its default.
    func value<T: YamlReadable>(_ key: String, default fallback: T) -> T {
        self[key].value(default: fallback)
    }

    /// The same for this node — handy when iterating a sequence.
    func value<T: YamlReadable>(default fallback: T) -> T {
        T(yaml: self) ?? fallback
    }
}

extension String: YamlReadable {
    /// Java returns the **original spelling** of a scalar into a `String` field,
    /// not the recomputed value (`1e3` -> "1e3", `007` -> "007", `TRUE` -> "TRUE"; measured).
    public init?(yaml value: YamlValue) {
        guard let text = value.rawText else { return nil }
        self = text
    }
}

extension Int: YamlReadable {
    public init?(yaml value: YamlValue) {
        switch value {
        case .int(let i, _):
            self = i
        case .double(let d, _):
            // Jackson truncates a decimal number into `int` (ACCEPT_FLOAT_AS_INT): 3.7 -> 3.
            guard d >= -9.223372036854775e18, d <= 9.223372036854775e18 else { return nil }
            self = Int(d)
        case .string(let s):
            guard let i = Int(s) else { return nil }
            self = i
        case .null, .bool, .sequence, .mapping:
            return nil
        }
    }
}

extension Double: YamlReadable {
    public init?(yaml value: YamlValue) {
        switch value {
        case .double(let d, _): self = d
        case .int(let i, _): self = Double(i)
        case .string(let s):
            guard let d = Double(s) else { return nil }
            self = d
        case .null, .bool, .sequence, .mapping: return nil
        }
    }
}

extension Bool: YamlReadable {
    public init?(yaml value: YamlValue) {
        switch value {
        case .bool(let b, _):
            self = b
        case .int(let i, _):
            self = i != 0
        case .string(let s):
            // From text Jackson accepts only "true"/"false" (in three letter
            // cases), not "yes" — measured on Java.
            switch s {
            case "true", "True", "TRUE": self = true
            case "false", "False", "FALSE": self = false
            default: return nil
            }
        case .null, .double, .sequence, .mapping:
            return nil
        }
    }
}

extension Array: YamlReadable where Element: YamlReadable {
    /// From a sequence; if **any** element fails to convert, the whole list
    /// fails (Jackson would fail too, and the caller gets the default value).
    public init?(yaml value: YamlValue) {
        guard case .sequence(let items) = value else { return nil }
        var out: [Element] = []
        out.reserveCapacity(items.count)
        for item in items {
            guard let converted = Element(yaml: item) else { return nil }
            out.append(converted)
        }
        self = out
    }
}

// `YamlValue` itself is deliberately **not** `YamlReadable`: `YamlValue` is
// `ExpressibleBy…Literal`, so `value("x", default: 0.0)` could be inferred as
// `YamlValue` too and the caller would get a node back instead of a `Double`.
// Whoever wants child nodes has `sequence`, `mapping` and `subscript`.
