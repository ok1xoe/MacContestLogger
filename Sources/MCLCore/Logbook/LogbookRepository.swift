import Foundation

/// CRUD over the `qso` table: insert, update, delete (single and bulk),
/// reading active contacts and counting. Corresponds to `insert`/`update`/`delete(long)`/
/// `delete(Collection<Long>)`/`deleteAll`/`findAll()`/`count()` and the private
/// mapping helper (`bind`/`map`) of Java `LogbookRepository` — over `LogbookDatabase`,
/// which holds the connection, schema and migrations.
///
/// Sync/tombstone operations (`upsertByUuid`, `markDeleted`, `findByUuid`,
/// `findAllIncludingDeleted`) — merging a network replica, idempotent by
/// `uuid` and LWW (last-writer-wins) by `version`: an incoming state with an older
/// *or equal* version is discarded (Java: `version > existing.version`, strict
/// inequality). `deleted` (tombstone, the QSO disappeared) and `xqso` (Cabrillo `X-QSO:`,
/// the QSO stays in the logbook, it just does not count toward the score) are independent fields — `xqso`
/// never hides a row from `findAll()`, only `deleted` does.
public final class LogbookRepository {

    private let logbookDatabase: LogbookDatabase

    /// Opens (or creates) the logbook file. Corresponds to the public constructor
    /// `LogbookRepository(Path dbFile)`.
    public init(url: URL) throws {
        logbookDatabase = try LogbookDatabase(url: url)
    }

    private init(logbookDatabase: LogbookDatabase) {
        self.logbookDatabase = logbookDatabase
    }

    /// In-memory variant for tests. Corresponds to `LogbookRepository.inMemory()`.
    public static func inMemory() throws -> LogbookRepository {
        LogbookRepository(logbookDatabase: try LogbookDatabase.inMemory())
    }

    /// Shared SQLite connection (for a later `ContestStore` over the same file).
    /// Corresponds to `connection()`.
    public var connection: SQLiteDatabase { logbookDatabase.database }

    public func close() {
        logbookDatabase.close()
    }

    // MARK: - Backup

    /// Backs up the whole database to a file (DXLog COPYLOG). `VACUUM INTO` makes a consistent
    /// copy even while running (without locking the logbook for long) — a full file copy of an open
    /// SQLite database could capture a half-written write. Corresponds to `backupTo`.
    ///
    /// - Throws: `LogbookError` if the target file already exists (`VACUUM INTO` would
    ///   silently overwrite it) or the backup fails.
    public func backupTo(_ target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            throw LogbookError("Záloha deníku: soubor už existuje: \(target.path)")
        }
        let escaped = target.standardizedFileURL.path.replacingOccurrences(of: "'", with: "''")
        do {
            try connection.execute("VACUUM INTO '\(escaped)'")
        } catch {
            throw LogbookError("Záloha deníku selhala: \(error)")
        }
    }

    // MARK: - Write

    /// Saves a new QSO and returns its assigned id (also sets it into `qso`).
    ///
    /// `qso` is `inout` because the Java version mutates a shared object: it fills in `uuid`
    /// if missing, `updatedAtUtc` if missing, and finally the assigned `id` — the same
    /// holds here for the caller's value.
    @discardableResult
    public func insert(_ qso: inout Qso) throws -> Int64 {
        if JavaText.isBlank(qso.uuid) {
            // Java `UUID.randomUUID().toString()`: lower case, the uuid goes over the wire of the cluster sync.
            qso.uuid = UUID().uuidString.lowercased()
        }
        if qso.updatedAtUtc == nil {
            qso.updatedAtUtc = qso.timestampUtc ?? Date()
        }
        let stmt = try connection.prepare("""
            INSERT INTO qso (timestamp_utc, call, freq_hz, band, mode, rst_sent, rst_rcvd,
                             exchange_sent, exchange_rcvd, serial_sent, serial_rcvd, points,
                             multiplier, run_mode, operator, comment, dxcc_entity, dxcc_name, continent,
                             uuid, station_id, version, updated_at_utc, deleted, contest_id, xqso)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """)
        defer { stmt.finalize() }
        try bind(stmt, qso)
        try stmt.step()
        let id = connection.lastInsertRowID()
        qso.id = id
        return id
    }

    public func update(_ qso: Qso) throws {
        guard let id = qso.id else {
            throw LogbookError("QSO bez id nelze aktualizovat")
        }
        let stmt = try connection.prepare("""
            UPDATE qso SET timestamp_utc=?, call=?, freq_hz=?, band=?, mode=?, rst_sent=?, rst_rcvd=?,
                           exchange_sent=?, exchange_rcvd=?, serial_sent=?, serial_rcvd=?, points=?,
                           multiplier=?, run_mode=?, operator=?, comment=?, dxcc_entity=?, dxcc_name=?, continent=?,
                           uuid=?, station_id=?, version=?, updated_at_utc=?, deleted=?, contest_id=?, xqso=?
            WHERE id=?
            """)
        defer { stmt.finalize() }
        let next = try bind(stmt, qso)
        try stmt.bindInt64(id, at: next)
        try stmt.step()
    }

    public func delete(id: Int64) throws {
        let stmt = try connection.prepare("DELETE FROM qso WHERE id=?")
        defer { stmt.finalize() }
        try stmt.bindInt64(id, at: 1)
        try stmt.step()
    }

    /// Deletes the listed QSOs in one transaction — bulk deletion from the logbook. Unknown
    /// ids are silently skipped (the row already disappeared another way), an empty list is a no-op.
    public func delete(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try connection.execute("BEGIN")
        do {
            let stmt = try connection.prepare("DELETE FROM qso WHERE id=?")
            defer { stmt.finalize() }
            for id in ids {
                try stmt.bindInt64(id, at: 1)
                try stmt.step()
                try stmt.reset()
            }
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    /// Deletes all QSOs (e.g. when starting a new contest).
    public func deleteAll() throws {
        try connection.execute("DELETE FROM qso")
    }

    // MARK: - Read

    /// Active QSOs (tombstones are excluded — out of dupe/multi/score).
    public func findAll() throws -> [Qso] {
        try queryQsos("SELECT * FROM qso WHERE deleted=0 ORDER BY timestamp_utc ASC, id ASC")
    }

    /// All QSOs including tombstones (for sync/diagnostics). Corresponds to `findAllIncludingDeleted()`.
    public func findAllIncludingDeleted() throws -> [Qso] {
        try queryQsos("SELECT * FROM qso ORDER BY timestamp_utc ASC, id ASC")
    }

    /// Finds a QSO by its primary key (also a tombstone); `nil` = no such row. Used by the log-table writes to take
    /// the stored state as authoritative (`LogbookMutations`).
    public func findById(_ id: Int64) throws -> Qso? {
        let stmt = try connection.prepare("SELECT * FROM qso WHERE id=?")
        defer { stmt.finalize() }
        try stmt.bindInt64(id, at: 1)
        guard try stmt.step() else { return nil }
        return mapRow(stmt)
    }

    /// Finds a QSO by the network merge key `uuid`. Corresponds to `findByUuid`
    /// (Java returns `Optional<Qso>`, here a plain `Qso?`).
    public func findByUuid(_ uuid: String) throws -> Qso? {
        let stmt = try connection.prepare("SELECT * FROM qso WHERE uuid=?")
        defer { stmt.finalize() }
        try stmt.bindText(uuid, at: 1)
        guard try stmt.step() else { return nil }
        return mapRow(stmt)
    }

    /// Merges an incoming QSO state into the replica by `uuid` (LWW by `version`).
    /// Applied only if the incoming `version` is **strictly higher** than the local one
    /// (an older and an equal version are discarded — idempotence); an unknown `uuid` is inserted.
    /// The local `id` (PK) is preserved. Corresponds to `upsertByUuid`.
    public func upsertByUuid(_ qso: Qso) throws {
        guard !JavaText.isBlank(qso.uuid) else {
            throw LogbookError("upsertByUuid vyžaduje uuid")
        }
        if let existing = try findByUuid(qso.uuid) {
            if qso.version > existing.version {
                var toUpdate = qso
                toUpdate.id = existing.id
                try update(toUpdate)
            }
            // otherwise: older or equal version — ignore (LWW)
        } else {
            var toInsert = qso
            try insert(&toInsert)
        }
    }

    /// Marks the QSO of the given `uuid` as deleted (tombstone) with LWW by `version`.
    /// If the QSO does not exist, it is a no-op (out-of-order delivery is handled by the event log
    /// in the cluster app). Corresponds to `markDeleted`.
    ///
    /// `updatedAtUtc` is optional: Java receives `null` (a tombstone without payload
    /// from `InMemorySyncTransport`, a state without a time) and writes it to the `updated_at_utc` column as `NULL`.
    public func markDeleted(uuid: String, version: Int64, updatedAtUtc: Date?) throws {
        guard let existing = try findByUuid(uuid), version > existing.version else { return }
        var q = existing
        q.deleted = true
        q.version = version
        q.updatedAtUtc = updatedAtUtc
        try update(q)
    }

    public func count() throws -> Int {
        let stmt = try connection.prepare("SELECT COUNT(*) FROM qso")
        defer { stmt.finalize() }
        guard try stmt.step() else { return 0 }
        return Int(stmt.columnInt64(at: 0))
    }

    // MARK: - Splitting by contest

    /// The empty sentinel `""` (Swift) at the boundary to SQL corresponds to Java `null`.
    ///
    /// Java holds `contestId` as a `String` **with a possible `null` value** and sends it everywhere
    /// via `ps.setString(…)`, which binds SQL `NULL` for `null`. Swift has `Qso.contestId`
    /// and `LogbookService.activeContestId` non-optional with a default of `""`, so `""` must be
    /// translated back to `nil` at this single boundary — otherwise an empty `TEXT` is written to the file
    /// where Java writes `NULL`, and `contest_id=?` would then match rows
    /// that would match nothing in Java (`NULL = NULL` is `NULL` in SQL, i.e. false).
    private static func sqlContestId(_ contestId: String) -> String? {
        contestId.isEmpty ? nil : contestId
    }

    /// Active QSOs of the given contest (tombstones excluded). Corresponds to `findAll(String)`.
    ///
    /// Without an active contest (`contestId == ""`, Java `null`) SQL `NULL` is bound
    /// and `contest_id=?` returns **nothing, ever** — including rows that themselves have
    /// `contest_id IS NULL`. That is not a bug but the literal Java semantics
    /// (`ps.setString(1, null)` + `contest_id=?`); hence `=?` stays here, not `IS ?`.
    public func findAll(contestId: String) throws -> [Qso] {
        let stmt = try connection.prepare(
            "SELECT * FROM qso WHERE deleted=0 AND contest_id=? ORDER BY timestamp_utc ASC, id ASC")
        defer { stmt.finalize() }
        try stmt.bindText(Self.sqlContestId(contestId), at: 1)
        var result: [Qso] = []
        while try stmt.step() {
            result.append(mapRow(stmt))
        }
        return result
    }

    /// Corresponds to `count(String)`. Without an active contest (`""`) it returns `0` for the same
    /// reason as `findAll(contestId:)` above.
    public func count(contestId: String) throws -> Int {
        let stmt = try connection.prepare("SELECT COUNT(*) FROM qso WHERE deleted=0 AND contest_id=?")
        defer { stmt.finalize() }
        try stmt.bindText(Self.sqlContestId(contestId), at: 1)
        guard try stmt.step() else { return 0 }
        return Int(stmt.columnInt64(at: 0))
    }

    /// The next serial number for the given contest — sent on the air. Computes `count(contestId:) + 1`,
    /// i.e. exactly what `findAll(contestId:)` returns (active QSOs, `xqso` counts,
    /// tombstone does not): an empty contest → `1`. Without an active contest (`""`) it is always `1`,
    /// because `count(contestId: "")` is always `0` — as in Java. Corresponds to
    /// `nextSerial(String)`.
    public func nextSerial(contestId: String) throws -> Int {
        try count(contestId: contestId) + 1
    }

    // MARK: - QTC (WAE)

    /// Saves a new QTC and returns its assigned id. Corresponds to `insertQtc`.
    @discardableResult
    public func insertQtc(_ q: QtcRecord) throws -> Int64 {
        let stmt = try connection.prepare("""
            INSERT INTO qtc (contest_id, sent, partner_call, group_nr, group_size, qso_time, qso_call,
                             qso_serial, at_utc, freq_hz, mode) VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """)
        defer { stmt.finalize() }
        try stmt.bindText(q.contestId, at: 1)
        try stmt.bindBool(q.sent, at: 2)
        try stmt.bindText(q.partnerCall, at: 3)
        try stmt.bindInt(q.groupNr, at: 4)
        try stmt.bindInt(q.groupSize, at: 5)
        try stmt.bindText(q.qsoTime, at: 6)
        try stmt.bindText(q.qsoCall, at: 7)
        try stmt.bindInt(q.qsoSerial, at: 8)
        try stmt.bindText(QtcRecord.formatAtUtc(q.at), at: 9)
        try stmt.bindInt64(q.freqHz, at: 10)
        try stmt.bindText(q.mode, at: 11)
        try stmt.step()
        return connection.lastInsertRowID()
    }

    /// Corresponds to `findQtcs` — `contest_id IS ?`, not `=?`, so that `nil` also compares
    /// against `NULL` rows (QTCs without an assigned contest).
    public func findQtcs(contestId: String?) throws -> [QtcRecord] {
        let stmt = try connection.prepare("SELECT * FROM qtc WHERE contest_id IS ? ORDER BY at_utc, id")
        defer { stmt.finalize() }
        try stmt.bindText(contestId, at: 1)
        var out: [QtcRecord] = []
        while try stmt.step() {
            out.append(QtcRecord(
                id: stmt.columnInt64(forName: "id"),
                contestId: stmt.columnText(forName: "contest_id"),
                sent: stmt.columnInt(forName: "sent") != 0,
                partnerCall: stmt.columnText(forName: "partner_call") ?? "",
                groupNr: Int(stmt.columnInt(forName: "group_nr")),
                groupSize: Int(stmt.columnInt(forName: "group_size")),
                qsoTime: stmt.columnText(forName: "qso_time") ?? "",
                qsoCall: stmt.columnText(forName: "qso_call") ?? "",
                qsoSerial: Int(stmt.columnInt(forName: "qso_serial")),
                at: QtcRecord.parseAtUtc(stmt.columnText(forName: "at_utc") ?? "") ?? Date(timeIntervalSince1970: 0),
                freqHz: stmt.columnInt64(forName: "freq_hz"),
                mode: stmt.columnText(forName: "mode")
            ))
        }
        return out
    }

    /// Corresponds to `deleteQtc`.
    public func deleteQtc(id: Int64) throws {
        let stmt = try connection.prepare("DELETE FROM qtc WHERE id=?")
        defer { stmt.finalize() }
        try stmt.bindInt64(id, at: 1)
        try stmt.step()
    }

    // MARK: - `meta` (delegation to `LogbookDatabase`)

    /// Corresponds to `metaGet` — in Java a method directly on `LogbookRepository`; here
    /// persistence is split, hence a thin delegation to `logbookDatabase`.
    public func metaGet(_ key: String) throws -> String? {
        try logbookDatabase.metaGet(key)
    }

    /// Corresponds to `metaSet`.
    public func metaSet(_ key: String, _ value: String) throws {
        try logbookDatabase.metaSet(key, value)
    }

    private func queryQsos(_ sql: String) throws -> [Qso] {
        let stmt = try connection.prepare(sql)
        defer { stmt.finalize() }
        var result: [Qso] = []
        while try stmt.step() {
            result.append(mapRow(stmt))
        }
        return result
    }

    // MARK: - Parameter binding / row mapping

    /// Binds the `qso` values to the `?` parameters in the same order as the `INSERT`/`UPDATE`
    /// above has them (corresponds to the private `bind` in Java). Returns the index of the next free parameter —
    /// `update` continues with `WHERE id=?` from it, exactly like `int next = bind(ps, qso)` in Java.
    @discardableResult
    private func bind(_ stmt: SQLiteStatement, _ qso: Qso) throws -> Int32 {
        var i: Int32 = 1
        try stmt.bindInt64(try qso.timestampUtc.map(Self.epochMillis) ?? 0, at: i); i += 1
        try stmt.bindText(qso.call, at: i); i += 1
        try stmt.bindInt64(Int64(qso.freqHz), at: i); i += 1
        try stmt.bindText(qso.band?.javaName, at: i); i += 1
        try stmt.bindText(qso.mode?.rawValue, at: i); i += 1
        try stmt.bindText(qso.rstSent, at: i); i += 1
        try stmt.bindText(qso.rstRcvd, at: i); i += 1
        try stmt.bindText(qso.exchangeSent, at: i); i += 1
        try stmt.bindText(qso.exchangeRcvd, at: i); i += 1
        try stmt.bindInt(qso.serialSent, at: i); i += 1
        try stmt.bindInt(qso.serialRcvd, at: i); i += 1
        try stmt.bindInt(qso.points, at: i); i += 1
        try stmt.bindBool(qso.multiplier, at: i); i += 1
        try stmt.bindText(qso.runMode.rawValue, at: i); i += 1
        try stmt.bindText(qso.`operator`, at: i); i += 1
        try stmt.bindText(qso.comment, at: i); i += 1
        try stmt.bindInt(qso.dxccEntity, at: i); i += 1
        try stmt.bindText(qso.dxccName, at: i); i += 1
        try stmt.bindText(qso.continent, at: i); i += 1
        try stmt.bindText(qso.uuid, at: i); i += 1
        try stmt.bindText(qso.stationId, at: i); i += 1
        try stmt.bindInt64(qso.version, at: i); i += 1
        try stmt.bindInt64(try qso.updatedAtUtc.map(Self.epochMillis), at: i); i += 1
        try stmt.bindBool(qso.deleted, at: i); i += 1
        try stmt.bindText(Self.sqlContestId(qso.contestId), at: i); i += 1
        try stmt.bindBool(qso.xqso, at: i); i += 1
        return i
    }

    /// Builds a `Qso` from the current `SELECT *` row.
    ///
    /// It must go through `var q = Qso()` and subsequent assignments outside this type — assignments
    /// inside `Qso`'s own init would not fire `didSet` on `call`/`freqHz` (Swift
    /// does not call a property observer on the first assignment inside the init of the same instance),
    /// so the callsign would not be normalized and the band not derived from the raw frequency.
    /// `Qso()` is a finished instance before it is assigned to from here, so
    /// every assignment below is a normal outside mutation and the observers run.
    private func mapRow(_ stmt: SQLiteStatement) -> Qso {
        var q = Qso()
        q.id = stmt.columnInt64(forName: "id")
        q.timestampUtc = Self.date(fromEpochMillis: stmt.columnInt64(forName: "timestamp_utc"))
        q.call = stmt.columnText(forName: "call") ?? ""
        q.freqHz = Int(stmt.columnInt64(forName: "freq_hz"))
        if let raw = stmt.columnText(forName: "band"), let band = Band(javaName: raw) {
            q.band = band
        }
        if let raw = stmt.columnText(forName: "mode"), let mode = Mode(rawValue: raw) {
            q.mode = mode
        }
        q.rstSent = stmt.columnText(forName: "rst_sent") ?? ""
        q.rstRcvd = stmt.columnText(forName: "rst_rcvd") ?? ""
        q.exchangeSent = stmt.columnText(forName: "exchange_sent") ?? ""
        q.exchangeRcvd = stmt.columnText(forName: "exchange_rcvd") ?? ""
        q.serialSent = nullableInt(stmt, forName: "serial_sent")
        q.serialRcvd = nullableInt(stmt, forName: "serial_rcvd")
        q.points = Int(stmt.columnInt(forName: "points"))
        q.multiplier = stmt.columnInt(forName: "multiplier") != 0
        if let raw = stmt.columnText(forName: "run_mode"), let runMode = RunMode(rawValue: raw) {
            q.runMode = runMode
        }
        q.`operator` = stmt.columnText(forName: "operator") ?? ""
        q.comment = stmt.columnText(forName: "comment") ?? ""
        q.dxccEntity = nullableInt(stmt, forName: "dxcc_entity")
        q.dxccName = stmt.columnText(forName: "dxcc_name") ?? ""
        q.continent = stmt.columnText(forName: "continent") ?? ""
        q.uuid = stmt.columnText(forName: "uuid") ?? ""
        q.stationId = stmt.columnText(forName: "station_id") ?? ""
        q.version = stmt.columnInt64(forName: "version")
        q.updatedAtUtc = stmt.isNull(forName: "updated_at_utc")
            ? nil
            : Self.date(fromEpochMillis: stmt.columnInt64(forName: "updated_at_utc"))
        q.deleted = stmt.columnInt(forName: "deleted") != 0
        q.contestId = stmt.columnText(forName: "contest_id") ?? ""
        q.xqso = stmt.columnInt(forName: "xqso") != 0
        // q.imported is not mapped: in Java it is `transient`, there is no column for it.
        return q
    }

    private func nullableInt(_ stmt: SQLiteStatement, forName name: String) -> Int? {
        stmt.isNull(forName: name) ? nil : Int(stmt.columnInt(forName: name))
    }

    /// Milliseconds since the epoch — **truncation**, not rounding.
    ///
    /// Java `Instant.toEpochMilli()` is `seconds * 1000 + nanos / 1_000_000`
    /// with integer division, i.e. floor. With rounding (the state before the fix) the
    /// instant `…000.9996 s` was stored a millisecond higher and after formatting to seconds
    /// came out a **whole second** different from Java (`…:40` vs. `…:41`). It affects
    /// both `timestamp_utc` and `updated_at_utc`, whose source is `Date()` with a random
    /// fraction.
    ///
    /// Note on precision: `Date` is a `Double`, so `Double(ms) / 1000` need not
    /// sit *exactly* on a millisecond and truncation could in theory shift a round-trip
    /// read→write down by 1 ms. Measured (5,000,000 random values):
    /// in the range **2004-11-03 to 2038-01-19** this does not happen even once — in that
    /// band the division error is less than half a ULP of the product, so the multiple comes back
    /// exactly. Outside it (and never for whole seconds, those are exact in a `Double`) a
    /// 1 ms shift could occur; on the formatted output (ADIF, Cabrillo, the time
    /// column — all in seconds) it does not show even then, because it does not
    /// cross the second boundary.
    ///
    /// A time whose milliseconds do not fit an `Int64` (a year beyond ~292 million, reachable by editing the time cell —
    /// Java `toEpochMilli` throws `ArithmeticException: long overflow` there) throws a `LogbookError` instead of trapping.
    static func epochMillis(_ date: Date) throws -> Int64 {
        guard let millis = Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded(.down)) else {
            throw LogbookError("Čas QSO je mimo rozsah (long overflow)")
        }
        return millis
    }

    private static func date(fromEpochMillis millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }
}

/// Mapping to the name of the Java enum constant (`Enum.name()`), not to the ADIF `rawValue`
/// (`"160m"`), which `Band` uses in Swift for other purposes (log export/import).
/// `LogbookRepository.bind`/`map` in Java store and read via `Band.valueOf(name)`/
/// `band.name()` — without this mapping `"160m"` would be written to the DB instead of `"M160"`
/// and reading an older (Java) database would silently lose the band.
extension Band {
    var javaName: String {
        switch self {
        case .m160: "M160"
        case .m80: "M80"
        case .m60: "M60"
        case .m40: "M40"
        case .m30: "M30"
        case .m20: "M20"
        case .m17: "M17"
        case .m15: "M15"
        case .m12: "M12"
        case .m10: "M10"
        case .m6: "M6"
        case .m2: "M2"
        case .cm70: "CM70"
        case .cm23: "CM23"
        case .cm13: "CM13"
        case .cm9: "CM9"
        case .cm6: "CM6"
        case .cm3: "CM3"
        }
    }

    init?(javaName: String) {
        switch javaName {
        case "M160": self = .m160
        case "M80": self = .m80
        case "M60": self = .m60
        case "M40": self = .m40
        case "M30": self = .m30
        case "M20": self = .m20
        case "M17": self = .m17
        case "M15": self = .m15
        case "M12": self = .m12
        case "M10": self = .m10
        case "M6": self = .m6
        case "M2": self = .m2
        case "CM70": self = .cm70
        case "CM23": self = .cm23
        case "CM13": self = .cm13
        case "CM9": self = .cm9
        case "CM6": self = .cm6
        case "CM3": self = .cm3
        default: return nil
        }
    }
}
