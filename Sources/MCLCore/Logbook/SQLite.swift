import Foundation
import SQLite3

/// Error when working with the SQLite logbook (QSO/QTC persistence). Analogous to Java
/// `LogbookException` — it supplements the message with the error text from SQLite, instead of holding
/// a separate `cause` (JDBC `SQLException`) we wire the text straight into the message.
public struct LogbookError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// `sqlite3_bind_text`/`sqlite3_bind_blob` need a destructor for the string copy;
/// `SQLITE_TRANSIENT` (in the C header the macro `(sqlite3_destructor_type)-1`) tells
/// SQLite to copy the data immediately, because Swift `String` is not held after the call.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A thin wrapper over the SQLite3 C API: opening a file or `:memory:`, executing a
/// statement without parameters and preparing a query with bound parameters. No ORM —
/// just what `LogbookDatabase` and the repository built on it in later
/// tasks need.
public final class SQLiteDatabase {
    private let handle: OpaquePointer
    /// A connection may be closed only once. Both `close()` and `deinit` call `sqlite3_close_v2`,
    /// and a second close of the same pointer is a use-after-free: SQLite
    /// returns the connection memory to the system allocator (`SQLITE_SYSTEM_MALLOC`) and it may
    /// meanwhile be allocated to another, live connection — the second `close_v2` then breaks someone else's
    /// database (`SQLITE_MISUSE`, "no such table", or an outright crash). The same safeguard
    /// as `finalized` in `SQLiteStatement`.
    private var closed = false

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    /// Opens (or creates, if it does not exist) the SQLite database file.
    ///
    /// The system SQLite on macOS is built with `SQLITE_THREADSAFE=2` (multi-thread),
    /// so a connection opened via `sqlite3_open` has no mutex of its own and must not be used
    /// from two threads at once. But the logbook shares one connection between the UI and background threads
    /// (CAT, network replication), so we open via `sqlite3_open_v2` with `SQLITE_OPEN_FULLMUTEX`
    /// — serialized mode is enabled per connection in mode 2.
    public static func open(at path: String) throws -> SQLiteDatabase {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(
            path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil)
        guard rc == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "neznámá chyba"
            if let handle { sqlite3_close_v2(handle) }
            throw LogbookError("Nelze otevřít deník: \(path) (\(message))")
        }
        return SQLiteDatabase(handle: handle)
    }

    /// In-memory variant for tests — always a new, empty database.
    public static func openInMemory() throws -> SQLiteDatabase {
        try open(at: ":memory:")
    }

    /// Executes one or more SQL statements without bound parameters (DDL, `ALTER TABLE`, `DELETE FROM …`…).
    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "neznámá chyba"
            sqlite3_free(errorMessage)
            throw LogbookError("SQL příkaz selhal: \(message)")
        }
    }

    /// Prepares a query/statement with bound parameters (`?`) for further use via `SQLiteStatement`.
    public func prepare(_ sql: String) throws -> SQLiteStatement {
        var stmtHandle: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmtHandle, nil)
        guard rc == SQLITE_OK, let stmtHandle else {
            throw LogbookError("Nelze připravit dotaz: \(lastErrorMessage())")
        }
        return SQLiteStatement(handle: stmtHandle)
    }

    /// Id of the last inserted row (`sqlite3_last_insert_rowid`) — for an `INSERT` that
    /// generates an `AUTOINCREMENT` key (see `Statement.RETURN_GENERATED_KEYS` in Java).
    public func lastInsertRowID() -> Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(handle))
    }

    public func close() {
        guard !closed else { return }
        sqlite3_close_v2(handle)
        closed = true
    }

    deinit {
        if !closed {
            sqlite3_close_v2(handle)
        }
    }
}

/// A prepared SQL statement/query: binding parameters by 1-based index (the same
/// as JDBC `PreparedStatement`), stepping rows and reading typed columns
/// by index and by name (for `SELECT *` mapping, as `LogbookRepository.map` does).
public final class SQLiteStatement {
    private let handle: OpaquePointer
    private var finalized = false

    private lazy var columnIndexByName: [String: Int32] = {
        var map: [String: Int32] = [:]
        let count = sqlite3_column_count(handle)
        guard count > 0 else { return map }
        for i in 0..<count {
            if let cName = sqlite3_column_name(handle, i) {
                map[String(cString: cName)] = i
            }
        }
        return map
    }()

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    // MARK: - Binding parameters (1-based index, like JDBC)

    public func bindInt64(_ value: Int64?, at index: Int32) throws {
        let rc: Int32
        if let value {
            rc = sqlite3_bind_int64(handle, index, value)
        } else {
            rc = sqlite3_bind_null(handle, index)
        }
        try checkBind(rc)
    }

    public func bindInt(_ value: Int?, at index: Int32) throws {
        try bindInt64(value.map(Int64.init), at: index)
    }

    public func bindText(_ value: String?, at index: Int32) throws {
        let rc: Int32
        if let value {
            rc = sqlite3_bind_text(handle, index, value, -1, SQLITE_TRANSIENT)
        } else {
            rc = sqlite3_bind_null(handle, index)
        }
        try checkBind(rc)
    }

    public func bindBool(_ value: Bool, at index: Int32) throws {
        try bindInt64(value ? 1 : 0, at: index)
    }

    private func checkBind(_ rc: Int32) throws {
        guard rc == SQLITE_OK else {
            throw LogbookError("Nelze navázat parametr: \(String(cString: sqlite3_errmsg(sqlite3_db_handle(handle))))")
        }
    }

    // MARK: - Stepping

    /// Advances to the next row. `true` = there is something to read (`SQLITE_ROW`), `false` = end (`SQLITE_DONE`).
    @discardableResult
    public func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw LogbookError("Krok dotazu selhal: \(String(cString: sqlite3_errmsg(sqlite3_db_handle(handle))))")
        }
    }

    public func reset() throws {
        let rc = sqlite3_reset(handle)
        guard rc == SQLITE_OK else {
            throw LogbookError("Nelze resetovat dotaz: \(String(cString: sqlite3_errmsg(sqlite3_db_handle(handle))))")
        }
    }

    public func finalize() {
        guard !finalized else { return }
        sqlite3_finalize(handle)
        finalized = true
    }

    deinit {
        if !finalized {
            sqlite3_finalize(handle)
        }
    }

    // MARK: - Reading columns by index (0-based, like the SQLite C API)

    public func isNull(at index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    public func columnInt64(at index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    public func columnInt(at index: Int32) -> Int32 {
        sqlite3_column_int(handle, index)
    }

    public func columnText(at index: Int32) -> String? {
        guard let cString = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: cString)
    }

    // MARK: - Reading columns by name (for `SELECT *`)

    public func columnIndex(forName name: String) -> Int32? {
        columnIndexByName[name]
    }

    public func isNull(forName name: String) -> Bool {
        guard let index = columnIndex(forName: name) else { return true }
        return isNull(at: index)
    }

    public func columnInt64(forName name: String) -> Int64 {
        guard let index = columnIndex(forName: name) else { return 0 }
        return columnInt64(at: index)
    }

    public func columnInt(forName name: String) -> Int32 {
        guard let index = columnIndex(forName: name) else { return 0 }
        return columnInt(at: index)
    }

    public func columnText(forName name: String) -> String? {
        guard let index = columnIndex(forName: name) else { return nil }
        return columnText(at: index)
    }
}

/// Persistence of QSO/QTC into a single-file SQLite database (analogous to N1MM `.mdb`).
/// Corresponds to the constructor and `initSchema`/`migrateSyncColumns`/`metaGet`/`metaSet`/`close`
/// of Java `LogbookRepository` — CRUD over `qso` lives elsewhere
/// over the shared `database`.
public final class LogbookDatabase {
    /// Shared connection for the repository/service layer built in later tasks.
    public let database: SQLiteDatabase

    /// Opens (or creates) the logbook file. Corresponds to the public constructor
    /// `LogbookRepository(Path dbFile)` — the path is taken as absolute, just as there.
    public convenience init(url: URL) throws {
        try self.init(path: url.absoluteURL.standardizedFileURL.path)
    }

    /// Internal variant via a raw path — shared with `inMemory()`, where `":memory:"`
    /// is not a valid file `URL`.
    private init(path: String) throws {
        database = try SQLiteDatabase.open(at: path)
        try Self.initSchema(database)
    }

    /// In-memory variant for tests.
    public static func inMemory() throws -> LogbookDatabase {
        try LogbookDatabase(path: ":memory:")
    }

    private static func initSchema(_ db: SQLiteDatabase) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS qso (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp_utc  INTEGER NOT NULL,
                call           TEXT    NOT NULL,
                freq_hz        INTEGER NOT NULL,
                band           TEXT,
                mode           TEXT,
                rst_sent       TEXT,
                rst_rcvd       TEXT,
                exchange_sent  TEXT,
                exchange_rcvd  TEXT,
                serial_sent    INTEGER,
                serial_rcvd    INTEGER,
                points         INTEGER NOT NULL DEFAULT 0,
                multiplier     INTEGER NOT NULL DEFAULT 0,
                run_mode       TEXT,
                operator       TEXT,
                comment        TEXT,
                dxcc_entity    INTEGER,
                dxcc_name      TEXT,
                continent      TEXT,
                uuid           TEXT,
                station_id     TEXT,
                version        INTEGER NOT NULL DEFAULT 0,
                updated_at_utc INTEGER,
                deleted        INTEGER NOT NULL DEFAULT 0,
                contest_id     TEXT,
                xqso           INTEGER NOT NULL DEFAULT 0
            )
            """)
        try migrateSyncColumns(db)
        // uuid is the network merge key; UNIQUE (SQLite allows multiple NULLs for old rows).
        try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_qso_uuid ON qso (uuid)")
        try db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
        // QTC (WAE): reports of earlier QSOs; local, cluster sync does not transfer them.
        try db.execute("""
            CREATE TABLE IF NOT EXISTS qtc (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                contest_id   TEXT,
                sent         INTEGER NOT NULL,
                partner_call TEXT NOT NULL,
                group_nr     INTEGER NOT NULL,
                group_size   INTEGER NOT NULL,
                qso_time     TEXT NOT NULL,
                qso_call     TEXT NOT NULL,
                qso_serial   INTEGER NOT NULL,
                at_utc       TEXT NOT NULL,
                freq_hz      INTEGER NOT NULL,
                mode         TEXT
            )
            """)
    }

    /// Adds the sync columns to an older DB created before cluster sync was introduced.
    /// Idempotent — adds only the columns that are not yet in `PRAGMA table_info(qso)`.
    private static func migrateSyncColumns(_ db: SQLiteDatabase) throws {
        var existing = Set<String>()
        let pragma = try db.prepare("PRAGMA table_info(qso)")
        defer { pragma.finalize() }
        while try pragma.step() {
            if let name = pragma.columnText(forName: "name") {
                existing.insert(name.lowercased())
            }
        }
        let required: [(name: String, ddlType: String)] = [
            ("uuid", "TEXT"),
            ("station_id", "TEXT"),
            ("version", "INTEGER NOT NULL DEFAULT 0"),
            ("updated_at_utc", "INTEGER"),
            ("deleted", "INTEGER NOT NULL DEFAULT 0"),
            ("xqso", "INTEGER NOT NULL DEFAULT 0"),
        ]
        for column in required where !existing.contains(column.name) {
            try db.execute("ALTER TABLE qso ADD COLUMN \(column.name) \(column.ddlType)")
        }
        if !existing.contains("contest_id") {
            try db.execute("ALTER TABLE qso ADD COLUMN contest_id TEXT")
            try db.execute("DELETE FROM qso") // migration to multi-contest: start from scratch
        }
    }

    public func metaGet(_ key: String) throws -> String? {
        let stmt = try database.prepare("SELECT value FROM meta WHERE key=?")
        defer { stmt.finalize() }
        try stmt.bindText(key, at: 1)
        guard try stmt.step() else { return nil }
        return stmt.columnText(at: 0)
    }

    public func metaSet(_ key: String, _ value: String) throws {
        let stmt = try database.prepare(
            "INSERT INTO meta (key, value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
        defer { stmt.finalize() }
        try stmt.bindText(key, at: 1)
        try stmt.bindText(value, at: 2)
        try stmt.step()
    }

    public func close() {
        database.close()
    }
}
