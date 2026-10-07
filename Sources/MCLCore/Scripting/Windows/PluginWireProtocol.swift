import Foundation

/// Splits a byte stream into JSON lines (`\n`, an optional `\r` before it is dropped; blank lines are skipped). A
/// line longer than `maxLineBytes` is dropped whole — up to its newline — and reported once.
public struct PluginLineFramer: Sendable {

    /// The longest line accepted (1 MiB).
    public static let maxLineBytes = 1 << 20

    public enum Output: Equatable, Sendable {
        case line([UInt8])
        /// A line over the limit was dropped.
        case overflow
    }

    private let limit: Int
    private var pending: [UInt8] = []
    private var dropping = false

    public init(limit: Int = PluginLineFramer.maxLineBytes) {
        self.limit = limit
    }

    public mutating func feed(_ bytes: [UInt8]) -> [Output] {
        var out: [Output] = []
        var start: Int = 0
        while start < bytes.count {
            guard let newline = bytes[start...].firstIndex(of: 0x0A) else {
                append(bytes[start...], into: &out)
                break
            }
            append(bytes[start..<newline], into: &out)
            if dropping {
                dropping = false
            } else {
                emit(into: &out)
            }
            pending.removeAll(keepingCapacity: true)
            start = newline + 1
        }
        return out
    }

    /// The end of the stream: an unfinished last line still counts.
    public mutating func finish() -> [Output] {
        var out: [Output] = []
        if !dropping {
            emit(into: &out)
        }
        pending.removeAll()
        dropping = false
        return out
    }

    private mutating func append(_ slice: ArraySlice<UInt8>, into out: inout [Output]) {
        guard !dropping else { return }
        if pending.count + slice.count > limit {
            pending.removeAll()
            dropping = true
            out.append(.overflow)
            return
        }
        pending += slice
    }

    private mutating func emit(into out: inout [Output]) {
        var line: [UInt8] = pending
        if line.last == 0x0D {
            line.removeLast()
        }
        if line.contains(where: { $0 != 0x20 && $0 != 0x09 }) {
            out.append(.line(line))
        }
    }
}

/// A message a window plugin sends (protocol 1).
public enum PluginInbound: Equatable, Sendable {
    /// The answer to `hello` (any first message counts as one).
    case ready
    /// Replaces the content of a window.
    case set(window: String, content: PluginUIContent)
    /// A request (`method` with `params`); answered by a `response` with the same `id`.
    case request(id: PluginJSON, method: String, params: [String: PluginJSON])
    /// A line for the messages window.
    case log(String)
    /// A message type this version does not know (ignored, reported once).
    case unknown(String)

    /// Decodes one line. A line that is not a JSON object with a `type`, or a known type with missing fields, is
    /// an error (the line is ignored and reported).
    public static func decode(_ line: [UInt8]) throws(PluginJSON.ParseError) -> PluginInbound {
        // `JSONSerialization` rejects a line that is not UTF-8.
        let json: PluginJSON = try PluginJSON.parse(line)
        guard let type = json["type"]?.stringValue else {
            throw PluginJSON.ParseError(message: "a message without a type")
        }
        switch type {
        case "ready":
            return .ready
        case "set":
            guard let window = json["window"]?.stringValue, let content = json["content"] else {
                throw PluginJSON.ParseError(message: "set needs window and content")
            }
            return .set(window: window, content: try PluginUIContent.parse(content))
        case "request":
            guard let id = json["id"], id.stringValue != nil || id.intValue != nil else {
                throw PluginJSON.ParseError(message: "request needs a number or text id")
            }
            guard let method = json["method"]?.stringValue else {
                throw PluginJSON.ParseError(message: "request needs a method")
            }
            return .request(id: id, method: method, params: json["params"]?.objectValue ?? [:])
        case "log":
            return .log(json["text"]?.stringValue ?? "")
        default:
            return .unknown(type)
        }
    }
}

/// The lines the app sends a window plugin (protocol 1). Each is one line of JSON without the newline.
public enum PluginOutbound {

    public struct Hello: Equatable, Sendable {
        public var appVersion: String?
        public var contestId: String?
        public var contestName: String?
        public var band: String?
        public var mode: String?
        public var windows: [String]
        public var permissions: [String]

        public init(appVersion: String?, contestId: String?, contestName: String?, band: String?, mode: String?,
                    windows: [String], permissions: [String]) {
            self.appVersion = appVersion
            self.contestId = contestId
            self.contestName = contestName
            self.band = band
            self.mode = mode
            self.windows = windows
            self.permissions = permissions
        }
    }

    public static func hello(_ hello: Hello) -> String {
        let contest: PluginJSON = hello.contestId.map { id in
            .object(["id": .string(id), "name": .optional(hello.contestName)])
        } ?? .null
        return PluginJSON.object([
            "type": .string("hello"), "protocol": .int(PluginManifest.protocolVersion),
            "app": .object(["version": .optional(hello.appVersion)]), "contest": contest,
            "band": .optional(hello.band), "mode": .optional(hello.mode),
            "windows": .array(hello.windows.map { .string($0) }),
            "permissions": .array(hello.permissions.map { .string($0) }),
        ]).serialized()
    }

    /// An event in its directory form with the payload of `PluginEventJson`.
    public static func event(_ name: String, json: String) -> String {
        PluginJSON.object(["type": .string("event"), "event": .string(name), "data": .raw(json)]).serialized()
    }

    /// An interaction in a window: `click`, `double-click` (table rows, list items, buttons), `change` (a toggle,
    /// with `value`), `select` (a tab, `target` = the tabs id, `value` = the tab id).
    public static func ui(window: String, action: String, target: String, row: Int? = nil, rowId: String? = nil,
                          value: PluginJSON? = nil) -> String {
        var fields: [String: PluginJSON] = [
            "type": .string("ui"), "window": .string(window), "action": .string(action), "target": .string(target),
        ]
        if let row {
            fields["row"] = .int(Int64(row))
            fields["rowId"] = .optional(rowId)
        }
        if let value {
            fields["value"] = value
        }
        return PluginJSON.object(fields).serialized()
    }

    /// A key bound to one of the plugin's actions was pressed (Settings → Keys).
    public static func key(action: String) -> String {
        PluginJSON.object(["type": .string("key"), "action": .string(action), "phase": .string("press")]).serialized()
    }

    public static func response(id: PluginJSON, result: PluginJSON) -> String {
        PluginJSON.object(["type": .string("response"), "id": id, "result": result]).serialized()
    }

    public static func error(id: PluginJSON, code: String, message: String) -> String {
        PluginJSON.object([
            "type": .string("response"), "id": id,
            "error": .object(["code": .string(code), "message": .string(message)]),
        ]).serialized()
    }
}
