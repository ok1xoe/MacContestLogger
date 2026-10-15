/// Default values of received exchange fields (Swift-only `prefill` key) — N1MM's ARRL DX default power: a W/VE
/// station working DX gets the DX station's usual power (100 W, 200 W in Russia and its neighbours, 400 W in the UK,
/// 500 W in Italy) put into the empty Power field by the space bar. The rules come from the definition, nothing is
/// built in.
public enum ExchangePrefill {

    /// The prefill of each field that has one: the value of its first rule whose `when` holds in `context` (a rule
    /// without `when` always does). Blank values and fields without an id are left out.
    public static func values(_ fields: [ContestDefinition.ExchangeField],
                              _ context: QsoContext) throws(ExpressionError) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        for field in fields {
            guard let id = field.id, let rules = field.prefill else { continue }
            for rule in rules {
                guard let rule else { continue }
                if try ConditionEvaluator.eval(rule.when, context) {
                    if let value = rule.value.map(KotlinText.trim), !value.isEmpty {
                        out.put(id, value)
                    }
                    break
                }
            }
        }
        return out
    }
}
