import Foundation
import Testing

@testable import MCLCore

/// Safeguard: a database written by the **real Java** `LogbookRepository`/
/// `ContestStore` (not hand-built SQL, not synthetic data written by Swift) must pass through the
/// Swift `LogbookRepository`/`ContestStore` without losing a single value. It corresponds to
/// `RealConfigCompatibilityTests` — the same trap: checking only the presence of keys/
/// the row count would be blind to a dropped assignment in `mapRow`.
///
/// **The fixtures are not the user's logbook.** The original plan counted on the real
/// `Deník.sqlite`, but that carries personal data (e-mail, home coordinates to four decimal
/// places in `station_json`) and the environment's security classifier refused to move even a sanitized
/// copy into the repository. Solution: the gate does not need the *user's* data, it needs
/// only *Java-written* data. Both fixtures are therefore produced by a one-off generator
/// (maintainer-only probe, see a maintainer-only probe for the exact
/// procedure) — it runs the real `cz.ok1xoe.maccontestlogger.logbook.LogbookRepository`/
/// `ContestStore` from the Java v1.1.1 sources over purely fabricated QSOs
/// (callsigns such as `OK1AAA`, operator `OK9TEST` — no link to real operation or to the
/// user's callsign). Advantages over a copy of the user's file: (1) it is still byte
/// for byte what Java wrote — that is the point here; (2) it contains nothing personal, needs
/// nobody's permission; (3) reproducible in CI and on another machine; (4) fabricated data can
/// cover more edge cases than a single real logbook happened to contain.
///
/// **Fixture `logbook-v1.1.1.sqlite` covers:** all 27 columns of `qso`, both filled and
/// empty — a row with the ten text columns from the accepted exception (`rst_sent`, `rst_rcvd`,
/// `comment`, `operator`, `dxcc_name`, `continent`, `station_id`, `exchange_sent`,
/// `exchange_rcvd`) set to `NULL` (id 2), `contest_id IS NULL` separately (id 3,
/// isolated from the other NULL fields), a tombstone (`deleted=1`, id 4), `xqso=1` (id 5),
/// all 13 bands incl. the edge `160m`/`70cm` (id 6–14), a gap between bands → `band IS NULL`
/// (id 8), a missing mode → `mode IS NULL` (id 9), all 10 `Mode` values, two contests
/// (`contest-gen-A`/`contest-gen-B`) across the QSOs. **`rst_sent`/`rst_rcvd` are deliberately
/// asymmetric** (`"599"`/`"579"`) in all rows where they are not `NULL` — if they were the same
/// everywhere (as they happen to be in the user's real logbook), a column swap in `mapRow` would
/// go unnoticed; the same is verified for `exchange_sent`/`exchange_rcvd` (differ
/// everywhere), `serial_sent`/`serial_rcvd` (differ for id 1/3/4/5), `dxcc_name`/`continent`
/// (different format and content) and `timestamp_utc`/`updated_at_utc` (differ for id 1) — no
/// pair of identically typed columns is identical across the whole fixture. `meta` has two
/// keys. `contests` has two rows — A fully filled, B with `name`/`started_at`/`ended_at`/
/// `setup_json`/`station_json` as `NULL` (non-trivial — it tests the optional columns of
/// `contests`, which no real row had). `qtc` has four rows covering all
/// fraction-of-a-second widths that `Instant.toString()` can produce (0, 3, 6, 9 digits),
/// plus one row with `contest_id IS NULL`.
///
/// The second fixture, `logbook-legacy-no-contest-id.sqlite`, has the schema **before** the introduction of
/// `contest_id`/`xqso` (exactly the shape the user's old `logbook.sqlite` had — verified
/// during a private inspection, the schema itself carries nothing personal) and **two live rows** (not zero
/// like the real file) — opening it must prove that the destructive migration
/// (`LogbookDatabase.migrateSyncColumns`, ported from `LogbookRepository.
/// migrateSyncColumns`) really deletes the existing rows, not merely that an empty table stays
/// empty.
///
/// **Reproduction:** a maintainer-only probe is in this repository (a Java file
/// in a Swift repo — somewhat unusual, but a reproducible fixture is worth more than
/// purity; it is **not** part of the SwiftPM build, `Package.swift` scans only `Sources/MCLCore`
/// and `Tests/MCLCoreTests`). a maintainer-only probe has the exact procedure: copy
/// unchanged `LogbookRepository.java`, `ContestStore.java`, `LogbookException.java`,
/// `Qso.java`, `Band.java`, `Mode.java`, `RunMode.java`, `QtcRecord.java` from
/// the Java v1.1.1 sources next to `FixtureGen.java`, compile
/// and run via `javac`/`java` with `sqlite-jdbc` on the classpath (same version as
/// `build.gradle.kts` — `org.xerial:sqlite-jdbc:3.47.1.0`). The legacy fixture is generated with raw
/// JDBC (today's `initSchema()` no longer creates the old schema).
@Suite struct RealLogbookCompatibilityTests {

    // MARK: - Columns with the accepted NULL vs. "" difference

    /// Text columns of `qso` where Java binds SQL `NULL` for an untouched field, whereas
    /// the Swift `Qso` has the corresponding property non-optional with a default of `""` — the behaviour is the same
    /// (Java treats NULL and "" the same at every call site), only the file content differs.
    /// The difference is accepted and must not grow beyond this list.
    ///
    /// **Note on `rst_rcvd`:** `Qso.rstRcvd`/`rst_rcvd` is architecturally an identical
    /// twin of `rstSent`/`rst_sent` in both Java and Swift (a plain `String` without a
    /// default in Java → `NULL` until someone calls the setter; Swift `""`) —
    /// `mapRow`/`bind` treat it exactly like `rst_sent`. The fixture generated by
    /// `FixtureGen.java` (row id 2, where the Java setter never touched `rstRcvd`) really produced this
    /// difference, and the test failed on it without this row, with the message
    /// `id=2 rst_rcvd: expected NULL, got ""` — not because the Swift `mapRow`
    /// had a bug, but because `rst_rcvd` belongs to the same category as `rst_sent`, so it is
    /// compared with the same justification as the other columns.
    ///
    /// **`contest_id` is not on the list.** It used to be, but that was untrue: `bind` wrote
    /// an empty `TEXT` for it where Java writes `NULL`, which changed the result of
    /// `findAll()`/`count()`/`nextSerial()` without an active contest. Since the fix `""`
    /// is translated to `NULL` at the SQL boundary (`LogbookRepository.sqlContestId`), so
    /// `contest_id` is compared **exactly** — see `check("contest_id", …)` below and the
    /// write arm.
    private static let nullEqualsEmptyStringColumns: Set<String> = [
        "rst_sent", "rst_rcvd", "comment", "operator", "dxcc_name", "continent",
        "station_id", "exchange_sent", "exchange_rcvd",
    ]

    // MARK: - Fixtures

    private func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "sqlite"))
    }

    /// Copies the fixture to a temporary file and opens it via `LogbookRepository` —
    /// the file in the test bundle is never touched directly (`LogbookRepository` opens the
    /// database for reading and writing, `initSchema`/migrations could change it).
    private func openCopy(of fixtureName: String) throws -> (repository: LogbookRepository, fileURL: URL) {
        let source = try fixtureURL(fixtureName)
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fixtureName)-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: source, to: target)
        let repo = try LogbookRepository(url: target)
        return (repo, target)
    }

    /// Opens the raw columns of the given table (read independently of `LogbookRepository`) —
    /// the truth against which values from the high-level API are compared. `columns` determines
    /// the name and type of each column (`.text`/`.int`), in the same order in which the table has
    /// its columns in `initSchema`.
    private func rawRows(
        at fileURL: URL, table: String, columns: [(name: String, kind: RawColumnKind)],
        orderBy: String = "id"
    ) throws -> [[String: RawValue]] {
        let db = try SQLiteDatabase.open(at: fileURL.path)
        defer { db.close() }
        let stmt = try db.prepare("SELECT * FROM \(table) ORDER BY \(orderBy)")
        defer { stmt.finalize() }
        var rows: [[String: RawValue]] = []
        while try stmt.step() {
            var row: [String: RawValue] = [:]
            for column in columns {
                if stmt.isNull(forName: column.name) {
                    row[column.name] = .null
                    continue
                }
                switch column.kind {
                case .text:
                    row[column.name] = .text(stmt.columnText(forName: column.name) ?? "")
                case .int:
                    row[column.name] = .int64(stmt.columnInt64(forName: column.name))
                }
            }
            rows.append(row)
        }
        return rows
    }

    private enum RawColumnKind { case text, int }

    private enum RawValue: Equatable, CustomStringConvertible {
        case null
        case text(String)
        case int64(Int64)

        var description: String {
            switch self {
            case .null: "NULL"
            case .text(let s): "\"\(s)\""
            case .int64(let i): "\(i)"
            }
        }

        /// Without quotes — for compact messages of the write arm (`java=M20 swift=20m`).
        var plain: String {
            switch self {
            case .null: "NULL"
            case .text(let s): s
            case .int64(let i): "\(i)"
            }
        }
    }

    /// Columns of the `qso` table in the order of `initSchema`/`LogbookRepository.java`.
    private static let qsoColumns: [(name: String, kind: RawColumnKind)] = [
        ("id", .int), ("timestamp_utc", .int), ("call", .text), ("freq_hz", .int),
        ("band", .text), ("mode", .text), ("rst_sent", .text), ("rst_rcvd", .text),
        ("exchange_sent", .text), ("exchange_rcvd", .text), ("serial_sent", .int),
        ("serial_rcvd", .int), ("points", .int), ("multiplier", .int), ("run_mode", .text),
        ("operator", .text), ("comment", .text), ("dxcc_entity", .int), ("dxcc_name", .text),
        ("continent", .text), ("uuid", .text), ("station_id", .text), ("version", .int),
        ("updated_at_utc", .int), ("deleted", .int), ("contest_id", .text), ("xqso", .int),
    ]

    /// A map `Band` → Java enum constant name (`Enum.name()`) written independently of `LogbookRepository`,
    /// for comparison against `band` in the raw data. It duplicates the private
    /// `Band.javaName` from `LogbookRepository.swift` deliberately — if a regression sat exactly
    /// the same in both places, the injected regression in `mapRow` would be caught
    /// elsewhere anyway (neither band nor mode is what the regression was demonstrated on).
    private static let javaBandNames: [Band: String] = [
        .m160: "M160", .m80: "M80", .m60: "M60", .m40: "M40", .m30: "M30", .m20: "M20",
        .m17: "M17", .m15: "M15", .m12: "M12", .m10: "M10", .m6: "M6", .m2: "M2", .cm70: "CM70",
    ]

    /// Constant names of the Java `enum Mode` (`model/Mode.java`) copied independently of Swift `Mode.rawValue`
    /// — without this table the `mode` comparison would be self-referential
    /// (Swift against Swift): a symmetric swap of two `Mode` values in `mapRow` would
    /// round-trip undetected, because the comparison would always agree with itself.
    private static let javaModeNames: [Mode: String] = [
        .cw: "CW", .ssb: "SSB", .fm: "FM", .am: "AM", .rtty: "RTTY",
        .psk: "PSK", .ft8: "FT8", .ft4: "FT4", .jt65: "JT65", .digital: "DIGITAL",
    ]

    /// The same for `enum RunMode` (`model/RunMode.java`: `RUN`, `SEARCH_AND_POUNCE`) — copied
    /// by hand from Java, not derived from `RunMode.rawValue`, for the same reason as `javaModeNames`.
    private static let javaRunModeNames: [RunMode: String] = [
        .run: "RUN", .searchAndPounce: "SEARCH_AND_POUNCE",
    ]

    /// An independent rewrite of Java's `Instant.toEpochMilli()`:
    /// `seconds * 1000 + nanos / 1_000_000` with **integer** division (i.e. truncation).
    /// Deliberately **not** copied from `LogbookRepository.epochMillis` — as long as the
    /// same expression (`.rounded()`) stood here, the gate could not catch replacing truncation with
    /// rounding, because the truth and the measured value shared the same bug.
    private static func epochMillis(_ date: Date?) -> Int64? {
        guard let date else { return nil }
        let t = date.timeIntervalSince1970
        let seconds = t.rounded(.down)
        let nanos = Int64(((t - seconds) * 1_000_000_000).rounded())
        return Int64(seconds) * 1000 + nanos / 1_000_000
    }

    // MARK: - `qso`: 14 QSOs (written by Java), all 27 columns, value by value

    @Test func realLogbookQsosMatchValueByValue() throws {
        let (repo, fileURL) = try openCopy(of: "logbook-v1.1.1")
        defer { repo.close(); try? FileManager.default.removeItem(at: fileURL) }

        let truth = try rawRows(at: fileURL, table: "qso", columns: Self.qsoColumns)
        #expect(truth.count == 14, "the fixture should have 14 QSOs, has \(truth.count)")

        let mapped = try repo.findAllIncludingDeleted()
        #expect(mapped.count == truth.count, "LogbookRepository returned a different number of rows than the table has")

        var mismatches: [String] = []
        for (index, qso) in mapped.enumerated() {
            guard index < truth.count else { break }
            let row = truth[index]
            let rowId = qso.id.map(String.init) ?? "?"

            func check(_ column: String, _ actual: RawValue) {
                guard let expected = row[column] else {
                    mismatches.append("id=\(rowId) \(column): missing in the raw data")
                    return
                }
                if expected == actual { return }
                // Accepted difference: Java NULL vs. Swift "" for text fields (documented here).
                if Self.nullEqualsEmptyStringColumns.contains(column),
                    expected == .null, actual == .text("")
                {
                    return
                }
                mismatches.append("id=\(rowId) \(column): expected \(expected), got \(actual)")
            }

            check("id", .int64(qso.id ?? -1))
            check("timestamp_utc", .int64(Self.epochMillis(qso.timestampUtc) ?? -1))
            check("call", .text(qso.call))
            check("freq_hz", .int64(Int64(qso.freqHz)))
            check("band", qso.band.flatMap { Self.javaBandNames[$0] }.map(RawValue.text) ?? .null)
            check("mode", qso.mode.flatMap { Self.javaModeNames[$0] }.map(RawValue.text) ?? .null)
            check("rst_sent", .text(qso.rstSent))
            check("rst_rcvd", .text(qso.rstRcvd))
            check("exchange_sent", .text(qso.exchangeSent))
            check("exchange_rcvd", .text(qso.exchangeRcvd))
            check("serial_sent", qso.serialSent.map { .int64(Int64($0)) } ?? .null)
            check("serial_rcvd", qso.serialRcvd.map { .int64(Int64($0)) } ?? .null)
            check("points", .int64(Int64(qso.points)))
            check("multiplier", .int64(qso.multiplier ? 1 : 0))
            check("run_mode", Self.javaRunModeNames[qso.runMode].map(RawValue.text) ?? .null)
            check("operator", .text(qso.`operator`))
            check("comment", .text(qso.comment))
            check("dxcc_entity", qso.dxccEntity.map { .int64(Int64($0)) } ?? .null)
            check("dxcc_name", .text(qso.dxccName))
            check("continent", .text(qso.continent))
            check("uuid", .text(qso.uuid))
            check("station_id", .text(qso.stationId))
            check("version", .int64(qso.version))
            check("updated_at_utc", Self.epochMillis(qso.updatedAtUtc).map(RawValue.int64) ?? .null)
            check("deleted", .int64(qso.deleted ? 1 : 0))
            // The sentinel is bidirectional: reading `NULL` → `""`, writing `""` → `NULL`.
            // So the comparison is made after applying the write side of the mapping, not via an exception —
            // `NULL` in the file must correspond to `""` in the model and nothing else (row id 3).
            check("contest_id", qso.contestId.isEmpty ? .null : .text(qso.contestId))
            check("xqso", .int64(qso.xqso ? 1 : 0))
        }

        #expect(mismatches.isEmpty, "mismatches against the file written by Java:\n\(mismatches.joined(separator: "\n"))")
    }

    // MARK: - `qso`: write arm — what Swift **writes** must be the same as what Java wrote

    /// The second arm of the gate. The test above checks only the **read** path (`mapRow`); the write
    /// path (`bind`) passes through it unnoticed, because nothing is ever written. Swift↔Swift
    /// round-trips in `LogbookRepositoryTests` do not fix that: they are blind to a **symmetric**
    /// bug (the same bug in `bind` and `mapRow`), which always agrees with itself.
    ///
    /// Procedure: read the Java fixture via `LogbookRepository`, insert all the QSOs via
    /// `insert` into a **fresh** database and compare the **raw column values** of both files.
    /// The truth is the file written by Java, not the Swift model — hence `rawRows` is compared
    /// against `rawRows`, without a single pass through `mapRow` on the expected side.
    ///
    /// Verified that the arm can fail: an injected swap of `Band.javaName` for ADIF
    /// (in `bind` and `mapRow` at once, i.e. symmetrically — exactly the regression the
    /// code once had) fails it with the message `row 1 band: java=M20 swift=20m` for every
    /// row with a band, while the read arm and the round-trips stay green.
    ///
    /// The accepted exceptions are the same as for the read arm (`nullEqualsEmptyStringColumns`):
    /// Java `NULL` vs. Swift `""` for nine text columns where `Qso` has no optional.
    /// `contest_id` is **not** among them — it must match exactly (NULL stays NULL).
    @Test func reinsertedQsosReproduceJavaWrittenColumns() throws {
        let (repo, fileURL) = try openCopy(of: "logbook-v1.1.1")
        defer { repo.close(); try? FileManager.default.removeItem(at: fileURL) }

        let javaRows = try rawRows(at: fileURL, table: "qso", columns: Self.qsoColumns)
        #expect(javaRows.count == 14, "the fixture should have 14 QSOs, has \(javaRows.count)")

        // `findAllIncludingDeleted` sorts by `timestamp_utc ASC, id ASC`, `rawRows` by `id`;
        // in the fixture both go in the same order (times grow with id), so the rows are paired
        // by index. The `id` column is not compared — in a fresh database SQLite assigns it
        // anew; only what `bind` actually writes is pinned.
        let loaded = try repo.findAllIncludingDeleted()
        #expect(loaded.count == javaRows.count, "a different number of QSOs was loaded than the fixture has")

        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("writeback-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: targetURL) }
        let fresh = try LogbookRepository(url: targetURL)
        for qso in loaded {
            var copy = qso
            try fresh.insert(&copy)
        }
        fresh.close()

        let swiftRows = try rawRows(at: targetURL, table: "qso", columns: Self.qsoColumns)
        #expect(swiftRows.count == javaRows.count, "Swift wrote a different number of rows than the fixture has")

        var mismatches: [String] = []
        for (index, javaRow) in javaRows.enumerated() {
            guard index < swiftRows.count else { break }
            let swiftRow = swiftRows[index]
            for column in Self.qsoColumns where column.name != "id" {
                let expected = javaRow[column.name] ?? .null
                let actual = swiftRow[column.name] ?? .null
                if expected == actual { continue }
                if Self.nullEqualsEmptyStringColumns.contains(column.name),
                    expected == .null, actual == .text("")
                {
                    continue
                }
                mismatches.append(
                    "row \(index + 1) \(column.name): java=\(expected.plain) swift=\(actual.plain)")
            }
        }

        #expect(
            mismatches.isEmpty,
            "Columns written by Swift differ from the file written by Java:\n\(mismatches.joined(separator: "\n"))"
        )
    }

    // MARK: - `meta`

    @Test func realLogbookMetaMatchesFile() throws {
        let (repo, fileURL) = try openCopy(of: "logbook-v1.1.1")
        defer { repo.close(); try? FileManager.default.removeItem(at: fileURL) }

        let truth = try rawRows(
            at: fileURL, table: "meta", columns: [("key", .text), ("value", .text)], orderBy: "key")
        #expect(truth.count == 2, "the fixture should have two meta keys (generator_note, last_contest_id)")

        var mismatches: [String] = []
        for row in truth {
            guard case .text(let key)? = row["key"], case .text(let expectedValue)? = row["value"] else {
                mismatches.append("meta row does not have the expected shape: \(row)")
                continue
            }
            let actual = try repo.metaGet(key)
            if actual != expectedValue {
                mismatches.append("key=\(key): expected \"\(expectedValue)\", got \(actual.map { "\"\($0)\"" } ?? "nil")")
            }
        }
        #expect(mismatches.isEmpty, "neshody v tabulce meta:\n\(mismatches.joined(separator: "\n"))")
    }

    // MARK: - `contests`

    @Test func realLogbookContestsMatchValueByValue() throws {
        let (repo, fileURL) = try openCopy(of: "logbook-v1.1.1")
        defer { repo.close(); try? FileManager.default.removeItem(at: fileURL) }

        let store = try ContestStore(repo)
        let columns: [(name: String, kind: RawColumnKind)] = [
            ("contest_id", .text), ("definition_id", .text), ("name", .text),
            ("started_at", .int), ("ended_at", .int), ("definition_yaml", .text),
            ("setup_json", .text), ("station_json", .text),
        ]
        let truthRows = try rawRows(at: fileURL, table: "contests", columns: columns, orderBy: "contest_id")
        // Two contests: `contest-gen-A` fully filled, `contest-gen-B` with the optional
        // columns (`name`/`started_at`/`ended_at`/`setup_json`/`station_json`) as NULL.
        #expect(truthRows.count == 2, "the fixture should have two contests (contest-gen-A, contest-gen-B)")

        var mismatches: [String] = []
        for row in truthRows {
            guard case .text(let contestId)? = row["contest_id"] else { continue }
            guard let found = try store.find(contestId) else {
                mismatches.append("contest_id=\(contestId): ContestStore.find returned nothing")
                continue
            }
            func expectText(_ column: String, _ actual: String?) {
                let expected = row[column] ?? .null
                let actualValue: RawValue = actual.map(RawValue.text) ?? .null
                if expected != actualValue {
                    mismatches.append("contest_id=\(contestId) \(column): expected \(expected), got \(actualValue)")
                }
            }
            func expectInt(_ column: String, _ actual: Int64?) {
                let expected = row[column] ?? .null
                let actualValue: RawValue = actual.map(RawValue.int64) ?? .null
                if expected != actualValue {
                    mismatches.append("contest_id=\(contestId) \(column): expected \(expected), got \(actualValue)")
                }
            }
            expectText("definition_id", found.definitionId)
            expectText("name", found.name)
            expectInt("started_at", found.startedAt)
            expectInt("ended_at", found.endedAt)
            expectText("definition_yaml", found.definitionYaml)
            expectText("setup_json", found.setupJson)
            expectText("station_json", found.stationJson)
        }
        #expect(mismatches.isEmpty, "neshody v tabulce contests:\n\(mismatches.joined(separator: "\n"))")
    }

    // MARK: - `qtc`

    /// A parse of `at_utc` into epoch milliseconds written independently of `QtcRecord.parseAtUtc` —
    /// the truth for comparison, not a reuse of the production parser. It takes the whole second plus
    /// the first three digits of the fraction (0 = no fraction), so it works the same for all four
    /// widths that `Instant.toString()` can write (0/3/6/9 digits).
    private func truthMillis(fromAtUtc text: String) throws -> Int64 {
        let body = try #require(text.hasSuffix("Z") ? text.dropLast() : nil)
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let baseDate = try #require(formatter.date(from: "\(parts[0])Z"))
        let baseMillis = Int64((baseDate.timeIntervalSince1970 * 1000).rounded())
        guard parts.count == 2 else { return baseMillis }
        let msDigits = String(parts[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return baseMillis + Int64(msDigits)!
    }

    @Test func realLogbookQtcMatchValueByValue() throws {
        let (repo, fileURL) = try openCopy(of: "logbook-v1.1.1")
        defer { repo.close(); try? FileManager.default.removeItem(at: fileURL) }

        let columns: [(name: String, kind: RawColumnKind)] = [
            ("id", .int), ("contest_id", .text), ("sent", .int), ("partner_call", .text),
            ("group_nr", .int), ("group_size", .int), ("qso_time", .text), ("qso_call", .text),
            ("qso_serial", .int), ("at_utc", .text), ("freq_hz", .int), ("mode", .text),
        ]
        let truth = try rawRows(at: fileURL, table: "qtc", columns: columns)
        // Four rows: whole-second, 3-digit, 6-digit and 9-digit fraction of a second in `at_utc`
        // (widths that Java's `Instant.toString()` can produce), one of them additionally
        // with `contest_id IS NULL`.
        #expect(truth.count == 4, "the fixture should have 4 QTCs (0/3/6/9-digit at_utc fraction)")

        // `findQtcs` uses `contest_id IS ?`, so it must be called for every value of
        // `contest_id` that occurs in the raw data (incl. NULL), to collect
        // all four rows.
        var byContestId: [String?: [QtcRecord]] = [:]
        let distinctContestIds: Set<String?> = Set(
            truth.map { row -> String? in
                if case .text(let cid)? = row["contest_id"] { return cid }
                return nil
            })
        for contestId in distinctContestIds {
            byContestId[contestId] = try repo.findQtcs(contestId: contestId)
        }
        let mappedById = Dictionary(
            uniqueKeysWithValues: byContestId.values.flatMap { $0 }.compactMap { record in
                record.id.map { ($0, record) }
            })
        #expect(mappedById.count == truth.count, "findQtcs returned a different total number of rows than the table has")

        var mismatches: [String] = []
        for row in truth {
            guard case .int64(let id)? = row["id"] else { continue }
            guard let record = mappedById[id] else {
                mismatches.append("id=\(id): findQtcs did not return it in any group")
                continue
            }
            func expect(_ column: String, _ actual: RawValue) {
                let expected = row[column] ?? .null
                if expected != actual {
                    mismatches.append("id=\(id) \(column): expected \(expected), got \(actual)")
                }
            }
            expect("contest_id", record.contestId.map(RawValue.text) ?? .null)
            expect("sent", .int64(record.sent ? 1 : 0))
            expect("partner_call", .text(record.partnerCall))
            expect("group_nr", .int64(Int64(record.groupNr)))
            expect("group_size", .int64(Int64(record.groupSize)))
            expect("qso_time", .text(record.qsoTime))
            expect("qso_call", .text(record.qsoCall))
            expect("qso_serial", .int64(Int64(record.qsoSerial)))
            expect("freq_hz", .int64(record.freqHz))
            expect("mode", record.mode.map(RawValue.text) ?? .null)

            guard case .text(let rawAtUtc)? = row["at_utc"] else {
                mismatches.append("id=\(id) at_utc: the raw data has no text")
                continue
            }
            let expectedMillis = try truthMillis(fromAtUtc: rawAtUtc)
            let actualMillis = Int64((record.at.timeIntervalSince1970 * 1000).rounded())
            if expectedMillis != actualMillis {
                mismatches.append("id=\(id) at_utc: expected \(expectedMillis) ms, got \(actualMillis) ms (raw: \(rawAtUtc))")
            }
        }
        #expect(mismatches.isEmpty, "neshody v tabulce qtc:\n\(mismatches.joined(separator: "\n"))")
    }

    // MARK: - Legacy schema (without `contest_id`) — destructive migration on a really written file

    /// Pins `LogbookDatabase.migrateSyncColumns` on a file with the old schema
    /// (corresponds to the shape the user's old `logbook.sqlite` had, but with two live
    /// rows instead of zero): opening must add `contest_id`/`xqso` and — because it is a
    /// migration to the multi-contest schema — empty `qso` (`DELETE FROM qso`), exactly as
    /// the Java source does. With two rows before the migration, this test proves that something was
    /// really deleted, not merely that an empty table stayed empty.
    @Test func legacyLogbookWithoutContestIdMigratesOnOpen() throws {
        let source = try fixtureURL("logbook-legacy-no-contest-id")
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("logbook-legacy-no-contest-id-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: source, to: target)
        defer { try? FileManager.default.removeItem(at: target) }

        // Pre-migration state read raw, before `LogbookRepository` opens anything.
        let preDb = try SQLiteDatabase.open(at: target.path)
        let preStmt = try preDb.prepare("SELECT COUNT(*) FROM qso")
        _ = try preStmt.step()
        let preCount = preStmt.columnInt64(at: 0)
        preStmt.finalize()
        preDb.close()
        #expect(preCount == 2, "the legacy fixture should have 2 rows BEFORE the migration (otherwise emptying proves nothing)")

        let repo = try LogbookRepository(url: target)
        defer { repo.close() }

        #expect(try repo.count() == 0, "the migration should have emptied the table via DELETE FROM qso after opening")

        let db = try SQLiteDatabase.open(at: target.path)
        defer { db.close() }
        let pragma = try db.prepare("PRAGMA table_info(qso)")
        defer { pragma.finalize() }
        var columnNames = Set<String>()
        while try pragma.step() {
            if let name = pragma.columnText(forName: "name") {
                columnNames.insert(name)
            }
        }
        #expect(columnNames.contains("contest_id"), "the migration should have added contest_id")
        #expect(columnNames.contains("xqso"), "the migration should have added xqso")
        #expect(columnNames.contains("uuid"), "the uuid column should already have been in the legacy file")
    }
}
