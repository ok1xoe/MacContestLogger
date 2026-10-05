import Foundation

/// The paths of the contest data and of the call history file that the Kotlin UI of v1.1.1 derives from the
/// configuration (`ui/AppState.kt`, `ui/DefinitionEditorWindow.kt`).
public enum ContestDataPaths {

    /// `AppState.contestDataRoot()`: the configured `contestDataDir` unless it is `nil` or blank (Kotlin
    /// `isNotBlank`, not trimmed), otherwise `defaultDir` (`AppPaths.defaultContestDataDir()`).
    public static func root(contestDataDir: String?, default defaultDir: URL) -> URL {
        guard let configured = contestDataDir, !KotlinStrings.isBlank(configured) else { return defaultDir }
        return URL(fileURLWithPath: configured)
    }

    /// The directory of the definition editor (`DefinitionEditorWindow`): `<root>/contests` when it is a
    /// directory **or when the root itself is not one**, otherwise the root (definitions directly in the root).
    public static func contestsDir(root: URL,
                                   isDirectory: (URL) -> Bool = ContestDataPaths.isDirectory) -> URL {
        let contests: URL = root.appendingPathComponent("contests")
        if isDirectory(contests) || !isDirectory(root) {
            return contests
        }
        return root
    }

    /// The target of "Update call history from log" (`AppState.updateCallHistoryFromLog`): the trimmed configured
    /// file (Kotlin `trim()`), or `<data>/CALLHISTORY.txt` when it is blank — then `persist` is `true`: after a
    /// successful save the path goes into `config.callHistoryFile` and the configuration is saved.
    public static func callHistoryTarget(configured: String, dataDir: URL) -> (url: URL, persist: Bool) {
        let trimmed: String = KotlinStrings.trim(configured)
        if !KotlinStrings.isBlank(trimmed) {
            return (URL(fileURLWithPath: trimmed), false)
        }
        return (dataDir.appendingPathComponent("CALLHISTORY.txt"), true)
    }

    /// The arguments of `CountyListImport.qsoPartyTemplate` for "New QSO party…" (`DefinitionEditorWindow`): the
    /// trimmed id, its Kotlin `uppercase()` as the name and `id.replace('-', '_') + "_counties"` as the county set.
    public static func qsoPartyArguments(id: String) -> (id: String, name: String, countySet: String) {
        let trimmed: String = KotlinStrings.trim(id)
        var underscored = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars {
            underscored.append(scalar == "-" ? "_" : scalar)
        }
        return (trimmed, KotlinStrings.uppercase(trimmed), String(underscored) + "_counties")
    }

    /// `Files.isDirectory` (follows symbolic links).
    public static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
}
