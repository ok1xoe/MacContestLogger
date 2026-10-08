import Foundation

/// Copies contests with their QSOs from the open database into another one (N1MM „Copy This Contest to Another
/// Database" / „Copy All Contests").
///
/// - The source is only read, never modified.
/// - A copy keeps every identity: the contest id, and every QSO's `uuid`, `version`, `updatedAtUtc` and station id.
///   So copying the same contest twice adds nothing the second time (QSOs are matched by `uuid` first, then by call,
///   band, mode and time as in „Sloučit deník"), and a database that is later synchronised sees the same QSOs, not
///   new ones. Two copies of one QSO exist in two files, but the application has one database open at a time.
/// - A contest the target already has keeps its stored row (definition, setup, station); only the QSOs it lacks are
///   added. The QTC records (WAE) of a contest are copied only together with the contest row.
/// - Tombstones (deleted QSOs) are not copied. Free-logging QSOs (no contest) are copied with „all".
/// - The whole copy into the target is one transaction: a failure leaves the target as it was.
///
/// Blocking SQLite I/O: call off the main thread.
public enum ContestCopier {

    public struct Summary: Equatable, Sendable {
        /// Contests whose row was added to the target.
        public var contestsAdded = 0
        /// Contests the target already had (only their missing QSOs were added).
        public var contestsPresent = 0
        public var qsosAdded = 0
        /// QSOs the target already had.
        public var qsosSkipped = 0
        public var qtcsAdded = 0
        /// Free-logging QSOs were part of the copy (all contests).
        public var includedFreeLogging = false
    }

    public struct CopyError: Error, Equatable, Sendable {
        public let message: String
    }

    /// Copies `contestIds` (`nil` = all contests and the free-logging QSOs) into the database file `target`, which
    /// is created when it does not exist yet.
    /// - Throws: `CopyError` when `target` is `source`'s own file, or a SQLite error (the target is unchanged).
    public static func copy(contestIds: [String]?, source: LogbookRepository, sourceContests: ContestStore,
                            sourceUrl: URL, target: URL) throws -> Summary {
        guard target.standardizedFileURL.resolvingSymlinksInPath()
                != sourceUrl.standardizedFileURL.resolvingSymlinksInPath() else {
            throw CopyError(message: "Cílová databáze je ta otevřená")
        }
        let ids: [String] = try contestIds ?? sourceContests.listSummaries().map(\.contestId)
        let repository = try LogbookRepository(url: target)
        defer { repository.close() }
        let contests = try ContestStore(repository)
        var summary = Summary()
        try repository.connection.execute("BEGIN")
        do {
            for id in ids {
                try copyContest(id, source: source, sourceContests: sourceContests, target: repository,
                                targetContests: contests, into: &summary)
            }
            if contestIds == nil {
                summary.includedFreeLogging = true
                try copyQsos(contestId: "", source: source, target: repository, into: &summary)
            }
            try repository.connection.execute("COMMIT")
        } catch {
            try? repository.connection.execute("ROLLBACK")
            throw error
        }
        return summary
    }

    private static func copyContest(_ id: String, source: LogbookRepository, sourceContests: ContestStore,
                                    target: LogbookRepository, targetContests: ContestStore,
                                    into summary: inout Summary) throws {
        guard let row = try sourceContests.find(id) else {
            throw CopyError(message: "Závod nenalezen v databázi")
        }
        if try targetContests.find(id) == nil {
            try targetContests.insert(row)
            summary.contestsAdded += 1
            for var qtc in try source.findQtcs(contestId: id) {
                qtc.id = nil
                try target.insertQtc(qtc)
                summary.qtcsAdded += 1
            }
        } else {
            summary.contestsPresent += 1
        }
        try copyQsos(contestId: id, source: source, target: target, into: &summary)
    }

    private static func copyQsos(contestId: String, source: LogbookRepository, target: LogbookRepository,
                                 into summary: inout Summary) throws {
        let incoming: [Qso] = try source.findAll(contestId: contestId)
        let existing: [Qso] = try target.findAll(contestId: contestId)
        let merged = LogMerger.merge(existing: existing, incoming: incoming)
        for var qso in merged.toAdd {
            qso.id = nil
            try target.insert(&qso)
        }
        summary.qsosAdded += merged.toAdd.count
        summary.qsosSkipped += merged.duplicates
    }
}
