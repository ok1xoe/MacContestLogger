/// What the station sends in the active contest. Port of `sentExchangeText` and `sentExchangeFlat`
/// of `ui/AppState.kt:3781-3810` without the Compose state: the caller passes the active definition,
/// the setup of the active contest (`activeContestSetup()`), the mode and the serial number.
///
/// Kotlin text semantics: `isNotBlank`/`ifBlank`/`trim` are Kotlin's (`KotlinText`, NBSP is whitespace),
/// `Regex("\\s+")` is Java's ASCII `\s`.
///
/// Leniency versus Kotlin: a `nil` element of `exchange.sent` and a `nil` default value (a station
/// key present with a JSON `null`) make Kotlin throw `NullPointerException`; here such an element is
/// skipped (`ExchangeEngine.sentDefaults` already skips `nil` fields) and a `nil` value counts as empty.
public enum SentExchange {

    /// The sent exchange shown once in the entry panel header (`sentExchangeText`): the default values
    /// of the sent fields that are not blank, joined with a space; `""` outside a contest.
    ///
    /// The `ROVER_QTH` value is the county line joined with `/` (`DAD/JEF`) when the county line is
    /// non-empty, otherwise the configured rover QTH as is (`config.station.roverQth`, not trimmed).
    public static func text(definition: ContestDefinition?, setup: ContestSetup?, mode: Mode, serial: Int,
                            roverQth: String, countyLine: [String]) -> String {
        guard let definition else {
            return ""
        }
        let qth: String = countyLine.isEmpty ? roverQth : countyLine.joined(separator: "/")
        let context = ExchangeContext(mode: mode, nextSerial: Int32(truncatingIfNeeded: serial),
                                      station: station(setup), roverQth: qth)
        let values = ExchangeEngine().sentDefaults(definition, context)
        var parts: [String] = []
        for entry in values.entries {
            guard let value = entry.value, !KotlinText.isBlank(value) else { continue }
            parts.append(value)
        }
        return parts.joined(separator: " ")
    }

    /// The sent exchange stored with a QSO (`sentExchangeFlat`): values of the sent fields in definition
    /// order; an `AUTO_RST` field takes the actually sent report `rstSent` when it is not blank; every
    /// value is Kotlin-trimmed and stripped of Java `\s` characters, an empty one becomes `-` (keeps the
    /// position). `nil` outside a contest and when the definition has no sent fields — a list of
    /// fields that are all empty gives dashes (`"- -"`), not `nil`.
    public static func flat(definition: ContestDefinition?, setup: ContestSetup?, mode: Mode, serial: Int,
                            rstSent: String, ownQth: String?) -> String? {
        guard let definition else {
            return nil
        }
        let context = ExchangeContext(mode: mode, nextSerial: Int32(truncatingIfNeeded: serial),
                                      station: station(setup), roverQth: ownQth ?? "")
        let values = ExchangeEngine().sentDefaults(definition, context)
        var parts: [String] = []
        for field in definition.exchange?.sent ?? [] {
            guard let field else { continue }
            let value: String
            if field.source == .AUTO_RST && !KotlinText.isBlank(rstSent) {
                value = rstSent
            } else {
                value = values[field.id] ?? ""
            }
            let compact = removingJavaSpaces(KotlinText.trim(value))
            parts.append(KotlinText.isBlank(compact) ? "-" : compact)
        }
        let joined = parts.joined(separator: " ")
        return KotlinText.isBlank(joined) ? nil : joined
    }

    /// Kotlin `activeContestSetup()?.sentExchange ?: emptyMap()` as the engine's station map.
    static func station(_ setup: ContestSetup?) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        for (key, value) in setup?.sentExchange ?? [:] {
            out.put(key, value)
        }
        return out
    }

    /// `replace(Regex("\\s+"), "")` — Java `\s` = `[ \t\n\u{0B}\f\r]`.
    static func removingJavaSpaces(_ text: String) -> String {
        let units: [UInt16] = Array(text.utf16)
        guard units.contains(where: JavaChar.isRegexSpace) else {
            return text
        }
        return JavaChar.string(units.filter { !JavaChar.isRegexSpace($0) })
    }
}
