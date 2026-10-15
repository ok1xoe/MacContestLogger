/// Multiplier counts that `ScoreEngine` reads from the tracker. The Java `ScoreEngine` takes the
/// `MultiplierTracker` directly; that implements this protocol (here only the
/// three methods the score needs). Return types are Java `int` (wrapping).
public protocol MultiplierCounts {
    /// Number of distinct keys across the scopes of one binding.
    func distinctForBinding(_ bindingId: String?) -> Int32
    /// Count with band weight (band = scope key before the first `|`, without a weight 1).
    func weightedForBinding(_ bindingId: String?, _ bandWeights: YamlOrderedMap<Int>) -> Int32
    /// Sum of distinct over **all** bindings of the tracker (even those the definition does not have).
    func totalDistinct() -> Int32
}

/// Final score from aggregates by the declarative formula `scoring.total`. Port of Java
/// `engine/ScoreEngine.java`: multiplication and composite formulas live in the formula, hence it is
/// evaluated from the aggregates (incrementally O(1)).
///
/// Java behaviour is copied: a duplicate binding id in a group is **summed** (`merge`),
/// `multTotal` without weights is the tracker's `totalDistinct()` (each binding once), with weights the sum of
/// groups; a `nil` id gives the variable literally `mult.null`. Counts are `int` (wrapping), the total
/// `(long) double` (saturation, NaN → 0). A missing `scoring`/`total` → 0. An expression error propagates.
///
/// A `nil` element of `multipliers`: Java NPE, Swift skips it ("`nil` binding
/// in the score").
public enum ScoreEngine {

    /// The points and QSO count of one `scoring.parts` entry (same order as the definition's parts).
    public struct PartTally: Equatable, Sendable {
        public var qsoPoints: Int64 = 0
        public var qsoCount: Int32 = 0

        public init(qsoPoints: Int64 = 0, qsoCount: Int32 = 0) {
            self.qsoPoints = qsoPoints
            self.qsoCount = qsoCount
        }
    }

    public static func compute(_ definition: ContestDefinition, qsoPoints: Int64, bonusPoints: Int64,
                               qtcPoints: Int64, qsoCount: Int32, powerCategory: String? = nil,
                               partTallies: [PartTally] = [],
                               tracker: some MultiplierCounts) throws(ExpressionError) -> ScoreState {
        var byGroup = JavaLinkedMap<Int32>()
        var weighted = false
        for case let binding? in definition.multipliers ?? [] {
            let n: Int32
            if let weights = binding.bandWeights, !weights.isEmpty {
                n = tracker.weightedForBinding(binding.id, weights)
                weighted = true
            } else {
                n = tracker.distinctForBinding(binding.id)
            }
            byGroup.put(binding.id, JavaMath.addInt(byGroup[binding.id] ?? 0, n))
        }
        var multTotal: Int32
        if weighted {
            // With band weights (WAE) the total count is the sum of weighted groups.
            multTotal = 0
            for entry in byGroup.entries {
                multTotal = JavaMath.addInt(multTotal, entry.value ?? 0)
            }
        } else {
            multTotal = tracker.totalDistinct()
        }

        var variables = JavaLinkedMap<ExpressionValue>()
        variables.put("qsoPoints", .number(Double(qsoPoints)))
        variables.put("bonusPoints", .number(Double(bonusPoints)))
        variables.put("qtcPoints", .number(Double(qtcPoints)))
        variables.put("qsoCount", .number(Double(qsoCount)))
        variables.put("multTotal", .number(Double(multTotal)))
        for entry in byGroup.entries {
            // Java "mult." + id: id null → the text "null".
            variables.put("mult." + (entry.key ?? "null"), .number(Double(entry.value ?? 0)))
        }

        let parts: [ScoreState.PartScore] = try partScores(definition, variables, byGroup, partTallies, powerCategory)
        var total: Int64
        if parts.isEmpty {
            total = JavaMath.d2l(try Expression.eval(definition.scoring?.total, variables))
        } else {
            // A combined contest (scoring.parts): the sum of the parts, `total` is only the older versions' fallback.
            total = parts.reduce(Int64(0)) { JavaMath.addLong($0, $1.total) }
        }
        if let scoring = definition.scoring, scoring.powerFactor != nil {
            // N1MM PowerMult: the score times the factor of the chosen power category.
            total = total.multipliedReportingOverflow(by: Int64(scoring.powerFactorFor(powerCategory))).partialValue
        }
        return ScoreState(qsoCount: qsoCount, qsoPoints: qsoPoints, multTotal: multTotal, multByGroup: byGroup,
                          bonusPoints: bonusPoints, qtcPoints: qtcPoints, total: total, parts: parts)
    }

    /// The scores of `scoring.parts`: each part's formula over its own points, QSO count and multipliers.
    private static func partScores(_ definition: ContestDefinition, _ shared: JavaLinkedMap<ExpressionValue>,
                                   _ byGroup: JavaLinkedMap<Int32>, _ tallies: [PartTally],
                                   _ powerCategory: String?) throws(ExpressionError) -> [ScoreState.PartScore] {
        guard let scoring = definition.scoring else { return [] }
        var out: [ScoreState.PartScore] = []
        for (index, part) in scoring.scoredParts.enumerated() {
            let tally: PartTally = index < tallies.count ? tallies[index] : PartTally()
            var mults: Int32 = 0
            for case let id? in part.multipliers ?? [] {
                mults = JavaMath.addInt(mults, byGroup[id] ?? 0)
            }
            var variables = shared
            variables.put("qsoPoints", .number(Double(tally.qsoPoints)))
            variables.put("qsoCount", .number(Double(tally.qsoCount)))
            variables.put("multTotal", .number(Double(mults)))
            var total = JavaMath.d2l(try Expression.eval(part.formula, variables))
            if part.powerFactor != nil {
                let factor = Int64(ContestDefinition.Scoring.factor(part.powerFactor, powerCategory))
                total = total.multipliedReportingOverflow(by: factor).partialValue
            }
            let label: String = part.label.flatMap { JavaText.isBlank($0) ? nil : $0 } ?? part.id ?? "?"
            out.append(ScoreState.PartScore(id: part.id, label: label, qsoCount: tally.qsoCount,
                                            qsoPoints: tally.qsoPoints, multTotal: mults, total: total))
        }
        return out
    }
}
