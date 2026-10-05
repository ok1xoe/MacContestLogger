/// Evaluation of operating rules for the chosen category. The rules differ by category for off-time
/// and band changes — in CQ WPX the ten-minute rule applies
/// to Multi-Single but not to Single-Op — so a flat notation is not enough.
///
/// The **first matching rule** is taken; a rule without conditions applies to
/// all. When none matches, the flat values written directly
/// in `operating` are used. Mirrors Java `contest.engine.OperatingRules` (a stateless
/// utility, hence a caseless enum). Only `resolve` is ported here; the rest of the
/// `contest/engine/` package lives elsewhere. The `OperatingGuard` type is a different concept
/// (guarding while writing a QSO), hence it is not shared.
public enum OperatingRules {

    /// Returns the rules valid for the given category, already without the conditional part.
    ///
    /// - Parameter category: category dimensions (OPERATOR, TRANSMITTER…) to the chosen
    ///   values; `nil` or an empty map means no category is chosen
    ///   and the conditional rules do not apply.
    public static func resolve(_ operating: ContestDefinition.Operating?,
                               _ category: [String: String]?) -> ContestDefinition.Operating? {
        guard let operating else { return nil }
        if let rules = operating.rules {
            // A `nil` element (`rules: [~]`): Java crashes here with an NPE, Swift skips it — a deliberate
            // divergence from Java v1.1.1 (`OperatingRules.resolve`).
            for case let rule? in rules where matches(rule.when, category) {
                return ContestDefinition.Operating(
                    offTime: rule.offTime, bandChange: rule.bandChange, rules: nil)
            }
        }
        return ContestDefinition.Operating(
            offTime: operating.offTime, bandChange: operating.bandChange, rules: nil)
    }

    /// A rule applies when all its conditions match; without conditions it always applies.
    private static func matches(_ when: YamlOrderedMap<String>?, _ category: [String: String]?) -> Bool {
        guard let when, !when.isEmpty else { return true }
        guard let category, !category.isEmpty else { return false }
        return when.pairs.allSatisfy { pair in
            guard let actual = category[pair.key] else { return false }
            // `when: {OPERATOR: ~}`: Java fails with an NPE on `getValue().trim()`, here the rule does not match
            // (a recorded divergence).
            guard let expected = pair.value else { return false }
            return JavaChar.equalsIgnoreCase(JavaText.trim(actual), JavaText.trim(expected))
        }
    }
}
