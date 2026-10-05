import Foundation
import Testing
@testable import MCLCore

/// Port of `ContestStoreTest.java` — the `contests` table (definition snapshot + setup) and
/// aggregated statistics over `qso` (`listSummaries`).
@Suite struct ContestStoreTests {

    // MARK: - Helpers

    /// Corresponds to the private `qso(call, band, contestId, iso)` in Java — the `band` parameter
    /// is dead code there (never used), the row always gets `Band.M20`. This
    /// counterpart does exactly the same, including the unused parameter.
    private func qso(_ call: String, _ band: String, _ contestId: String, _ iso: String) -> Qso {
        var q = Qso()
        q.call = call
        q.timestampUtc = ISO8601DateFormatter().date(from: iso)
        q.contestId = contestId
        q.band = .m20
        return q
    }

    // MARK: - `ContestStoreTest.insertFindRoundTrip`

    @Test func insertFindRoundTrip() throws {
        let repo = try LogbookRepository.inMemory()
        let store = try ContestStore(repo)
        try store.insert(ContestStore.ContestRow(
            contestId: "c1", definitionId: "cq-ww-cw", name: "CQ WW CW",
            startedAt: 1_000, endedAt: 2_000, definitionYaml: "schemaVersion: 1",
            setupJson: "{}", stationJson: "{}"))
        let got = try #require(try store.find("c1"))
        #expect(got.definitionId == "cq-ww-cw")
        #expect(got.name == "CQ WW CW")
        #expect(got.startedAt == 1_000)
        #expect(got.definitionYaml == "schemaVersion: 1")
    }

    // MARK: - `ContestStoreTest.updateSetupPersistsAndIsReadBack`

    @Test func updateSetupPersistsAndIsReadBack() throws {
        let repo = try LogbookRepository.inMemory()
        let store = try ContestStore(repo)
        try store.insert(ContestStore.ContestRow(
            contestId: "c1", definitionId: "cq-ww-cw", name: "CQ WW CW",
            startedAt: 1, endedAt: 2, definitionYaml: "y", setupJson: "{}", stationJson: "{}"))
        // Skeds, TOUR and bonus stations are stored here — read by activeContestSetup.
        #expect(try store.updateSetup(contestId: "c1", setupJson: "{\"tour\":\"1200/30\"}"))
        #expect(try store.find("c1")?.setupJson == "{\"tour\":\"1200/30\"}")
        // The definition snapshot and the other columns must not be overwritten.
        #expect(try store.find("c1")?.definitionYaml == "y")
    }

    // MARK: - `ContestStoreTest.updateSetupOfUnknownContestReportsFailure`

    @Test func updateSetupOfUnknownContestReportsFailure() throws {
        let repo = try LogbookRepository.inMemory()
        let store = try ContestStore(repo)
        #expect(try store.updateSetup(contestId: "neexistuje", setupJson: "{}") == false)
    }

    // MARK: - `ContestStoreTest.listSummariesAggregatesQsoStats`

    @Test func listSummariesAggregatesQsoStats() throws {
        let repo = try LogbookRepository.inMemory()
        let store = try ContestStore(repo)
        try store.insert(ContestStore.ContestRow(
            contestId: "c1", definitionId: "cq-ww-cw", name: "CQ WW CW",
            startedAt: 1, endedAt: 2, definitionYaml: "y", setupJson: "{}", stationJson: "{}"))
        var a = qso("AA1A", "20m", "c1", "2026-07-04T10:00:00Z")
        var b = qso("BB2B", "20m", "c1", "2026-07-04T11:00:00Z")
        _ = try repo.insert(&a)
        _ = try repo.insert(&b)

        let list = try store.listSummaries()
        #expect(list.count == 1)
        let s = try #require(list.first)
        #expect(s.contestId == "c1")
        #expect(s.qsoCount == 2)
        #expect(s.bands.contains("M20"))
        let expectedFirst = try #require(ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z"))
        let expectedLast = try #require(ISO8601DateFormatter().date(from: "2026-07-04T11:00:00Z"))
        #expect(s.firstQso == Int64((expectedFirst.timeIntervalSince1970 * 1000).rounded()))
        #expect(s.lastQso == Int64((expectedLast.timeIntervalSince1970 * 1000).rounded()))
    }
}
