import Foundation

/// Write side of the logbook for the log window and entry: the blocking SQLite writes and the in-memory state that
/// follows them.
///
/// The split mirrors the threading rule of the app: the static functions (`insert`, `update`, `bulk`, `delete`,
/// `deleteLast`, `wipe`) touch SQLite and run on a dedicated queue, never on the main thread or the cooperative pool;
/// they return `Change`s, which `apply(_:)` takes into the dupe index in O(1) per QSO where the model state lives
/// (the main actor).
///
/// Kotlin (`AppState`, v1.1.1) rebuilds its `DupeChecker` from `logbook.findAll()` after every update and delete; the
/// `DupeIndex` here follows the same changes incrementally and is tested to stay equal to that rebuild.
public struct LogbookMutations: Sendable {

    /// One change of the logbook, as the dupe index needs to see it.
    public enum Change: Equatable, Sendable {
        /// A new QSO was stored.
        case inserted(Qso)
        /// A stored QSO changed from `old` to `new` (same id).
        case updated(old: Qso, new: Qso)
        /// A stored QSO was deleted.
        case deleted(Qso)
        /// The logbook was replaced as a whole (reload, import); the QSOs are the active ones that remain.
        case reset([Qso])
    }

    /// One edit of a row: the row as the table had it and the row after the edit.
    public struct Edit: Equatable, Sendable {
        public let old: Qso
        public let new: Qso

        public init(old: Qso, new: Qso) {
            self.old = old
            self.new = new
        }
    }

    /// Dupe index of the open logbook.
    public private(set) var dupes: DupeIndex

    public init(existing: [Qso]) {
        dupes = DupeIndex(existing: existing)
    }

    // MARK: - Blocking writes (off the main thread)

    /// Saves a new QSO (`LogbookService.log`: active contest, time if missing, `uuid`/`id`) and returns the stored
    /// QSO. Blocking.
    public static func insert(_ qso: Qso, into service: LogbookService) throws -> Qso {
        var stored = qso
        try service.log(&stored)
        return stored
    }

    /// Saves an edited QSO (Kotlin `logbook.update(qso)` in `AppState.update`). Blocking.
    ///
    /// The stored row is authoritative: it is read by id inside this job, the fields the edit changed (`edit.old` →
    /// `edit.new`) are applied onto it and that is written. So an edit started from a stale copy of the row (an earlier
    /// edit of the same row still in flight) neither loses the earlier edit nor feeds the dupe index a wrong old state —
    /// the returned change carries the stored row as `old` and the written row as `new`. Kotlin is immune by construction
    /// (it edits the shared `Qso` instance and rebuilds its `DupeChecker` after every update).
    ///
    /// - Returns: `nil` when the row is no longer stored (deleted meanwhile — Kotlin's `UPDATE … WHERE id=?` then
    ///   changes nothing) or has no id.
    public static func update(_ edit: Edit, in service: LogbookService) throws -> Change? {
        guard let id = edit.new.id, let stored = try service.findById(id) else {
            return nil
        }
        let written: Qso = merged(stored: stored, old: edit.old, new: edit.new)
        try service.update(written)
        return .updated(old: stored, new: written)
    }

    /// Saves the QSOs of a bulk edit one by one (Kotlin `bulkUpdate`: `selected.forEach { update(it) }` — separate
    /// writes, not one transaction), each as `update(_:in:)`. On an error the edits saved before it are returned with
    /// the error, so the caller can still take them into its state. Blocking.
    public static func bulk(_ edits: [Edit], in service: LogbookService) -> (changes: [Change], error: (any Error)?) {
        var changes: [Change] = []
        for edit in edits {
            do {
                if let change = try update(edit, in: service) {
                    changes.append(change)
                }
            } catch {
                return (changes, error)
            }
        }
        return (changes, nil)
    }

    /// Deletes the given rows (Kotlin `delete(qso)` / `delete(list)` outside a cluster: a hard delete of the rows'
    /// ids in one transaction). Only rows still stored are deleted and returned, in their stored state — a row without
    /// an id (Kotlin collects only non-null ids) or one deleted already (a stale list) is skipped, so the dupe index
    /// never removes a QSO twice. Blocking.
    ///
    /// `tombstone` = the cluster runs (Kotlin `persistDelete`): a row with a `uuid` is not removed but marked
    /// `deleted` (a tombstone, written with `LogbookService.update`) so the deletion can be published and wins over
    /// the other stations' copies; a row without a `uuid` is removed for good. Either way the change is
    /// `.deleted(stored row)` — the row is gone from the active log.
    public static func delete(_ rows: [Qso], in service: LogbookService, tombstone: Bool = false) throws -> [Change] {
        var stored: [Qso] = []
        var seen: Set<Int64> = []
        for row in rows {
            guard let id = row.id, !seen.contains(id), let current = try service.findById(id) else { continue }
            seen.insert(id)
            stored.append(current)
        }
        var hard: [Int64] = []
        for current in stored {
            if tombstone && !current.uuid.isEmpty {
                var marked: Qso = current
                marked.deleted = true
                try service.update(marked)
            } else if let id = current.id {
                hard.append(id)
            }
        }
        try service.delete(ids: hard)
        return stored.map { Change.deleted($0) }
    }

    /// Kotlin `deleteLastQso` (Ctrl+D): deletes the last row of the in-memory list (write order, not time order).
    /// The row is picked when the job runs: the last row of `rows` that is still stored, so a repeated Ctrl+D over a
    /// stale list deletes the previous row, as Kotlin would. None left → only the status `tr("Deník je prázdný")`.
    /// Blocking.
    public static func deleteLast(of rows: [Qso], in service: LogbookService, tombstone: Bool = false) throws
        -> (changes: [Change], status: ContestMessage) {
        for row in rows.reversed() {
            guard let id = row.id, let current = try service.findById(id) else { continue }
            let changes: [Change] = try delete([current], in: service, tombstone: tombstone)
            return (changes, ContestMessage("Smazáno poslední QSO %s", .string(current.call)))
        }
        return ([], ContestMessage("Deník je prázdný"))
    }

    /// Kotlin `wipeLog` (WIPELOG / CLEARLOGNOW): deletes all rows of the in-memory list (a delete, not
    /// `deleteAll` — other contests stay), status `tr("Deník vymazán (%s QSO)", count)` with the list's count
    /// (Kotlin `qsos.size`). Blocking.
    public static func wipe(_ rows: [Qso], in service: LogbookService, tombstone: Bool = false) throws
        -> (changes: [Change], status: ContestMessage) {
        let changes: [Change] = try delete(rows, in: service, tombstone: tombstone)
        return (changes, ContestMessage("Deník vymazán (%s QSO)", .int(rows.count)))
    }

    /// The stored row with the fields the edit changed (`old` → `new`) applied. The frequency goes before the band
    /// (setting it derives the band), so an edited band wins over a derived one.
    static func merged(stored: Qso, old: Qso, new: Qso) -> Qso {
        var out: Qso = stored
        take(\.timestampUtc, &out, old, new)
        take(\.call, &out, old, new)
        take(\.freqHz, &out, old, new)
        take(\.band, &out, old, new)
        take(\.mode, &out, old, new)
        take(\.rstSent, &out, old, new)
        take(\.rstRcvd, &out, old, new)
        take(\.exchangeSent, &out, old, new)
        take(\.exchangeRcvd, &out, old, new)
        take(\.serialSent, &out, old, new)
        take(\.serialRcvd, &out, old, new)
        take(\.points, &out, old, new)
        take(\.multiplier, &out, old, new)
        take(\.runMode, &out, old, new)
        take(\.operator, &out, old, new)
        take(\.comment, &out, old, new)
        take(\.dxccEntity, &out, old, new)
        take(\.dxccName, &out, old, new)
        take(\.continent, &out, old, new)
        take(\.stationId, &out, old, new)
        take(\.version, &out, old, new)
        take(\.updatedAtUtc, &out, old, new)
        take(\.deleted, &out, old, new)
        take(\.xqso, &out, old, new)
        take(\.contestId, &out, old, new)
        take(\.imported, &out, old, new)
        return out
    }

    private static func take<T: Equatable>(_ field: WritableKeyPath<Qso, T>, _ out: inout Qso, _ old: Qso,
                                           _ new: Qso) {
        if old[keyPath: field] != new[keyPath: field] {
            out[keyPath: field] = new[keyPath: field]
        }
    }

    // MARK: - In-memory state (main actor)

    /// Takes a stored QSO into the in-memory state (Kotlin `dupeChecker.add(qso)` after `logbook.log`).
    public mutating func didInsert(_ qso: Qso) {
        dupes.add(qso)
    }

    /// Takes saved changes into the dupe index. The changes carry the stored states (see `update`/`delete`), so the
    /// index follows the database even when the caller's rows were stale.
    public mutating func apply(_ changes: [Change]) {
        for change in changes {
            switch change {
            case .inserted(let qso):
                dupes.add(qso)
            case .updated(let old, let new):
                dupes.replace(old: old, new: new)
            case .deleted(let qso):
                dupes.remove(qso)
            case .reset(let remaining):
                dupes = DupeIndex(existing: remaining)
            }
        }
    }

    /// Is the callsign on the band a duplicate?
    public func isDupe(call: String?, band: Band?) -> Bool {
        dupes.isDupe(call: call, band: band)
    }
}
