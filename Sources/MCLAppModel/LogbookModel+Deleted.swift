import Foundation
import MCLCore

/// N1MM's DELETEDQS log: every QSO deleted from the log is kept in an archive of the database (`deleted_qso`), from
/// where it can be put back.
extension LogbookModel {

    /// The deleted QSOs of the active contest, the most recently deleted first (`nil` = the database is closed).
    public func deletedQsos() async -> [LogbookRepository.DeletedQso]? {
        await settleMutations()
        return try? await database.handle.run { access in
            try access.service.findDeleted()
        }
    }

    /// Puts deleted QSOs back into the active contest's log: each is logged again as a new QSO (a new id and merge
    /// key, so a cluster tombstone of the old one does not hide it) with its time and fields, published to the
    /// running cluster like a QSO just logged, and leaves the archive. Returns how many were restored.
    @discardableResult
    public func restoreDeleted(_ entries: [LogbookRepository.DeletedQso]) async -> Int {
        guard !entries.isEmpty else { return 0 }
        let contestId: String = activeContestId
        var planned: [Qso] = []
        for entry in entries {
            var qso: Qso = entry.qso
            qso.id = nil
            qso.uuid = UUID().uuidString.lowercased()
            qso.deleted = false
            qso.version = 0
            qso.updatedAtUtc = nil
            qso.imported = false
            planned.append(qso)
        }
        let qsos: [Qso] = planned
        let outcome: BatchOutcome<Void> = await importBatch(contestId: contestId) { _ in
            BatchPlan(qsos: qsos, value: ())
        }
        let inserted: Int
        switch outcome {
        case .refused(let error):
            status.showVerbatim(ErrorText.message(error))
            return 0
        case .stored(let count, _, let error):
            inserted = count
            if let error {
                status.showVerbatim(ErrorText.message(error))
            }
        }
        let restored: [Int64] = entries.prefix(inserted).map(\.archiveId)
        _ = try? await database.handle.run { access in
            try access.repository.removeDeleted(archiveIds: restored)
        }
        let uuids: Set<String> = Set(qsos.prefix(inserted).map(\.uuid))
        for row in rows where uuids.contains(row.uuid) && outwardGate(row) && Self.syncsToCluster(row) {
            cluster?.publishInsert(row)
        }
        if inserted > 0 {
            status.show(ContestMessage("Obnoveno %s smazaných QSO", .int(inserted)))
        }
        return inserted
    }
}
