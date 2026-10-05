/// Builds variables from a `QsoContext` for evaluating expressions (`when.expr`, `value.expr`)
/// in `Expression`. Port of Java `engine/QsoVariables.java`.
///
/// Order like the Java `LinkedHashMap`: `call`, `band`, `mode`, `workedContinent`,
/// `ownContinent`, `ownItuZone` (texts, `nil` → `""`), `ownDxcc`, `sameContinent`,
/// `otherContinent` (numbers 1/0), then each received field `id → canonical` (a `nil` value
/// and an invalid field → `""`). A received field named like a context variable **overwrites** it
/// at its position (measured: `band`, `ownDxcc`). `workedClass`, `ownGrid`, `ownQth`
/// and `bonusStation` are not among the variables — in an expression they give 0.
///
/// The container is a `JavaLinkedMap`, not a dictionary: field ids from a definition that differ only
/// canonically (`K` / `K`) are two variables in Java and stay two here too.
public enum QsoVariables {

    public static func of(_ context: QsoContext) -> JavaLinkedMap<ExpressionValue> {
        var variables = JavaLinkedMap<ExpressionValue>()
        variables.put("call", .text(context.call ?? ""))
        variables.put("band", .text(context.band ?? ""))
        variables.put("mode", .text(context.mode ?? ""))
        variables.put("workedContinent", .text(context.workedContinent ?? ""))
        variables.put("ownContinent", .text(context.ownContinent ?? ""))
        variables.put("ownItuZone", .text(context.ownItuZone ?? ""))
        variables.put("ownDxcc", Expression.bool(context.ownDxcc))
        variables.put("sameContinent", Expression.bool(context.sameContinent))
        variables.put("otherContinent", Expression.bool(context.otherContinent))
        // Received fields by id → canonical value (text).
        if let received = context.received {
            for (id, value) in received.entries {
                variables.put(id, .text(value?.canonical ?? ""))
            }
        }
        return variables
    }
}
