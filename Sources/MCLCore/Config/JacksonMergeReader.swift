import Foundation

/// A JSON tree of a configuration (what `JSONEncoder` writes for `AppConfig` and what `ConfigStore.load` reads).
indirect enum ProfileJson: Equatable, Sendable, Encodable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([ProfileJson])
    case object([String: ProfileJson])

    /// Parses JSON text (as `JSONEncoder` writes it) with the Jackson parser port — much faster than decoding
    /// this enum with `JSONDecoder`. `nil` for invalid input.
    static func parse(_ data: Data) -> ProfileJson? {
        let parser = JacksonUtf8Parser(data)
        guard (try? parser.nextToken()) != nil else { return nil }
        return try? parseValue(parser)
    }

    private static func parseValue(_ parser: JacksonUtf8Parser) throws(JacksonFailure) -> ProfileJson {
        switch parser.currentToken {
        case .startObject:
            var fields: [String: ProfileJson] = [:]
            while let name = try parser.nextFieldName() {
                try parser.nextToken()
                fields[name] = try parseValue(parser)
            }
            return .object(fields)
        case .startArray:
            var items: [ProfileJson] = []
            while try parser.nextToken() != .endArray {
                items.append(try parseValue(parser))
            }
            return .array(items)
        case .string:
            return .string(try parser.getText() ?? "")
        case .numberInt:
            if let value = Int64(try parser.getText() ?? "") {
                return .int(value)
            }
            return .double(parser.doubleValue)
        case .numberFloat:
            return .double(parser.doubleValue)
        case .valueTrue:
            return .bool(true)
        case .valueFalse:
            return .bool(false)
        default:
            return .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The tree as Swift can decode it: a `null` (in an object, a map or a list) is dropped — Swift's
    /// configuration types hold no `null`, and a dropped key decodes to the field default just like `null` —, and
    /// a non-finite `double` is written as Jackson's string (`NaN`, `Infinity`, `-Infinity`), which
    /// `ProfileMerge.decode` reads back as the number.
    var decodable: ProfileJson {
        switch self {
        case .array(let items):
            return .array(items.compactMap { $0.decodableOrDropped })
        case .object(let fields):
            return .object(fields.compactMapValues { $0.decodableOrDropped })
        default:
            return self
        }
    }

    private var decodableOrDropped: ProfileJson? {
        switch self {
        case .null:
            return nil
        case .double(let value):
            if value.isNaN {
                return .string("NaN")
            }
            if value.isInfinite {
                return .string(value < 0 ? "-Infinity" : "Infinity")
            }
            return self
        default:
            return decodable
        }
    }
}

/// A port of the Jackson 2.22 data binding that `ConfigProfiles.loadInto` runs (`readerForUpdating(config)`
/// with `setDefaultMergeable(true)` and non-mergeable `List`/`Map`), over the streaming `JacksonUtf8Parser` and
/// the generated `ProfileMergeSchema`. The target is the JSON tree of the current configuration, changed in
/// place exactly where Jackson changes the Java object (also before an exception).
///
/// Ported paths (default features, measured by the probe): `ObjectReader._bindAndClose`,
/// `BeanDeserializer.deserialize` with and without an instance to update, `MergingSettableBeanProperty`,
/// `CollectionDeserializer`, `StringCollectionDeserializer`, `MapDeserializer` (string keys), `StringDeserializer`,
/// the primitive `int`/`long`/`double`/`boolean` and boxed `Integer` coercions of `StdDeserializer`,
/// `EnumDeserializer`, and the messages of `DeserializationContext` and `PropertyBindingException`.
final class JacksonMergeReader {

    private let parser: JacksonUtf8Parser
    private let rootDefaults: [String: ProfileJson]
    private let classes: [String: ProfileMergeSchema.BeanClass]

    init(data: Data, rootDefaults: [String: ProfileJson],
         classes: [String: ProfileMergeSchema.BeanClass] = ProfileMergeSchema.classes) {
        parser = JacksonUtf8Parser(data)
        self.rootDefaults = rootDefaults
        self.classes = classes
    }

    /// `ObjectReader._bindAndClose(p)` with a value to update.
    func mergeRoot(into root: inout [String: ProfileJson]) throws(JacksonFailure) {
        guard let token = try parser.nextToken() else {
            throw JacksonFailure(javaClass: JacksonFailure.mismatchedInputException,
                                 originalMessage: "No content to map due to end-of-input",
                                 location: parser.tokenLocation)
        }
        if token == .valueNull || token == .endArray || token == .endObject {
            return
        }
        guard let rootClass = classes[ProfileMergeSchema.root] else { return }
        try mergeBean(rootClass, into: &root, defaults: rootDefaults)
    }

    // MARK: - Beans

    /// `BeanDeserializer.deserialize(p, ctxt, bean)`: anything but an object leaves the bean as it is (an array is
    /// not even consumed — the caller then continues inside it).
    private func mergeBean(_ bean: ProfileMergeSchema.BeanClass, into fields: inout [String: ProfileJson],
                           defaults: [String: ProfileJson]?) throws(JacksonFailure) {
        let first: String?
        if parser.currentToken == .startObject {
            first = try parser.nextFieldName()
        } else if parser.currentToken == .fieldName {
            first = parser.currentName
        } else {
            return
        }
        try bindFields(bean, first: first, into: &fields, defaults: defaults)
    }

    /// `BeanDeserializer.deserialize(p, ctxt)`: a new instance.
    private func freshBean(_ bean: ProfileMergeSchema.BeanClass) throws(JacksonFailure) -> ProfileJson {
        guard let token = parser.currentToken else { throw unexpectedToken(bean.name) }
        var fields: [String: ProfileJson] = [:]
        switch token {
        case .startObject:
            if try parser.nextToken() == .fieldName {
                try bindFields(bean, first: parser.currentName, into: &fields, defaults: nil)
            }
            return .object(fields)
        case .fieldName:
            try bindFields(bean, first: parser.currentName, into: &fields, defaults: nil)
            return .object(fields)
        case .endObject:
            return .object(fields)
        case .string:
            throw try beanFromString(bean.name, coercedType: "`" + bean.name + "` value")
        case .numberInt:
            throw beanFromNumber(bean.name)
        case .numberFloat:
            let value: String = JavaDouble.toString(parser.doubleValue)
            throw missingInstantiator(bean.name, "no double/Double-argument constructor/factory method to"
                                      + " deserialize from Number value (" + value + ")")
        case .valueTrue, .valueFalse:
            let value: String = token == .valueTrue ? "true" : "false"
            throw missingInstantiator(bean.name, "no boolean/Boolean-argument constructor/factory method to"
                                      + " deserialize from boolean value (" + value + ")")
        case .valueNull:
            return .null
        default:
            throw unexpectedToken(bean.name)
        }
    }

    /// The property loop of `BeanDeserializer` (`vanillaDeserialize` / `deserialize(p, ctxt, bean)`).
    private func bindFields(_ bean: ProfileMergeSchema.BeanClass, first: String?,
                            into fields: inout [String: ProfileJson],
                            defaults: [String: ProfileJson]?) throws(JacksonFailure) {
        var name: String? = first
        while let field = name {
            try parser.nextToken()
            guard let property = bean.property(field) else {
                throw unrecognized(bean, field)
            }
            do {
                try set(property, in: &fields, defaults: defaults)
            } catch {
                throw error.wrapped(JacksonFailure.reference(bean.name, field: field))
            }
            name = try parser.nextFieldName()
        }
    }

    /// `SettableBeanProperty.deserializeAndSet` (merging for bean-typed properties).
    private func set(_ property: ProfileMergeSchema.Property, in fields: inout [String: ProfileJson],
                     defaults: [String: ProfileJson]?) throws(JacksonFailure) {
        if parser.currentToken == .valueNull {
            try setNull(property, in: &fields)
            return
        }
        guard case .bean(let beanName) = property.kind,
              let bean = classes[beanName] else {
            fields[property.name] = try value(property.kind)
            return
        }
        let current: ProfileJson = fields[property.name] ?? defaults?[property.name] ?? .object([:])
        guard case .object(var merged) = current else {
            fields[property.name] = try freshBean(bean)
            return
        }
        defer { fields[property.name] = .object(merged) }
        try mergeBean(bean, into: &merged, defaults: nil)
    }

    private func setNull(_ property: ProfileMergeSchema.Property,
                         in fields: inout [String: ProfileJson]) throws(JacksonFailure) {
        switch property.onNull {
        case .null:
            fields[property.name] = .null
        case .fieldDefault:
            fields[property.name] = nil
        case .value(let value):
            fields[property.name] = value
        case .throwsNullPointer:
            // `MethodProperty._throwAsIOE`: a `NullPointerException` without a message.
            throw JacksonFailure(javaClass: JacksonFailure.mappingException, originalMessage: nil,
                                 location: parser.tokenLocation)
        }
    }

    // MARK: - Values

    /// The value deserializer of a property type, at a non-`null` token.
    private func value(_ kind: ProfileMergeSchema.Kind) throws(JacksonFailure) -> ProfileJson {
        switch kind {
        case .string:
            return try stringValue()
        case .int:
            return .int(Int64(try intValue(boxed: false) ?? 0))
        case .integer:
            guard let value = try intValue(boxed: true) else { return .null }
            return .int(Int64(value))
        case .long:
            return .int(try longValue())
        case .double:
            return .double(try doubleValue())
        case .boolean:
            return .bool(try boolValue())
        case .enumeration(let name):
            return .string(try enumValue(name))
        case .bean(let name):
            guard let bean = classes[name] else { throw unexpectedToken(name) }
            return try freshBean(bean)
        case .list(let element):
            return try listValue(element)
        case .map(let element):
            return try mapValue(element)
        }
    }

    /// `StringDeserializer` (`_parseString`): scalars as their text, objects and arrays are errors.
    private func stringValue() throws(JacksonFailure) -> ProfileJson {
        switch parser.currentToken {
        case .string, .numberInt, .numberFloat, .valueTrue, .valueFalse:
            return .string(try parser.getText() ?? "")
        default:
            throw unexpectedToken("java.lang.String")
        }
    }

    /// `_parseIntPrimitive` (`int`) and `_parseInteger` (`Integer`, where an empty or textual null is `null`).
    private func intValue(boxed: Bool) throws(JacksonFailure) -> Int32? {
        let type: String = boxed ? "java.lang.Integer" : "int"
        switch parser.currentToken {
        case .numberInt, .numberFloat:
            return try parser.intValue()
        case .string:
            let raw: String = try parser.getText() ?? ""
            guard let text = coercibleText(raw) else { return boxed ? nil : 0 }
            if text.utf16.count > 9 {
                if let failure = JacksonFailure.numberLength(text.utf16.count) {
                    throw failure
                }
                guard let wide = try? JavaInteger.parseLong(text) else {
                    throw weirdString(type, text, "not a valid `" + type + "` value")
                }
                guard let value = Int32(exactly: wide) else {
                    let range: String = boxed ? "`java.lang.Integer`" : "int"
                    throw weirdString(type, text, "Overflow: numeric value (" + text + ") out of range of " + range
                                      + " (-2147483648 -2147483647)")
                }
                return value
            }
            guard let value = JavaInteger.parseInt(text) else {
                throw weirdString(type, text, "not a valid `" + type + "` value")
            }
            return value
        default:
            throw unexpectedToken(type)
        }
    }

    /// `_parseLongPrimitive`.
    private func longValue() throws(JacksonFailure) -> Int64 {
        switch parser.currentToken {
        case .numberInt, .numberFloat:
            return try parser.longValue()
        case .string:
            let raw: String = try parser.getText() ?? ""
            guard let text = coercibleText(raw) else { return 0 }
            if let failure = JacksonFailure.numberLength(text.utf16.count) {
                throw failure
            }
            guard let value = try? JavaInteger.parseLong(text) else {
                throw weirdString("long", text, "not a valid `long` value")
            }
            return value
        default:
            throw unexpectedToken("long")
        }
    }

    /// `_parseDoublePrimitive`: the textual `NaN` and infinities come before the coercion rules.
    private func doubleValue() throws(JacksonFailure) -> Double {
        switch parser.currentToken {
        case .numberInt, .numberFloat:
            return parser.doubleValue
        case .string:
            let raw: String = try parser.getText() ?? ""
            switch raw {
            case "NaN": return .nan
            case "Infinity", "INF", "+Infinity", "+INF": return .infinity
            case "-Infinity", "-INF": return -.infinity
            default: break
            }
            guard let text = coercibleText(raw) else { return 0 }
            guard let value = JavaDouble.parseDouble(text) else {
                throw weirdString("double", text, "not a valid `double` value (as String to convert)")
            }
            return value
        default:
            throw unexpectedToken("double")
        }
    }

    /// `_parseBooleanPrimitive` (an integer is `!= 0`, a big one compared as text with `"0"`).
    private func boolValue() throws(JacksonFailure) -> Bool {
        switch parser.currentToken {
        case .valueTrue:
            return true
        case .valueFalse:
            return false
        case .numberInt:
            if parser.numberType == .int {
                return try parser.intValue() != 0
            }
            return try parser.getText() != "0"
        case .string:
            let raw: String = try parser.getText() ?? ""
            guard let text = coercibleText(raw) else { return false }
            if text == "true" || text == "True" || text == "TRUE" {
                return true
            }
            if text == "false" || text == "False" || text == "FALSE" {
                return false
            }
            throw weirdString("boolean", text,
                              "only \"true\"/\"True\"/\"TRUE\" or \"false\"/\"False\"/\"FALSE\" recognized")
        default:
            throw unexpectedToken("boolean")
        }
    }

    /// `EnumDeserializer` (exact name, trimmed name, a quoted index, an integer index).
    private func enumValue(_ name: String) throws(JacksonFailure) -> String {
        let type: ProfileMergeSchema.EnumType = ProfileMergeSchema.enums[name]
            ?? ProfileMergeSchema.EnumType(constants: [], keys: [])
        switch parser.currentToken {
        case .string:
            let text: String = try parser.getText() ?? ""
            if type.constants.contains(text) {
                return text
            }
            let trimmed: String = JavaText.trim(text)
            if trimmed != text, type.constants.contains(trimmed) {
                return trimmed
            }
            if trimmed.isEmpty {
                throw emptyCoercion("`" + name + "` value")
            }
            let first: UInt16 = trimmed.utf16.first ?? 0
            let leadingZero: Bool = first == 0x30 && trimmed.utf16.count > 1
            if first >= 0x30, first <= 0x39, !leadingZero, let index = JavaInteger.parseInt(trimmed),
               index >= 0, Int(index) < type.constants.count {
                return type.constants[Int(index)]
            }
            throw weirdString(name, trimmed, "not one of the values accepted for Enum class: ["
                              + type.keys.joined(separator: ", ") + "]")
        case .numberInt:
            let index: Int32 = try parser.intValue()
            if index >= 0, Int(index) < type.constants.count {
                return type.constants[Int(index)]
            }
            let message: String = "Cannot deserialize value of type `" + name + "` from number " + String(index)
                + ": index value outside legal index range [0.." + String(type.constants.count - 1) + "]"
            throw JacksonFailure(javaClass: JacksonFailure.invalidFormatException, originalMessage: message,
                                 location: parser.tokenLocation)
        default:
            throw unexpectedToken(name)
        }
    }

    // MARK: - Collections

    /// `CollectionDeserializer` (bean elements) and `StringCollectionDeserializer` (`String` elements).
    private func listValue(_ element: ProfileMergeSchema.Kind) throws(JacksonFailure) -> ProfileJson {
        let containerType: String = ProfileMergeSchema.Kind.list(element).javaType
        guard parser.currentToken == .startArray else {
            if parser.currentToken == .string {
                _ = try parser.getText()
                if element == .string {
                    throw try beanFromString("java.util.ArrayList", coercedType: "element of `java.util.ArrayList`")
                }
            }
            throw unexpectedToken(containerType)
        }
        var items: [ProfileJson] = []
        if element == .string {
            // `StringCollectionDeserializer`: the read of the next element is inside the wrapping `try`.
            while true {
                do {
                    let token: JacksonUtf8Parser.Token? = try parser.nextToken()
                    if token == .endArray {
                        break
                    }
                    items.append(token == .valueNull ? .null : try stringValue())
                } catch {
                    throw error.wrapped(JacksonFailure.reference("java.util.ArrayList", index: items.count))
                }
            }
            return .array(items)
        }
        while true {
            let token: JacksonUtf8Parser.Token? = try parser.nextToken()
            if token == .endArray {
                break
            }
            do {
                items.append(token == .valueNull ? .null : try value(element))
            } catch {
                throw error.wrapped(JacksonFailure.reference("java.util.ArrayList", index: items.count))
            }
        }
        return .array(items)
    }

    /// `MapDeserializer._readAndBindStringKeyMap` (reading the next key is outside the wrapping `try`; only a mapping
    /// exception gets the key in its reference chain).
    private func mapValue(_ element: ProfileMergeSchema.Kind) throws(JacksonFailure) -> ProfileJson {
        var entries: [String: ProfileJson] = [:]
        var key: String?
        switch parser.currentToken {
        case .startObject:
            key = try parser.nextFieldName()
        case .fieldName:
            key = parser.currentName
        case .endObject:
            return .object(entries)
        case .string:
            throw try beanFromString("java.util.LinkedHashMap", coercedType: "element of `java.util.LinkedHashMap`")
        default:
            throw unexpectedToken(ProfileMergeSchema.Kind.map(element).javaType)
        }
        while let name = key {
            let token: JacksonUtf8Parser.Token? = try parser.nextToken()
            do {
                entries[name] = token == .valueNull ? .null : try value(element)
            } catch {
                // `ContainerDeserializerBase.wrapAndThrow`: a parser exception passes unwrapped.
                guard error.isMapping else { throw error }
                throw error.wrapped(JacksonFailure.reference("java.util.LinkedHashMap", field: name))
            }
            key = try parser.nextFieldName()
        }
        return .object(entries)
    }

    // MARK: - Messages

    /// `_checkFromStringCoercion` + `trim()` + `_hasTextualNull`: `nil` for an empty, blank or `"null"` text.
    private func coercibleText(_ raw: String) -> String? {
        if raw.utf16.allSatisfy({ $0 <= 0x20 }) {
            return nil
        }
        let text: String = JavaText.trim(raw)
        return text == "null" ? nil : text
    }

    /// `StdDeserializer._deserializeFromString` of a type without a String creator (a bean, `ArrayList`,
    /// `LinkedHashMap`).
    private func beanFromString(_ className: String, coercedType: String) throws(JacksonFailure) -> JacksonFailure {
        let value: String = try parser.valueAsString() ?? ""
        if value.utf16.allSatisfy({ $0 <= 0x20 }) {
            return emptyCoercion(coercedType)
        }
        return missingInstantiator(className, "no String-argument constructor/factory method to deserialize from"
                                   + " String value ('" + JavaText.trim(value) + "')")
    }

    private func beanFromNumber(_ className: String) -> JacksonFailure {
        let value: String
        let argument: String
        switch parser.numberType {
        case .int:
            value = String((try? parser.intValue()) ?? 0)
            argument = "int/Int"
        case .long:
            value = String((try? parser.longValue()) ?? 0)
            argument = "long/Long"
        default:
            value = (try? parser.getText()) ?? ""
            argument = "BigInteger"
        }
        return missingInstantiator(className, "no " + argument + "-argument constructor/factory method to"
                                   + " deserialize from Number value (" + value + ")")
    }

    private func missingInstantiator(_ className: String, _ message: String) -> JacksonFailure {
        let text: String = "Cannot construct instance of `" + className + "` (although at least one Creator exists): "
            + message
        return JacksonFailure(javaClass: JacksonFailure.mismatchedInputException, originalMessage: text,
                              location: parser.tokenLocation)
    }

    private func emptyCoercion(_ coercedType: String) -> JacksonFailure {
        let text: String = "Cannot coerce empty String (\"\") to " + coercedType
            + " (but could if coercion was enabled using `CoercionConfig`)"
        return JacksonFailure(javaClass: JacksonFailure.invalidFormatException, originalMessage: text,
                              location: parser.tokenLocation)
    }

    /// `DeserializationContext.weirdStringException`.
    private func weirdString(_ type: String, _ value: String, _ message: String) -> JacksonFailure {
        let text: String = "Cannot deserialize value of type `" + type + "` from String \"" + Self.truncated(value)
            + "\": " + message
        return JacksonFailure(javaClass: JacksonFailure.invalidFormatException, originalMessage: text,
                              location: parser.tokenLocation)
    }

    /// `DeserializationContext.handleUnexpectedToken` (a scalar's text is read first, finishing a string).
    private func unexpectedToken(_ type: String) -> JacksonFailure {
        guard let token = parser.currentToken else {
            return JacksonFailure(javaClass: JacksonFailure.mismatchedInputException,
                                  originalMessage: "Unexpected end-of-input when trying read value of type `" + type
                                    + "`", location: parser.tokenLocation)
        }
        if token.isScalarValue {
            do {
                _ = try parser.getText()
            } catch {
                return error
            }
        }
        let text: String = "Cannot deserialize value of type `" + type + "` from " + Self.shape(token)
            + " (token `JsonToken." + token.javaName + "`)"
        return JacksonFailure(javaClass: JacksonFailure.mismatchedInputException, originalMessage: text,
                              location: parser.tokenLocation)
    }

    /// `UnrecognizedPropertyException.from` with `PropertyBindingException.getMessageSuffix()`.
    private func unrecognized(_ bean: ProfileMergeSchema.BeanClass, _ field: String) -> JacksonFailure {
        let text: String = "Unrecognized field \"" + field + "\" (class " + bean.name + "), not marked as ignorable"
        var suffix: String
        if bean.known.count == 1 {
            suffix = " (one known property: \"" + bean.known[0] + "\""
        } else {
            suffix = " (" + String(bean.known.count) + " known properties: "
            for (index, name) in bean.known.enumerated() {
                suffix += "\"" + name + "\""
                if suffix.utf16.count > 1000 {
                    suffix += " [truncated]"
                    break
                }
                if index < bean.known.count - 1 {
                    suffix += ", "
                }
            }
        }
        suffix += ")"
        return JacksonFailure(javaClass: JacksonFailure.unrecognizedPropertyException, originalMessage: text,
                              suffix: suffix, location: parser.currentLocation,
                              path: [JacksonFailure.reference(bean.name, field: field)])
    }

    /// `JsonToken.valueDescFor`.
    private static func shape(_ token: JacksonUtf8Parser.Token) -> String {
        switch token {
        case .startObject, .endObject, .fieldName: return "Object value"
        case .startArray, .endArray: return "Array value"
        case .valueTrue, .valueFalse: return "Boolean value"
        case .numberFloat: return "Floating-point value"
        case .numberInt: return "Integer value"
        case .string: return "String value"
        case .valueNull: return "Null value"
        }
    }

    /// `DatabindContext._truncate`: over 500 UTF-16 units the first and last 500 around `]...[`.
    private static func truncated(_ text: String) -> String {
        let units: [UInt16] = Array(text.utf16)
        guard units.count > 500 else { return text }
        let head: String = String(decoding: units[0..<500], as: UTF16.self)
        let tail: String = String(decoding: units[(units.count - 500)...], as: UTF16.self)
        return head + "]...[" + tail
    }
}
