import Foundation
import Testing
@testable import MCLCore

/// `QsoMarksTracker`: after every append the marks equal `QsoMarks.compute` over the whole logbook, for seeded logs of
/// all 22 contest definitions (dupes, X-QSOs, QSOs without a band or callsign, modes and bands the contest does not
/// count, equal times); an append that does not extend the replay at its end returns `false` and changes nothing.
@Suite struct QsoMarksTrackerTests {

    static let files: [String] = [
        "arrl-dx-cw.yaml", "arrl-dx-ssb.yaml", "cq-160-cw.yaml", "cq-160-ssb.yaml", "cq-wpx-cw.yaml",
        "cq-wpx-rtty.yaml", "cq-wpx-ssb.yaml", "cq-ww-cw.yaml", "cq-ww-rtty.yaml", "cq-ww-ssb.yaml", "dx.yaml",
        "iaru-hf.yaml", "iaru-r1-uhf.yaml", "iaru-r1-vhf.yaml", "marconi-memorial.yaml", "ok-om-dx-cw.yaml",
        "ok-om-dx-ssb.yaml", "rdxc.yaml", "sp-dx.yaml", "wae-cw.yaml", "wae-ssb.yaml", "ww-digi.yaml",
    ]

    static let calls = ["W1AW", "DL1ABC", "OK1XOE", "OK2ZZ", "JA1AA", "VK2XX", "SP9ABC", "G4AAA", "K1ABC", "OM3XX",
                        "UA9AA", "ZS6AA", "PY1AA", "ok1abc/p", ""]
    static let freqs = [1_830_000, 3_520_000, 7_010_000, 10_110_000, 14_025_000, 21_030_000, 28_020_000,
                        50_100_000, 144_100_000, 432_100_000, 0]
    static let exchanges = ["599 14", "59 5", "599 001", "599 15 OK", "599 JN79", "599 JO62QM 001", "5NN 100",
                            "599 OK1", "599 KA", "59 015 IL", "599 25", "", "599"]
    static let modes: [Mode] = [.cw, .cw, .ssb, .ssb, .rtty, .ft8]
    static let start = Date(timeIntervalSince1970: 1_795_867_200)
    static let fixedNow = Date(timeIntervalSince1970: 1_795_900_000)

    struct Fixture {
        let dxcc: DxccResolver
        let registry: MultiplierSetRegistry

        init() throws {
            dxcc = try SessionFixture.dxcc()
            registry = try SessionFixture.registry(dxcc)
        }

        func fresh(_ def: ContestDefinition) -> ContestSession {
            ContestSession(definition: def, dxcc: dxcc, registry: registry, myCall: "OK1XOE", myGrid: "JO70",
                           myItuZone: "28")
        }
    }

    static func randomQso(_ rng: inout DupeIndexTests.SplitMix, id: Int64, clock: inout Double) -> Qso {
        var q = Qso()
        q.id = id
        let advance: [Double] = [0, 0.5, 30, 61, 300]
        clock += advance[rng.below(advance.count)]
        q.timestampUtc = start.addingTimeInterval(clock)
        q.call = calls[rng.below(calls.count)]
        q.freqHz = freqs[rng.below(freqs.count)]
        q.mode = modes[rng.below(modes.count)]
        q.exchangeRcvd = exchanges[rng.below(exchanges.count)]
        q.exchangeSent = "599 15"
        q.serialRcvd = rng.below(3) == 0 ? nil : 1 + rng.below(300)
        q.xqso = rng.below(20) == 0
        return q
    }

    @Test(arguments: files)
    func appendsEqualAFullRecompute(file: String) throws {
        let fixture = try Fixture()
        let def = try SessionFixture.definition("@" + file)
        var rng = DupeIndexTests.SplitMix(state: file.utf8.reduce(UInt64(17)) { $0 &* 31 &+ UInt64($1) })
        let tracker = QsoMarksTracker(fresh: fixture.fresh(def))
        var log: [Qso] = []
        var clock: Double = 0
        for step in 0..<70 {
            let q = Self.randomQso(&rng, id: Int64(step + 1), clock: &clock)
            let accepted1: Bool = tracker.append(q, now: { Self.fixedNow })

            #expect(accepted1)
            log.append(q)
            let expected = QsoMarks.compute(fixture.fresh(def), log, now: { Self.fixedNow })
            #expect(tracker.marks == expected, "\(file) step \(step)")
        }
        #expect(!tracker.marks.isEmpty, "\(file): the seeded log is scored")
        let rebuilt = QsoMarksTracker.recomputed(fresh: fixture.fresh(def), qsos: log, now: { Self.fixedNow })
        #expect(rebuilt.marks == tracker.marks)
    }

    @Test func appendsThatNeedARecomputeChangeNothing() throws {
        let fixture = try Fixture()
        let def = try SessionFixture.definition("@cq-ww-cw.yaml")
        var rng = DupeIndexTests.SplitMix(state: 5)
        var clock: Double = 0
        var log: [Qso] = []
        for id in 1...20 {
            var q = Self.randomQso(&rng, id: Int64(id), clock: &clock)
            q.xqso = false
            log.append(q)
        }
        let tracker = QsoMarksTracker.recomputed(fresh: fixture.fresh(def), qsos: log, now: { Self.fixedNow })
        let before = tracker.marks
        #expect(before == QsoMarks.compute(fixture.fresh(def), log, now: { Self.fixedNow }))

        var earlier = log[5]
        earlier.id = 100
        let accepted2: Bool = tracker.append(earlier)

        #expect(!accepted2, "an earlier time sorts into the middle")
        var edit = log[19]
        edit.call = "ZS6AA"
        let accepted3: Bool = tracker.append(edit)

        #expect(!accepted3, "an id already seen is an edit")
        var tombstone = log[19]
        tombstone.id = 101
        tombstone.deleted = true
        tombstone.timestampUtc = Self.start.addingTimeInterval(clock + 10)
        let accepted4: Bool = tracker.append(tombstone)

        #expect(!accepted4, "a delete")
        var untimed = log[0]
        untimed.id = 102
        untimed.timestampUtc = nil
        let acceptedUntimed: Bool = tracker.append(untimed)
        #expect(!acceptedUntimed, "a QSO without a time is replayed last at \"now\"")
        #expect(tracker.marks == before)

        var next = log[0]
        next.id = 103
        next.timestampUtc = Self.start.addingTimeInterval(clock + 20)
        let accepted5: Bool = tracker.append(next, now: { Self.fixedNow })

        #expect(accepted5)
        log.append(next)
        #expect(tracker.marks == QsoMarks.compute(fixture.fresh(def), log, now: { Self.fixedNow }))
    }

    @Test func aRecomputedLogWithAnUntimedQsoAcceptsNoAppend() throws {
        let fixture = try Fixture()
        let def = try SessionFixture.definition("@cq-ww-cw.yaml")
        var untimed = QsoMarksTests.qso(1, 0, "W1AW", 14_025_000, "599 5")
        untimed.timestampUtc = nil
        let tracker = QsoMarksTracker.recomputed(fresh: fixture.fresh(def), qsos: [untimed], now: { Self.fixedNow })
        let later = QsoMarksTests.qso(2, 1, "DL1ABC", 14_025_000, "599 14")
        let accepted6: Bool = tracker.append(later)

        #expect(!accepted6)
    }

    @Test func anXqsoAppendIsNotMarkedButAcceptsLaterAppends() throws {
        let fixture = try Fixture()
        let def = try SessionFixture.definition("@cq-ww-ssb.yaml")
        let tracker = QsoMarksTracker(fresh: fixture.fresh(def))
        var x = QsoMarksTests.qso(1, 5, "W1AW", 14_200_000, "59 5")
        x.xqso = true
        let accepted7: Bool = tracker.append(x)

        #expect(accepted7)
        #expect(tracker.marks.isEmpty)
        let earlier = QsoMarksTests.qso(2, 0, "W1AW", 14_200_000, "59 5")
        let accepted8: Bool = tracker.append(earlier)

        #expect(accepted8, "an X-QSO is not in the replay, so it does not set the order")
        #expect(tracker.marks == QsoMarks.compute(fixture.fresh(def), [x, earlier]))
    }
}
