import Foundation

/// The `contests` table: a registry of contests in the DB (definition snapshot + setup + station) and their
/// statistics. Despite its name it does not belong to the contest package (`contest/`) — it stores in the same
/// database as the logbook, over the shared `LogbookRepository.connection`, and creates
/// its own table itself (`CREATE TABLE IF NOT EXISTS` in the constructor), exactly like
/// Java `ContestStore` — unlike `qso`/`meta`/`qtc`, which `LogbookDatabase` creates.
public final class ContestStore {

    /// One `contests` row. `startedAt`/`endedAt` are raw epoch milliseconds
    /// (`Long` in Java, without formatting via `Instant.toString()` — unlike
    /// `QtcRecord.at`/`at_utc` these two fields do not go through any textual date
    /// serialization, they are stored and read as a plain integer).
    public struct ContestRow: Equatable, Sendable {
        public var contestId: String
        public var definitionId: String
        public var name: String?
        public var startedAt: Int64?
        public var endedAt: Int64?
        public var definitionYaml: String
        public var setupJson: String?
        public var stationJson: String?

        public init(
            contestId: String,
            definitionId: String,
            name: String?,
            startedAt: Int64?,
            endedAt: Int64?,
            definitionYaml: String,
            setupJson: String?,
            stationJson: String?
        ) {
            self.contestId = contestId
            self.definitionId = definitionId
            self.name = name
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.definitionYaml = definitionYaml
            self.setupJson = setupJson
            self.stationJson = stationJson
        }
    }

    /// Statistics of one contest for the overview screen. `bands` is a list of raw
    /// values of the `qso.band` column (the Java enum constant name, e.g. `"M20"`, see
    /// `LogbookRepository.javaName` elsewhere) — `listSummaries`/`bandsFor` only read them
    /// back, they do not convert.
    public struct ContestSummary: Equatable, Sendable {
        public var contestId: String
        public var definitionId: String
        public var name: String?
        public var startedAt: Int64?
        public var endedAt: Int64?
        public var qsoCount: Int64
        public var bands: [String]
        public var firstQso: Int64?
        public var lastQso: Int64?
    }

    private let connection: SQLiteDatabase

    /// Corresponds to `ContestStore(LogbookRepository repo)` — shares the connection with the logbook and immediately
    /// creates (if missing) the `contests` table.
    public init(_ repository: LogbookRepository) throws {
        connection = repository.connection
        try initSchema()
    }

    private func initSchema() throws {
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS contests (
                contest_id      TEXT PRIMARY KEY,
                definition_id   TEXT NOT NULL,
                name            TEXT,
                started_at      INTEGER,
                ended_at        INTEGER,
                definition_yaml TEXT NOT NULL,
                setup_json      TEXT,
                station_json    TEXT
            )
            """)
    }

    public func insert(_ row: ContestRow) throws {
        let stmt = try connection.prepare("""
            INSERT INTO contests (contest_id, definition_id, name, started_at, ended_at,
                                  definition_yaml, setup_json, station_json)
            VALUES (?,?,?,?,?,?,?,?)
            """)
        defer { stmt.finalize() }
        try stmt.bindText(row.contestId, at: 1)
        try stmt.bindText(row.definitionId, at: 2)
        try stmt.bindText(row.name, at: 3)
        try stmt.bindInt64(row.startedAt, at: 4)
        try stmt.bindInt64(row.endedAt, at: 5)
        try stmt.bindText(row.definitionYaml, at: 6)
        try stmt.bindText(row.setupJson, at: 7)
        try stmt.bindText(row.stationJson, at: 8)
        try stmt.step()
    }

    /// Overwrites the contest setup (skeds, TOUR, bonus stations, category). The setup belongs to
    /// a specific contest, so it lives here next to its definition snapshot — not in
    /// `config.json`, where nobody reads it from.
    ///
    /// - Returns: `false` when the contest is not in the table. Java detects this from `executeUpdate() == 0`
    ///   (no row satisfied the `WHERE`); this wrapper over `SQLiteDatabase` does not expose the number of affected
    ///   rows, so it verifies existence with a separate `SELECT` beforehand — for
    ///   single-threaded access over one file/memory the same result as Java.
    @discardableResult
    public func updateSetup(contestId: String, setupJson: String) throws -> Bool {
        guard try find(contestId) != nil else { return false }
        let stmt = try connection.prepare("UPDATE contests SET setup_json=? WHERE contest_id=?")
        defer { stmt.finalize() }
        try stmt.bindText(setupJson, at: 1)
        try stmt.bindText(contestId, at: 2)
        try stmt.step()
        return true
    }

    public func find(_ contestId: String) throws -> ContestRow? {
        let stmt = try connection.prepare("SELECT * FROM contests WHERE contest_id=?")
        defer { stmt.finalize() }
        try stmt.bindText(contestId, at: 1)
        guard try stmt.step() else { return nil }
        return mapRow(stmt)
    }

    public func listSummaries() throws -> [ContestSummary] {
        let stmt = try connection.prepare("""
            SELECT c.contest_id, c.definition_id, c.name, c.started_at, c.ended_at,
                   COUNT(q.id) AS qso_count, MIN(q.timestamp_utc) AS first_q, MAX(q.timestamp_utc) AS last_q
            FROM contests c
            LEFT JOIN qso q ON q.contest_id = c.contest_id AND q.deleted = 0
            GROUP BY c.contest_id
            ORDER BY c.started_at DESC
            """)
        defer { stmt.finalize() }
        var out: [ContestSummary] = []
        while try stmt.step() {
            let contestId = stmt.columnText(forName: "contest_id") ?? ""
            out.append(ContestSummary(
                contestId: contestId,
                definitionId: stmt.columnText(forName: "definition_id") ?? "",
                name: stmt.columnText(forName: "name"),
                startedAt: nullableInt64(stmt, forName: "started_at"),
                endedAt: nullableInt64(stmt, forName: "ended_at"),
                qsoCount: stmt.columnInt64(forName: "qso_count"),
                bands: try bandsFor(contestId),
                firstQso: nullableInt64(stmt, forName: "first_q"),
                lastQso: nullableInt64(stmt, forName: "last_q")
            ))
        }
        return out
    }

    private func bandsFor(_ contestId: String) throws -> [String] {
        let stmt = try connection.prepare(
            "SELECT DISTINCT band FROM qso WHERE contest_id=? AND deleted=0 AND band IS NOT NULL")
        defer { stmt.finalize() }
        try stmt.bindText(contestId, at: 1)
        var bands: [String] = []
        while try stmt.step() {
            if let band = stmt.columnText(at: 0) {
                bands.append(band)
            }
        }
        return bands
    }

    private func mapRow(_ stmt: SQLiteStatement) -> ContestRow {
        ContestRow(
            contestId: stmt.columnText(forName: "contest_id") ?? "",
            definitionId: stmt.columnText(forName: "definition_id") ?? "",
            name: stmt.columnText(forName: "name"),
            startedAt: nullableInt64(stmt, forName: "started_at"),
            endedAt: nullableInt64(stmt, forName: "ended_at"),
            definitionYaml: stmt.columnText(forName: "definition_yaml") ?? "",
            setupJson: stmt.columnText(forName: "setup_json"),
            stationJson: stmt.columnText(forName: "station_json")
        )
    }

    private func nullableInt64(_ stmt: SQLiteStatement, forName name: String) -> Int64? {
        stmt.isNull(forName: name) ? nil : stmt.columnInt64(forName: name)
    }
}
