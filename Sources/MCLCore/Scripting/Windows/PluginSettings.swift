import Foundation

/// What the operator decided about the window plugins, kept in `<data dir>/plugin-settings.json` (not in
/// `config.json`, so profiles and the JVM-era configuration are untouched): the permissions granted per plugin, the
/// plugins whose first-use consent was answered, the keys bound to plugin actions and the docked windows.
public struct PluginSettings: Codable, Equatable, Sendable {

    public static let fileName = "plugin-settings.json"

    /// Granted permissions by plugin id (only the ones that need a grant; `read` and `ui` never appear).
    public var grants: [String: [String]] = [:]
    /// Plugins whose consent sheet was answered (granted or not): it is not shown again.
    public var decided: [String] = []
    /// Key bindings: `<plugin>/<action>` → key text (`Ctrl+Alt+P`, the `KeyCombo` form).
    public var keys: [String: String] = [:]
    /// `<plugin>/<action>` whose key also keeps its own function in the entry window.
    public var passThrough: [String] = []
    /// Plugin window keys (`plugin:<plugin>/<window>`) docked into the main window.
    public var docked: [String] = []

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grants = try container.decodeIfPresent([String: [String]].self, forKey: .grants) ?? [:]
        decided = try container.decodeIfPresent([String].self, forKey: .decided) ?? []
        keys = try container.decodeIfPresent([String: String].self, forKey: .keys) ?? [:]
        passThrough = try container.decodeIfPresent([String].self, forKey: .passThrough) ?? []
        docked = try container.decodeIfPresent([String].self, forKey: .docked) ?? []
    }

    /// The permissions a plugin may use now: the implicit ones it asked for and the granted ones it asked for.
    public func effectivePermissions(_ manifest: PluginManifest) -> [String] {
        let granted: Set<String> = Set(grants[manifest.id] ?? [])
        return manifest.permissions.filter { PluginManifest.implicitPermissions.contains($0) || granted.contains($0) }
    }

    /// Whether the consent sheet is due: the plugin asks for permissions needing a grant and was never decided.
    public func needsConsent(_ manifest: PluginManifest) -> Bool {
        !manifest.permissionsNeedingGrant.isEmpty && !decided.contains(manifest.id)
    }

    public mutating func setGranted(_ plugin: String, _ permissions: [String]) {
        let allowed: [String] = permissions.filter { !PluginManifest.implicitPermissions.contains($0) }
        grants[plugin] = allowed.isEmpty ? nil : Array(Set(allowed)).sorted()
        // `spots.send` only together with `spots`.
        if let list = grants[plugin], list.contains("spots.send") && !list.contains("spots") {
            grants[plugin] = list.filter { $0 != "spots.send" }
        }
        if !decided.contains(plugin) {
            decided.append(plugin)
            decided.sort()
        }
    }

    public static func actionKey(plugin: String, action: String) -> String {
        plugin + "/" + action
    }

    // MARK: - file

    /// Reads the file; a missing or broken file gives empty settings. Blocking.
    public static func load(dataDir: URL) -> PluginSettings {
        let url: URL = dataDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(PluginSettings.self, from: data) else {
            return PluginSettings()
        }
        return settings
    }

    /// Writes the file atomically. Blocking.
    public func save(dataDir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data = try encoder.encode(self)
        try data.write(to: dataDir.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
