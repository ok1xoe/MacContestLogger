import Darwin
import Foundation

/// The manifest `plugins/<name>/plugin.json` of a window plugin (protocol 1): a long-running process that shows
/// declarative windows and reads the log through requests. A directory with a `plugin.json` is a window plugin; the
/// directories named after events (`qso-logged`, …) are the event plugins of `PluginRunner` and are never read as
/// window plugins — those names are reserved.
public struct PluginManifest: Equatable, Sendable {

    /// The protocol this version speaks.
    public static let protocolVersion: Int64 = 1
    /// The permissions this version knows. `read` and `ui` are always granted; the others act on the app and need
    /// the operator's grant (`grantedPermissions`). Later versions add `cat`, `transmit` and `web`.
    public static let supportedPermissions: [String] = ["read", "ui", "entry", "rig", "spots", "spots.send",
                                                        "app.command"]
    /// The permissions granted without asking.
    public static let implicitPermissions: Set<String> = ["read", "ui"]
    /// At most this many windows per plugin.
    public static let maxWindows = 8
    /// At most this many key actions per plugin.
    public static let maxActions = 32

    /// An action the operator can bind to a key (Settings → Keys); the plugin gets a `key` message.
    public struct Action: Equatable, Sendable {
        public let id: String
        public let title: String
    }

    public struct Window: Equatable, Sendable {
        public let id: String
        public let title: String
        /// The default size (`size: [w, h]`), `nil` = 480×360.
        public let width: Int?
        public let height: Int?
    }

    /// The directory name: the plugin's id (window ids `plugin:<id>/<window>`).
    public let id: String
    /// The shown name (`name`, else the id).
    public let name: String
    public let version: String?
    public let permissions: [String]
    /// The subscribed events in their directory form (`qso-logged`).
    public let events: [String]
    public let windows: [Window]
    /// The key actions (a plugin may have actions and no window).
    public let actions: [Action]
    /// The executable relative to the plugin directory (`run`, default `run`).
    public let run: String

    /// The permissions this version does not grant (the plugin is then not started).
    public var unsupportedPermissions: [String] {
        permissions.filter { !Self.supportedPermissions.contains($0) }
    }

    public func window(_ id: String) -> Window? {
        windows.first { $0.id == id }
    }

    public func action(_ id: String) -> Action? {
        actions.first { $0.id == id }
    }

    /// The requested permissions that need the operator's grant.
    public var permissionsNeedingGrant: [String] {
        permissions.filter { !Self.implicitPermissions.contains($0) && Self.supportedPermissions.contains($0) }
    }

    /// Parses and checks a manifest. The checks name the problem in a message for the messages window.
    public static func parse(_ bytes: [UInt8], directoryName: String) throws(ContestMessage) -> PluginManifest {
        guard let json = try? PluginJSON.parse(bytes), let root = json.objectValue else {
            throw ContestMessage("plugin.json není platný JSON objekt")
        }
        guard let version = root["protocol"]?.intValue else {
            throw ContestMessage("plugin.json: chybí číslo protokolu")
        }
        guard version == protocolVersion else {
            throw ContestMessage("plugin.json: protokol %s, tato verze umí jen %s", .string(String(version)),
                                 .string(String(protocolVersion)))
        }
        let name: String = root["name"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? directoryName
        let permissions: [String] = try strings(root["permissions"], field: "permissions")
        let events: [String] = try strings(root["events"], field: "events")
        let known: Set<String> = Set(PluginRunner.Event.allCases.map(PluginRunner.dirName))
        if let unknown = events.first(where: { !known.contains($0) }) {
            throw ContestMessage("plugin.json: neznámá událost %s", .string(unknown))
        }
        let actions: [Action] = try parseActions(root["actions"])
        let windows: [Window] = try parseWindows(root["windows"], name: name, required: actions.isEmpty)
        let run: String = root["run"]?.stringValue ?? "run"
        guard isSafeRelativePath(run) else {
            throw ContestMessage("plugin.json: neplatná cesta ke spustitelnému souboru %s", .string(run))
        }
        return PluginManifest(id: directoryName, name: name, version: root["version"]?.stringValue,
                              permissions: permissions, events: events, windows: windows, actions: actions, run: run)
    }

    private static func strings(_ value: PluginJSON?, field: String) throws(ContestMessage) -> [String] {
        guard let value, value != .null else { return [] }
        guard let list = value.arrayValue else {
            throw ContestMessage("plugin.json: %s musí být seznam textů", .string(field))
        }
        var out: [String] = []
        for item in list {
            guard let text = item.stringValue else {
                throw ContestMessage("plugin.json: %s musí být seznam textů", .string(field))
            }
            if !out.contains(text) {
                out.append(text)
            }
        }
        return out
    }

    private static func parseActions(_ value: PluginJSON?) throws(ContestMessage) -> [Action] {
        guard let value, value != .null else { return [] }
        guard let list = value.arrayValue, list.count <= maxActions else {
            throw ContestMessage("plugin.json: akce (actions) musí být seznam nejvýš %s položek",
                                 .string(String(maxActions)))
        }
        var actions: [Action] = []
        for item in list {
            guard let id = item["id"]?.stringValue, isValidId(id), !actions.contains(where: { $0.id == id }) else {
                throw ContestMessage("plugin.json: akce bez platného nebo jedinečného id")
            }
            actions.append(Action(id: id, title: item["title"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? id))
        }
        return actions
    }

    private static func parseWindows(_ value: PluginJSON?, name: String,
                                     required: Bool) throws(ContestMessage) -> [Window] {
        if !required && (value == nil || value == .null || value?.arrayValue?.isEmpty == true) {
            return []
        }
        guard let list = value?.arrayValue, !list.isEmpty else {
            throw ContestMessage("plugin.json: chybí okna (windows)")
        }
        guard list.count <= maxWindows else {
            throw ContestMessage("plugin.json: víc než %s oken", .string(String(maxWindows)))
        }
        var windows: [Window] = []
        for item in list {
            guard let id = item["id"]?.stringValue, isValidId(id) else {
                throw ContestMessage("plugin.json: okno bez platného id")
            }
            guard !windows.contains(where: { $0.id == id }) else {
                throw ContestMessage("plugin.json: okno %s je uvedeno dvakrát", .string(id))
            }
            let title: String = item["title"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? name
            var width: Int?
            var height: Int?
            if let size = item["size"]?.arrayValue, size.count == 2, let w = size[0].intValue, let h = size[1].intValue {
                width = Int(min(max(w, 160), 4000))
                height = Int(min(max(h, 120), 4000))
            }
            windows.append(Window(id: id, title: title, width: width, height: height))
        }
        return windows
    }

    /// Ids of plugins and windows: letters, digits, `-`, `_`, `.`; not starting with a dot; at most 64 characters.
    public static func isValidId(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 64, id.first != "." else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))) || scalar == "-" || scalar == "_"
                || scalar == "."
        }
    }

    /// A relative path that stays inside the plugin directory.
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/").contains("..")
    }
}

/// A window plugin found in the plugins directory.
public struct PluginPackage: Equatable, Sendable {
    public let manifest: PluginManifest
    /// The plugin directory (absolute).
    public let directory: String
    /// The executable (absolute).
    public let executable: String

    public var id: String { manifest.id }
}

/// The window plugins of a plugins directory (`plugins/<name>/plugin.json`).
public enum PluginCatalog {

    public static let manifestName = "plugin.json"
    /// The largest manifest read.
    static let maxManifestBytes = 64 * 1024

    /// The event directories of `PluginRunner` — never window plugins.
    public static let reservedNames: Set<String> = Set(PluginRunner.Event.allCases.map(PluginRunner.dirName))

    public struct Problem: Equatable, Sendable {
        /// The directory name.
        public let plugin: String
        public let message: ContestMessage
    }

    public struct Scan: Equatable, Sendable {
        public var packages: [PluginPackage] = []
        public var problems: [Problem] = []

        public init(packages: [PluginPackage] = [], problems: [Problem] = []) {
            self.packages = packages
            self.problems = problems
        }

        public func package(_ id: String) -> PluginPackage? {
            packages.first { $0.id == id }
        }
    }

    /// Lists the window plugins of `root`, sorted by name. Blocking (file system) — never on the main actor.
    /// Directories without `plugin.json` (the event directories, anything else) are skipped silently; a reserved
    /// name with a manifest, an unreadable or invalid manifest is a problem.
    public static func scan(root: String) -> Scan {
        var scan = Scan()
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        for name in names.sorted() where !name.hasPrefix(".") {
            let directory: String = (root as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let manifestPath: String = (directory as NSString).appendingPathComponent(manifestName)
            guard FileManager.default.fileExists(atPath: manifestPath) else { continue }
            if reservedNames.contains(name) {
                scan.problems.append(Problem(plugin: name, message: ContestMessage(
                    "název adresáře je vyhrazen pro událostní pluginy")))
                continue
            }
            guard PluginManifest.isValidId(name) else {
                scan.problems.append(Problem(plugin: name, message: ContestMessage(
                    "název adresáře smí obsahovat jen písmena, číslice, -, _ a .")))
                continue
            }
            guard let data = FileManager.default.contents(atPath: manifestPath),
                  data.count <= maxManifestBytes else {
                scan.problems.append(Problem(plugin: name, message: ContestMessage("plugin.json nelze přečíst")))
                continue
            }
            do throws(ContestMessage) {
                let manifest: PluginManifest = try PluginManifest.parse(Array(data), directoryName: name)
                let executable: String = (directory as NSString).appendingPathComponent(manifest.run)
                scan.packages.append(PluginPackage(manifest: manifest, directory: directory, executable: executable))
            } catch {
                scan.problems.append(Problem(plugin: name, message: error))
            }
        }
        return scan
    }

    /// The id of a plugin window in `config.openWindows`: `plugin:<plugin>/<window>`.
    public static func windowKey(plugin: String, window: String) -> String {
        "plugin:" + plugin + "/" + window
    }

    /// The plugin and window ids of a window key; `nil` for any other id.
    public static func parseWindowKey(_ key: String) -> (plugin: String, window: String)? {
        guard key.hasPrefix("plugin:") else { return nil }
        let rest: Substring = key.dropFirst("plugin:".count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let plugin = String(rest[..<slash])
        let window = String(rest[rest.index(after: slash)...])
        guard PluginManifest.isValidId(plugin), PluginManifest.isValidId(window) else { return nil }
        return (plugin, window)
    }
}
