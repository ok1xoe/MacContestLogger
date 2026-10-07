import Foundation

/// What the operator decided about the window plugins, kept in `<data dir>/plugin-settings.json` (not in
/// `config.json`, so profiles and the JVM-era configuration are untouched): the permissions granted per plugin, the
/// plugins whose first-use consent was answered, the keys bound to plugin actions and the docked windows.
public struct PluginSettings: Codable, Equatable, Sendable {

    public static let fileName = "plugin-settings.json"

    /// Granted permissions by plugin identity (`identity(_:)`: the directory and the manifest's name, so another
    /// plugin put into the same directory does not inherit them). Only permissions that need a grant appear.
    public var grants: [String: [String]] = [:]
    /// The permissions the operator decided on (granted or not), by plugin identity: the consent asks only for the
    /// ones not decided yet (a manifest that grows asks again for the new ones).
    public var decidedPermissions: [String: [String]] = [:]
    /// Key bindings: `<plugin>/<action>` → key text (`Ctrl+Alt+P`, the `KeyCombo` form).
    public var keys: [String: String] = [:]
    /// `<plugin>/<action>` whose key also keeps its own function in the entry window.
    public var passThrough: [String] = []
    /// Plugin window keys (`plugin:<plugin>/<window>`) docked into the main window.
    public var docked: [String] = []
    /// A plugin's PTT is released after this many seconds however the plugin behaves (5–300).
    public var pttTimeoutSeconds: Int = PluginSettings.defaultPttTimeoutSeconds

    public static let defaultPttTimeoutSeconds = 30
    /// A message (CW, voice, F-key) a plugin started is cut after this many seconds (5–300).
    public var messageLimitSeconds: Int = 60
    /// Plugins together may be on the air at most this share of any 5 minutes (10–100 %).
    public var dutyPercent: Int = 50

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grants = try container.decodeIfPresent([String: [String]].self, forKey: .grants) ?? [:]
        decidedPermissions = try container.decodeIfPresent([String: [String]].self, forKey: .decidedPermissions)
            ?? [:]
        keys = try container.decodeIfPresent([String: String].self, forKey: .keys) ?? [:]
        passThrough = try container.decodeIfPresent([String].self, forKey: .passThrough) ?? []
        docked = try container.decodeIfPresent([String].self, forKey: .docked) ?? []
        let timeout: Int = try container.decodeIfPresent(Int.self, forKey: .pttTimeoutSeconds)
            ?? Self.defaultPttTimeoutSeconds
        pttTimeoutSeconds = min(max(timeout, 5), 300)
        messageLimitSeconds = min(max(try container.decodeIfPresent(Int.self, forKey: .messageLimitSeconds) ?? 60, 5), 300)
        dutyPercent = min(max(try container.decodeIfPresent(Int.self, forKey: .dutyPercent) ?? 50, 10), 100)
    }

    /// The key of a plugin's grants: its directory and its manifest name.
    public static func identity(_ manifest: PluginManifest) -> String {
        manifest.id + "|" + manifest.name
    }

    /// The permissions a plugin may use now: the implicit ones it asked for and the granted ones it asked for.
    public func effectivePermissions(_ manifest: PluginManifest) -> [String] {
        let granted: Set<String> = Set(grants[Self.identity(manifest)] ?? [])
        return manifest.permissions.filter { PluginManifest.implicitPermissions.contains($0) || granted.contains($0) }
    }

    /// The requested permissions needing a grant that were never decided (the consent asks for these).
    public func undecided(_ manifest: PluginManifest) -> [String] {
        let decided: Set<String> = Set(decidedPermissions[Self.identity(manifest)] ?? [])
        return manifest.permissionsNeedingGrant.filter { !decided.contains($0) }
    }

    /// Whether the consent is due: some requested permission needing a grant was never decided.
    public func needsConsent(_ manifest: PluginManifest) -> Bool {
        !undecided(manifest).isEmpty
    }

    /// Records a decision: `granted` (limited to what the manifest asks for and needs a grant) for the permissions
    /// `decided` (the ones the operator saw); a permission decided now and not granted is revoked.
    public mutating func decide(_ manifest: PluginManifest, granted: [String], decided: [String]) {
        let identity: String = Self.identity(manifest)
        let asked: Set<String> = Set(manifest.permissionsNeedingGrant)
        let seen: Set<String> = Set(decided).intersection(asked)
        var current: Set<String> = Set(grants[identity] ?? []).intersection(asked)
        current.subtract(seen)
        current.formUnion(Set(granted).intersection(seen))
        // `spots.send` only together with `spots`.
        if current.contains("spots.send") && !current.contains("spots") {
            current.remove("spots.send")
        }
        grants[identity] = current.isEmpty ? nil : current.sorted()
        let decidedBefore: Set<String> = Set(decidedPermissions[identity] ?? [])
        decidedPermissions[identity] = decidedBefore.union(seen).sorted()
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
