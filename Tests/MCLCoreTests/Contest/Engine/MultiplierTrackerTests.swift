import Foundation
import Testing
@testable import MCLCore

/// `MultiplierTracker` — there is no Java test for it. The counter, `null` keys, UTF-16 keys and the ordering of
/// `keysForBinding` are measured in the `tracker` scenario of the `MultiplierMeasured` table; here is
/// the score table (`ScoreMeasured`, probe `ProbeScore.java`) run with the **real**
/// tracker instead of the test replacement, and the policy for a `nil` band weight.
@Suite struct MultiplierTrackerTests {

    /// A tracker filled from the probe's "binding|scope|key;…" of `ProbeScore` (binding `~` = null).
    static func tracker(_ adds: String) -> MultiplierTracker {
        var tracker = MultiplierTracker()
        for add in adds.split(separator: ";") {
            let parts = add.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let binding: String? = parts[0] == "~" ? nil : parts[0]
            let scope = parts[1..<(parts.count - 1)].joined(separator: "|")
            tracker.add(binding, scope, parts[parts.count - 1])
        }
        return tracker
    }

    /// The whole score table with the real tracker: band weights, duplicate and `null` ids,
    /// `int` wraparound. Rows where Java fails have a pinned value
    /// in `ScoreEngineTests.lenientScores`.
    @Test(arguments: ScoreMeasured.scores)
    func scoreTableMatchesJavaWithRealTracker(_ row: ScoreMeasured.StateRow) throws {
        let definition = try PointsCalculatorTests.definition(row.name)
        let swift = ScoreEngineTests.compute(definition, row.input, Self.tracker(try ScoreEngineTests.adds(row.name)))
        if row.java == .npe {
            let lenient = try #require(ScoreEngineTests.lenientScores[row.name], "NPE row without a pinned value")
            let (qso, bonus, qtc, count) = ScoreEngineTests.inputs[row.input]
            #expect(swift == .state(count, qso, lenient.multTotal, lenient.groups, bonus, qtc, lenient.total))
        } else {
            #expect(swift == row.java)
        }
    }

    private static func weights(_ pairs: [(String, Int?)]) -> YamlOrderedMap<Int> {
        var map = YamlOrderedMap<Int>()
        for (band, weight) in pairs {
            map.set(band, weight)
        }
        return map
    }

    /// `bandWeights: {80m: ~}` with a multiplier on 80m: Java NPE (unboxing a `null` from `getOrDefault`);
    /// Swift takes weight 1 like a band without a weight (a deliberate divergence from Java v1.1.1). An unused `nil`
    /// weight does not bother Java either (`weighted-null-weight-unused`).
    @Test func nilBandWeightCountsAsOne() {
        let tracker = Self.tracker("w|80m|A;w|80m|B;w|40m|A;w|20m|C")
        #expect(tracker.weightedForBinding("w", Self.weights([("80m", nil), ("40m", 3)])) == 2 + 3 + 1)
    }

    /// The band is the part of the scope before the **first** `|` by UTF-16 units: a `|` followed by a combining character
    /// is a different character for a Swift `Character`, for Java still a separator.
    @Test func bandIsPrefixBeforeFirstPipeByUtf16() {
        let tracker = Self.tracker("w|80m|\u{301}CW|A;w|80m|SSB|x|B")
        #expect(tracker.weightedForBinding("w", Self.weights([("80m", 4)])) == 8)
    }

    /// Weights are looked up by UTF-16: the band `A`+U+030A does not get the weight of the key U+00C5 (Java `HashMap`).
    @Test func bandWeightLookupIsUtf16() {
        let tracker = Self.tracker("w|A\u{30A}|X;w|\u{C5}|Y")
        #expect(tracker.weightedForBinding("w", Self.weights([("\u{C5}", 3)])) == 1 + 3)
    }

    /// A `nil` key in the grid of a non-enumerated set: Java `Collections.sort` fails with an NPE as soon as
    /// there are at least two keys; Swift sorts `nil` first ("`nil` tracker
    /// key in the grid"). Java does not sort a single `nil` key, so there they agree.
    @Test func nilKeySortsFirstWhereJavaThrows() {
        var tracker = MultiplierTracker()
        tracker.add("b", "20m", "B")
        tracker.add("b", "40m", nil)
        tracker.add("b", "40m", "A")
        #expect(tracker.keysForBinding("b") == [nil, "A", "B"])
        var single = MultiplierTracker()
        single.add("b", "*", nil)
        #expect(single.keysForBinding("b") == [nil])
    }

    /// Counter: a key lives while its count is > 0; empty scopes contribute zero.
    @Test func counterKeepsKeyUntilLastRemove() {
        var tracker = MultiplierTracker()
        let created = tracker.add("b", "20m", "K")
        let createdAgain = tracker.add("b", "20m", "K")
        let removedFromTwo = tracker.remove("b", "20m", "K")
        #expect(created && !createdAgain && !removedFromTwo)
        #expect(tracker.isWorked("b", "20m", "K"))
        let removedLast = tracker.remove("b", "20m", "K")
        #expect(removedLast)
        #expect(!tracker.isWorked("b", "20m", "K"))
        #expect(tracker.distinctForBinding("b") == 0)
        #expect(tracker.keysForBinding("b").isEmpty)
        tracker.add("c", "*", "Q")
        tracker.reset()
        #expect(tracker.totalDistinct() == 0)
    }

    /// Value semantics: a copy of the tracker (handing the session to another thread, a preview) is
    /// not changed by writing to the original.
    @Test func trackerIsAValue() {
        var original = MultiplierTracker()
        original.add("b", "*", "K")
        let copy = original
        original.add("b", "*", "L")
        #expect(copy.distinctForBinding("b") == 1)
        #expect(original.distinctForBinding("b") == 2)
    }
}
