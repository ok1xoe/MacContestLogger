/// Is a county / location one of the active contest's enumerated multiplier values? Port of Kotlin
/// `ContestController.isKnownLocation(value)` (v1.1.1), used by ROVERQTH and COUNTYLINE to warn about a typo.
public enum KnownLocation {

    /// `nil` = the contest has no list to check against (no definition, no registry, or no enumerable non-empty set
    /// bound to an exchange field — `from` set and not `callsign`); otherwise whether a value's key equals `value`
    /// ignoring case (Java `equalsIgnoreCase`).
    ///
    /// Leniency: Java `registry.get` throws for a set id that is not registered (Kotlin would crash); such a binding
    /// is skipped here.
    public static func check(_ value: String, definition: ContestDefinition?,
                             registry: MultiplierSetRegistry?) -> Bool? {
        guard let definition, let registry else { return nil }
        var sets: [any MultiplierSet] = []
        for binding in definition.multipliers ?? [] {
            guard let binding, let from = binding.from, from != "callsign" else { continue }
            guard let set = try? registry.get(binding.set) else { continue }
            if set.enumerable && !set.values.isEmpty {
                sets.append(set)
            }
        }
        if sets.isEmpty {
            return nil
        }
        return sets.contains { set in
            set.values.contains { candidate in
                guard let key = candidate.key else { return false }
                return JavaChar.equalsIgnoreCase(key, value)
            }
        }
    }
}
