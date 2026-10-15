import Foundation

/// N1MM's separate user files area (UserDir): the app starts again over another data directory through
/// `MCL_DATA_DIR`. The old instance quits; a detached shell waits a moment (so the rig, the ports and the logbook are
/// released) and opens a new instance of the bundle with the variable set. An empty directory = the default one.
public enum DataFolderRelaunch {

    /// Seconds the shell waits before the new instance starts.
    public static let delaySeconds = 3

    /// The executable and its arguments: `/bin/sh -c '…' <bundle> <variable assignment>` — the paths are positional
    /// parameters of the script, never part of its text, so no path needs quoting.
    public static func command(bundle: URL, dataDir: URL?) -> (executable: String, arguments: [String]) {
        let script: String = "sleep \(delaySeconds); exec /usr/bin/open -n -a \"$0\" --env \"$1\""
        let assignment: String = AppPaths.dataDirOverrideVariable + "=" + (dataDir?.path ?? "")
        return ("/bin/sh", ["-c", script, bundle.path, assignment])
    }

    /// `true` when `dir` is not where the app keeps its data now (choosing the same folder again does nothing).
    public static func differs(_ dir: URL, from current: URL) -> Bool {
        dir.standardizedFileURL.resolvingSymlinksInPath().path
            != current.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// N1MM keeps the station data in each database: with „Údaje stanice podle databáze" on, the station of a database
/// lives next to it as `<name>.station.json`; switching databases saves the station to the database left and takes
/// the opened database's own (a database without one gets the current station). Disk access: off the main thread.
public enum DatabaseStation {

    /// The station file of a database file (`Contest.sqlite` → `Contest.station.json`).
    public static func file(forDatabase database: URL) -> URL {
        database.deletingPathExtension().appendingPathExtension("station.json")
    }

    public static func read(_ file: URL) throws -> StationConfig? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(StationConfig.self, from: Data(contentsOf: file))
    }

    public static func write(_ station: StationConfig, to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(station).write(to: file, options: .atomic)
    }

    /// The switch from `old` to `new`: the station is saved to the old database, then the new database's station
    /// is returned when it has one that differs, otherwise the current one is saved to it and `nil` is returned.
    public static func switchDatabase(from old: URL?, to new: URL, current: StationConfig) throws -> StationConfig? {
        if let old {
            try write(current, to: file(forDatabase: old))
        }
        let target: URL = file(forDatabase: new)
        if let stored = try read(target) {
            return stored == current ? nil : stored
        }
        try write(current, to: target)
        return nil
    }
}
