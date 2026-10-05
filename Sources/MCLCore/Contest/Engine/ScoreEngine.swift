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

    public static func compute(_ definition: ContestDefinition, qsoPoints: Int64, bonusPoints: Int64,
                               qtcPoints: Int64, qsoCount: Int32,
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

        let total = JavaMath.d2l(try Expression.eval(definition.scoring?.total, variables))
        return ScoreState(qsoCount: qsoCount, qsoPoints: qsoPoints, multTotal: multTotal, multByGroup: byGroup,
                          bonusPoints: bonusPoints, qtcPoints: qtcPoints, total: total)
    }
}
