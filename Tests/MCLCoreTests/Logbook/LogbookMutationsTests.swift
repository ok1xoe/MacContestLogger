import Foundation
import Testing
@testable import MCLCore

/// `LogbookMutations`: the incrementally kept `DupeIndex` equals `DupeChecker(existing:)` built over
/// the whole logbook (what Kotlin rebuilds with `DupeChecker(logbook.findAll())`).
@Suite struct LogbookMutationsTests {

    /// Deterministic generator (SplitMix64) so the seeded logbook is the same on every run.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let prefixes = ["OK1", "ok2", "Dl1", "w1", "G4", "SP9", "ok1"]
    private static let suffixes = ["ABC", "xoe", "Z", "AA", "kw"]
    private static let decorations = ["", "/P", "/p", " ", "\t", "\u{00A0}", "/M"]
    private static let freqs = [1_830_000, 3_520_000, 7_010_000, 14_025_000, 21_030_000, 28_020_000, 0, 5_000]

    private static func randomQso(_ rng: inout SplitMix) -> Qso {
        var q = Qso()
        let prefix: String = prefixes.randomElement(using: &rng)!
        let suffix: String = suffixes.randomElement(using: &rng)!
        let deco: String = decorations.randomElement(using: &rng)!
        let call: String = prefix + suffix + deco
        q.call = call
        q.freqHz = freqs.randomElement(using: &rng)!
        q.deleted = Int.random(in: 0..<20, using: &rng) == 0
        return q
    }

    @Test func incrementalIndexEqualsFullRebuild() throws {
        var rng = SplitMix(state: 20_261_002)
        var logbook: [Qso] = []
        var mutations = LogbookMutations(existing: [])
        for step in 0..<3_000 {
            let q = Self.randomQso(&rng)
            logbook.append(q)
            mutations.didInsert(q)
            if step % 250 == 0 {
                try Self.expectEquivalent(mutations, DupeChecker(existing: logbook), &rng)
            }
        }
        try Self.expectEquivalent(mutations, DupeChecker(existing: logbook), &rng)
    }

    private static func expectEquivalent(_ m: LogbookMutations, _ checker: DupeChecker, _ rng: inout SplitMix) throws {
        for _ in 0..<400 {
            let probe = randomQso(&rng)
            let prefix: String = prefixes.randomElement(using: &rng)!
            let suffix: String = suffixes.randomElement(using: &rng)!
            let deco: String = decorations.randomElement(using: &rng)!
            let raw: String = prefix + suffix + deco
            var bands: [Band?] = [probe.band, nil]
            for band in Band.allCases.prefix(4) {
                bands.append(band)
            }
            let calls: [String] = [probe.call, raw, raw.lowercased(), " " + raw]
            for call in calls {
                for band in bands {
                    #expect(m.isDupe(call: call, band: band) == checker.isDupe(call: call, band: band),
                            "\(call) \(String(describing: band))")
                }
            }
        }
        #expect(m.isDupe(call: nil, band: .m20) == false)
    }

    @Test func insertPersistsAndReturnsStoredQso() throws {
        let service = LogbookService(repository: try LogbookRepository.inMemory())
        service.activeContestId = "test-contest"
        var q = Qso()
        q.call = "OK1ABC"
        q.freqHz = 14_025_000
        let stored = try LogbookMutations.insert(q, into: service)
        #expect(stored.id != nil)
        #expect(!stored.uuid.isEmpty)
        #expect(stored.contestId == "test-contest")
        #expect(stored.timestampUtc != nil)
        var mutations = LogbookMutations(existing: try service.findAll())
        #expect(mutations.isDupe(call: "ok1abc", band: .m20))
        var next = Qso()
        next.call = "OK2ZZ"
        next.freqHz = 7_010_000
        let second = try LogbookMutations.insert(next, into: service)
        mutations.didInsert(second)
        #expect(mutations.isDupe(call: "OK2ZZ", band: .m40))
        #expect(!mutations.isDupe(call: "OK2ZZ", band: .m20))
        #expect(try service.count() == 2)
    }

    /// The blocking writes against a real (in-memory) logbook: after each update, bulk edit, delete, Ctrl+D and wipe
    /// the index equals the one rebuilt from `findAll()` (Kotlin `DupeChecker(logbook.findAll())`).
    @Test func writesKeepTheIndexEqualToTheStoredLogbook() throws {
        let service = LogbookService(repository: try LogbookRepository.inMemory())
        service.activeContestId = "test-contest"
        var rng = DupeIndexTests.SplitMix(state: 99)
        var rows: [Qso] = []
        var mutations = LogbookMutations(existing: [])
        func check() throws {
            let stored: [Qso] = try service.findAll()
            #expect(mutations.dupes == DupeIndex(existing: stored))
            let checker = DupeChecker(existing: stored)
            for _ in 0..<6 {
                let call: String = DupeIndexTests.randomCall(&rng)
                let band: Band? = Band.from(frequencyHz: DupeIndexTests.freqs[rng.below(DupeIndexTests.freqs.count)])
                #expect(mutations.isDupe(call: call, band: band) == checker.isDupe(call: call, band: band))
            }
        }
        for step in 0..<600 {
            let roll: Int = rng.below(100)
            if rows.isEmpty || roll < 40 {
                var q = DupeIndexTests.randomQso(&rng, id: 0)
                q.id = nil
                q.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000 + Double(step))
                let stored = try LogbookMutations.insert(q, into: service)
                rows.append(stored)
                mutations.didInsert(stored)
            } else if roll < 70 {
                let i: Int = rng.below(rows.count)
                let edited: Qso = LogTableEdit.apply(column: .call, text: DupeIndexTests.randomCall(&rng), to: rows[i])
                let edit = LogbookMutations.Edit(old: rows[i], new: edited)
                let change = try #require(try LogbookMutations.update(edit, in: service))
                if case .updated(_, let written) = change {
                    rows[i] = written
                }
                mutations.apply([change])
            } else if roll < 80 {
                let picked: [Int] = Array(Set([rng.below(rows.count), rng.below(rows.count)])).sorted()
                let outcome = BulkAction.frequency.run(text: "7010", on: picked.map { rows[$0] })
                let saved = LogbookMutations.bulk(outcome.edits, in: service)
                #expect(saved.error == nil)
                for (index, change) in zip(picked, saved.changes) {
                    if case .updated(_, let written) = change {
                        rows[index] = written
                    }
                }
                mutations.apply(saved.changes)
            } else if roll < 92 {
                let i: Int = rng.below(rows.count)
                let changes = try LogbookMutations.delete([rows[i]], in: service)
                rows.remove(at: i)
                mutations.apply(changes)
            } else if roll < 98 {
                let result = try LogbookMutations.deleteLast(of: rows, in: service)
                #expect(result.status == ContestMessage("Smazáno poslední QSO %s", .string(rows[rows.count - 1].call)))
                rows.removeLast()
                mutations.apply(result.changes)
            } else {
                let result = try LogbookMutations.wipe(rows, in: service)
                #expect(result.status == ContestMessage("Deník vymazán (%s QSO)", .int(rows.count)))
                rows.removeAll()
                mutations.apply(result.changes)
            }
            try check()
        }
    }

    @Test func deleteLastOfAnEmptyLogOnlyReports() throws {
        let service = LogbookService(repository: try LogbookRepository.inMemory())
        let result = try LogbookMutations.deleteLast(of: [], in: service)
        #expect(result.changes.isEmpty)
        #expect(result.status.czech == "Deník je prázdný")
    }

    @Test func deleteSkipsRowsWithoutAnId() throws {
        let service = LogbookService(repository: try LogbookRepository.inMemory())
        var unsaved = Qso()
        unsaved.call = "OK1ABC"
        let changes = try LogbookMutations.delete([unsaved], in: service)
        #expect(changes.isEmpty)
    }

    /// A stored logbook with `count` QSOs on 20 m (`OK1AA`, `OK1AB`, …) and the stored rows.
    private static func storedLog(_ count: Int) throws -> (LogbookService, [Qso]) {
        let service = LogbookService(repository: try LogbookRepository.inMemory())
        service.activeContestId = "test-contest"
        for i in 0..<count {
            var q = Qso()
            q.call = "OK1A" + String(UnicodeScalar(UInt8(65 + i)))
            q.freqHz = 14_025_000
            q.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000 + Double(i))
            _ = try LogbookMutations.insert(q, into: service)
        }
        return (service, try service.findAll())
    }

    /// Two edits of the same row started from the same (stale) copy: both persist, and the index follows the store.
    @Test func editsFromAStaleRowKeepEarlierEditsAndTheIndex() throws {
        let (service, rows) = try Self.storedLog(3)
        var mutations = LogbookMutations(existing: rows)
        let stale: Qso = rows[0]
        let first = LogTableEdit.apply(column: .call, text: "DL1ABC", to: stale)
        let second = LogTableEdit.apply(column: .note, text: "late", to: stale)
        let c1 = try #require(try LogbookMutations.update(LogbookMutations.Edit(old: stale, new: first), in: service))
        let c2 = try #require(try LogbookMutations.update(LogbookMutations.Edit(old: stale, new: second), in: service))
        mutations.apply([c1, c2])
        let staleId: Int64 = try #require(stale.id)
        let stored = try #require(try service.findById(staleId))
        #expect(stored.call == "DL1ABC", "the first edit is not lost")
        #expect(stored.comment == "late")
        var oldOfSecond: Qso = stored
        oldOfSecond.comment = ""
        #expect(c2 == .updated(old: oldOfSecond, new: stored), "the stored row is the old state, not the stale copy")
        #expect(mutations.dupes == DupeIndex(existing: try service.findAll()))
        #expect(!mutations.isDupe(call: "OK1AA", band: .m20))
        #expect(mutations.isDupe(call: "DL1ABC", band: .m20))
    }

    /// A bulk edit over a stale selection after a single edit keeps the single edit and the index.
    @Test func bulkFromStaleRowsKeepsEarlierEdits() throws {
        let (service, rows) = try Self.storedLog(3)
        var mutations = LogbookMutations(existing: rows)
        let edited = LogTableEdit.apply(column: .call, text: "SP9XX", to: rows[1])
        let c1 = try #require(try LogbookMutations.update(LogbookMutations.Edit(old: rows[1], new: edited), in: service))
        let outcome = BulkAction.frequency.run(text: "7010", on: rows) // stale rows[1]
        let saved = LogbookMutations.bulk(outcome.edits, in: service)
        #expect(saved.error == nil)
        mutations.apply([c1] + saved.changes)
        let stored = try service.findAll()
        #expect(stored.map(\.call).sorted() == ["OK1AA", "OK1AC", "SP9XX"])
        #expect(stored.allSatisfy { $0.band == .m40 })
        #expect(mutations.dupes == DupeIndex(existing: stored))
    }

    @Test func updateOfADeletedRowChangesNothing() throws {
        let (service, rows) = try Self.storedLog(2)
        _ = try LogbookMutations.delete([rows[0]], in: service)
        let edited = LogTableEdit.apply(column: .call, text: "DL1ABC", to: rows[0])
        #expect(try LogbookMutations.update(LogbookMutations.Edit(old: rows[0], new: edited), in: service) == nil)
        #expect(try service.count() == 1)
    }

    /// Deleting with a stale list twice removes each QSO once; a repeated Ctrl+D over a stale list deletes the previous
    /// row, as Kotlin (whose list is never stale) would.
    @Test func staleDeletesNeverRemoveTwice() throws {
        let (service, rows) = try Self.storedLog(4)
        var mutations = LogbookMutations(existing: rows)
        mutations.apply(try LogbookMutations.delete([rows[0], rows[0]], in: service))
        let again = try LogbookMutations.delete([rows[0]], in: service)
        #expect(again.isEmpty)
        mutations.apply(again)
        let first = try LogbookMutations.deleteLast(of: rows, in: service)
        let second = try LogbookMutations.deleteLast(of: rows, in: service)
        #expect(first.status.czech == "Smazáno poslední QSO OK1AD")
        #expect(second.status.czech == "Smazáno poslední QSO OK1AC")
        mutations.apply(first.changes + second.changes)
        let left = try service.findAll()
        #expect(left.map(\.call) == ["OK1AB"])
        #expect(mutations.dupes == DupeIndex(existing: left))
        let wiped = try LogbookMutations.wipe(rows, in: service)
        #expect(wiped.changes == [.deleted(left[0])])
        #expect(try LogbookMutations.deleteLast(of: rows, in: service).status.czech == "Deník je prázdný")
    }

    @Test func resetRebuildsTheIndex() throws {
        let (_, rows) = try Self.storedLog(3)
        var mutations = LogbookMutations(existing: rows)
        mutations.apply([.reset([rows[2]])])
        #expect(mutations.dupes == DupeIndex(existing: [rows[2]]))
        #expect(!mutations.isDupe(call: "OK1AA", band: .m20))
        #expect(mutations.isDupe(call: "OK1AC", band: .m20))
    }

    /// The time cell accepts years Java accepts; their milliseconds overflow `Int64` — the save throws (Java
    /// `toEpochMilli` throws too) instead of trapping.
    @Test func aTimeBeyondTheMillisecondRangeThrowsOnSave() throws {
        let (service, rows) = try Self.storedLog(1)
        let edited = LogTableEdit.apply(column: .time, text: "+999999999-12-31 23:59:59", to: rows[0])
        #expect(edited.timestampUtc != rows[0].timestampUtc)
        #expect(throws: LogbookError.self) {
            try LogbookMutations.update(LogbookMutations.Edit(old: rows[0], new: edited), in: service)
        }
        #expect(try service.findAll() == rows, "nothing written")
    }
}
