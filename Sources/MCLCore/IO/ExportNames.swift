/// Suggested file names for the export dialogs.
///
/// Port of the Kotlin `AppState.cabrilloFileName()` (`ui/AppState.kt`, v1.1.1) and of the default
/// name of the ADIF save dialog (`app/App.kt`, `chooseAdifPath`). The text functions are Kotlin's,
/// not Java's (measured, a maintainer-only probe): `trim`/`isBlank` treat U+00A0, U+2007,
/// U+202F and U+3000 as white space and keep control characters; `uppercase()` is the full
/// `Locale.ROOT` mapping (`ß` → `SS`).
public enum ExportNames {

    /// Default file name of the ADIF export dialog.
    public static let adifDefaultName = "maccontestlogger.adi"

    /// `CALL-CONTEST.log` (like N1MM `<call>.log`, plus the contest's Cabrillo name).
    ///
    /// The callsign is trimmed, upper-cased and every `/` becomes `_`; a blank result is `log`.
    /// The contest name (`cabrillo.contestName`) is only trimmed — neither upper-cased nor
    /// sanitised, so a `/` in it stays. Without a definition, a `cabrillo` block or a name the
    /// result is `CALL.log`.
    public static func cabrilloFileName(stationCall: String, definition: ContestDefinition?) -> String {
        let upper: String = JavaText.toUpperCase(KotlinText.trim(stationCall))
        var call: String = JavaText.replace(upper, "/", "_")
        if KotlinText.isBlank(call) {
            call = "log"
        }
        let contestName: String = KotlinText.trim(definition?.cabrillo?.contestName ?? "")
        if KotlinText.isBlank(contestName) {
            return call + ".log"
        }
        return call + "-" + contestName + ".log"
    }

    /// One EDI file per band (`AS:4069`): `call.replace('/', '_') + "_" + band.adif + ".edi"` — the call is neither
    /// trimmed nor upper-cased and a blank one stays blank (`_2m.edi`).
    public static func ediFileName(call: String, band: Band) -> String {
        JavaText.replace(call, "/", "_") + "_" + band.adif + ".edi"
    }

    /// The base name of the other exports (`AS:4041`): `call.replace('/', '_').ifBlank { "log" }` — **without**
    /// `trim`, so `" "` is blank (`log`) but `" X"` keeps its space.
    public static func otherBase(call: String) -> String {
        let base: String = JavaText.replace(call, "/", "_")
        return KotlinText.isBlank(base) ? "log" : base
    }
}
