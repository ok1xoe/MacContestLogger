import Foundation
import Testing
@testable import MCLCore

/// Port of `LogbookContestPartitionTest.java` — partitioning `qso` by contest
/// (`findAll(contestId:)`, `count(contestId:)`, `nextSerial(contestId:)`) and
/// round-trip of `meta` via `LogbookRepository` (not directly via `LogbookDatabase`,
/// as `SQLiteTests.swift` tests it — Java has `metaGet`/`metaSet`
/// directly on `LogbookRepository`, so this file adds thin
/// delegating methods there, so that the repository API matches 1:1).
///
/// Additionally `QtcStoreTest.java` (package `qtc/`, not `logbook/` — hence it is
/// not part of the `logbook/` port) —
/// the only Java test for `insertQtc`/`findQtcs`/`deleteQtc`, which this
/// task also introduces.
@Suite struct LogbookContestPartitionTests {

    // MARK: - Helpers

    private func qso(_ call: String, _ contestId: String) -> Qso {
        var q = Qso()
        q.call = call
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z")
        q.contestId = contestId
        return q
    }

    // MARK: - `LogbookContestPartitionTest.findAllAndCountAreScopedByContest`

    @Test func findAllAndCountAreScopedByContest() throws {
        let repo = try LogbookRepository.inMemory()
        var a = qso("AA1A", "c1")
        var b = qso("BB2B", "c1")
        var c = qso("CC3C", "c2")
        _ = try repo.insert(&a)
        _ = try repo.insert(&b)
        _ = try repo.insert(&c)
        #expect(try repo.count(contestId: "c1") == 2)
        #expect(try repo.count(contestId: "c2") == 1)
        #expect(try repo.findAll(contestId: "c1").count == 2)
        #expect(try repo.findAll(contestId: "c2")[0].call == "CC3C")
    }

    // MARK: - `LogbookContestPartitionTest.nextSerialScopedByContest`

    @Test func nextSerialScopedByContest() throws {
        let repo = try LogbookRepository.inMemory()
        var a = qso("AA1A", "c1")
        var b = qso("BB2B", "c1")
        _ = try repo.insert(&a)
        _ = try repo.insert(&b)
        #expect(try repo.nextSerial(contestId: "c1") == 3) // 2 QSOs → next serial 3
        #expect(try repo.nextSerial(contestId: "c2") == 1) // empty contest → 1
    }

    // MARK: - `LogbookContestPartitionTest.metaRoundTrip`

    @Test func metaRoundTrip() throws {
        let repo = try LogbookRepository.inMemory()
        #expect(try repo.metaGet("last_contest_id") == nil)
        try repo.metaSet("last_contest_id", "c1")
        #expect(try repo.metaGet("last_contest_id") == "c1")
        try repo.metaSet("last_contest_id", "c2")
        #expect(try repo.metaGet("last_contest_id") == "c2")
    }

    // MARK: - `LogbookContestPartitionTest.insertPersistsContestId`

    @Test func insertPersistsContestId() throws {
        let repo = try LogbookRepository.inMemory()
        var a = qso("AA1A", "c9")
        _ = try repo.insert(&a)
        #expect(try repo.findAll(contestId: "c9")[0].contestId == "c9")
    }

    // MARK: - New tests without a Java ancestor: `nextSerial` edge cases

    /// Java `count(String)`/`nextSerial` filters only `deleted=0 AND contest_id=?` —
    /// regardless of `xqso`. A tombstone (`deleted=true`) drops out of the count (it must not
    /// reuse an already sent number again), an `xqso` row is still counted — the serial
    /// number was actually sent, even though the QSO does not count towards the score.
    @Test func nextSerialCountsXqsoButExcludesTombstones() throws {
        let repo = try LogbookRepository.inMemory()
        var active = qso("AA1A", "c1")
        _ = try repo.insert(&active)

        var xqso = qso("BB2B", "c1")
        xqso.xqso = true
        _ = try repo.insert(&xqso)

        var tomb = qso("CC3C", "c1")
        tomb.deleted = true
        _ = try repo.insert(&tomb)

        #expect(try repo.count(contestId: "c1") == 2) // active + xqso, not the tombstone
        #expect(try repo.nextSerial(contestId: "c1") == 3)
    }

    // MARK: - `QtcStoreTest.insertFindDelete` (package `qtc/`, see the doc comment above)

    @Test func qtcInsertFindDelete() throws {
        let repo = try LogbookRepository.inMemory()
        let q = QtcRecord(
            contestId: "wae-cw",
            sent: false,
            partnerCall: "W1AW",
            groupNr: 1,
            groupSize: 2,
            qsoTime: "1200",
            qsoCall: "DL1ABC",
            qsoSerial: 5,
            at: try #require(ISO8601DateFormatter().date(from: "2026-08-08T13:00:00Z")),
            freqHz: 14_025_000,
            mode: "CW"
        )
        let id = try repo.insertQtc(q)
        _ = try repo.insertQtc(QtcRecord(
            contestId: "other",
            sent: true,
            partnerCall: "K1X",
            groupNr: 1,
            groupSize: 1,
            qsoTime: "1300",
            qsoCall: "G3A",
            qsoSerial: 1,
            at: try #require(ISO8601DateFormatter().date(from: "2026-08-08T13:05:00Z")),
            freqHz: 7_010_000,
            mode: "CW"
        ))

        let found = try repo.findQtcs(contestId: "wae-cw")
        #expect(found.count == 1)
        #expect(found[0].qsoCall == "DL1ABC")

        try repo.deleteQtc(id: id)
        #expect(try repo.findQtcs(contestId: "wae-cw").isEmpty)
    }

    // MARK: - New tests without a Java ancestor: fix of `at_utc`
    //
    // Java `Instant.toString()` has a variable width of the fraction of a second (0/3/6/9
    // digits depending on the precision of the value). The four tests below cover one
    // width each, with literal Java strings as input (the last two
    // are real `Instant.now()` output on this machine, and
    // `Instant.ofEpochSecond` with a nine-digit fraction, respectively) — and for 6/9 digits
    // they openly show that a byte-for-byte match is **not** guaranteed there (see the doc
    // comment of `QtcRecord.formatAtUtc`), only microsecond precision.

    /// 0 digits — a whole second. Without the fix, `ISO8601DateFormatter`
    /// with `.withFractionalSeconds` would append a hard-coded `".000"` here too.
    @Test func formatAtUtcForWholeSecond() throws {
        let javaText = "2023-11-14T22:13:20Z" // Instant.ofEpochSecond(1_700_000_000L)
        let date = try #require(QtcRecord.parseAtUtc(javaText))
        #expect(QtcRecord.formatAtUtc(date) == javaText) // byte-for-byte match
    }

    /// 3 digits — milliseconds. The `Date` error (ULP ~200–250 ns for the current
    /// epoch) is three orders of magnitude smaller than a millisecond step (10⁶ ns), so
    /// the round-trip is byte-exact here too.
    @Test func formatAtUtcForMillisecond() throws {
        let javaText = "2023-11-14T22:13:20.500Z" // Instant.ofEpochSecond(1_700_000_000L, 500_000_000)
        let date = try #require(QtcRecord.parseAtUtc(javaText))
        #expect(QtcRecord.formatAtUtc(date) == javaText) // byte-for-byte match
    }

    /// 6 digits — microseconds. A literal `Instant.now()` output on the machine where
    /// this task was done — **not** a byte-exact round-trip: `Date` adds a
    /// large number (seconds since the epoch) to a small fraction, which rounds the fraction
    /// to ~22 remaining mantissa bits before `formatAtUtc` gets a chance to
    /// take it apart again — the really measured error on this input is 29 ns,
    /// enough for `formatAtUtc` to conclude it is a nine-digit (not
    /// six-digit) value. The test does not hide this: it only verifies that
    /// microsecond precision is preserved, not that the same text comes out.
    @Test func microsecondPrecisionRoundTripsWithinAMicrosecond() throws {
        let javaText = "2026-09-29T08:38:26.420028Z" // actual Instant.now() output on this machine
        let originalDate = try #require(ISO8601DateFormatter().date(from: "2026-09-29T08:38:26Z"))
            .addingTimeInterval(0.420028)
        let date = try #require(QtcRecord.parseAtUtc(javaText))
        #expect(abs(date.timeIntervalSince1970 - originalDate.timeIntervalSince1970) < 0.000_001) // < 1 µs

        let roundTripped = QtcRecord.formatAtUtc(date)
        #expect(roundTripped != javaText) // measured, not assumed — a byte-for-byte match does not hold here
        let decodedBack = try #require(QtcRecord.parseAtUtc(roundTripped))
        #expect(abs(decodedBack.timeIntervalSince1970 - originalDate.timeIntervalSince1970) < 0.000_001) // < 1 µs
    }

    /// 9 digits — nanoseconds. The same as microseconds, just explicitly on
    /// a value that is no longer a multiple of 1000 ns on input — `Date` simply
    /// does not have enough bits to store individual nanoseconds. It documents the ceiling
    /// of this implementation instead of pretending otherwise: parsing does **not** truncate
    /// the fraction to three digits (as `ISO8601DateFormatter` used to do with
    /// `.withFractionalSeconds`), but precision beyond ~1 microsecond
    /// cannot be guaranteed.
    @Test func nanosecondPrecisionRoundTripsWithinAMicrosecond() throws {
        let javaText = "2023-11-14T22:13:20.123456789Z" // Instant.ofEpochSecond(1_700_000_000L, 123_456_789)
        let originalDate = try #require(ISO8601DateFormatter().date(from: "2023-11-14T22:13:20Z"))
            .addingTimeInterval(0.123_456_789)
        let date = try #require(QtcRecord.parseAtUtc(javaText))

        // Safeguard against silent truncation to milliseconds (the old bug
        // `ISO8601DateFormatter` with `.withFractionalSeconds`): if the parser
        // dropped everything beyond three digits, it would yield exactly 1_700_000_000.123,
        // which is ~456 µs off — three orders of magnitude more than `Date` allows.
        let truncatedToMilliseconds = try #require(ISO8601DateFormatter().date(from: "2023-11-14T22:13:20Z"))
            .addingTimeInterval(0.123)
        #expect(abs(date.timeIntervalSince1970 - truncatedToMilliseconds.timeIntervalSince1970) > 0.0001)

        #expect(abs(date.timeIntervalSince1970 - originalDate.timeIntervalSince1970) < 0.000_001) // < 1 µs

        let roundTripped = QtcRecord.formatAtUtc(date)
        #expect(roundTripped != javaText) // implementation ceiling: a nine-digit byte-for-byte match is not possible
        let decodedBack = try #require(QtcRecord.parseAtUtc(roundTripped))
        #expect(abs(decodedBack.timeIntervalSince1970 - originalDate.timeIntervalSince1970) < 0.000_001) // < 1 µs
    }

    /// `parseAtUtc` on a string without a fraction (older rows or an `Instant` without a
    /// decimal part) — a literal round-trip, separate from the width tests
    /// above.
    @Test func parseAtUtcRoundTripsWholeSecond() throws {
        let whole = try #require(ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z"))
        let decodedWhole = try #require(QtcRecord.parseAtUtc(QtcRecord.formatAtUtc(whole)))
        #expect(abs(decodedWhole.timeIntervalSince1970 - whole.timeIntervalSince1970) < 0.001)
    }

    /// A concrete impact, reproduced directly: `ORDER BY at_utc`
    /// in `qtc` sorts purely textually. A row inserted by "Java" (a direct write via
    /// SQL, the literal `Instant.toString()` text without a fraction) and a row for
    /// the **same instant** inserted via `insertQtc` must have an identical `at_utc` text —
    /// otherwise the order would be governed not by time/insertion, but by whose formatter wrote
    /// the row. Before the fix `insertQtc` would write `".000Z"` (an extra fraction), which
    /// is textually *smaller* than a bare `"Z"` (`.` = 0x2E < `Z` = 0x5A) — the Swift
    /// row would be placed before the Java one, even if inserted later.
    @Test func atUtcTextMatchesJavaWrittenRowForSameInstant() throws {
        let repo = try LogbookRepository.inMemory()
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z"))

        let insertRaw = try repo.connection.prepare("""
            INSERT INTO qtc (contest_id, sent, partner_call, group_nr, group_size, qso_time, qso_call,
                             qso_serial, at_utc, freq_hz, mode) VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """)
        try insertRaw.bindText("c1", at: 1)
        try insertRaw.bindBool(true, at: 2)
        try insertRaw.bindText("X", at: 3)
        try insertRaw.bindInt(1, at: 4)
        try insertRaw.bindInt(1, at: 5)
        try insertRaw.bindText("1000", at: 6)
        try insertRaw.bindText("JAVA", at: 7)
        try insertRaw.bindInt(1, at: 8)
        try insertRaw.bindText("2026-07-04T10:00:00Z", at: 9) // literal `Instant.toString()`, no fraction
        try insertRaw.bindInt64(1, at: 10)
        try insertRaw.bindText(nil, at: 11)
        try insertRaw.step()
        insertRaw.finalize()
        let javaId = repo.connection.lastInsertRowID()

        let swiftId = try repo.insertQtc(QtcRecord(
            contestId: "c1", sent: true, partnerCall: "X", groupNr: 1, groupSize: 1,
            qsoTime: "1000", qsoCall: "SWIFT", qsoSerial: 1, at: instant, freqHz: 1, mode: nil))

        let ordered = try repo.findQtcs(contestId: "c1")
        #expect(ordered.map(\.id) == [javaId, swiftId]) // insertion order, not a format artifact
        #expect(Set(ordered.map(\.qsoCall)) == ["JAVA", "SWIFT"])
    }

    // MARK: - New test without a Java ancestor: `findQtcs` with `contestId: nil`

    /// Java: `findQtcs` uses `contest_id IS ?`, not `=?` — the only place in the
    /// repository where `contest_id` is compared even for `NULL`. It must work
    /// for a QTC without an assigned contest too.
    @Test func findQtcsMatchesNilContestId() throws {
        let repo = try LogbookRepository.inMemory()
        let q = QtcRecord(
            contestId: nil,
            sent: true,
            partnerCall: "W1AW",
            groupNr: 1,
            groupSize: 1,
            qsoTime: "0900",
            qsoCall: "G1XYZ",
            qsoSerial: 3,
            at: try #require(ISO8601DateFormatter().date(from: "2026-08-08T09:00:00Z")),
            freqHz: 3_560_000,
            mode: "CW"
        )
        _ = try repo.insertQtc(q)
        let found = try repo.findQtcs(contestId: nil)
        #expect(found.count == 1)
        #expect(found[0].qsoCall == "G1XYZ")
    }
}
