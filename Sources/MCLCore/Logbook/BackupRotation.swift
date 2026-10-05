import Foundation

/// Automatic logbook backup (N1MM / DXLog auto backup): backup names with time
/// and rotation — only the last `keep` backups of the given logbook remain in the directory.
/// Corresponds to Java `BackupRotation`.
public enum BackupRotation {

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Path of a new backup `<logbook>-auto-<time>.sqlite` in directory `dir`. Corresponds to `target`.
    public static func target(dir: URL, logName: String, now: Date) -> URL {
        dir.appendingPathComponent(prefix(logName) + stampFormatter.string(from: now) + ".sqlite")
    }

    /// The automatic-backup prefix of `logName` (`prefix`), for callers outside the rotation.
    public static func autoPrefix(_ logName: String) -> String {
        prefix(logName)
    }

    /// `<logbook without the .sqlite extension>-auto-`. Rotation considers only this prefix —
    /// other logbooks (`other-auto-…`) and manual backups without `-auto-` (`cqww-20260101…`)
    /// are none of its business.
    private static func prefix(_ logName: String) -> String {
        var name = logName
        if name.hasSuffix(".sqlite") {
            name.removeLast(".sqlite".count)
        }
        return name + "-auto-"
    }

    /// Deletes the oldest automatic backups beyond the count `keep`; returns the number deleted.
    /// Corresponds to `prune`.
    @discardableResult
    public static func prune(dir: URL, logName: String, keep: Int) throws -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }
        let p = prefix(logName)
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix(p) && $0.lastPathComponent.hasSuffix(".sqlite") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let remove = max(0, backups.count - max(1, keep))
        for i in 0..<remove {
            let path = backups[i]
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
        }
        return remove
    }
}
