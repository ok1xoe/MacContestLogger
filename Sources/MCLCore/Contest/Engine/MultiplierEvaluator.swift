/// Evaluates a QSO's multipliers. `preview` does not change the tracker (while typing), `commit` counts the new ones.
/// A QSO is never blocked; unknown and suspicious values are accepted and flagged. Port of Java
/// `engine/MultiplierEvaluator.java`.
///
/// The Java evaluator holds a **reference** to the tracker, which it shares with `ContestSession`. Here the tracker
/// is a value (`struct`), so the evaluator **owns** it (`tracker`) and the session reads it from there.
/// The evaluator is `Sendable`: the registry is `Sendable` and the tracker a value, so it can be built
/// in the background and handed to the main actor; each session has its own copy of the tracker.
///
/// Java bugs that are copied:
/// - two bindings with the **same id** in one QSO: `preview` reports both as new, `commit` the second as already
///   worked (the first filled the tracker in the meantime),
/// - `appliesWhen` is inherited from the exchange field by `from` **case-insensitively**, but
///   the value is read with `fieldRaw(from)` **exactly** — `from: ZONE` over a field `zone` is `INVALID_FORMAT`,
/// - a missing band or mode in the scope is the text `null` (`MultiplierEvaluator.scopeKey`),
/// - an unknown set throws `MultiplierError` in the middle of evaluation and the bindings before it
///   stay in the tracker (`commit` has no transaction).
public struct MultiplierEvaluator: Sendable {

    public let registry: MultiplierSetRegistry
    /// Worked multipliers of the session (Java's shared `MultiplierTracker`).
    public var tracker: MultiplierTracker

    public init(registry: MultiplierSetRegistry, tracker: MultiplierTracker = MultiplierTracker()) {
        self.registry = registry
        self.tracker = tracker
    }

    /// Preview without writing to the tracker.
    ///
    /// - Throws: `MultiplierError.failure` when a binding refers to a set that is not in the registry.
    public func preview(_ definition: ContestDefinition,
                        _ context: QsoContext) throws(MultiplierError) -> [MultiplierEvalResult] {
        var unchanged = tracker
        return try Self.evaluate(definition, context, registry, &unchanged, commit: false)
    }

    /// Evaluates and counts. On an error the bindings evaluated before it stay in the tracker.
    ///
    /// - Throws: `MultiplierError.failure` when a binding refers to a set that is not in the registry.
    public mutating func commit(_ definition: ContestDefinition,
                                _ context: QsoContext) throws(MultiplierError) -> [MultiplierEvalResult] {
        try Self.evaluate(definition, context, registry, &tracker, commit: true)
    }

    /// Java `MultiplierEvaluator.scopeKey(scope, ctx)` (shared by the dupe check and the bonuses).
    public static func scopeKey(_ scope: ContestDefinition.Scope?, _ context: QsoContext) -> String {
        ScopeKey.make(scope, context)
    }

    /// Bindings in definition order; non-applicable ones (`appliesWhen`) are missing from the result.
    ///
    /// A `nil` binding (`multipliers: [~]`) makes Java fail with an NPE (after counting earlier bindings);
    /// Swift skips it (a deliberate divergence from Java v1.1.1).
    private static func evaluate(_ definition: ContestDefinition, _ context: QsoContext,
                                 _ registry: MultiplierSetRegistry, _ tracker: inout MultiplierTracker,
                                 commit: Bool) throws(MultiplierError) -> [MultiplierEvalResult] {
        guard let multipliers = definition.multipliers else { return [] }
        var out: [MultiplierEvalResult] = []
        for case let binding? in multipliers where applies(definition, binding, context) {
            out.append(try evaluateBinding(binding, context, registry, &tracker, commit: commit))
        }
        return out
    }

    /// Does the binding apply to this other station? Its own `appliesWhen`, otherwise inherited from the exchange field;
    /// without a condition or without `workedClass` it always applies, otherwise a class match by UTF-16.
    private static func applies(_ definition: ContestDefinition, _ binding: ContestDefinition.MultiplierBinding,
                                _ context: QsoContext) -> Bool {
        let condition = binding.appliesWhen ?? sourceFieldAppliesWhen(definition, binding)
        guard let workedClass = condition?.workedClass else { return true }
        return JavaText.equals(workedClass, context.workedClass)
    }

    /// Condition of the first received field whose id matches `from` case-insensitively
    /// **and** which has a condition. A binding from the callsign or without `from` inherits nothing.
    ///
    /// A `nil` element of `exchange.received` makes Java fail with an NPE (in practice already in `QsoContextFactory.build`);
    /// Swift skips it (a deliberate divergence from Java v1.1.1).
    private static func sourceFieldAppliesWhen(_ definition: ContestDefinition,
                                               _ binding: ContestDefinition.MultiplierBinding)
        -> ContestDefinition.AppliesWhen? {
        guard let from = binding.from, !JavaChar.equalsIgnoreCase("callsign", from),
              let received = definition.exchange?.received else { return nil }
        for case let field? in received where JavaChar.equalsIgnoreCase(from, field.id) {
            if let condition = field.appliesWhen {
                return condition
            }
        }
        return nil
    }

    private static func evaluateBinding(_ binding: ContestDefinition.MultiplierBinding, _ context: QsoContext,
                                        _ registry: MultiplierSetRegistry, _ tracker: inout MultiplierTracker,
                                        commit: Bool) throws(MultiplierError) -> MultiplierEvalResult {
        let set = try registry.get(binding.set)
        let scopeKey = ScopeKey.make(binding.scope, context)
        let fromCallsign = JavaChar.equalsIgnoreCase("callsign", binding.from)

        let resolution = fromCallsign
            ? set.deriveFromCallsign(context.call)
            : set.normalize(context.fieldRaw(binding.from))

        // Failure: from the callsign = suspicious (a garbled callsign), from a field = invalid format.
        guard resolution.isValid else {
            return MultiplierEvalResult(bindingId: binding.id, setId: binding.set, key: nil, scopeKey: scopeKey,
                                        state: fromCallsign ? .suspicious : .invalidFormat,
                                        countsAsMultiplier: false, isNew: false)
        }

        let key = resolution.key
        let already = tracker.isWorked(binding.id, scopeKey, key)
        let state: MultiplierEvalResult.MultiplierState
        if set.enumerable && !set.isExpected(key) {
            state = .unknownAccepted
        } else {
            state = already ? .knownAlreadyWorked : .knownNewMultiplier
        }
        if commit {
            tracker.add(binding.id, scopeKey, key)
        }
        return MultiplierEvalResult(bindingId: binding.id, setId: binding.set, key: key, scopeKey: scopeKey,
                                    state: state, countsAsMultiplier: true, isNew: !already)
    }
}
