import Foundation

/// Loading and saving `AppConfig` to `config.json`. For a missing or
/// corrupt file it returns the default configuration — a corrupt file must not
/// crash the app. Mirrors `ConfigStore.java`.
public struct ConfigStore: Sendable {

    private let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    public func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
    }

    /// Serializes any value with the same encoder (for setup and station snapshots).
    public func toJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Best-effort deserialization; `nil` on empty or invalid input (never throws).
    public func fromJSON<T: Decodable>(_ json: String?, as type: T.Type) -> T? {
        guard let json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
