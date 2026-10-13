import Foundation

/// Which country table filled a log's DXCC fields, and how new it was (N1MM warns when a database whose country
/// table is older than the downloaded country file is opened).
///
/// The stamp is the DXCC source in use (Club Log `cty.xml`, `cty.dat` or `dxcc.json`) with its date: the last
/// successful Club Log download, otherwise the modification date of the data file. It is stored in the logbook's
/// `meta` table under `metaKey` whenever the log is (re)filled with that data, and compared with the current data's
/// stamp when a database is opened (`decide`). The user's own call → country assignments (`dxcc-overrides.json`)
/// are not part of the stamp. Dates are kept to whole seconds, so a stored stamp reads back equal.
public struct DxccDataStamp: Equatable, Sendable {

    /// The DXCC source the stamp describes.
    public enum Source: String, Sendable, CaseIterable {
        case clubLog = "clublog"
        case ctyDat = "cty.dat"
        case dxccJson = "dxcc.json"
    }

    /// The `meta` key of the logbook database.
    public static let metaKey = "dxcc_data_stamp"

    public let source: Source
    public let date: Date

    public init(source: Source, date: Date) {
        self.source = source
        self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// `<source> <ISO-8601 UTC date>`, e.g. `clublog 2026-10-12T08:00:00Z`.
    public var encoded: String {
        source.rawValue + " " + Self.formatter.string(from: date)
    }

    /// Reads `encoded`; `nil` for anything else.
    public init?(encoded text: String) {
        let parts: [Substring] = text.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let source = Source(rawValue: String(parts[0])),
              let date = Self.formatter.date(from: String(parts[1])) else {
            return nil
        }
        self.init(source: source, date: date)
    }

    /// The day of the stamp (`yyyy-MM-dd`, UTC) for the messages.
    public var day: String {
        String(Self.formatter.string(from: date).prefix(10))
    }

    /// The stamp of the DXCC data the app loads (the same choice as `ContestEnvironment.load`): Club Log when its
    /// copy is in use (the last successful download, else the cached file's modification date), otherwise
    /// `cty.dat` when it is readable, otherwise `dxcc.json`. `nil` when no source has a date.
    ///
    /// - Parameters:
    ///   - clubLogInUse: the cached Club Log data is the DXCC source.
    ///   - clubLogState: the cache's `cty-state.json`.
    ///   - clubLogDir: the cache directory (`<data>/clublog`).
    ///   - dxccDir: the local DXCC directory (`~/dxcc-json`).
    ///   - modificationDate: a file's modification date, `nil` when it does not exist (injected by tests).
    public static func current(clubLogInUse: Bool, clubLogState: ClubLogCtyCache.State?, clubLogDir: URL?,
                               dxccDir: URL?,
                               modificationDate: (URL) -> Date? = Self.fileModificationDate) -> DxccDataStamp? {
        if clubLogInUse {
            let fileDate: Date? = clubLogDir.flatMap { dir in
                modificationDate(dir.appendingPathComponent("cty.json"))
                    ?? modificationDate(dir.appendingPathComponent("cty.xml"))
            }
            if let date = clubLogState?.downloadedAt ?? fileDate {
                return DxccDataStamp(source: .clubLog, date: date)
            }
        }
        guard let dxccDir else { return nil }
        if let date = modificationDate(dxccDir.appendingPathComponent("cty.dat")) {
            return DxccDataStamp(source: .ctyDat, date: date)
        }
        if let date = modificationDate(dxccDir.appendingPathComponent("dxcc.json")) {
            return DxccDataStamp(source: .dxccJson, date: date)
        }
        return nil
    }

    /// The modification date of a readable file; `nil` otherwise.
    public static func fileModificationDate(_ url: URL) -> Date? {
        guard FileManager.default.isReadableFile(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    /// What opening a database does with its stored stamp.
    public enum Decision: Equatable, Sendable {
        /// Nothing (the stamp is current or newer, or there is no current data).
        case keep
        /// Store the current stamp silently: a database without a stamp (an empty one, or one filled before stamps
        /// existed — its data cannot be known, so it is not flagged), or an empty one with an older stamp.
        case store(DxccDataStamp)
        /// The log was filled with an older country table: warn and keep the old stamp until the log is refilled.
        case warn(stored: DxccDataStamp, current: DxccDataStamp)
    }

    /// The decision when a database is opened.
    ///
    /// - Parameters:
    ///   - stored: the `meta` value (`nil` or unreadable = no stamp).
    ///   - current: the stamp of the data in use.
    ///   - hasQsos: the database holds QSOs.
    public static func decide(stored: String?, current: DxccDataStamp?, hasQsos: Bool) -> Decision {
        guard let current else { return .keep }
        guard let old = stored.flatMap(DxccDataStamp.init(encoded:)) else {
            return .store(current)
        }
        if old.date >= current.date { return .keep }
        return hasQsos ? .warn(stored: old, current: current) : .store(current)
    }

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
