/// Evaluates a `Condition` over a `QsoContext`. Port of Java `engine/ConditionEvaluator.java`.
///
/// Several filled-in predicates in one condition = their AND in Java order (`allOf`,
/// `anyOf`, `not`, then the predicates up to `expr`); the first unmet one ends it, so an expression
/// error shows only if it is reached. An empty condition and `nil` = true.
///
/// Java `null` semantics are copied (baseline 5.3): an `allOf: [~]` element is true,
/// `anyOf: [~, …]` is thereby satisfied, `anyOf: []` is ignored, `dxccIn`/`bandIn: [~]` match
/// only a `nil` value, `fieldEquals.value: ~` does not match. Texts are compared by UTF-16
/// (`continentIs`, `workedClass`, `dxccIn`, `bandIn` are case-sensitive, `mode`
/// and `fieldEquals` are not). An expression error (`ExpressionError`) propagates as in Java.
///
/// Recursion over the levels of `not`/`allOf`/`anyOf` has no limit of its own (Java has none either):
/// at most 13 levels come from a definition, the YAML reader allows no more (`YamlParser.maxNestingDepth`).
/// The recursive function holds only the combinators, the predicates and the expression are in a separate function,
/// so the frame of one level stays small even in a debug build (an expression at the limit takes ~340 KB
/// of the 512 KB thread; guarded by `ConditionEvaluatorTests`).
public enum ConditionEvaluator {

    public static func eval(_ condition: ContestDefinition.Condition?,
                            _ context: QsoContext) throws(ExpressionError) -> Bool {
        guard let condition else { return true }
        if let allOf = condition.allOf {
            for sub in allOf {
                if try !eval(sub, context) {
                    return false
                }
            }
        }
        if let anyOf = condition.anyOf, !anyOf.isEmpty {
            var any = false
            for sub in anyOf {
                if try eval(sub, context) {
                    any = true
                    break
                }
            }
            if !any {
                return false
            }
        }
        if let not = condition.not, try eval(not, context) {
            return false
        }
        return try predicates(condition, context)
    }

    /// Predicates of one condition (without combinators), in Java order.
    @inline(never)
    private static func predicates(_ c: ContestDefinition.Condition,
                                   _ ctx: QsoContext) throws(ExpressionError) -> Bool {
        // ownDxcc and sameDxcc both compare with ctx.ownDxcc (an alias in Java).
        if let wanted = c.ownDxcc, wanted != ctx.ownDxcc {
            return false
        }
        if let wanted = c.sameDxcc, wanted != ctx.ownDxcc {
            return false
        }
        if let wanted = c.sameContinent, wanted != ctx.sameContinent {
            return false
        }
        if let wanted = c.otherContinent, wanted != ctx.otherContinent {
            return false
        }
        if let wanted = c.continentIs, !JavaText.equals(wanted, ctx.workedContinent) {
            return false
        }
        if let wanted = c.ownContinentIs, !JavaText.equals(wanted, ctx.ownContinent) {
            return false
        }
        if let wanted = c.workedClass, !JavaText.equals(wanted, ctx.workedClass) {
            return false
        }
        if let list = c.dxccIn {
            guard let worked = ctx.workedEntity, contains(list, worked.countryCode) else {
                return false
            }
        }
        if let list = c.bandIn, !contains(list, ctx.band) {
            return false
        }
        if let wanted = c.mode, !JavaChar.equalsIgnoreCase(wanted, ctx.mode) {
            return false
        }
        if let fieldEquals = c.fieldEquals {
            guard let value = ctx.fieldCanonical(fieldEquals.field),
                  JavaChar.equalsIgnoreCase(value, fieldEquals.value) else {
                return false
            }
        }
        if let id = c.fieldPresent, !ctx.fieldPresent(id) {
            return false
        }
        if let wanted = c.bonusStation, wanted != ctx.bonusStation {
            return false
        }
        // NaN == 0 is false → NaN satisfies the condition (as in Java).
        if let expr = c.expr, try Expression.eval(expr, ctx.expressionVariables) == 0 {
            return false
        }
        return true
    }

    /// Java `List.contains(o)`: `nil` looks for a `nil` element, otherwise `o.equals(element)` by UTF-16.
    private static func contains(_ list: [String?], _ value: String?) -> Bool {
        guard let value else {
            return list.contains { $0 == nil }
        }
        return list.contains { JavaText.equals(value, $0) }
    }
}
