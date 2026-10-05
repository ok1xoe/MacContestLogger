/// QSO-party settings typed as call-field commands (`AS:3879-3943` of v1.1.1): COUNTYLINE, BONUS and ROVERQTH —
/// the parsing of the entered text and the Kotlin status texts. Saving and the contest session are the app's job.
///
/// Splitting is Kotlin `text.uppercase().split(Regex(…)).filter { it.isNotBlank() }.distinct()`: Java `\s` is ASCII
/// only (space, `\t`, `\n`, `\u000B`, `\f`, `\r`), a token that is only Unicode blanks (NBSP…) is dropped, a token
/// with an NBSP inside stays whole, duplicates by UTF-16 equality (measured, a maintainer-only probe).
public enum CountyLineSetting {

    /// `applyCountyLine(text)`: the counties and the status. `isKnownLocation` = `contest.isKnownLocation(c)`
    /// (`nil` = the contest has no list of counties; only an explicit `false` warns).
    public static func apply(text: String, usesRoverQth: Bool,
                             isKnownLocation: (String) -> Bool?) -> (counties: [String], status: EntryStatus) {
        let counties: [String] = tokens(text, separators: countySeparators)
        let joined: String = counties.joined(separator: "/")
        if counties.isEmpty {
            // Not translated in Kotlin.
            return (counties, .verbatim("County line vypnuto"))
        }
        if !usesRoverQth {
            return (counties, .tr("County line %s — pozor: závod okres ve výměně nemá, QSO se zapíše jen jednou",
                                  .string(joined)))
        }
        var status: EntryStatus = .tr("County line %s: každé QSO se zapíše %s×", .string(joined), .int(counties.count))
        let unknown: [String] = counties.filter { isKnownLocation($0) == false }
        if !unknown.isEmpty {
            status = status.appending(.verbatim(" — "))
                .appending(.tr("pozor, není v seznamu okresů: %s", .string(unknown.joined(separator: " "))))
        }
        return (counties, status)
    }

    /// `NOCOUNTYLINE` = `applyCountyLine("")`.
    public static func off() -> (counties: [String], status: EntryStatus) {
        apply(text: "", usesRoverQth: false) { _ in nil }
    }

    /// `applyBonusStations(text)`: the bonus calls (`[,;\s]+`, a slash stays inside a call) and the status.
    public static func bonusStations(_ text: String) -> (calls: [String], status: EntryStatus) {
        let calls: [String] = tokens(text, separators: bonusSeparators)
        if calls.isEmpty {
            return (calls, .tr("Bonusové stanice smazány"))
        }
        // Not translated in Kotlin.
        return (calls, .verbatim("Bonusové stanice (\(calls.count)): " + calls.joined(separator: " ")))
    }

    /// `applyRoverQth(county)`: `county.trim().uppercase().replace(Regex("\\s+"), "")` (Kotlin `trim` removes Unicode
    /// whitespace at the ends, the regex only ASCII inside).
    public static func roverQth(_ county: String) -> String {
        let upper: String = JavaText.toUpperCase(KotlinStrings.trim(county))
        let units: [UInt16] = upper.utf16.filter { !asciiWhitespace.contains($0) }
        return JavaChar.string(units)
    }

    /// The status of `applyRoverQth`.
    public static func roverQthStatus(_ county: String, usesRoverQth: Bool, isKnownLocation: Bool?) -> EntryStatus {
        if county.isEmpty {
            return .tr("Rover QTH smazáno")
        }
        let base: EntryStatus = .verbatim("Rover QTH: " + county)
        if !usesRoverQth {
            return base.appending(.tr(" (závod okres ve výměně nemá — jen pro makro {ROVERQTH})"))
        }
        if isKnownLocation == false {
            return base.appending(.verbatim(" — ")).appending(.tr("pozor: %s není v seznamu okresů závodu", .string(county)))
        }
        return base
    }

    /// Java `\s`.
    private static let asciiWhitespace: Set<UInt16> = [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D]
    private static let countySeparators: Set<UInt16> = asciiWhitespace.union([0x2C, 0x3B, 0x2F])
    private static let bonusSeparators: Set<UInt16> = asciiWhitespace.union([0x2C, 0x3B])

    private static func tokens(_ text: String, separators: Set<UInt16>) -> [String] {
        var out: [String] = []
        var seen = Set<JavaStringKey>()
        var current: [UInt16] = []
        func flush() {
            let token: String = JavaChar.string(current)
            current = []
            if !KotlinStrings.isBlank(token), seen.insert(JavaStringKey(token)).inserted {
                out.append(token)
            }
        }
        for unit in JavaText.toUpperCase(text).utf16 {
            if separators.contains(unit) {
                flush()
            } else {
                current.append(unit)
            }
        }
        flush()
        return out
    }
}
