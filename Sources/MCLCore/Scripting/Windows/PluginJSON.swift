import Foundation

/// A JSON value of the window-plugin protocol (one line of `PluginWireProtocol`). Parsed with `JSONSerialization`
/// (strict UTF-8, no comments), written with the escapes of `WireJsonWriter`. Objects are written with their keys
/// sorted, so a written line is deterministic; `raw` embeds an already rendered value (the event payloads of
/// `PluginEventJson`, which keep their own key order).
public indirect enum PluginJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([PluginJSON])
    case object([String: PluginJSON])
    /// An already rendered JSON value (written as is, never produced by `parse`).
    case raw(String)

    public struct ParseError: Error, Equatable, Sendable {
        public let message: String
    }

    /// Parses one JSON document (any value at the top level).
    public static func parse(_ bytes: [UInt8]) throws(ParseError) -> PluginJSON {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])
        } catch {
            throw ParseError(message: "malformed JSON")
        }
        return from(object)
    }

    public static func parse(_ text: String) throws(ParseError) -> PluginJSON {
        try parse(Array(text.utf8))
    }

    private static func from(_ value: Any) -> PluginJSON {
        switch value {
        case let text as String:
            return .string(text)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if CFNumberIsFloatType(number) {
                return .double(number.doubleValue)
            }
            return .int(number.int64Value)
        case let list as [Any]:
            return .array(list.map(from))
        case let map as [String: Any]:
            return .object(map.mapValues(from))
        default:
            return .null
        }
    }

    // MARK: - access

    public subscript(key: String) -> PluginJSON? {
        if case .object(let map) = self {
            return map[key]
        }
        return nil
    }

    public var stringValue: String? {
        if case .string(let text) = self {
            return text
        }
        return nil
    }

    /// An integer, also from a whole double (`3.0`).
    public var intValue: Int64? {
        switch self {
        case .int(let number):
            return number
        case .double(let number) where number.rounded() == number && abs(number) < 9.0e15:
            return Int64(number)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let number):
            return Double(number)
        case .double(let number):
            return number
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let flag) = self {
            return flag
        }
        return nil
    }

    public var arrayValue: [PluginJSON]? {
        if case .array(let list) = self {
            return list
        }
        return nil
    }

    public var objectValue: [String: PluginJSON]? {
        if case .object(let map) = self {
            return map
        }
        return nil
    }

    // MARK: - writing

    /// One line of JSON (no newline inside: control characters are escaped).
    public func serialized() -> String {
        var writer = WireJsonWriter(escapeAstral: false)
        write(&writer)
        return String(decoding: writer.bytes, as: UTF8.self)
    }

    private func write(_ writer: inout WireJsonWriter) {
        switch self {
        case .null:
            writer.null()
        case .bool(let flag):
            writer.ascii(flag ? "true" : "false")
        case .int(let number):
            writer.ascii(String(number))
        case .double(let number):
            if number.isFinite {
                writer.ascii(number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number))
            } else {
                writer.null()
            }
        case .string(let text):
            writer.string(text)
        case .array(let list):
            writer.bytes.append(0x5B)
            for (index, item) in list.enumerated() {
                if index > 0 {
                    writer.bytes.append(0x2C)
                }
                item.write(&writer)
            }
            writer.bytes.append(0x5D)
        case .object(let map):
            writer.bytes.append(0x7B)
            for (index, key) in map.keys.sorted().enumerated() {
                if index > 0 {
                    writer.bytes.append(0x2C)
                }
                writer.string(key)
                writer.bytes.append(0x3A)
                map[key]?.write(&writer)
            }
            writer.bytes.append(0x7D)
        case .raw(let json):
            writer.bytes += Array(json.utf8)
        }
    }
}

extension PluginJSON {
    /// A text or `null`.
    public static func optional(_ text: String?) -> PluginJSON {
        text.map { .string($0) } ?? .null
    }
}
