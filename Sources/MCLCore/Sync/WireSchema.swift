/// Description of the `:sync-shared` wire record for `WireJson`: names and types of components in the declaration order of the Java
/// record (Jackson writes them in this order and reads by name). The component type determines coercion on read
/// (`WireJsonReader`) and writing (`WireJsonWriter`).
public indirect enum WireKind: Sendable {
    /// `String` (may be `null`).
    case string
    /// `long` (primitive, missing/`null` = 0).
    case long
    /// `int` (primitive, missing/`null` = 0).
    case int
    /// `boolean` (primitive, missing/`null` = false).
    case bool
    /// `Integer` (may be `null`).
    case intBox
    /// `Boolean` (may be `null`).
    case boolBox
    /// `java.time.Instant` (may be `null`), ISO-8601 string.
    case instant
    /// Nested record (may be `null`).
    case record([WireField])
}

public struct WireField: Sendable {
    public let name: String
    public let kind: WireKind

    init(_ name: String, _ kind: WireKind) {
        self.name = name
        self.kind = kind
    }
}

/// Value of one record component (read result, write input).
public enum WireValue: Equatable, Sendable {
    case string(String?)
    case long(Int64)
    case int(Int32)
    case bool(Bool)
    case intBox(Int32?)
    case boolBox(Bool?)
    case instant(JavaInstant?)
    case record([WireValue]?)

    /// Value of a missing component (the Java record constructor gets the type's default value).
    static func missing(_ kind: WireKind) -> WireValue {
        switch kind {
        case .string: return .string(nil)
        case .long: return .long(0)
        case .int: return .int(0)
        case .bool: return .bool(false)
        case .intBox: return .intBox(nil)
        case .boolBox: return .boolBox(nil)
        case .instant: return .instant(nil)
        case .record: return .record(nil)
        }
    }

    var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var long: Int64 {
        if case .long(let v) = self { return v }
        return 0
    }

    var int: Int32 {
        if case .int(let v) = self { return v }
        return 0
    }

    var bool: Bool {
        if case .bool(let v) = self { return v }
        return false
    }

    var intBox: Int32? {
        if case .intBox(let v) = self { return v }
        return nil
    }

    var boolBox: Bool? {
        if case .boolBox(let v) = self { return v }
        return nil
    }

    var instant: JavaInstant? {
        if case .instant(let v) = self { return v }
        return nil
    }

    var record: [WireValue]? {
        if case .record(let v) = self { return v }
        return nil
    }
}

/// Cluster sync wire message (a Java record from `:sync-shared`) that `WireJson` can write and read.
public protocol WireMessage: Equatable, Sendable {
    /// `Class.getSimpleName()` — into the `SyncSerializationError` text.
    static var wireTypeName: String { get }
    static var wireFields: [WireField] { get }
    init(wireValues: [WireValue])
    var wireValues: [WireValue] { get }
}
