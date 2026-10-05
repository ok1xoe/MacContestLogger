import Foundation
import Testing
@testable import MCLCore

/// `DupeIndex` (reference-counted dupe index): after every step of seeded insert/update/delete/bulk/wipe sequences
/// the incrementally kept index equals the index rebuilt from the logbook, and every `isDupe` answer equals
/// `DupeChecker(existing: logbook)` — what Kotlin rebuilds after each edit and delete.
@Suite struct DupeIndexTests {

    /// Deterministic generator (SplitMix64).
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }
    }

    static let prefixes = ["OK1", "ok2", "Dl1", "w1", "G4", "ok1"]
    static let suffixes = ["ABC", "xoe", "Z", "AA"]
    static let decorations = ["", "/P", " ", "\t", "\u{00A0}", "\u{0001}"]
    static let freqs = [1_830_000, 3_520_000, 7_010_000, 14_025_000, 21_030_000, 0, 5_000]

    static func randomCall(_ rng: inout SplitMix) -> String {
        let prefix: String = prefixes[rng.below(prefixes.count)]
        let suffix: String = suffixes[rng.below(suffixes.count)]
        let deco: String = decorations[rng.below(decorations.count)]
        return prefix + suffix + deco
    }

    static func randomQso(_ rng: inout SplitMix, id: Int64) -> Qso {
        var q = Qso()
        q.id = id
        q.call = rng.below(40) == 0 ? "" : randomCall(&rng)
        q.freqHz = freqs[rng.below(freqs.count)]
        q.mode = rng.below(2) == 0 ? .cw : .ssb
        q.exchangeRcvd = String(rng.below(40))
        return q
    }

    /// The logbook model of one sequence: the rows, the incremental state and the next id.
    struct Model {
        var rows: [Qso] = []
        var mutations = LogbookMutations(existing: [])
        var nextId: Int64 = 1
    }

    /// One random step, applied to the rows and — as `Change`s — to the index.
    static func step(_ m: inout Model, _ rng: inout SplitMix) {
        let roll: Int = rng.below(1_000)
        if m.rows.isEmpty || (roll < 330 && m.rows.count < 250) {
            let q = randomQso(&rng, id: m.nextId)
            m.nextId += 1
            m.rows.append(q)
            m.mutations.didInsert(q)
            return
        }
        let i: Int = rng.below(m.rows.count)
        let old: Qso = m.rows[i]
        var changes: [LogbookMutations.Change] = []
        switch roll {
        case 0..<470: // edit of a cell: call, band (frequency), mode or a text column
            var new: Qso = old
            switch rng.below(5) {
            case 0: new = LogTableEdit.apply(column: .call, text: randomCall(&rng), to: old)
            case 1: new.freqHz = freqs[rng.below(freqs.count)]
            case 2: new = LogTableEdit.pickMode(rng.below(2) == 0 ? .cw : .ft8, to: old)
            case 3: new = LogTableEdit.apply(column: .call, text: rng.below(2) == 0 ? "" : " ", to: old)
            default: new = LogTableEdit.apply(column: .exchange, text: "15", to: old)
            }
            m.rows[i] = new
            changes = [.updated(old: old, new: new)]
        case 470..<560: // X-QSO toggle (stays in the dupe index, as in Kotlin)
            let new: Qso = LogTableEdit.toggleXqso(old).qso
            m.rows[i] = new
            changes = [.updated(old: old, new: new)]
        case 560..<620: // cluster-style tombstone (deleted flag set by an update)
            var new: Qso = old
            new.deleted = !old.deleted
            m.rows[i] = new
            changes = [.updated(old: old, new: new)]
        case 620..<800: // delete one row
            m.rows.remove(at: i)
            changes = [.deleted(old)]
        case 800..<880: // bulk: frequency or X-QSO over a random selection
            let picked: [Int] = Array(Set((0..<(1 + rng.below(6))).map { _ in rng.below(m.rows.count) })).sorted()
            let chosen: [Qso] = picked.map { m.rows[$0] }
            let action: BulkAction = rng.below(2) == 0 ? .frequency : .xqso
            let text: String = ["7010", "14025.5", "3520"][rng.below(3)]
            let outcome = action.run(text: text, on: chosen)
            for (index, edit) in zip(picked, outcome.edits) {
                m.rows[index] = edit.new
                changes.append(.updated(old: edit.old, new: edit.new))
            }
        case 880..<960: // county line: the same contact logged again (copies share call and band)
            var copy: Qso = old
            copy.id = m.nextId
            m.nextId += 1
            copy.exchangeRcvd = "C" + String(rng.below(9))
            m.rows.append(copy)
            changes = [.inserted(copy)]
        case 960..<995: // delete several rows at once
            let picked: Set<Int> = Set((0..<(1 + rng.below(8))).map { _ in rng.below(m.rows.count) })
            for index in picked.sorted(by: >) {
                changes.append(.deleted(m.rows.remove(at: index)))
            }
        default: // wipe: every row deleted
            changes = m.rows.map { LogbookMutations.Change.deleted($0) }
            m.rows.removeAll()
        }
        m.mutations.apply(changes)
    }

    static func expectEqualToRebuild(_ m: Model, _ rng: inout SplitMix, queries: Int) {
        let rebuilt = DupeIndex(existing: m.rows)
        #expect(m.mutations.dupes == rebuilt)
        let checker = DupeChecker(existing: m.rows)
        for _ in 0..<queries {
            let call: String = rng.below(4) == 0 ? (m.rows.randomElement(using: &rng)?.call ?? "") : randomCall(&rng)
            let band: Band? = rng.below(8) == 0 ? nil : Band.from(frequencyHz: freqs[rng.below(freqs.count)])
            #expect(m.mutations.isDupe(call: call, band: band) == checker.isDupe(call: call, band: band))
        }
    }

    @Test(arguments: [UInt64(20_261_002), 7, 0xDEAD_BEEF])
    func indexEqualsRebuildAfterEveryStep(seed: UInt64) {
        var rng = SplitMix(state: seed)
        var model = Model()
        for _ in 0..<10_000 {
            Self.step(&model, &rng)
            Self.expectEqualToRebuild(model, &rng, queries: 6)
        }
    }

    @Test func removeKeepsAKeySharedByAnotherQso() {
        var a = Qso()
        a.call = "OK1ABC"
        a.freqHz = 14_025_000
        var b = a
        b.call = "ok1abc " // normalises to the same key
        var index = DupeIndex(existing: [a, b])
        index.remove(a)
        #expect(index.isDupe(call: "OK1ABC", band: .m20))
        index.remove(b)
        #expect(!index.isDupe(call: "OK1ABC", band: .m20))
        index.remove(b) // never below zero
        index.add(a)
        #expect(index == DupeIndex(existing: [a]))
    }

    @Test func ignoredQsosAreNeitherAddedNorRemoved() {
        var kept = Qso()
        kept.call = "DL1AA"
        kept.freqHz = 7_010_000
        var tombstone = kept
        tombstone.deleted = true
        var noBand = kept
        noBand.band = nil
        var noCall = kept
        noCall.call = ""
        var index = DupeIndex(existing: [kept])
        index.remove(tombstone)
        index.remove(noBand)
        index.remove(noCall)
        #expect(index.isDupe(call: "DL1AA", band: .m40))
        index.replace(old: kept, new: tombstone) // a cluster delete
        #expect(!index.isDupe(call: "DL1AA", band: .m40))
        #expect(index == DupeIndex(existing: []))
    }
}
