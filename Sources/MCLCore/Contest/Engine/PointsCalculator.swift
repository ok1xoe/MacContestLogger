/// Points for one QSO by `scoring.qsoPoints` (`FIRST_MATCH`/`SUM`). Port of Java
/// `engine/PointsCalculator.java`; a pure function over `QsoContext`.
///
/// The Java domains are kept explicitly: points are `int` (`Int32`) — the `SUM` total **wraps around**
/// past 2³¹ (2e9 + 2e9 → −294967296), an expression is clipped by `(int)` (saturation, NaN → 0, truncation
/// toward zero), `perKm` computes in `long` and the result takes the **low 32 bits** (`(int) long`).
/// An expression or condition error (`ExpressionError`) propagates as in Java.
///
/// A `nil` element of `qsoPoints.rules`: Java fails on it with an NPE (only if it is reached — `FIRST_MATCH`
/// does not read further after a match); Swift skips it ("`nil` points rule").
public enum PointsCalculator {

    public static func points(_ definition: ContestDefinition,
                              _ context: QsoContext) throws(ExpressionError) -> Int32 {
        guard let qsoPoints = definition.scoring?.qsoPoints else {
            return 0
        }
        let defaultValue = Int32(truncatingIfNeeded: qsoPoints.defaultValue)
        guard let rules = qsoPoints.rules else {
            return defaultValue
        }
        if qsoPoints.mode == .SUM {
            var sum: Int32 = 0
            var any = false
            for case let rule? in rules {
                if try ConditionEvaluator.eval(rule.when, context) {
                    sum = JavaMath.addInt(sum, try value(rule.value, context))
                    any = true
                }
            }
            return any ? sum : defaultValue
        }
        // FIRST_MATCH (also `mode` nil)
        for case let rule? in rules {
            if try ConditionEvaluator.eval(rule.when, context) {
                return try value(rule.value, context)
            }
        }
        return defaultValue
    }

    /// Points value (fixed / expression / per km) — shared by the QSO points calculation and the bonuses.
    /// Priority `fixed` > `expr` > `perKm`; none of them (also `nil`) → 0.
    public static func value(_ pointValue: ContestDefinition.PointValue?,
                             _ context: QsoContext) throws(ExpressionError) -> Int32 {
        guard let pointValue else {
            return 0
        }
        if let fixed = pointValue.fixed {
            // Java `Integer`; from YAML it always arrives in int range.
            return Int32(truncatingIfNeeded: fixed)
        }
        if let expr = pointValue.expr {
            return JavaMath.d2i(try Expression.eval(expr, context.expressionVariables))
        }
        if let perKm = pointValue.perKm {
            return perKmPoints(perKm, context)
        }
        return 0
    }

    /// Points by locator distance: rounded `distance × factor`, clipped to
    /// `[min, max]` in `long`. If there is no valid locator, the result is `min` (or 0) and `max`
    /// does not apply. `round` is compared after `toUpperCase(Locale.ROOT)` (without trimming spaces):
    /// `CEIL` → `(long) Math.ceil`, `FLOOR` → `(long) Math.floor`, anything else (also `nil`,
    /// `TRUNC`, `""`) → `Math.round`.
    private static func perKmPoints(_ perKm: ContestDefinition.PerKm, _ context: QsoContext) -> Int32 {
        let worked = context.fieldCanonical(perKm.field)
        let distance = Maidenhead.distanceKm(context.ownGrid, worked)
        if distance < 0 {
            return perKm.min.map { Int32(truncatingIfNeeded: $0) } ?? 0
        }
        let raw = distance * perKm.factor
        var points: Int64
        switch perKm.round?.uppercased() ?? "ROUND" {
        case "CEIL":
            points = JavaMath.d2l(raw.rounded(.up))
        case "FLOOR":
            points = JavaMath.d2l(raw.rounded(.down))
        default:
            points = JavaMath.round(raw)
        }
        if let min = perKm.min, points < Int64(min) {
            points = Int64(min)
        }
        if let max = perKm.max, points > Int64(max) {
            points = Int64(max)
        }
        return JavaMath.l2i(points)
    }
}
