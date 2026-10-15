import Foundation

/// A saved window layout (N1MM Tools › Save / Restore Window Positions, also per operator): the open windows and
/// their geometry as `config.json` keeps them.
public struct WindowLayout: Codable, Equatable, Sendable {
    public var openWindows: [String]
    public var windowGeometry: [String: WindowGeometry]

    public init(openWindows: [String], windowGeometry: [String: WindowGeometry]) {
        self.openWindows = openWindows
        self.windowGeometry = windowGeometry
    }

    enum CodingKeys: String, CodingKey {
        case openWindows, windowGeometry
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openWindows = c.value(.openWindows, default: [])
        windowGeometry = c.value(.windowGeometry, default: [:])
    }

    /// The layout of a configuration now.
    public static func of(_ config: AppConfig) -> WindowLayout {
        WindowLayout(openWindows: config.openWindows, windowGeometry: config.windowGeometry)
    }

    /// The configuration with the layout's geometry over its own (a window the layout does not know keeps its place)
    /// and the layout's windows added to the open ones (none is closed), in the layout's order.
    public func applied(to config: AppConfig) -> AppConfig {
        var out: AppConfig = config
        out.windowGeometry.merge(windowGeometry) { _, saved in saved }
        for id in openWindows where !out.openWindows.contains(id) {
            out.openWindows.append(id)
        }
        return out
    }
}

/// The saved layouts: `<data>/layouts/<name>.json`. A name is trimmed; characters a file name cannot hold become
/// `_`. Every method touches the disk: call them off the main thread.
public struct WindowLayouts: Sendable {

    public static let dirName = "layouts"

    public let dir: URL

    public init(dataDir: URL) {
        dir = dataDir.appendingPathComponent(Self.dirName, isDirectory: true)
    }

    /// The file name of a layout name (`OK1ABC`, `Home/Field` → `Home_Field`); `nil` for a blank name.
    public static func fileName(_ name: String) -> String? {
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let safe = String(trimmed.map { "/:\\".contains($0) || $0.isNewline ? "_" : $0 })
        return (safe.hasPrefix(".") ? "_" + safe.dropFirst() : Substring(safe)) + ".json"
    }

    public func save(_ layout: WindowLayout, name: String) throws {
        guard let file = Self.fileName(name) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(layout).write(to: dir.appendingPathComponent(file), options: .atomic)
    }

    /// The layout of a name, `nil` = none saved.
    public func load(name: String) throws -> WindowLayout? {
        guard let file = Self.fileName(name) else { return nil }
        let url: URL = dir.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(WindowLayout.self, from: Data(contentsOf: url))
    }

    /// The saved names, sorted.
    public func names() throws -> [String] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
    }
}
