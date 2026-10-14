import Foundation
import Testing
@testable import MCLCore

/// N1MM's transaction file: every QSO write of the repository is appended; the QSO table is rebuilt from it.
@Suite struct TransactionJournalTests {

    private static func qso(_ call: String, contest: String = "c1", minute: Int = 0) -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = 14_025_000
        q.mode = .cw
        q.rstSent = "599"
        q.exchangeRcvd = "14"
        q.serialSent = 7
        q.points = 3
        q.multiplier = true
        q.runMode = .searchAndPounce
        q.dxccEntity = 230
        q.dxccName = "Germany"
        q.continent = "EU"
        q.timestampUtc = Date(timeIntervalSince1970: 1_800_000_000 + Double(minute * 60) + 0.125)
        q.contestId = contest
        return q
    }

    @Test func everyWriteIsJournalledAndTheTableIsRebuilt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbUrl = dir.appendingPathComponent("Test.sqlite")
        let journalUrl = TransactionJournal.fileURL(forDatabase: dbUrl)
        #expect(journalUrl.lastPathComponent == "Test.sqlite.trn")
        let repository = try LogbookRepository(url: dbUrl)
        repository.journal = TransactionJournal(url: journalUrl)
        var a = Self.qso("DL1ABC")
        var b = Self.qso("W1AW", minute: 1)
        var c = Self.qso("JA1ABC", minute: 2)
        try repository.insert(&a)
        try repository.insert(&b)
        try repository.insert(&c)
        b.comment = "edited"
        try repository.update(b)
        try repository.delete(id: try #require(c.id))
        repository.close()

        let text = try String(contentsOf: journalUrl, encoding: .utf8)
        let parsed = TransactionJournal.parse(text + "{\"cut short")
        #expect(parsed.entries.map(\.op) == [.insert, .insert, .insert, .update, .delete])
        #expect(parsed.unreadable == 1)
        let rebuilt: [Qso] = TransactionJournal.replay(parsed.entries)
        #expect(rebuilt.map(\.call) == ["DL1ABC", "W1AW"])
        #expect(rebuilt[1].comment == "edited")
        var expected = a
        expected.id = rebuilt[0].id
        #expect(rebuilt[0] == expected)

        // Bulk deletes and „delete all" are journalled too.
        let again = try LogbookRepository(url: dbUrl)
        again.journal = TransactionJournal(url: journalUrl)
        try again.delete(ids: [try #require(a.id)])
        try again.deleteAll()
        again.close()
        let all = TransactionJournal.parse(try String(contentsOf: journalUrl, encoding: .utf8)).entries
        #expect(all.suffix(2).map(\.op) == [.delete, .deleteAll])
        #expect(TransactionJournal.replay(all).isEmpty)
    }

    @Test func theOpenContestOrTheLastOneIsRecovered() {
        var first = Self.qso("DL1ABC", contest: "old")
        first.id = 1
        var second = Self.qso("W1AW", contest: "new", minute: 1)
        second.id = 2
        var tombstone = Self.qso("JA1ABC", contest: "new", minute: 2)
        tombstone.deleted = true
        let entries: [TransactionJournal.Entry] = [
            .init(at: 0, op: .insert, id: 1, qso: JournalQso(first)),
            .init(at: 0, op: .insert, id: 2, qso: JournalQso(second)),
            .init(at: 0, op: .insert, id: 3, qso: JournalQso(tombstone)),
        ]
        let rebuilt: [Qso] = TransactionJournal.replay(entries)
        #expect(rebuilt.map(\.call) == ["DL1ABC", "W1AW"])
        #expect(TransactionJournal.recoverable(rebuilt, activeContestId: "old").map(\.call) == ["DL1ABC"])
        #expect(TransactionJournal.recoverable(rebuilt, activeContestId: "fresh").map(\.call) == ["W1AW"])
        #expect(TransactionJournal.recoverable([], activeContestId: "fresh").isEmpty)
    }
}
