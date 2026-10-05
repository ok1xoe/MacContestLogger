/// Status texts of the rig, tuning and SO2V/SO2R operations of v1.1.1, `tr` vs. verbatim exactly as Kotlin
/// (`AS:` = `ui/AppState.kt`). The CAT connection texts live in `CatSession`, the rotator texts in `RotorAzimuth`.
public enum RigTexts {

    // MARK: - tuning (`AS:817-838`, `AS:2215-2235`)

    /// `AS:819` — Alt+F8 without a previous frequency.
    public static let noPreviousFrequency = EntryStatus.tr("Alt+F8: žádná předchozí frekvence")

    /// `AS:2223` — Alt+Q / CQ_FREQUENCY on a band without a CQ (`band?.adif() ?: ""`).
    public static func noCqOnBand(_ band: Band?) -> EntryStatus {
        .tr("Na pásmu %s zatím nebylo CQ", .string(band?.adif ?? ""))
    }

    /// `AS:2196` — Alt+U: `"Run (CQ frekvence ${khz(freqHz)})"` / `"S&P"` (not translated).
    public static func runModeToggled(run: Bool, freqHz: Int64) -> EntryStatus {
        run ? .verbatim("Run (CQ frekvence " + CatStatusLine.khz(freqHz) + ")") : .verbatim("S&P")
    }

    // MARK: - VFO B and split (`AS:2239-2248`, `AS:2342-2360`, `AS:957-982`)

    /// `vfoOperation` without CAT.
    public static func vfoNeedsCat(_ label: String) -> EntryStatus {
        .tr("%s: připoj TRX (CAT) — bez něj druhé VFO ani split nejdou", .string(label))
    }

    /// `vfoOperation` failure: `"$label: ${it.message}"` (not translated).
    public static func vfoFailure(_ label: String, _ message: String?) -> EntryStatus {
        .verbatim(label + ": " + (message ?? "null"))
    }

    /// Labels of the VFO operations (`"VFO B"`, `"Split"`, `"SWAP"` — not translated).
    public static let otherVfoLabel = "VFO B"
    public static let splitLabel = "Split"
    public static let swapLabel = "SWAP"

    /// `setOtherVfo`: `"VFO B ${khz(freqHz)}"`.
    public static func otherVfoDone(_ freqHz: Int64) -> EntryStatus {
        .verbatim("VFO B " + CatStatusLine.khz(freqHz))
    }

    /// `setSplit`: with a TX frequency `tr("Split: vysílám na %s", khz)`, otherwise `tr("Split zapnut (vysílám na VFO B)")`.
    public static func splitOn(txFreqHz: Int64) -> EntryStatus {
        txFreqHz > 0 ? .tr("Split: vysílám na %s", .string(CatStatusLine.khz(txFreqHz)))
            : .tr("Split zapnut (vysílám na VFO B)")
    }

    /// `splitOff` (not translated).
    public static let splitOff = EntryStatus.verbatim("Split vypnut")
    /// `swapVfo` (not translated).
    public static let swapped = EntryStatus.verbatim("VFO A ↔ B prohozena")

    /// `promptSplit` (`AS:965-981`): the prompt title — shown as is, Kotlin does not translate it.
    public static let splitPromptTitle = "Split"
    /// `promptSplit`: the prompt hint — a translation **key**, the view must pass it through `tr` (Kotlin `tr(...)`).
    public static let splitPromptHint = "Vysílací frekvence v kHz nebo posun (+2 = up 2); prázdné = vypnout split"

    /// `promptSplit` — neither a split nor an invalid command.
    public static func splitInvalid(_ text: String) -> EntryStatus {
        .tr("Split: neplatná frekvence „%s“", .string(text))
    }

    // MARK: - RIT (`AS:2316-2335`)

    public static let ritNeedsCat = EntryStatus.tr("RIT: připoj TRX (CAT)")

    /// Success: `if (v == 0) "RIT vypnut" else "RIT ${if (v > 0) "+" else ""}$v Hz"` (not translated).
    public static func rit(_ offsetHz: Int) -> EntryStatus {
        if offsetHz == 0 {
            return .verbatim("RIT vypnut")
        }
        return .verbatim("RIT " + (offsetHz > 0 ? "+" : "") + String(offsetHz) + " Hz")
    }

    /// Failure: `"RIT: ${it.message}"`.
    public static func ritFailure(_ message: String?) -> EntryStatus {
        .verbatim("RIT: " + (message ?? "null"))
    }

    // MARK: - SO2V / SO2R (`AS:2259-2307`)

    /// `syncRadioModeFromConfig` — OTRSP cannot be opened: `"SO2R: ${it.message}"`.
    public static func so2rOpenFailure(_ message: String?) -> EntryStatus {
        .verbatim("SO2R: " + (message ?? "null"))
    }

    /// `toggleSo2rStereo`: on `"SO2R: stereo (oba rigy)"` (not translated), off translated.
    public static func so2rStereo(_ on: Bool) -> EntryStatus {
        on ? .verbatim("SO2R: stereo (oba rigy)") : .tr("SO2R: poslech jen aktivního rigu")
    }

    /// SO2R `activateVfo`: `tr("Aktivní rig %s", vfo + 1) + if (o == null) " (bez OTRSP kontroléru)" else ""`.
    public static func activeRig(_ rig: Int, hasOtrsp: Bool) -> EntryStatus {
        let text = EntryStatus.tr("Aktivní rig %s", .int(rig))
        return hasOtrsp ? text : text.appending(.verbatim(" (bez OTRSP kontroléru)"))
    }

    /// SO2V `activateVfo` success: `tr("Aktivní VFO %s", if (vfo == 0) "A" else "B")`.
    public static func activeVfo(b: Bool) -> EntryStatus {
        .tr("Aktivní VFO %s", .string(b ? "B" : "A"))
    }

    /// SO2V `activateVfo` failure.
    public static func so2vFailure(_ message: String?) -> EntryStatus {
        .tr("SO2V: %s", .string(message))
    }

    // MARK: - antennas (`AS:775-797`)

    public static func noAntennaForBand(_ band: Band) -> EntryStatus {
        .tr("Pro %s není v Nastavení → Antennas žádná anténa", .string(band.adif))
    }

    public static func antenna(_ entry: AntennaEntry) -> EntryStatus {
        .tr("Anténa: %s (kód %s)", .string(entry.name), .int(entry.code))
    }

    // MARK: - tuning carrier (`AS:984-1011`)

    public static let tuneOn = EntryStatus.tr("LADĚNÍ — nosná (Ctrl+T nebo Esc ukončí, pojistka 30 s)")
    public static let tuneOff = EntryStatus.tr("Ladění ukončeno")

    public static func tuneFailure(_ message: String?) -> EntryStatus {
        .tr("Ladění: %s", .string(message))
    }

    // MARK: - reset and footswitch (`AS:2107-2115`, `AS:647-657`)

    /// `resetInterfaces`: `tr("Rozhraní resetována") + if (wasConnected) tr(" — připojuji TRX znovu") else
    /// tr(" (CW klíč se otevře při dalším vysílání)")`.
    public static func interfacesReset(wasConnected: Bool) -> EntryStatus {
        let tail: EntryStatus = wasConnected ? .tr(" — připojuji TRX znovu")
            : .tr(" (CW klíč se otevře při dalším vysílání)")
        return EntryStatus.tr("Rozhraní resetována").appending(tail)
    }

    /// `resetInterfaces` disconnect message (not translated).
    public static let resetDisconnect = "reset"

    /// `reloadFootswitch` failure: `it.message ?: tr("Footswitch nejde otevřít")`.
    public static func footswitchFailure(_ message: String?) -> EntryStatus {
        guard let message else { return .tr("Footswitch nejde otevřít") }
        return .verbatim(message)
    }
}
