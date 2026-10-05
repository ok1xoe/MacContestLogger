import Foundation
import Testing
@testable import MCLCore

/// Port of `LogbookRepositoryTest.java` — basic CRUD over the `qso` table
/// (`insert`/`update`/`delete(id)`/`delete(ids)`/`deleteAll`/`findAll`/`count`)
/// and network replication (`upsertByUuid`/`markDeleted`/`findByUuid`/
/// `findAllIncludingDeleted`).
@Suite struct LogbookRepositoryTests {

    // MARK: - Helpers

    private func sampleQso(_ call: String) -> Qso {
        var q = Qso()
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-06-17T12:00:00Z")
        q.call = call
        q.freqHz = 14_074_000
        q.mode = .ssb
        q.rstSent = "59"
        q.rstRcvd = "59"
        q.serialSent = 1
        q.serialRcvd = 42
        return q
    }

    // MARK: - `LogbookRepositoryTest.deleteAllEmptiesLog`

    @Test func deleteAllEmptiesLog() throws {
        let repo = try LogbookRepository.inMemory()
        var a = sampleQso("DL1ABC")
        var b = sampleQso("W1AW")
        _ = try repo.insert(&a)
        _ = try repo.insert(&b)
        #expect(try repo.count() == 2)
        try repo.deleteAll()
        #expect(try repo.count() == 0)
        #expect(try repo.findAll().isEmpty)
    }

    // MARK: - `LogbookRepositoryTest.insertAssignsIdAndPersistsFields`

    @Test func insertAssignsIdAndPersistsFields() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        let id = try repo.insert(&q)

        #expect(id > 0)
        #expect(q.id == id)

        let all = try repo.findAll()
        #expect(all.count == 1)
        let loaded = all[0]
        #expect(loaded.call == "DL1ABC")
        #expect(loaded.mode == .ssb)
        #expect(loaded.freqHz == 14_074_000)
        #expect(loaded.serialRcvd == 42)
        #expect(loaded.band != nil) // derived from the frequency (20m)
    }

    // MARK: - `LogbookRepositoryTest.countReflectsInserts`

    @Test func countReflectsInserts() throws {
        let repo = try LogbookRepository.inMemory()
        var a = sampleQso("DL1ABC")
        var b = sampleQso("G3XYZ")
        _ = try repo.insert(&a)
        _ = try repo.insert(&b)
        #expect(try repo.count() == 2)
    }

    // MARK: - `LogbookRepositoryTest.deleteRemovesQso`

    @Test func deleteRemovesQso() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        let id = try repo.insert(&q)
        try repo.delete(id: id)
        #expect(try repo.count() == 0)
    }

    // MARK: - `LogbookRepositoryTest.deleteByIdsRemovesOnlySelectedQsos`

    @Test func deleteByIdsRemovesOnlySelectedQsos() throws {
        let repo = try LogbookRepository.inMemory()
        var qa = sampleQso("DL1ABC")
        var qb = sampleQso("W1AW")
        var qc = sampleQso("G3XYZ")
        let a = try repo.insert(&qa)
        let b = try repo.insert(&qb)
        let c = try repo.insert(&qc)

        try repo.delete(ids: [a, c])

        #expect(try repo.count() == 1)
        let remaining = try repo.findAll()
        #expect(remaining[0].call == "W1AW")
        #expect(remaining[0].id == b)
    }

    // MARK: - `LogbookRepositoryTest.deleteByIdsIgnoresEmptyAndUnknownIds`

    @Test func deleteByIdsIgnoresEmptyAndUnknownIds() throws {
        let repo = try LogbookRepository.inMemory()
        var qa = sampleQso("DL1ABC")
        let a = try repo.insert(&qa)

        try repo.delete(ids: [])
        #expect(try repo.count() == 1)

        try repo.delete(ids: [a + 999])
        #expect(try repo.count() == 1)
    }

    // MARK: - `LogbookRepositoryTest.updateModifiesExistingQso`

    @Test func updateModifiesExistingQso() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        _ = try repo.insert(&q)
        q.comment = "test poznámka"
        try repo.update(q)

        #expect(try repo.findAll()[0].comment == "test poznámka")
    }

    // MARK: - `LogbookRepositoryTest.insertGeneratesUuidAndSyncDefaults`

    @Test func insertGeneratesUuidAndSyncDefaults() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        #expect(q.uuid.isEmpty) // no uuid yet when created
        _ = try repo.insert(&q)

        // uuid assigned on insert (and propagated into the object)
        #expect(!q.uuid.isEmpty)

        let loaded = try repo.findAll()[0]
        #expect(loaded.uuid == q.uuid)
        #expect(loaded.version == 0)
        #expect(loaded.deleted == false)
        #expect(loaded.updatedAtUtc != nil)
    }

    // MARK: - `LogbookRepositoryTest.insertPreservesExplicitSyncFields`

    @Test func insertPreservesExplicitSyncFields() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("OK1XOE")
        q.uuid = "9f1c0c2e-aaaa-bbbb-cccc-000000000001"
        q.stationId = "OP1"
        q.version = 3

        _ = try repo.insert(&q)

        let loaded = try repo.findAll()[0]
        #expect(loaded.uuid == "9f1c0c2e-aaaa-bbbb-cccc-000000000001")
        #expect(loaded.stationId == "OP1")
        #expect(loaded.version == 3)
    }

    // MARK: - `LogbookRepositoryTest.findAllOmitsTombstones`

    @Test func findAllOmitsTombstones() throws {
        let repo = try LogbookRepository.inMemory()
        var active = sampleQso("DL1ABC")
        _ = try repo.insert(&active)

        var tomb = sampleQso("W1AW")
        tomb.deleted = true
        _ = try repo.insert(&tomb)

        // the tombstone is persisted (count sees both), but findAll hides it
        #expect(try repo.count() == 2)
        let active2 = try repo.findAll()
        #expect(active2.count == 1)
        #expect(active2[0].call == "DL1ABC")
    }

    // MARK: - `LogbookRepositoryTest.opensAndMigratesLegacySchema`
    //
    // The Java version reads the result via `findAll(String contestId)` (filtered by contest) —
    // that overloaded `findAll` is not in the repository interface (only the parameterless `findAll()`).
    // In this scenario there is a single QSO in the DB, so the unfiltered `findAll()` returns
    // the same result; it also allows testing the round-trip of the `contestId` column,
    // which none of the other 17 tests covers.

    @Test func opensAndMigratesLegacySchema() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let legacy = try SQLiteDatabase.open(at: tmp.path)
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

        // Opening the old DB must not crash (ALTER TABLE migration). A missing contest_id
        // triggers the one-off migration to multi-contest, which deletes the old QSOs (a
        // clean start) — the DB stays usable for new writes, though.
        let migrated = try LogbookRepository(url: tmp)
        #expect(try migrated.findAll().isEmpty)

        var fresh = sampleQso("NEW1ABC")
        fresh.contestId = "c1"
        _ = try migrated.insert(&fresh)
        let all = try migrated.findAll()
        #expect(all.count == 1)
        #expect(all[0].call == "NEW1ABC")
        #expect(all[0].contestId == "c1")
        migrated.close()
    }

    // MARK: - Helper for sync tests (`LogbookRepositoryTest.syncQso`)

    private func syncQso(_ uuid: String, _ call: String, _ version: Int64) -> Qso {
        var q = sampleQso(call)
        q.uuid = uuid
        q.stationId = "OP1"
        q.version = version
        let base = ISO8601DateFormatter().date(from: "2026-06-17T12:00:00Z")!
        q.updatedAtUtc = base.addingTimeInterval(TimeInterval(version))
        return q
    }

    // MARK: - `LogbookRepositoryTest.upsertByUuidInsertsWhenAbsent`

    @Test func upsertByUuidInsertsWhenAbsent() throws {
        let repo = try LogbookRepository.inMemory()
        try repo.upsertByUuid(syncQso("uuid-A", "DL1ABC", 1))

        let all = try repo.findAll()
        #expect(all.count == 1)
        #expect(all[0].call == "DL1ABC")
        #expect(all[0].version == 1)
    }

    // MARK: - `LogbookRepositoryTest.upsertByUuidAppliesNewerVersion`

    @Test func upsertByUuidAppliesNewerVersion() throws {
        let repo = try LogbookRepository.inMemory()
        try repo.upsertByUuid(syncQso("uuid-A", "DL1ABC", 1))
        try repo.upsertByUuid(syncQso("uuid-A", "DL1XYZ", 2)) // callsign correction, higher version

        let all = try repo.findAll()
        #expect(all.count == 1) // still one row (merging by uuid)
        #expect(all[0].call == "DL1XYZ")
        #expect(all[0].version == 2)
    }

    // MARK: - `LogbookRepositoryTest.upsertByUuidIgnoresOlderOrEqualVersion`

    @Test func upsertByUuidIgnoresOlderOrEqualVersion() throws {
        let repo = try LogbookRepository.inMemory()
        try repo.upsertByUuid(syncQso("uuid-A", "DL1XYZ", 2))
        try repo.upsertByUuid(syncQso("uuid-A", "OLD", 1)) // older — ignore
        try repo.upsertByUuid(syncQso("uuid-A", "SAME", 2)) // same version — ignore (LWW)

        let loaded = try repo.findAll()[0]
        #expect(loaded.call == "DL1XYZ")
        #expect(loaded.version == 2)
    }

    // MARK: - `LogbookRepositoryTest.markDeletedHidesFromFindAllButKeepsTombstone`

    @Test func markDeletedHidesFromFindAllButKeepsTombstone() throws {
        let repo = try LogbookRepository.inMemory()
        try repo.upsertByUuid(syncQso("uuid-A", "DL1ABC", 1))
        try repo.markDeleted(uuid: "uuid-A", version: 2,
                              updatedAtUtc: ISO8601DateFormatter().date(from: "2026-06-17T13:00:00Z")!)

        #expect(try repo.findAll().isEmpty)

        let withTomb = try repo.findAllIncludingDeleted()
        #expect(withTomb.count == 1)
        #expect(withTomb[0].deleted == true)
        #expect(withTomb[0].version == 2)
    }

    // MARK: - `LogbookRepositoryTest.markDeletedIgnoresOlderVersion`

    @Test func markDeletedIgnoresOlderVersion() throws {
        let repo = try LogbookRepository.inMemory()
        try repo.upsertByUuid(syncQso("uuid-A", "DL1ABC", 5))
        try repo.markDeleted(uuid: "uuid-A", version: 3,
                              updatedAtUtc: ISO8601DateFormatter().date(from: "2026-06-17T13:00:00Z")!) // older — do not apply

        #expect(try repo.findAll().count == 1) // still active
        #expect(try repo.findAll()[0].deleted == false)
    }

    // MARK: - `LogbookRepositoryTest.findByUuidReturnsMatchOrEmpty`

    @Test func findByUuidReturnsMatchOrEmpty() throws {
        let repo = try LogbookRepository.inMemory()
        try repo.upsertByUuid(syncQso("uuid-A", "DL1ABC", 1))
        #expect(try repo.findByUuid("uuid-A") != nil)
        #expect(try repo.findByUuid("uuid-A")?.call == "DL1ABC")
        #expect(try repo.findByUuid("nope") == nil)
    }

    // MARK: - New test without a Java ancestor (safeguard for the `upsertByUuid` guard)

    /// Java `upsertByUuid` throws `IllegalArgumentException` if `qso.getUuid()`
    /// is `null`/empty — none of the existing tests tries this directly.
    @Test func upsertByUuidWithBlankUuidThrows() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        q.uuid = ""
        #expect(throws: LogbookError.self) {
            try repo.upsertByUuid(q)
        }
    }

    // MARK: - New tests without a Java ancestor

    /// Safeguard against falling into the trap described in the design notes: `Qso.call`/`Qso.freqHz`
    /// have a `didSet` that does not fire on assignment inside the type's own init.
    /// The row is deliberately inserted directly via `connection` (bypassing the `Qso.call` setter),
    /// so the `call` column contains unmodified text — the row mapping (`findAll`)
    /// must trim it and convert it to upper case itself, via `var q = Qso()` +
    /// subsequent assignments outside `Qso`. If the row mapping were rewritten so that
    /// it builds `Qso` differently (e.g. via memberwise/decoding init), this test fails.
    @Test func findAllNormalizesCallEvenWhenStoredRaw() throws {
        let repo = try LogbookRepository.inMemory()
        let insert = try repo.connection.prepare(
            "INSERT INTO qso (timestamp_utc, call, freq_hz) VALUES (0, ?, 14074000)")
        defer { insert.finalize() }
        try insert.bindText("  ok1xoe ", at: 1)
        try insert.step()

        let loaded = try repo.findAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].call == "OK1XOE")
    }

    /// `Qso.imported` is (like `transient` in Java) purely a runtime flag of origin from the
    /// network — it has no column of its own and `insert`/`update`/the row mapping must not store it.
    @Test func insertDoesNotPersistTransientImportedFlag() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        q.imported = true
        _ = try repo.insert(&q)

        let loaded = try repo.findAll()[0]
        #expect(loaded.imported == false)
    }

    /// Java `update` throws on a QSO without `id` (`IllegalArgumentException`); the Swift equivalent
    /// reports the same behaviour via `LogbookError`.
    @Test func updateWithoutIdThrows() throws {
        let repo = try LogbookRepository.inMemory()
        let q = sampleQso("DL1ABC") // never stored, id == nil
        #expect(throws: LogbookError.self) {
            try repo.update(q)
        }
    }

    /// In Swift, `Band` has a `rawValue` derived from the ADIF string (`"160m"`), not from the
    /// Java constant name (`"M160"`) that `LogbookRepository.bind`/`map`
    /// actually store/read (`q.getBand().name()` / `Band.valueOf(...)`). Persistence
    /// therefore has to map to the Java name separately — this test verifies that for every band.
    @Test func insertAndReloadRoundTripsEveryBandUsingJavaEnumName() throws {
        let repo = try LogbookRepository.inMemory()
        for band in Band.allCases {
            var q = sampleQso("DL1ABC")
            q.freqHz = 0 // outside an amateur segment, so that the frequency didSet does not derive the band itself
            q.band = band
            _ = try repo.insert(&q)
        }

        let loaded = try repo.findAll()
        #expect(loaded.map { $0.band } == Band.allCases.map { Optional($0) })
    }

    /// The microwave bands are stored as `CM23`…`CM3` (a product decision). Java v1.1.1 reads the column with
    /// `Band.valueOf` and cannot open such a logbook — documented as a deliberate divergence from Java v1.1.1.
    @Test func microwaveBandsAreStoredUnderTheirJavaStyleNames() throws {
        let repo = try LogbookRepository.inMemory()
        for band in Band.allCases.suffix(5) {
            var q = sampleQso("DL1ABC")
            q.freqHz = 0
            q.band = band
            _ = try repo.insert(&q)
        }
        let select = try repo.connection.prepare("SELECT band FROM qso ORDER BY id")
        defer { select.finalize() }
        var names: [String] = []
        while try select.step() { names.append(select.columnText(forName: "band") ?? "<null>") }
        #expect(names == ["CM23", "CM13", "CM9", "CM6", "CM3"])
    }

    /// In Swift, `Mode`/`RunMode` have a `rawValue` identical to Java's `Enum.name()`
    /// (unlike `Band`) — the test pins it directly on the stored text in the column,
    /// so that a future change of `rawValue` (e.g. to an ADIF alias) does not go unnoticed.
    @Test func modeAndRunModeColumnsStoreJavaEnumNames() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        q.mode = .ssb
        q.runMode = .searchAndPounce
        _ = try repo.insert(&q)

        let select = try repo.connection.prepare("SELECT mode, run_mode FROM qso")
        defer { select.finalize() }
        #expect(try select.step())
        #expect(select.columnText(forName: "mode") == "SSB")
        #expect(select.columnText(forName: "run_mode") == "SEARCH_AND_POUNCE")
    }

    /// A fraction of a millisecond is **truncated**, not rounded — Java `Instant.toEpochMilli()`
    /// is `seconds * 1000 + nanos / 1_000_000` with integer division.
    ///
    /// Measured on frozen Java v1.1.1:
    /// `Instant.ofEpochSecond(1780000000, 999_600_000).toEpochMilli()` → `1780000000999`.
    /// Rounding would make Swift yield `1780000001000`, which after formatting to
    /// seconds (ADIF, Cabrillo, the time column) is off by a **whole second**. The fixture
    /// `logbook-v1.1.1.sqlite` has all times on whole seconds, so the gate
    /// `RealLogbookCompatibilityTests` does not see this difference — it is pinned here.
    @Test func subMillisecondFractionIsTruncatedNotRounded() throws {
        let repo = try LogbookRepository.inMemory()
        var q = sampleQso("DL1ABC")
        let instant = Date(timeIntervalSince1970: 1_780_000_000.999_6)
        q.timestampUtc = instant
        q.updatedAtUtc = instant
        _ = try repo.insert(&q)

        let select = try repo.connection.prepare("SELECT timestamp_utc, updated_at_utc FROM qso")
        defer { select.finalize() }
        #expect(try select.step())
        #expect(select.columnInt64(forName: "timestamp_utc") == 1_780_000_000_999)
        #expect(select.columnInt64(forName: "updated_at_utc") == 1_780_000_000_999)
    }
}
