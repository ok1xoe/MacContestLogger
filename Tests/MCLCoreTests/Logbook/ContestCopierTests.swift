import Foundation
import Testing
@testable import MCLCore

/// Copying contests with their QSOs into another database file.
@Suite struct ContestCopierTests {

    private struct Fixture {
        let dir: URL
        let sourceUrl: URL
        let source: LogbookRepository
        let contests: ContestStore

        init() throws {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcl-copy-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            sourceUrl = dir.appendingPathComponent("source.sqlite")
            source = try LogbookRepository(url: sourceUrl)
            contests = try ContestStore(source)
        }

        var target: URL {
            dir.appendingPathComponent("target.sqlite")
        }

        func remove() {
            source.close()
            try? FileManager.default.removeItem(at: dir)
        }

        func addContest(_ id: String, name: String, qsos: [(call: String, minute: Int64)]) throws {
            try contests.insert(ContestStore.ContestRow(
                contestId: id, definitionId: "def-" + id, name: name, startedAt: 1_000, endedAt: nil,
                definitionYaml: "id: " + id, setupJson: "{\"s\":1}", stationJson: "{}"))
            for item in qsos {
                var qso = Qso()
                qso.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200 + TimeInterval(item.minute * 60))
                qso.call = item.call
                qso.freqHz = 14_025_000
                qso.mode = .cw
                qso.contestId = id
                qso.points = 3
                qso.multiplier = true
                qso.stationId = "station-1"
                qso.version = 7
                try source.insert(&qso)
            }
        }

        func addFreeQso(_ call: String) throws {
            var qso = Qso()
            qso.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200)
            qso.call = call
            qso.freqHz = 7_025_000
            qso.mode = .cw
            try source.insert(&qso)
        }
    }

    private static func read(_ url: URL) throws -> (qsos: [Qso], contests: [ContestStore.ContestRow]) {
        let repository = try LogbookRepository(url: url)
        defer { repository.close() }
        let store = try ContestStore(repository)
        let ids: [String] = try store.listSummaries().map(\.contestId).sorted()
        return (try repository.findAll().sorted { $0.call < $1.call },
                try ids.compactMap { try store.find($0) })
    }

    @Test func oneContestIsCopiedWithItsQsosAndIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.addContest("c1", name: "One", qsos: [("DL1ABC", 0), ("W1AW", 1)])
        try fixture.addContest("c2", name: "Two", qsos: [("OK1XYZ", 2)])
        let before = try Self.read(fixture.sourceUrl)

        let summary = try ContestCopier.copy(contestIds: ["c1"], source: fixture.source,
                                             sourceContests: fixture.contests, sourceUrl: fixture.sourceUrl,
                                             target: fixture.target)

        #expect(summary.contestsAdded == 1)
        #expect(summary.qsosAdded == 2)
        #expect(summary.qsosSkipped == 0)
        let copied = try Self.read(fixture.target)
        #expect(copied.contests.map(\.contestId) == ["c1"])
        #expect(copied.contests.first?.definitionYaml == "id: c1")
        #expect(copied.contests.first?.setupJson == "{\"s\":1}")
        #expect(copied.qsos.map(\.call) == ["DL1ABC", "W1AW"])
        // Every QSO keeps its uuid, version, station and score fields.
        let originals = before.qsos.filter { $0.contestId == "c1" }.sorted { $0.call < $1.call }
        for (copy, original) in zip(copied.qsos, originals) {
            #expect(copy.uuid == original.uuid)
            #expect(!copy.uuid.isEmpty)
            #expect(copy.version == 7)
            #expect(copy.stationId == "station-1")
            #expect(copy.points == 3)
            #expect(copy.multiplier)
            #expect(copy.contestId == "c1")
            #expect(copy.timestampUtc == original.timestampUtc)
        }
        // The source is untouched.
        let after = try Self.read(fixture.sourceUrl)
        #expect(after.qsos == before.qsos)
        #expect(after.contests == before.contests)
    }

    @Test func copyingAgainAddsNothing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.addContest("c1", name: "One", qsos: [("DL1ABC", 0), ("W1AW", 1)])
        _ = try ContestCopier.copy(contestIds: ["c1"], source: fixture.source, sourceContests: fixture.contests,
                                   sourceUrl: fixture.sourceUrl, target: fixture.target)
        // A QSO logged later in the source is the only new one.
        var late = Qso()
        late.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200 + 3_600)
        late.call = "VE3XX"
        late.freqHz = 14_030_000
        late.mode = .cw
        late.contestId = "c1"
        try fixture.source.insert(&late)

        let again = try ContestCopier.copy(contestIds: ["c1"], source: fixture.source,
                                           sourceContests: fixture.contests, sourceUrl: fixture.sourceUrl,
                                           target: fixture.target)

        #expect(again.contestsAdded == 0)
        #expect(again.contestsPresent == 1)
        #expect(again.qsosAdded == 1)
        #expect(again.qsosSkipped == 2)
        #expect(try Self.read(fixture.target).qsos.count == 3)
    }

    @Test func allContestsAndTheFreeLoggingQsosAreCopied() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.addContest("c1", name: "One", qsos: [("DL1ABC", 0)])
        try fixture.addContest("c2", name: "Two", qsos: [("OK1XYZ", 2)])
        try fixture.addFreeQso("G3ABC")

        let summary = try ContestCopier.copy(contestIds: nil, source: fixture.source,
                                             sourceContests: fixture.contests, sourceUrl: fixture.sourceUrl,
                                             target: fixture.target)

        #expect(summary.contestsAdded == 2)
        #expect(summary.qsosAdded == 3)
        #expect(summary.includedFreeLogging)
        let copied = try Self.read(fixture.target)
        #expect(copied.contests.map(\.contestId) == ["c1", "c2"])
        #expect(copied.qsos.map(\.call) == ["DL1ABC", "G3ABC", "OK1XYZ"])
        #expect(copied.qsos.first { $0.call == "G3ABC" }?.contestId == "")
    }

    @Test func aContestTheTargetHasKeepsItsRow() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.addContest("c1", name: "One", qsos: [("DL1ABC", 0)])
        let other = try LogbookRepository(url: fixture.target)
        let otherContests = try ContestStore(other)
        try otherContests.insert(ContestStore.ContestRow(
            contestId: "c1", definitionId: "kept", name: "Kept", startedAt: nil, endedAt: nil,
            definitionYaml: "id: kept", setupJson: nil, stationJson: nil))
        other.close()

        let summary = try ContestCopier.copy(contestIds: ["c1"], source: fixture.source,
                                             sourceContests: fixture.contests, sourceUrl: fixture.sourceUrl,
                                             target: fixture.target)

        #expect(summary.contestsAdded == 0)
        #expect(summary.contestsPresent == 1)
        #expect(summary.qsosAdded == 1)
        #expect(try Self.read(fixture.target).contests.first?.name == "Kept")
    }

    @Test func qtcRecordsGoWithANewContestRow() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.addContest("c1", name: "One", qsos: [("DL1ABC", 0)])
        try fixture.source.insertQtc(QtcRecord(contestId: "c1", sent: true, partnerCall: "DL1ABC", groupNr: 1,
                                               groupSize: 1, qsoTime: "1200", qsoCall: "W1AW", qsoSerial: 5,
                                               at: Date(timeIntervalSince1970: 1_795_867_300), freqHz: 14_025_000,
                                               mode: "CW"))
        for _ in 0..<2 {
            _ = try ContestCopier.copy(contestIds: ["c1"], source: fixture.source,
                                       sourceContests: fixture.contests, sourceUrl: fixture.sourceUrl,
                                       target: fixture.target)
        }
        let repository = try LogbookRepository(url: fixture.target)
        defer { repository.close() }
        #expect(try repository.findQtcs(contestId: "c1").count == 1)
    }

    @Test func theOpenDatabaseCannotBeTheTarget() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.addContest("c1", name: "One", qsos: [("DL1ABC", 0)])
        #expect(throws: ContestCopier.CopyError.self) {
            _ = try ContestCopier.copy(contestIds: ["c1"], source: fixture.source, sourceContests: fixture.contests,
                                       sourceUrl: fixture.sourceUrl, target: fixture.sourceUrl)
        }
        #expect(try Self.read(fixture.sourceUrl).qsos.count == 1)
    }

    @Test func aFailureLeavesTheTargetAsItWas() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.addContest("c1", name: "One", qsos: [("DL1ABC", 0)])
        // The second contest does not exist: the first one's copy is rolled back.
        #expect(throws: ContestCopier.CopyError.self) {
            _ = try ContestCopier.copy(contestIds: ["c1", "missing"], source: fixture.source,
                                       sourceContests: fixture.contests, sourceUrl: fixture.sourceUrl,
                                       target: fixture.target)
        }
        let copied = try Self.read(fixture.target)
        #expect(copied.contests.isEmpty)
        #expect(copied.qsos.isEmpty)
    }
}
