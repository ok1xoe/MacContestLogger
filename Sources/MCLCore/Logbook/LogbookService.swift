import Foundation

/// Application service over `LogbookRepository`. Adds a timestamp to a QSO when
/// logging (corrected by `clockOffset`) and separates reading/writing by the active
/// contest (`activeContestId`). Corresponds to Java `LogbookService`.
///
/// On `LogbookException`: the Java version is unchecked (`RuntimeException`) — every
/// `LogbookRepository` method that can fail just silently rethrows it, and
/// no call site in `AppState`/`EntryPanel` catches it (`logbook.log(qso)`
/// etc. are called without `try`/`catch`); in practice a SQLite error either crashes the app
/// or is caught only by a generic handler at the UI-thread boundary, never closer to the call.
/// Swift has no unchecked exceptions — `LogbookRepository` therefore already reports all
/// these errors as `LogbookError: Error` (see `SQLite.swift`), not as
/// `fatalError`/`try!`. Instead of introducing a second error type (which would duplicate the existing one) this service just adopts `LogbookError` and bubbles it up
/// (`throws` on every method that calls the repository) — a new type would be a duplicate
/// declaration in the same module.
///
/// Consequence for callers: previously the error could be ignored (let it propagate without
/// mention in the signature); now Swift does not allow that — every call of `LogbookService`
/// must be either in a `throws` function (it bubbles up, same behaviour as Java) or
/// explicitly handled (`do/catch`, `try?`). The UI layer is the main caller of
/// `LogbookService`, so nothing
/// breaks today — once a future UI layer starts calling `log`/`update`/…, it will have to
/// handle the error actively (typically `do/catch` with a status message, analogous to `runCatching` in
/// other places of `AppState.kt`), instead of being able — as in Kotlin today — to silently
/// let it fall through.
public final class LogbookService {

    public let repository: LogbookRepository

    /// Source of "now" — in Java a `Clock` (default `Clock.systemUTC()`, in tests
    /// `Clock.fixed(...)`). The Swift equivalent is a plain injected function.
    private let now: () -> Date

    /// Clock correction by NTP (`SNTPClient.Result.offsetMs`, in seconds) —
    /// added to the time of newly written QSOs. `0` (Java `Duration.ZERO`/`null`) =
    /// no correction. `SNTPClient` documents a positive value as "the computer is
    /// behind" (its clock lags the real time); adding it therefore
    /// moves the raw reading of the computer clock **forward**, to the real time —
    /// not subtracts. Pinned by `ClockOffsetTest.newQsoTimeIsCorrected` (see tests):
    /// clock fixed at `12:00:00Z`, offset `+2.5 s` → logged time `12:00:02.5Z`.
    public var clockOffset: TimeInterval = 0

    /// Active contest: `log`/`findAll`/`count`/`nextSerial` without an explicit
    /// `contestId` follow this value. `""` (Java `null`) = no contest —
    /// the same sentinel as `Qso.contestId`. `LogbookRepository` translates it back to `NULL`
    /// at the SQL boundary (see `sqlContestId`), so:
    /// logged QSOs have `contest_id IS NULL` (as in Java, where `qso.setContestId(null)`
    /// + `ps.setString` writes `NULL`) and `findAll()`/`count()` return **nothing**,
    /// because `contest_id=?` with a bound `NULL` matches no row. The practical
    /// consequence — and exactly what Java does too: without an active contest `findAll()` is
    /// empty, `count()` is `0` and `nextSerial()` is `1`, however many QSOs were
    /// logged in the meantime. The state is reachable (Kotlin `AppState`
    /// calls `setActiveContest(null)` after switching the database).
    public var activeContestId: String = ""

    public init(repository: LogbookRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    /// Logs a QSO: sets `contestId` to the active contest, fills in the time (if
    /// missing) corrected by `clockOffset` and saves via `repository.insert`.
    /// Java returns the same (mutated) instance; `qso` is `inout` here for the same
    /// reason as in `LogbookRepository.insert` — the caller sees the assigned
    /// `uuid`/`id`/computed time on its `var`. The `@discardableResult` return
    /// value copies Java's `Qso log(Qso qso)` 1:1 for callers that want to
    /// chain it without having to read back from the `inout`.
    @discardableResult
    public func log(_ qso: inout Qso) throws -> Qso {
        qso.contestId = activeContestId
        if qso.timestampUtc == nil {
            qso.timestampUtc = now().addingTimeInterval(clockOffset)
        }
        try repository.insert(&qso)
        return qso
    }

    public func update(_ qso: Qso) throws {
        try repository.update(qso)
    }

    /// The stored row with this id (also a tombstone), `nil` = none.
    public func findById(_ id: Int64) throws -> Qso? {
        try repository.findById(id)
    }

    public func delete(id: Int64) throws {
        try repository.delete(id: id)
    }

    /// Bulk deletion of the listed QSOs (one transaction). Corresponds to
    /// `delete(Collection<Long>)`.
    public func delete(ids: [Int64]) throws {
        try repository.delete(ids: ids)
    }

    public func deleteAll() throws {
        try repository.deleteAll()
    }

    /// Active QSOs (tombstones excluded) of the active contest. Corresponds to `findAll()`.
    public func findAll() throws -> [Qso] {
        try repository.findAll(contestId: activeContestId)
    }

    /// Corresponds to `findAllIncludingDeleted()` — does not filter by the active contest,
    /// as in Java.
    public func findAllIncludingDeleted() throws -> [Qso] {
        try repository.findAllIncludingDeleted()
    }

    /// Merges an incoming network QSO state into the local replica (LWW by `version`).
    /// See `LogbookRepository.upsertByUuid`.
    public func upsertByUuid(_ qso: Qso) throws {
        try repository.upsertByUuid(qso)
    }

    /// Marks the QSO of the given `uuid` as deleted (tombstone, LWW by `version`).
    public func markDeleted(uuid: String, version: Int64, updatedAtUtc: Date?) throws {
        try repository.markDeleted(uuid: uuid, version: version, updatedAtUtc: updatedAtUtc)
    }

    /// Number of active QSOs of the active contest. Corresponds to `count()`.
    public func count() throws -> Int {
        try repository.count(contestId: activeContestId)
    }

    /// Next serial number to send (1 + the number of QSOs logged so far
    /// in the active contest). Corresponds to `nextSerial()`.
    public func nextSerial() throws -> Int {
        try repository.nextSerial(contestId: activeContestId)
    }
}
