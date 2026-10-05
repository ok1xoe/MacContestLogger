import Foundation
import Testing
@testable import MCLCore

/// `QtcRecord` and the SQLite wrapper itself have no direct test in Java — `LogbookRepository`
/// (whose constructor/DDL/`migrateSyncColumns`/`metaGet`/`metaSet`/`close` are covered here as the
/// specification) is tested via `LogbookRepositoryTest`, but that also exercises
/// `insert`/`findAll` (qso CRUD), which is tested elsewhere. This suite therefore **does not port**
/// any particular Java test 1:1; instead it verifies the same thing the
/// port of `LogbookRepositoryTest.opensAndMigratesLegacySchema` and of the constructor/DDL would have to verify,
/// only without qso CRUD — and additionally the schema column by column against `LogbookRepository.initSchema`.
@Suite struct SQLiteTests {

    // MARK: - Helpers

    /// One row of `PRAGMA table_info(<table>)`.
    private struct ColumnInfo: Equatable {
        let name: String
        let type: String
        let notNull: Bool
        let defaultValue: String?
        let primaryKey: Bool
    }

    private func columns(of table: String, in db: SQLiteDatabase) throws -> [ColumnInfo] {
        let stmt = try db.prepare("PRAGMA table_info(\(table))")
        defer { stmt.finalize() }
        var result: [ColumnInfo] = []
        while try stmt.step() {
            result.append(ColumnInfo(
                name: stmt.columnText(forName: "name") ?? "",
                type: stmt.columnText(forName: "type") ?? "",
                notNull: stmt.columnInt(forName: "notnull") != 0,
                defaultValue: stmt.columnText(forName: "dflt_value"),
                primaryKey: stmt.columnInt(forName: "pk") != 0
            ))
        }
        return result
    }

    private func tempDbURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-test-\(UUID().uuidString).sqlite")
    }

    // MARK: - Opening

    @Test func opensInMemoryDatabase() throws {
        let db = try LogbookDatabase.inMemory()
        let count = try db.database.prepare("SELECT COUNT(*) FROM qso")
        defer { count.finalize() }
        #expect(try count.step())
        #expect(count.columnInt64(at: 0) == 0)
    }

    @Test func opensFileDatabaseCreatingItIfMissing() throws {
        let url = tempDbURL()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let db = try LogbookDatabase(url: url)
        db.close()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Schema of `qso` — column by column against `LogbookRepository.initSchema`

    @Test func qsoTableSchemaMatchesJavaDdl() throws {
        let db = try LogbookDatabase.inMemory()
        let actual = try columns(of: "qso", in: db.database)
        let expected: [ColumnInfo] = [
            ColumnInfo(name: "id", type: "INTEGER", notNull: false, defaultValue: nil, primaryKey: true),
            ColumnInfo(name: "timestamp_utc", type: "INTEGER", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "call", type: "TEXT", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "freq_hz", type: "INTEGER", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "band", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "mode", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "rst_sent", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "rst_rcvd", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "exchange_sent", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "exchange_rcvd", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "serial_sent", type: "INTEGER", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "serial_rcvd", type: "INTEGER", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "points", type: "INTEGER", notNull: true, defaultValue: "0", primaryKey: false),
            ColumnInfo(name: "multiplier", type: "INTEGER", notNull: true, defaultValue: "0", primaryKey: false),
            ColumnInfo(name: "run_mode", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "operator", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "comment", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "dxcc_entity", type: "INTEGER", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "dxcc_name", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "continent", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "uuid", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "station_id", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "version", type: "INTEGER", notNull: true, defaultValue: "0", primaryKey: false),
            ColumnInfo(name: "updated_at_utc", type: "INTEGER", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "deleted", type: "INTEGER", notNull: true, defaultValue: "0", primaryKey: false),
            ColumnInfo(name: "contest_id", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "xqso", type: "INTEGER", notNull: true, defaultValue: "0", primaryKey: false),
        ]
        #expect(actual == expected)
    }

    @Test func metaTableSchema() throws {
        let db = try LogbookDatabase.inMemory()
        let actual = try columns(of: "meta", in: db.database)
        let expected: [ColumnInfo] = [
            ColumnInfo(name: "key", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: true),
            ColumnInfo(name: "value", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
        ]
        #expect(actual == expected)
    }

    @Test func qtcTableSchema() throws {
        let db = try LogbookDatabase.inMemory()
        let actual = try columns(of: "qtc", in: db.database)
        let expected: [ColumnInfo] = [
            ColumnInfo(name: "id", type: "INTEGER", notNull: false, defaultValue: nil, primaryKey: true),
            ColumnInfo(name: "contest_id", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "sent", type: "INTEGER", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "partner_call", type: "TEXT", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "group_nr", type: "INTEGER", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "group_size", type: "INTEGER", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "qso_time", type: "TEXT", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "qso_call", type: "TEXT", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "qso_serial", type: "INTEGER", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "at_utc", type: "TEXT", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "freq_hz", type: "INTEGER", notNull: true, defaultValue: nil, primaryKey: false),
            ColumnInfo(name: "mode", type: "TEXT", notNull: false, defaultValue: nil, primaryKey: false),
        ]
        #expect(actual == expected)
    }

    @Test func uuidUniqueIndexExists() throws {
        let db = try LogbookDatabase.inMemory()
        let stmt = try db.database.prepare(
            "SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_qso_uuid'")
        defer { stmt.finalize() }
        #expect(try stmt.step())
        let sql = stmt.columnText(at: 0) ?? ""
        #expect(sql.contains("UNIQUE"))
        #expect(sql.contains("qso"))
        #expect(sql.contains("uuid"))
    }

    // MARK: - Migration of an older database (`migrateSyncColumns`)

    /// Corresponds to the scenario `LogbookRepositoryTest.opensAndMigratesLegacySchema`, only
    /// without `insert`/`findAll` — verifies the result of `migrateSyncColumns` directly:
    /// an older DB without sync columns and without `contest_id` opens, the columns are added and
    /// existing rows (without `contest_id`) are deleted during the one-off migration to multi-contest.
    @Test func migratesLegacySchemaAddingSyncColumnsAndClearingRows() throws {
        let url = tempDbURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let legacy = try SQLiteDatabase.open(at: url.path)
        try legacy.execute("""
            CREATE TABLE qso (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp_utc INTEGER NOT NULL,
                call          TEXT    NOT NULL,
                freq_hz       INTEGER NOT NULL,
                band          TEXT,
                mode          TEXT,
                rst_sent      TEXT,
                rst_rcvd      TEXT,
                exchange_sent TEXT,
                exchange_rcvd TEXT,
                serial_sent   INTEGER,
                serial_rcvd   INTEGER,
                points        INTEGER NOT NULL DEFAULT 0,
                multiplier    INTEGER NOT NULL DEFAULT 0,
                run_mode      TEXT,
                operator      TEXT,
                comment       TEXT,
                dxcc_entity   INTEGER,
                dxcc_name     TEXT,
                continent     TEXT
            )
            """)
        try legacy.execute("INSERT INTO qso (timestamp_utc, call, freq_hz) VALUES (0, 'OLD1ABC', 14074000)")
        legacy.close()

        // Opening the old DB must not crash.
        let migrated = try LogbookDatabase(url: url)
        let names = Set(try columns(of: "qso", in: migrated.database).map(\.name))
        #expect(names.isSuperset(of: [
            "uuid", "station_id", "version", "updated_at_utc", "deleted", "xqso", "contest_id",
        ]))

        let count = try migrated.database.prepare("SELECT COUNT(*) FROM qso")
        defer { count.finalize() }
        #expect(try count.step())
        // A missing contest_id triggered the one-off migration to multi-contest, which
        // deletes the old QSOs (a clean start) — the DB stays usable for new writes, though.
        #expect(count.columnInt64(at: 0) == 0)
    }

    @Test func migrationIsIdempotentAndPreservesDataOnReopen() throws {
        let url = tempDbURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try LogbookDatabase(url: url)
        try first.metaSet("greeting", "ahoj")
        first.close()

        // Reopening an already current DB (it also has contest_id) must not delete anything or crash.
        let second = try LogbookDatabase(url: url)
        #expect(try second.metaGet("greeting") == "ahoj")
        second.close()
    }

    // MARK: - `meta` key/value

    @Test func metaGetReturnsNilForMissingKey() throws {
        let db = try LogbookDatabase.inMemory()
        #expect(try db.metaGet("chybi") == nil)
    }

    @Test func metaSetAndGetRoundTrip() throws {
        let db = try LogbookDatabase.inMemory()
        try db.metaSet("schemaVersion", "3")
        #expect(try db.metaGet("schemaVersion") == "3")
    }

    @Test func metaSetUpdatesExistingKeyInsteadOfDuplicating() throws {
        let db = try LogbookDatabase.inMemory()
        try db.metaSet("k", "prvni")
        try db.metaSet("k", "druha")
        #expect(try db.metaGet("k") == "druha")

        let count = try db.database.prepare("SELECT COUNT(*) FROM meta WHERE key='k'")
        defer { count.finalize() }
        #expect(try count.step())
        #expect(count.columnInt64(at: 0) == 1)
    }

    // MARK: - Unique index `uuid` — multiple NULLs allowed, a duplicate value not

    private func insertMinimalQso(_ db: SQLiteDatabase, call: String, uuid: String?) throws {
        let stmt = try db.prepare("INSERT INTO qso (timestamp_utc, call, freq_hz, uuid) VALUES (0, ?, 14074000, ?)")
        defer { stmt.finalize() }
        try stmt.bindText(call, at: 1)
        try stmt.bindText(uuid, at: 2)
        try stmt.step()
    }

    @Test func uuidIndexAllowsMultipleNullValues() throws {
        let db = try LogbookDatabase.inMemory()
        try insertMinimalQso(db.database, call: "AA1AAA", uuid: nil)
        try insertMinimalQso(db.database, call: "BB1BBB", uuid: nil)
        let count = try db.database.prepare("SELECT COUNT(*) FROM qso")
        defer { count.finalize() }
        #expect(try count.step())
        #expect(count.columnInt64(at: 0) == 2)
    }

    @Test func uuidIndexRejectsDuplicateNonNullValue() throws {
        let db = try LogbookDatabase.inMemory()
        try insertMinimalQso(db.database, call: "AA1AAA", uuid: "same-uuid")
        #expect(throws: LogbookError.self) {
            try insertMinimalQso(db.database, call: "BB1BBB", uuid: "same-uuid")
        }
    }

    // MARK: - General wrapper behaviour: bound parameters, iteration, typed NULL columns

    @Test func statementBindsAndReadsTypedColumnsIncludingNulls() throws {
        let db = try SQLiteDatabase.openInMemory()
        try db.execute("CREATE TABLE t (a INTEGER, b TEXT)")

        let insert = try db.prepare("INSERT INTO t (a, b) VALUES (?, ?)")
        try insert.bindInt64(1, at: 1)
        try insert.bindText("jedna", at: 2)
        try insert.step()
        insert.finalize()

        let insertNulls = try db.prepare("INSERT INTO t (a, b) VALUES (?, ?)")
        try insertNulls.bindInt64(nil, at: 1)
        try insertNulls.bindText(nil, at: 2)
        try insertNulls.step()
        insertNulls.finalize()

        let select = try db.prepare("SELECT a, b FROM t ORDER BY rowid")
        defer { select.finalize() }

        #expect(try select.step())
        #expect(select.isNull(at: 0) == false)
        #expect(select.columnInt64(at: 0) == 1)
        // sqlite3_column_text on an INTEGER column returns the text representation (SQLite type conversion), not nil.
        #expect(select.columnText(at: 0) == "1")
        #expect(select.columnText(at: 1) == "jedna")
        #expect(select.columnText(forName: "b") == "jedna")
        #expect(select.columnInt64(forName: "a") == 1)

        #expect(try select.step())
        #expect(select.isNull(at: 0))
        #expect(select.isNull(forName: "b"))
        #expect(select.columnText(at: 1) == nil)

        #expect(try select.step() == false) // end
    }

    @Test func executeThrowsLogbookErrorOnInvalidSql() throws {
        let db = try SQLiteDatabase.openInMemory()
        #expect(throws: LogbookError.self) {
            try db.execute("TOTAL NESMYSL")
        }
    }

    @Test func lastInsertRowIdReflectsAutoincrement() throws {
        let db = try SQLiteDatabase.openInMemory()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)")
        let stmt = try db.prepare("INSERT INTO t (v) VALUES (?)")
        try stmt.bindText("x", at: 1)
        try stmt.step()
        stmt.finalize()
        #expect(db.lastInsertRowID() == 1)
    }

    // MARK: - `QtcRecord` — no Java test, covered by our own row encoding/decoding

    @Test func qtcRecordRoundTripsThroughQtcTable() throws {
        let db = try LogbookDatabase.inMemory()
        let at = Date(timeIntervalSince1970: 1_750_000_000.123)
        let record = QtcRecord(
            contestId: "weae-2026",
            sent: true,
            partnerCall: "OK1XOE",
            groupNr: 2,
            groupSize: 10,
            qsoTime: "1230",
            qsoCall: "DL1ABC",
            qsoSerial: 42,
            at: at,
            freqHz: 3_560_000,
            mode: "CW"
        )

        let insert = try db.database.prepare("""
            INSERT INTO qtc (contest_id, sent, partner_call, group_nr, group_size, qso_time, qso_call,
                             qso_serial, at_utc, freq_hz, mode) VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """)
        try insert.bindText(record.contestId, at: 1)
        try insert.bindBool(record.sent, at: 2)
        try insert.bindText(record.partnerCall, at: 3)
        try insert.bindInt(record.groupNr, at: 4)
        try insert.bindInt(record.groupSize, at: 5)
        try insert.bindText(record.qsoTime, at: 6)
        try insert.bindText(record.qsoCall, at: 7)
        try insert.bindInt(record.qsoSerial, at: 8)
        try insert.bindText(QtcRecord.formatAtUtc(record.at), at: 9)
        try insert.bindInt64(record.freqHz, at: 10)
        try insert.bindText(record.mode, at: 11)
        try insert.step()
        insert.finalize()
        let generatedId = db.database.lastInsertRowID()

        let select = try db.database.prepare("SELECT * FROM qtc WHERE id = ?")
        defer { select.finalize() }
        try select.bindInt64(generatedId, at: 1)
        #expect(try select.step())

        let decodedAt = QtcRecord.parseAtUtc(select.columnText(forName: "at_utc") ?? "")
        let decoded = QtcRecord(
            id: select.columnInt64(forName: "id"),
            contestId: select.columnText(forName: "contest_id"),
            sent: select.columnInt(forName: "sent") != 0,
            partnerCall: select.columnText(forName: "partner_call") ?? "",
            groupNr: Int(select.columnInt(forName: "group_nr")),
            groupSize: Int(select.columnInt(forName: "group_size")),
            qsoTime: select.columnText(forName: "qso_time") ?? "",
            qsoCall: select.columnText(forName: "qso_call") ?? "",
            qsoSerial: Int(select.columnInt(forName: "qso_serial")),
            at: try #require(decodedAt),
            freqHz: select.columnInt64(forName: "freq_hz"),
            mode: select.columnText(forName: "mode")
        )

        #expect(decoded.id == generatedId)
        #expect(decoded.contestId == record.contestId)
        #expect(decoded.sent == record.sent)
        #expect(decoded.partnerCall == record.partnerCall)
        #expect(decoded.groupNr == record.groupNr)
        #expect(decoded.groupSize == record.groupSize)
        #expect(decoded.qsoTime == record.qsoTime)
        #expect(decoded.qsoCall == record.qsoCall)
        #expect(decoded.qsoSerial == record.qsoSerial)
        #expect(abs(decoded.at.timeIntervalSince1970 - record.at.timeIntervalSince1970) < 0.001)
        #expect(decoded.freqHz == record.freqHz)
        #expect(decoded.mode == record.mode)
    }

    @Test func qtcRecordEncodesNullContestIdAndMode() throws {
        let db = try LogbookDatabase.inMemory()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let record = QtcRecord(
            contestId: nil,
            sent: false,
            partnerCall: "OK1ABC",
            groupNr: 1,
            groupSize: 5,
            qsoTime: "0800",
            qsoCall: "G1XYZ",
            qsoSerial: 7,
            at: at,
            freqHz: 7_040_000,
            mode: nil
        )

        let insert = try db.database.prepare("""
            INSERT INTO qtc (contest_id, sent, partner_call, group_nr, group_size, qso_time, qso_call,
                             qso_serial, at_utc, freq_hz, mode) VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """)
        try insert.bindText(record.contestId, at: 1)
        try insert.bindBool(record.sent, at: 2)
        try insert.bindText(record.partnerCall, at: 3)
        try insert.bindInt(record.groupNr, at: 4)
        try insert.bindInt(record.groupSize, at: 5)
        try insert.bindText(record.qsoTime, at: 6)
        try insert.bindText(record.qsoCall, at: 7)
        try insert.bindInt(record.qsoSerial, at: 8)
        try insert.bindText(QtcRecord.formatAtUtc(record.at), at: 9)
        try insert.bindInt64(record.freqHz, at: 10)
        try insert.bindText(record.mode, at: 11)
        try insert.step()
        insert.finalize()

        let select = try db.database.prepare("SELECT contest_id, mode FROM qtc")
        defer { select.finalize() }
        #expect(try select.step())
        #expect(select.isNull(forName: "contest_id"))
        #expect(select.isNull(forName: "mode"))
    }
}
