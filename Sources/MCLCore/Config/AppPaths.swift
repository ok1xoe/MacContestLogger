import Foundation

/// Location of application data: `~/Library/Application Support/MacContestLogger`.
/// The paths must match the Java version, otherwise the app would stop seeing
/// the existing logbook and settings.
public enum AppPaths {

    private static let appDirName = "MacContestLogger"

    /// Computes the data directory. Pure function, testable without writing to disk.
    public static func resolveDataDir(userHome: URL) -> URL {
        userHome
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent(appDirName)
    }

    /// Environment variable that replaces the data directory **root** (the directory itself, not the home).
    /// A technique for tests and scripted runs of the app over a temporary directory, so they never touch the real
    /// data. Java needs none — it has `-Duser.home`; here `HOME=<dir>` does **not** redirect
    /// `homeDirectoryForCurrentUser` (measured 2026-10-02: it still returns the account's home).
    public static let dataDirOverrideVariable = "MCL_DATA_DIR"

    /// Computes the data directory with the `MCL_DATA_DIR` override; an empty value is ignored.
    public static func resolveDataDir(userHome: URL, environment: [String: String]) -> URL {
        if let override = environment[dataDirOverrideVariable], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return resolveDataDir(userHome: userHome)
    }

    /// Application data directory; creates it if it does not exist.
    public static func dataDir() -> URL {
        let dir = resolveDataDir(
            userHome: FileManager.default.homeDirectoryForCurrentUser,
            environment: ProcessInfo.processInfo.environment)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // A creation failure is not ignored — as in Java it is reported immediately,
            // so the error shows up on the spot and does not later become an unclear SQLite error.
            preconditionFailure("Nelze vytvořit adresář dat: \(dir)")
        }
        return dir
    }

    /// Directory with UI translations (`lang_<code>.json`); the user drops their own in.
    public static func languageDir() -> URL { dataDir().appendingPathComponent("language") }

    /// SQLite logbook file.
    public static func logbookFile() -> URL { dataDir().appendingPathComponent("logbook.sqlite") }

    /// Configuration file.
    public static func configFile() -> URL { dataDir().appendingPathComponent("config.json") }

    /// Offered default path for contest data; it is not seeded.
    public static func defaultContestDataDir() -> URL { dataDir().appendingPathComponent("contest-data") }

    /// Default directory of voice-keyer wav files.
    public static func defaultWavDir() -> URL { dataDir().appendingPathComponent("wav") }

    /// Directory of the persistent MQTT session; creates it if missing.
    public static func clusterPersistenceDir() -> URL {
        let dir = dataDir().appendingPathComponent("mqtt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // A failure is not ignored — as in Java it is reported immediately.
            preconditionFailure("Nelze vytvořit adresář MQTT session: \(dir)")
        }
        return dir
    }
}
