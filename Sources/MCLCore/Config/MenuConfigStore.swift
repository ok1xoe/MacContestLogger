import Foundation

/// Loading and saving the menu definition (`menu.json`) in the user's data directory.
///
/// The user's file in the data directory takes precedence — only that way can someone who has the app installed
/// and no access to the sources customize the menus. Without
/// it the built-in resource bundled in the package (`builtIn()`) is used and, as a
/// last resort, `DefaultMenu.tree()` when the resource is missing or broken.
///
/// A broken user file must not leave the app without menus: the
/// built-in definition is returned along with the reason (`LoadResult.error`), so the UI can show it —
/// the user would not look into a log and would think their edit
/// simply does not work. Mirrors `MenuConfigStore.java`.
public enum MenuConfigStore {

    /// Where the used definition came from.
    public enum Source: Equatable, Sendable {
        /// The user's file in the data directory.
        case user
        /// Built-in definition (there is no user file).
        case builtIn
        /// The user file exists but could not be used — the built-in definition is running.
        case userInvalid
    }

    /// Load result.
    public struct LoadResult: Equatable, Sendable {
        /// The definition used (never empty).
        public let menu: MenuConfig
        /// Where the definition came from.
        public let source: Source
        /// Why the user file was not used, or `nil`.
        public let error: String?
    }

    /// File name in the data directory.
    public static let fileName = "menu.json"

    private static let resourceName = "menu"
    private static let resourceExtension = "json"

    /// Menu from the file `url`; for a missing, unreadable or empty menu
    /// it returns `builtIn()`.
    ///
    /// A simplified interface over one specific file. For behaviour identical
    /// to Java `MenuConfigStore` (load source, error message, writing
    /// an editable copy) use `loadFrom(dataDir:)`/`writeBuiltIn`.
    public static func load(from url: URL) -> MenuConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(MenuConfig.self, from: data),
              !config.menu.isEmpty
        else {
            return builtIn()
        }
        return config
    }

    /// Saves the menu to the file `url` (including creating the directory if missing).
    public static func save(_ config: MenuConfig, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    /// Path to the user file in the given directory (regardless of whether it exists).
    public static func userFile(dataDir: URL) -> URL {
        dataDir.appendingPathComponent(fileName)
    }

    /// Loads the menu from `<dataDir>/menu.json`, and when it is missing or broken, from `builtIn()`.
    public static func loadFrom(dataDir: URL) -> LoadResult {
        let file = userFile(dataDir: dataDir)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            return LoadResult(menu: builtIn(), source: .builtIn, error: nil)
        }
        do {
            let data = try Data(contentsOf: file)
            let config = try JSONDecoder().decode(MenuConfig.self, from: data)
            guard !config.menu.isEmpty else {
                return LoadResult(
                    menu: builtIn(), source: .userInvalid,
                    error: "Soubor \(file.path) nemá žádnou položku menu.")
            }
            return LoadResult(menu: config, source: .user, error: nil)
        } catch {
            let data = (try? Data(contentsOf: file)) ?? Data()
            return LoadResult(
                menu: builtIn(), source: .userInvalid,
                error: "Soubor \(file.path) se nepodařilo přečíst: \(describe(error, data: data))")
        }
    }

    /// Writes the built-in definition into the data directory so the user has something to edit.
    ///
    /// - Parameter overwrite: `true` overwrites an existing file (resets the menu to its default state).
    /// - Returns: path to the written file, or `nil` when the file exists and `overwrite`
    ///   is `false` (someone else's edits are not overwritten without permission).
    public static func writeBuiltIn(dataDir: URL, overwrite: Bool) throws -> URL? {
        let file = userFile(dataDir: dataDir)
        if FileManager.default.fileExists(atPath: file.path), !overwrite {
            return nil
        }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let resourceUrl = CoreResources.bundle?.url(forResource: resourceName, withExtension: resourceExtension) {
            let data = try Data(contentsOf: resourceUrl)
            try data.write(to: file)
        } else {
            // The resource in the package is missing (a stripped bundle) — at least write the default tree from code.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(DefaultMenu.tree())
            try data.write(to: file)
        }
        return file
    }

    /// Built-in definition bundled in the package; when that is missing too, the default tree from code.
    public static func builtIn() -> MenuConfig {
        guard let url = CoreResources.bundle?.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url)
        else {
            return DefaultMenu.tree()
        }
        return parse(data)
    }

    /// The definition from the given resource bundle **without** the fallback to `DefaultMenu.tree()`: `nil` when
    /// `menu.json` is missing, unreadable, invalid or empty. For the start-up check of the assembled app.
    public static func bundled(in bundle: Bundle) -> MenuConfig? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(MenuConfig.self, from: data),
              !config.menu.isEmpty
        else {
            return nil
        }
        return config
    }

    /// Parses data into `MenuConfig`; empty or invalid returns `DefaultMenu.tree()`.
    public static func parse(_ data: Data) -> MenuConfig {
        guard let config = try? JSONDecoder().decode(MenuConfig.self, from: data), !config.menu.isEmpty else {
            return DefaultMenu.tree()
        }
        return config
    }

    /// An understandable description of a JSON error: what was wrong and where. `JSONDecoder`
    /// does not give the error position, unlike `JSONSerialization` — so the same data
    /// is also tried through the latter for the message, just for the line/column.
    /// A user editing the file in an editor wants to know the line and column,
    /// not Swift's technical message (analogous to Java `describe(Exception)`,
    /// which does the same with Jackson's `JsonLocation`).
    private static func describe(_ error: Error, data: Data) -> String {
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch let nsError as NSError {
            let raw = (nsError.userInfo[NSDebugDescriptionErrorKey] as? String) ?? nsError.localizedDescription
            let message = raw.replacingOccurrences(
                of: #"\s*around line \d+, column \d+\.?$"#, with: "", options: .regularExpression)
            if let index = nsError.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                let (line, column) = lineAndColumn(in: data, at: index)
                return "\(message) (řádek \(line), sloupec \(column))"
            }
            return message
        } catch {
            // unlikely — an error other than NSError
        }
        // The JSON is syntactically fine but the shape does not fit (e.g. „menu" is not an array) —
        // there is no line to report, at least Swift's message is returned.
        return String(describing: error)
    }

    private static func lineAndColumn(in data: Data, at byteIndex: Int) -> (line: Int, column: Int) {
        let prefix = data.prefix(byteIndex)
        let text = String(decoding: prefix, as: UTF8.self)
        var line = 1
        var column = 1
        for character in text {
            if character == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }
}
