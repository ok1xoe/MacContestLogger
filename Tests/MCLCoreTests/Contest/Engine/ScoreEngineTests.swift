import Foundation
import Testing
@testable import MCLCore

/// `ScoreEngine` and `ScoreState` — there are no Java tests, a table measured by the probe
/// a maintainer-only probe (JDK 21.0.2): formula variables
/// (`qsoPoints`, `bonusPoints`, `qtcPoints`, `qsoCount`, `multTotal`, `mult.<id>`), band weights,
/// duplicate and `null` binding ids, `int` wraparound of counts and `(long)` saturation of the total
/// and `scoring.total` of all 22 definitions from `contest-data`.
///
/// The tracker is a test replacement with the same counts as the Java `MultiplierTracker`
/// (`distinctForBinding` = sum of scope sizes, `weightedForBinding` = size × the weight
/// of the band before `|` looked up by UTF-16, `nil` weight = 1, `totalDistinct` = sum over all
/// tracker bindings). It keeps scopes and keys as Swift `String` (canonical equality) — the table
/// has no canonically equal keys; the match by UTF-16 is verified there by the real tracker. The same table
/// with the real `MultiplierTracker` is run by `MultiplierTrackerTests`.
@Suite struct ScoreEngineTests {

    /// A replacement for the Java `MultiplierTracker` filled from the probe's "binding|scope|key;…".
    struct FakeTracker: MultiplierCounts {
        /// binding (by UTF-16 like a Java `HashMap`) → scope → keys; adding again changes
        /// nothing, like the counter in Java.
        var counts: [[UInt16]?: [String: Set<String>]] = [:]

        init(_ adds: String) {
            for add in adds.split(separator: ";") {
                let parts = add.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                let binding: [UInt16]? = parts[0] == "~" ? nil : Array(parts[0].utf16)
                let scope = parts[1..<(parts.count - 1)].joined(separator: "|")
                counts[binding, default: [:]][scope, default: []].insert(parts[parts.count - 1])
            }
        }

        func distinctForBinding(_ bindingId: String?) -> Int32 {
            var total: Int32 = 0
            for keys in (counts[bindingId.map { Array($0.utf16) }] ?? [:]).values {
                total = JavaMath.addInt(total, Int32(keys.count))
            }
            return total
        }

        func weightedForBinding(_ bindingId: String?, _ bandWeights: YamlOrderedMap<Int>) -> Int32 {
            var total: Int32 = 0
            for (scope, keys) in counts[bindingId.map { Array($0.utf16) }] ?? [:] {
                let band = Array(scope.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0].utf16)
                // band looked up by UTF-16; `nil` weight (Java NPE) = 1 like the real tracker
                let weight = bandWeights.pairs.first { Array($0.key.utf16) == band }?.value ?? 1
                total = JavaMath.addInt(total, JavaMath.multiplyInt(Int32(keys.count),
                                                                     Int32(truncatingIfNeeded: weight)))
            }
            return total
        }

        func totalDistinct() -> Int32 {
            var total: Int32 = 0
            for scopes in counts.values {
                for keys in scopes.values {
                    total = JavaMath.addInt(total, Int32(keys.count))
                }
            }
            return total
        }
    }

    /// Probe inputs (`ProbeScore.INPUTS`): qsoPoints, bonusPoints, qtcPoints, qsoCount.
    static let inputs: [(Int64, Int64, Int64, Int32)] = [
        (0, 0, 0, 0),
        (1234, 50, 17, 321),
        (Int64.max, 0, 0, Int32.max),
        (-5000, -7, 3, -1),
        (9_007_199_254_740_993, 1, 0, 1),
    ]

    static func adds(_ name: String) throws -> String {
        try #require(ScoreMeasured.adds.first { $0.0 == name }?.1, "missing tracker for case \(name)")
    }

    static func outcome(_ state: ScoreState) -> ScoreMeasured.Outcome {
        let groups = state.multByGroup.entries.map { ScoreMeasured.Group($0.key, $0.value ?? 0) }
        return .state(state.qsoCount, state.qsoPoints, state.multTotal, groups,
                      state.bonusPoints, state.qtcPoints, state.total)
    }

    static func compute(_ definition: ContestDefinition, _ input: Int,
                        _ tracker: some MultiplierCounts) -> ScoreMeasured.Outcome {
        let (qso, bonus, qtc, count) = inputs[input]
        do {
            return outcome(try ScoreEngine.compute(definition, qsoPoints: qso, bonusPoints: bonus,
                                                   qtcPoints: qtc, qsoCount: count, tracker: tracker))
        } catch {
            return .error(error.kind, error.message)
        }
    }

    /// Cases where Java fails with an NPE (`multipliers: [~, …]`): Swift skips the `nil` binding
    /// ("`nil` binding in the score"). Counts do not depend on the input.
    static let lenientScores: [String: (multTotal: Int32, groups: [ScoreMeasured.Group], total: Int64)] = [
        "multipliers-nil": (1, [], 1),
        "multipliers-nil-mixed": (2, [.init("a", 1), .init("b", 1)], 21),
    ]

    @Test(arguments: ScoreMeasured.scores)
    func scoreMatchesJava(_ row: ScoreMeasured.StateRow) throws {
        let definition = try PointsCalculatorTests.definition(row.name)
        let swift = Self.compute(definition, row.input, FakeTracker(try Self.adds(row.name)))
        if row.java == .npe {
            let lenient = try #require(Self.lenientScores[row.name], "NPE row without a pinned value")
            let (qso, bonus, qtc, count) = Self.inputs[row.input]
            #expect(swift == .state(count, qso, lenient.multTotal, lenient.groups, bonus, qtc, lenient.total))
        } else {
            #expect(swift == row.java)
        }
    }

    /// `scoring.total` of all 22 definitions is measured and Swift loads it the same; each definition
    /// has rows for all inputs.
    @Test func everyContestTotalIsMeasured() throws {
        let directory = try PointsCalculatorTests.contestsDirectory()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".yaml") }
        #expect(files.count == 22)
        #expect(Set(ScoreMeasured.totals.map(\.0)) == Set(files))
        for (file, total) in ScoreMeasured.totals {
            let definition = try ContestDefinitionLoader.loadFile(directory.appendingPathComponent(file))
            #expect(definition.scoring?.total == total, "\(file)")
            let inputs = ScoreMeasured.scores.filter { $0.name == "@" + file }.map(\.input)
            #expect(inputs == Array(Self.inputs.indices), "\(file)")
        }
    }

    // MARK: - nil elements (pinned outside the table)

    private static func definition(_ bindings: [ContestDefinition.MultiplierBinding?]?,
                                   total: String?) -> ContestDefinition {
        ContestDefinition(id: "t", scoring: .init(qsoPoints: nil, bonuses: nil, total: total),
                          multipliers: bindings)
    }

    private static func binding(_ id: String?, weights: [(String, Int?)]? = nil) -> ContestDefinition.MultiplierBinding {
        var map: YamlOrderedMap<Int>?
        if let weights {
            var out = YamlOrderedMap<Int>()
            for (band, weight) in weights {
                out.set(band, weight)
            }
            map = out
        }
        return .init(id: id, set: "s", from: "callsign", scope: .PER_BAND, label: nil, appliesWhen: nil,
                     bandWeights: map)
    }

    /// Weighted counts over 2³¹ wrap like a Java `int` (two bindings at Int32.max → −2)
    /// and the total over 2⁶³ saturates like `(long)` — nothing crashes.
    @Test func largeScoreWrapsAndSaturatesLikeJava() throws {
        let weights: [(String, Int?)] = [("80m", Int(Int32.max))]
        let definition = Self.definition([Self.binding("a", weights: weights), Self.binding("b", weights: weights)],
                                         total: "qsoPoints * multTotal")
        let state = try ScoreEngine.compute(definition, qsoPoints: 3, bonusPoints: 0, qtcPoints: 0, qsoCount: 1,
                                            tracker: FakeTracker("a|80m|A;b|80m|B"))
        #expect(state.multTotal == -2)
        #expect(state.total == -6)
        let huge = try ScoreEngine.compute(Self.definition([Self.binding("a")], total: "qsoPoints * 1000"),
                                           qsoPoints: Int64.max, bonusPoints: 0, qtcPoints: 0, qsoCount: 1,
                                           tracker: FakeTracker("a|20m|A"))
        #expect(huge.total == Int64.max)
        let negative = try ScoreEngine.compute(Self.definition(nil, total: "qsoPoints * 1000"),
                                               qsoPoints: Int64.min, bonusPoints: 0, qtcPoints: 0, qsoCount: 1,
                                               tracker: FakeTracker(""))
        #expect(negative.total == Int64.min)
    }

    /// A `null` element of `multipliers`: Java NPE, Swift skips it (a deliberate divergence from Java v1.1.1).
    @Test func nilBindingIsSkipped() throws {
        let definition = Self.definition([nil, Self.binding("a"), nil], total: "multTotal * 10 + mult.a")
        let state = try ScoreEngine.compute(definition, qsoPoints: 0, bonusPoints: 0, qtcPoints: 0, qsoCount: 0,
                                            tracker: FakeTracker("a|20m|K;a|40m|K;zz|*|Q"))
        #expect(state.multByGroup.entries.map(\.key) == ["a"])
        #expect(state.multTotal == 3)
        #expect(state.total == 32)
    }

    /// `mult.<id>` is built with a Java `put` by UTF-16: the ids `K` and KELVIN SIGN (U+212A) are two
    /// groups and two variables (a Swift dictionary would merge them canonically).
    @Test func groupKeysCompareByUtf16() throws {
        let definition = Self.definition([Self.binding("K"), Self.binding("\u{212A}")],
                                         total: "mult.K * 10 + mult.\u{212A}")
        let state = try ScoreEngine.compute(definition, qsoPoints: 0, bonusPoints: 0, qtcPoints: 0, qsoCount: 0,
                                            tracker: FakeTracker("K|20m|A;K|40m|A"))
        #expect(state.multByGroup.count == 2)
        #expect(state.total == 20)
    }
}
