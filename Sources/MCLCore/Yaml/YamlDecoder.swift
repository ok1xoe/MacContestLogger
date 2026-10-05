import Foundation

// MARK: - Strict YAML decoder -> types
//
// Replacement for Java's `ObjectMapper.readValue(in, Record.class)` (Jackson 2.22
// with default coercion and `FAIL_ON_UNKNOWN_PROPERTIES` turned off) for contest
// definitions and multiplier sets.
//
// Unlike `YamlValue.value(_:default:)` it **does not swallow** a type
// error: `scope: per_band`, `required: ano` or `bands: 20m` rejects the whole
// document with the line and column that Jackson points at too. A missing key
// and `~` are not errors, though — they give `nil` and the caller picks the default.
//
// The coercion rules are **measured on Java** (table in
// `YamlDecoderTests.coercionCases`) and transcribed from Jackson 2.21/2.22
// (`StdDeserializer._parseIntPrimitive`, `_parseBooleanPrimitive`,
// `_parseDoublePrimitive`, `EnumDeserializer._fromString`, `YAMLParser`).

// MARK: - Protocols

/// A type that can be read strictly from a YAML node, like Jackson.
///
/// `init` is called **only for a node that is not `null`** (a missing key and `~`
/// are handled by the decoder itself as `nil`). When the node cannot be turned into a value,
/// `init` records an error via `node.typeMismatch(_:)` and returns `nil`; it must not
/// return `nil` without a recorded error.
///
/// `String`, `Int32`, `Double`, `Bool`, every `YamlEnum` and
/// `YamlRecord` conform. A type that takes several shapes (a Java record with another
/// single-parameter constructor, e.g. `Period(Integer)`, takes a number and a mapping),
/// implements this protocol directly and decides by `node.value`.
public protocol YamlDecodable {
    init?(yamlNode node: YamlNode)
}

/// A Java record: read from a mapping, unknown keys are ignored.
///
/// `init(yaml:)` is to read **every field of the Java record** — Java checks the
/// type of every known property even if nobody uses it afterwards. Fields are read via
/// `YamlObject` (`string`, `int`, `decode`, `list`, `map`…), which record errors
/// themselves; `init` therefore throws nothing and the order of reading fields does not matter
/// (the first error **in document order** is reported, as in Java).
///
/// Anything other than a mapping is an error (even from empty text `""`).
public protocol YamlRecord: YamlDecodable {
    init(yaml object: YamlObject)
}

public extension YamlRecord {
    init?(yamlNode node: YamlNode) {
        guard let object = node.object() else { return nil }
        self.init(yaml: object)
    }
}

/// A Java enum. `rawValue` is the Java constant **name** (case-sensitive)
/// and **the order of cases must be the same as in Java** — Jackson also accepts
/// the numeric ordinal (`scope: 1` -> second constant), see `init(yamlNode:)`.
public protocol YamlEnum: YamlDecodable, CaseIterable, RawRepresentable where RawValue == String {}

public extension YamlEnum {
    /// `EnumDeserializer` with default settings (measured):
    /// - text: exact name; otherwise the name after Java `trim()`; empty or
    ///   blank text is an error; text starting with an ASCII digit (except `0x…`
    ///   with a leading zero and length over 1) is tried as an ordinal via
    ///   `Integer.parseInt` (`" 1"` -> second constant, `"01"`, `"+1"` not),
    /// - integer: ordinal; outside `int` is an error at the **end** of the token, outside the
    ///   number of constants at the start,
    /// - anything else (`true`, `1.0`, collections) is an error.
    init?(yamlNode node: YamlNode) {
        let cases = Array(Self.allCases)
        switch node.value {
        case .string(let text):
            if let match = Self(rawValue: text) {
                self = match
                return
            }
            let trimmed = JavaText.trim(text)
            if trimmed != text, let match = Self(rawValue: trimmed) {
                self = match
                return
            }
            if trimmed.isEmpty {
                node.typeMismatch("prázdný text nejde převést na výčet \(Self.javaNames)")
                return nil
            }
            if let first = trimmed.utf16.first, first >= 0x30, first <= 0x39,
               !(first == 0x30 && trimmed.utf16.count > 1),
               let index = JacksonCoercion.parseInt(trimmed), index >= 0, Int(index) < cases.count {
                self = cases[Int(index)]
                return
            }
            node.typeMismatch("„\(text)\" není platná hodnota výčtu \(Self.javaNames)")
            return nil
        case .int(let value, _):
            guard let index = Int32(exactly: value) else {
                node.typeMismatchAtEnd("číslo \(value) je mimo rozsah int")
                return nil
            }
            guard index >= 0, Int(index) < cases.count else {
                node.typeMismatch("pořadí \(index) je mimo rozsah 0…\(cases.count - 1) výčtu \(Self.javaNames)")
                return nil
            }
            self = cases[Int(index)]
        default:
            node.typeMismatch("\(node.value.kindDescription) nejde převést na výčet \(Self.javaNames)")
            return nil
        }
    }

    /// List of permitted names for the message.
    internal static var javaNames: String {
        "(" + allCases.map(\.rawValue).joined(separator: ", ") + ")"
    }
}

// MARK: - Entry point

public enum YamlDecoder {

    /// Reads the document root as `T`.
    ///
    /// - Returns: `nil` when the root is `null` (`~`, a lone `---`) — Java's
    ///   `readValue` returns `null` and the caller turns that into its own error
    ///   ("the definition is empty").
    /// - Throws: `YamlError` of kind `.type`: the first type error in document
    ///   order (Jackson reads streaming and stops at the first), or empty input
    ///   without a document (Java: "No content to map due to end-of-input", at the position
    ///   of the end of input).
    public static func decode<T: YamlDecodable>(_ type: T.Type, from document: YamlDocument) throws -> T? {
        if document.isEmptyStream {
            let end = document.positions.endOfInput
            throw YamlError(kind: .type, message: "vstup neobsahuje žádný dokument",
                            line: end.line, column: end.column)
        }
        let context = YamlDecodingContext(document: document)
        let node = YamlNode(value: document.root, path: .root, context: context)
        let result = node.decode(T.self)
        if let error = context.firstError { throw error }
        return result
    }

    /// Parses the text (`YamlParser.parseDocument`) and reads it as `T`.
    /// Syntax errors of the parser pass through unchanged (`.syntax`/`.unsupported`).
    public static func decode<T: YamlDecodable>(_ type: T.Type, from text: String) throws -> T? {
        try decode(type, from: YamlParser.parseDocument(text))
    }
}

/// Error collector of a single read. Errors are **not thrown immediately**: a Swift `init`
/// reads fields in declaration order, Jackson in document order, and the error to report
/// must be the one Java would hit — that is, the one whose node starts
/// earliest in the document.
final class YamlDecodingContext {
    let document: YamlDocument
    private var errors: [(order: YamlPosition, sequence: Int, error: YamlError)] = []

    init(document: YamlDocument) { self.document = document }

    func record(_ error: YamlError, order: YamlPosition) {
        errors.append((order, errors.count, error))
    }

    var firstError: YamlError? {
        errors.min { ($0.order, $0.sequence) < ($1.order, $1.sequence) }?.error
    }

    /// Start of the node; when the parser did not record it, the nearest ancestor with a position.
    func start(of path: YamlPath) -> YamlPosition {
        var current = path
        while true {
            if let position = document.positions.start(current) { return position }
            if current.isRoot { return YamlPosition(line: 1, column: 1) }
            current = current.parent
        }
    }
}

// MARK: - Node

/// A single document node while reading: the value, the path to it (for the position in an error)
/// and the error collector.
public struct YamlNode {
    public let value: YamlValue
    public let path: YamlPath
    let context: YamlDecodingContext

    init(value: YamlValue, path: YamlPath, context: YamlDecodingContext) {
        self.value = value
        self.path = path
        self.context = context
    }

    /// Start of the node's token (where most type errors point).
    public var position: YamlPosition { context.start(of: path) }

    /// The value as `T`; `null` -> `nil` without an error.
    public func decode<T: YamlDecodable>(_ type: T.Type = T.self) -> T? {
        if value.isNull { return nil }
        return T(yamlNode: self)
    }

    /// The node as a Java record mapping, or `nil` and a recorded error.
    public func object() -> YamlObject? {
        guard case .mapping(let mapping) = value else {
            if case .string("") = value {
                typeMismatch("prázdný text nejde převést na objekt")
            } else {
                typeMismatch("čeká se mapa (objekt), ne \(value.kindDescription)")
            }
            return nil
        }
        return YamlObject(node: self, mapping: mapping)
    }

    /// The node as a Java `List<T>`: only from a sequence (`ACCEPT_SINGLE_VALUE_AS_ARRAY`
    /// is off, so `bands: 20m` is an error). `null` elements **are kept**
    /// (`[~, 160m]` -> `[nil, "160m"]`, as in Java).
    public func list<T: YamlDecodable>(of type: T.Type) -> [T?]? {
        guard case .sequence(let items) = value else {
            if value.isNull { return nil }
            typeMismatch("čeká se sekvence (seznam), ne \(value.kindDescription)")
            return nil
        }
        return items.enumerated().map { index, item in
            YamlNode(value: item, path: path.appending(index: index), context: context).decode(T.self)
        }
    }

    /// The node as a Java `Map<String, T>` (`LinkedHashMap`): document order,
    /// `null` values are kept. Overwritten occurrences of a duplicate key are read
    /// too (because of errors), the last one wins.
    public func map<T: YamlDecodable>(of type: T.Type) -> YamlOrderedMap<T>? {
        guard case .mapping(let mapping) = value else {
            if value.isNull { return nil }
            typeMismatch("čeká se mapa, ne \(value.kindDescription)")
            return nil
        }
        let object = YamlObject(node: self, mapping: mapping)
        var result = YamlOrderedMap<T>()
        for key in mapping.keys {
            result.set(key, object.decode(key, as: T.self))
        }
        return result
    }

    /// Records a type error at the **start** of the node.
    public func typeMismatch(_ message: String) {
        let start = position
        context.record(YamlError(kind: .type, message: message, line: start.line, column: start.column),
                       order: start)
    }

    /// Records a type error at the **end** of the scalar — that is where Jackson reports it
    /// for a number outside the `int` range (`JsonParser.currentLocation()`).
    public func typeMismatchAtEnd(_ message: String) {
        let start = position
        let end = context.document.positions.end(path) ?? start
        context.record(YamlError(kind: .type, message: message, line: end.line, column: end.column),
                       order: start)
    }
}

// MARK: - Object (mapping of a Java record)

/// A mapping from which a Java record is read. A missing key and `~` give `nil`;
/// an unknown key is ignored (and its content is not checked). A type error gives
/// `nil` and is recorded — only `YamlDecoder.decode` throws it.
public struct YamlObject {
    public let node: YamlNode
    let mapping: YamlMapping

    public var keys: [String] { mapping.keys }

    public func contains(_ key: String) -> Bool { mapping.contains(key) }

    /// Generic reading of a key with a custom function. The function gets a node that is **not**
    /// `null`, and is also called for overwritten earlier occurrences of a duplicate key
    /// (their result is discarded, but the errors count — Java reads them streaming).
    public func decode<R>(_ key: String, using read: (YamlNode) -> R?) -> R? {
        let path = node.path.appending(key: key)
        for (occurrence, shadowed) in node.context.document.shadowedValues(of: path).enumerated()
        where !shadowed.isNull {
            let shadowPath = node.path.appending(.shadowedKey(key, occurrence: occurrence))
            _ = read(YamlNode(value: shadowed, path: shadowPath, context: node.context))
        }
        guard let value = mapping[key], !value.isNull else { return nil }
        return read(YamlNode(value: value, path: path, context: node.context))
    }

    /// The value of a key as `T` (nested record, enum, custom type…).
    public func decode<T: YamlDecodable>(_ key: String, as type: T.Type = T.self) -> T? {
        decode(key) { T(yamlNode: $0) }
    }

    /// A Java `String` field: the scalar text **in its original spelling** (`007`, `1e3`,
    /// `yes` stay as written); a mapping and a sequence are an error.
    public func string(_ key: String) -> String? { decode(key, as: String.self) }

    /// A Java `int`/`Integer` field (32 bits!). For `int` the caller adds `?? 0`,
    /// for `Integer` leaves `nil`.
    public func int(_ key: String) -> Int32? { decode(key, as: Int32.self) }

    /// A Java `double` field; the default `0.0` is added by the caller.
    public func double(_ key: String) -> Double? { decode(key, as: Double.self) }

    /// A Java `boolean`/`Boolean` field; for `boolean` the caller adds `?? false`.
    public func bool(_ key: String) -> Bool? { decode(key, as: Bool.self) }

    /// A Java `List<T>` field, see `YamlNode.list(of:)`.
    public func list<T: YamlDecodable>(_ key: String, of type: T.Type) -> [T?]? {
        decode(key) { $0.list(of: T.self) }
    }

    /// A Java `Map<String, T>` field, see `YamlNode.map(of:)`.
    public func map<T: YamlDecodable>(_ key: String, of type: T.Type) -> YamlOrderedMap<T>? {
        decode(key) { $0.map(of: T.self) }
    }
}

// MARK: - Ordered mapping

/// A Java `LinkedHashMap<String, V>` from YAML: keys in document order, the value
/// may be `null`. A duplicate key keeps its original position and the last value.
public struct YamlOrderedMap<Value> {
    public private(set) var keys: [String] = []
    private var storage: [String: Value?] = [:]

    public init() {}

    /// The value of a key like Java's `get`: a missing key and a `null` value give `nil`.
    public subscript(key: String) -> Value? { storage[key] ?? nil }

    /// Java's `containsKey` — true even for a key with a `null` value.
    public func containsKey(_ key: String) -> Bool { storage[key] != nil }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    /// Pairs in document order.
    public var pairs: [(key: String, value: Value?)] {
        keys.map { (key: $0, value: storage[$0] ?? nil) }
    }

    public mutating func set(_ key: String, _ value: Value?) {
        if storage.updateValue(value, forKey: key) == nil { keys.append(key) }
    }
}

extension YamlOrderedMap: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keys == rhs.keys && lhs.storage == rhs.storage
    }
}

extension YamlOrderedMap: Sendable where Value: Sendable {}

// MARK: - Scalar types

extension String: YamlDecodable {
    /// Jackson `StringDeserializer`: from a scalar `getText()` = the original spelling
    /// (`48` -> "48", `yes` -> "yes", `0x1` -> "0x1"); an error from a mapping and a sequence.
    public init?(yamlNode node: YamlNode) {
        guard let text = node.value.rawText else {
            node.typeMismatch("čeká se text, ne \(node.value.kindDescription)")
            return nil
        }
        self = text
    }
}

extension Int32: YamlDecodable {
    /// Jackson `_parseIntPrimitive` / `_parseInteger` (measured):
    /// - integer: outside the `int` range is an error at the **end** of the token,
    /// - decimal number: truncation towards zero (`1.9` -> 1, `-1.9` -> -1), outside the
    ///   `int` range an error at the end of the token,
    /// - text: empty or blank -> `nil`, otherwise Java `trim()`, `"null"` -> `nil`,
    ///   and then `Integer.parseInt` (sign, Unicode `Nd` digits from the BMP,
    ///   `"1.9"`/`"0x10"`/`"1_000"` are errors),
    /// - boolean, mapping, sequence: error.
    public init?(yamlNode node: YamlNode) {
        switch node.value {
        case .int(let value, _):
            guard let exact = Int32(exactly: value) else {
                node.typeMismatchAtEnd("číslo \(value) je mimo rozsah int")
                return nil
            }
            self = exact
        case .double(let value, let raw):
            guard value >= -2147483648.0, value <= 2147483647.0 else {
                node.typeMismatchAtEnd("číslo \(raw) je mimo rozsah int")
                return nil
            }
            self = Int32(value.rounded(.towardZero))
        case .string(let text):
            guard let parsed = JacksonCoercion.intFromText(text) else {
                node.typeMismatch("„\(text)\" není celé číslo")
                return nil
            }
            guard let value = parsed else { return nil }
            self = value
        default:
            node.typeMismatch("\(node.value.kindDescription) nejde převést na celé číslo")
            return nil
        }
    }
}

extension Double: YamlDecodable {
    /// Jackson `_parseDoublePrimitive` (measured): numbers directly; text via
    /// Java `Double.parseDouble` (`"1d"`, `"0x1p3"`, `"Infinity"` pass,
    /// `"inf"`, `"1_000"` do not) plus Jackson's `"INF"`/`"-INF"`/`"+INF"`;
    /// empty, blank or `"null"` text -> `nil`.
    public init?(yamlNode node: YamlNode) {
        switch node.value {
        case .double(let value, _):
            self = value
        case .int(let value, _):
            self = Double(value)
        case .string(let text):
            guard let parsed = JacksonCoercion.doubleFromText(text) else {
                node.typeMismatch("„\(text)\" není desetinné číslo")
                return nil
            }
            guard let value = parsed else { return nil }
            self = value
        default:
            node.typeMismatch("\(node.value.kindDescription) nejde převést na desetinné číslo")
            return nil
        }
    }
}

extension Bool: YamlDecodable {
    /// Jackson `_parseBooleanPrimitive` / `_parseBoolean` (measured):
    /// - YAML boolean (`yes`, `on`, `True`…) directly,
    /// - integer: non-zero -> `true` (`-1` too); a number that Jackson keeps
    ///   as `long` (a long hexadecimal/octal/binary spelling of zero)
    ///   is compared as **text** with "0", so `0x000000000` is `true`,
    /// - text: empty/blank -> `nil`, after Java `trim()` only `true`/`True`/`TRUE`
    ///   and `false`/`False`/`FALSE` (`"yes"`, `"1"` are errors), `"null"` -> `nil`,
    /// - decimal number, mapping, sequence: error.
    public init?(yamlNode node: YamlNode) {
        switch node.value {
        case .bool(let value, _):
            self = value
        case .int(let value, let raw):
            self = JacksonCoercion.isIntToken(raw) ? value != 0 : raw != "0"
        case .string(let text):
            if text.isEmpty { return nil }
            let trimmed = JavaText.trim(text)
            switch trimmed {
            case "true", "True", "TRUE": self = true
            case "false", "False", "FALSE": self = false
            case "", "null": return nil
            default:
                node.typeMismatch("„\(text)\" není logická hodnota (platí jen true/True/TRUE a false/False/FALSE)")
                return nil
            }
        default:
            node.typeMismatch("\(node.value.kindDescription) nejde převést na logickou hodnotu")
            return nil
        }
    }
}

// MARK: - Description of a value for messages

extension YamlValue {
    /// Kind of the value in Czech, for error messages.
    var kindDescription: String {
        switch self {
        case .null: return "null"
        case .bool(_, let raw): return "logická hodnota „\(raw)\""
        case .int(_, let raw): return "celé číslo „\(raw)\""
        case .double(_, let raw): return "desetinné číslo „\(raw)\""
        case .string(let text): return "text „\(text)\""
        case .sequence: return "sekvence"
        case .mapping: return "mapa"
        }
    }
}

// MARK: - Java text-to-number conversions

/// Text conversions as Jackson does them over the JDK. Swift `Int(_:)`
/// and `Double(_:)` are not used on user text — they accept other spellings
/// (`Int("٣")` is `nil`, Java 3; `Double("inf")` is infinity, Java an error).
enum JacksonCoercion {

    /// Jackson `int` from text: `nil` = error, `.some(nil)` = empty value
    /// (default `0` resp. `null`), `.some(n)` = number.
    static func intFromText(_ text: String) -> Int32?? {
        // Empty and blank text is an "empty value" (`_checkFromStringCoercion`),
        // `"null"` after trim too (`_hasTextualNull`).
        let trimmed = JavaText.trim(text)
        if trimmed.isEmpty || trimmed == "null" { return .some(nil) }
        // `StreamReadConstraints.validateIntegerLength`: over 1000 characters an error.
        guard trimmed.utf16.count <= 1000, let value = parseInt(trimmed) else { return nil }
        return .some(value)
    }

    /// Jackson `double` from text: `nil` = error, `.some(nil)` = empty value.
    static func doubleFromText(_ text: String) -> Double?? {
        // `_checkDoubleSpecialValue` goes **before** trim: `" INF"` does not pass any more.
        switch text {
        case "INF", "+INF", "Infinity", "+Infinity": return .some(.infinity)
        case "-INF", "-Infinity": return .some(-.infinity)
        case "NaN": return .some(.nan)
        default: break
        }
        let trimmed = JavaText.trim(text)
        if trimmed.isEmpty || trimmed == "null" { return .some(nil) }
        guard let value = parseDouble(trimmed) else { return nil }
        return .some(value)
    }

    /// Java `Integer.parseInt(s)` — the only implementation is `JavaInteger.parseInt`
    /// (sign, decimal Unicode `Nd` digits from the BMP, `int` range).
    static func parseInt(_ text: String) -> Int32? {
        JavaInteger.parseInt(text)
    }

    /// Java `Double.parseDouble` over already trimmed text — the only
    /// implementation is `JavaDouble.parseDouble` (`FloatingDecimal.readJavaFormatString`).
    static func parseDouble(_ text: String) -> Double? {
        JavaDouble.parseDouble(text)
    }

    /// Does Jackson keep a YAML integer as `int` (`JsonParser.NumberType.INT`)?
    ///
    /// It decides only for the conversion to `boolean`: an `int` is compared with zero,
    /// `long`/`BigInteger` as **text** with "0". According to `YAMLParser._decodeNumberScalar`
    /// and `_parseNumericValue`: binary notation up to 31 digits, octal up to 10
    /// and hexadecimal up to 7 is `int`; binary with 32 and hexadecimal with 8 digits
    /// is `int` only when the value fits (otherwise it is non-zero and the result
    /// does not depend on it); longer notation is always `long`. The difference is thus only for
    /// a long-written zero (`0x000000000` -> `true`, measured). Decimal notation does not
    /// start with zero, there a non-zero number is `true` either way.
    static func isIntToken(_ raw: String) -> Bool {
        var chars = Array(raw)
        if let first = chars.first, first == "-" || first == "+" { chars.removeFirst() }
        guard chars.count >= 2, chars[0] == "0" else { return true }
        let digits: Int
        let intDigits: Int
        let checkedDigits: Int?
        switch chars[1] {
        case "b", "B":
            digits = chars.dropFirst(2).filter { $0 != "_" }.count
            intDigits = 31
            checkedDigits = 32
        case "x", "X":
            digits = chars.dropFirst(2).filter { $0 != "_" }.count
            intDigits = 7
            checkedDigits = 8
        default:
            digits = chars.dropFirst(1).filter { $0 != "_" }.count
            intDigits = 10
            checkedDigits = nil
        }
        if digits <= intDigits { return true }
        // Boundary length: `int` if the value fits — it is then non-zero
        // or zero the same as the text, so `true` suffices for "fits".
        if digits == checkedDigits { return true }
        return false
    }
}
