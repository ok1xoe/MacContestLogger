import Foundation

/// N1MM's daily settings backups (the INI `.bak` files): a copy of `config.json` once a day into
/// `<data>/config-backups/config-<yyyy-MM-dd>.json`, the newest `keep` (7) kept. A reset to the defaults first saves
/// the current file as `config-<yyyy-MM-dd>-<HHmmss>.json`. Every method touches the disk: call them off the main
/// thread.
public struct ConfigBackups: Sendable {

    /// The backups kept (N1MM: 7 days).
    public static let keep = 7
    /// The directory under the data directory.
    public static let dirName = "config-backups"

    /// One backup file.
    public struct Entry: Equatable, Sendable, Identifiable {
        public let url: URL
        /// The file name without `config-` and `.json` (`2026-10-15`, `2026-10-15-120501`), newest first by name.
        public let label: String

        public var id: String { label }
    }

    public let dir: URL

    public init(dataDir: URL) {
        dir = dataDir.appendingPathComponent(Self.dirName, isDirectory: true)
    }

    /// `config-2026-10-15` of a UTC day.
    static func dayStamp(_ date: Date) -> String {
        stamp(date, format: "yyyy-MM-dd")
    }

    private static func stamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// The day's backup of `configFile` when there is none yet for the UTC day of `now` (a missing config file is not
    /// backed up), then the old ones beyond `keep` removed. Returns the new file, `nil` = nothing written.
    @discardableResult
    public func daily(configFile: URL, now: Date) throws -> URL? {
        let files = FileManager.default
        guard files.fileExists(atPath: configFile.path) else { return nil }
        let day: String = Self.dayStamp(now)
        if try list().contains(where: { $0.label.hasPrefix(day) }) {
            return nil
        }
        let target: URL = dir.appendingPathComponent("config-" + day + ".json")
        try copy(configFile, to: target)
        try prune()
        return target
    }

    /// A backup of `config` made now whatever the day (before a reset or a restore), written like `config.json`.
    @discardableResult
    public func backupNow(_ config: AppConfig, now: Date) throws -> URL {
        let target: URL = dir.appendingPathComponent("config-" + Self.stamp(now, format: "yyyy-MM-dd-HHmmss") + ".json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(config).write(to: target, options: .atomic)
        try prune()
        return target
    }

    private func copy(_ source: URL, to target: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try Data(contentsOf: source)
        try data.write(to: target, options: .atomic)
    }

    /// The backups, newest first (an absent directory = none).
    public func list() throws -> [Entry] {
        let files = FileManager.default
        guard files.fileExists(atPath: dir.path) else { return [] }
        let names: [String] = try files.contentsOfDirectory(atPath: dir.path)
        return names.compactMap { name -> Entry? in
            guard name.hasPrefix("config-"), name.hasSuffix(".json") else { return nil }
            let label = String(name.dropFirst("config-".count).dropLast(".json".count))
            guard !label.isEmpty else { return nil }
            return Entry(url: dir.appendingPathComponent(name), label: label)
        }
        .sorted { $0.label > $1.label }
    }

    /// Removes the backups beyond the newest `keep`.
    public func prune() throws {
        for entry in try list().dropFirst(Self.keep) {
            try FileManager.default.removeItem(at: entry.url)
        }
    }

    /// The configuration of a backup (lenient like `config.json`); a file that is not a configuration throws.
    public func read(_ entry: Entry) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: entry.url))
    }

    /// What a reset or a restore keeps from the live configuration: where the logs and the contest data are, the
    /// open windows and their places, and (on a reset) the station — so the log stays reachable and the call sign
    /// stays.
    public static func preserving(_ live: AppConfig, into next: AppConfig, station: Bool) -> AppConfig {
        var out: AppConfig = next
        out.databasesDir = live.databasesDir
        out.lastDatabase = live.lastDatabase
        out.contestDataDir = live.contestDataDir
        out.windowGeometry = live.windowGeometry
        out.openWindows = live.openWindows
        if station {
            out.station = live.station
        }
        return out
    }
}
