import Foundation
import Testing
@testable import MCLCore

/// Port of `LogbookServiceTest.java` (2 tests), `LogbookServiceContestTest.java`
/// (1 test) and `ClockOffsetTest.java` (1 test) — three Java test classes for
/// one service, merged here (one file
/// `LogbookServiceTests.swift`), the same precedent as merging several Java
/// classes into `LogbookContestPartitionTests.swift`.
@Suite struct LogbookServiceTests {

    // MARK: - `LogbookServiceTest`

    private func syncQso(uuid: String, call: String, version: Int64) -> Qso {
        var q = Qso()
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-06-17T12:00:00Z")
        q.call = call
        q.freqHz = 14_074_000
        q.mode = .ssb
        q.uuid = uuid
        q.version = version
        q.contestId = "test-contest"
        return q
    }

    @Test func upsertByUuidMergesIncomingState() throws {
        let repo = try LogbookRepository.inMemory()
        let service = LogbookService(repository: repo)
        service.activeContestId = "test-contest"

        try service.upsertByUuid(syncQso(uuid: "uuid-A", call: "DL1ABC", version: 1))
        try service.upsertByUuid(syncQso(uuid: "uuid-A", call: "DL1XYZ", version: 2)) // newer version

        let all = try service.findAll()
        #expect(all.count == 1)
        #expect(all[0].call == "DL1XYZ")
    }

    @Test func markDeletedRemovesFromActiveButKeepsTombstone() throws {
        let repo = try LogbookRepository.inMemory()
        let service = LogbookService(repository: repo)
        service.activeContestId = "test-contest"

        try service.upsertByUuid(syncQso(uuid: "uuid-A", call: "DL1ABC", version: 1))
        let deletedAt: Date = try #require(ISO8601DateFormatter().date(from: "2026-06-17T13:00:00Z"))
        try service.markDeleted(uuid: "uuid-A", version: 2, updatedAtUtc: deletedAt)

        #expect(try service.findAll().isEmpty)
        let includingDeleted = try service.findAllIncludingDeleted()
        #expect(includingDeleted.count == 1)
        #expect(includingDeleted[0].deleted)
    }

    // MARK: - `LogbookServiceContestTest.logAndReadScopedToActiveContest`

    private func contestQso(_ call: String) -> Qso {
        var q = Qso()
        q.call = call
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z")
        return q
    }

    @Test func logAndReadScopedToActiveContest() throws {
        let s = LogbookService(repository: try LogbookRepository.inMemory())
        s.activeContestId = "c1"
        var aa1a = contestQso("AA1A")
        try s.log(&aa1a)
        s.activeContestId = "c2"
        var bb2b = contestQso("BB2B")
        try s.log(&bb2b)

        #expect(try s.count() == 1) // active c2
        #expect(try s.findAll()[0].call == "BB2B")
        s.activeContestId = "c1"
        #expect(try s.count() == 1)
        #expect(try s.findAll()[0].call == "AA1A")
        #expect(try s.nextSerial() == 2) // c1 has 1 QSO → next is 2
    }

    // MARK: - Without an active contest (free logging)

    /// The "no active contest" state (`activeContestId == ""`, Java `null`) is free logging: QSOs are
    /// stored with `contest_id` SQL `NULL` (as in Java) and `findAll()`/`count()`/`nextSerial()` follow
    /// exactly those rows. A deliberate divergence from Java v1.1.1, where `contest_id=?` with a bound
    /// `NULL` matched nothing; a contest's log and the free-logging log never mix.
    @Test func withoutActiveContestTheFreeLoggingQsosAreTheLog() throws {
        let repo = try LogbookRepository.inMemory()
        let s = LogbookService(repository: repo) // activeContestId == "" (Java null)

        var aa1a = contestQso("AA1A")
        try s.log(&aa1a)
        var bb2b = contestQso("BB2B")
        try s.log(&bb2b)
        s.activeContestId = "c1"
        var cc3c = contestQso("CC3C")
        try s.log(&cc3c)

        #expect(try s.findAll().map(\.call) == ["CC3C"], "the contest sees only its own QSO")
        #expect(try s.count() == 1)

        s.activeContestId = ""
        #expect(try s.findAll().map(\.call) == ["AA1A", "BB2B"])
        #expect(try s.findAll().allSatisfy { $0.contestId.isEmpty })
        #expect(try s.count() == 2)
        #expect(try s.nextSerial() == 3)
        #expect(try s.findAllIncludingDeleted().count == 3)

        // In the file they have `contest_id` as SQL NULL, not an empty TEXT (as in Java).
        let stmt = try repo.connection.prepare("SELECT typeof(contest_id) FROM qso ORDER BY id")
        defer { stmt.finalize() }
        var types: [String] = []
        while try stmt.step() {
            types.append(stmt.columnText(at: 0) ?? "?")
        }
        #expect(types == ["null", "null", "text"], "contest_id must be NULL, not ''")
    }

    // MARK: - `ClockOffsetTest.newQsoTimeIsCorrected`

    @Test func newQsoTimeIsCorrected() throws {
        let repo = try LogbookRepository.inMemory()
        let fixed = try #require(ISO8601DateFormatter().date(from: "2026-11-28T12:00:00Z"))
        let s = LogbookService(repository: repo, now: { fixed })
        s.clockOffset = 2.5 // 2 500 ms

        var q = Qso()
        q.call = "W1AW"
        try s.log(&q)
        #expect(q.timestampUtc == fixed.addingTimeInterval(2.5)) // 2026-11-28T12:00:02.500Z

        var paper = Qso()
        paper.call = "DL1ABC"
        paper.timestampUtc = ISO8601DateFormatter().date(from: "2026-11-28T10:00:00Z")
        try s.log(&paper)
        // the entered time is not changed
        #expect(paper.timestampUtc == ISO8601DateFormatter().date(from: "2026-11-28T10:00:00Z"))
    }
}
