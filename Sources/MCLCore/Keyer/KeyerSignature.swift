/// The identity of an open CW keyer (`AppState.cwKeyerOrOpen`, `AS:1471-1490`): `"${c.method}|${c.winkeyerPort}"`.
/// A different signature closes the open keyer and opens a new one; the speed is not part of it (a speed change
/// goes to the open keyer with `setSpeed`).
public enum KeyerSignature {

    public static func of(method: CwKeyerConfig.Method, port: String) -> String {
        method.rawValue + "|" + port
    }

    /// The fldigi client identity (`AppState.fldigiClient`, `AS:1554-1562`): `"${host}:${port}"`.
    public static func fldigi(host: String, port: Int) -> String {
        host + ":" + String(port)
    }
}

/// Status texts of the CW / digital keying and the CQ repeat of v1.1.1 (`AS:1443-1799`), `tr` vs. verbatim exactly
/// as Kotlin.
public enum KeyerTexts {

    /// `cwKeyerOrOpen` with method NONE — the message of the thrown error (shown as `"CW: " + message`).
    public static let cwDisabled = "CW klíč je vypnutý (Nastavení → CW klíč)"
    /// `cwKeyerOrOpen` with Winkeyer and no port — likewise.
    public static let winkeyerNoPort = "Winkeyer: vyber port v Nastavení → CW klíč"

    /// A failed CW send: `"CW: ${it.message}"` (the message may already be a translated text).
    public static func cwFailure(_ message: String?) -> EntryStatus {
        .verbatim("CW: " + (message ?? "null"))
    }

    /// A failed fldigi transmit: `"fldigi: ${it.message ?: tr("nedostupné")} (běží fldigi s XML-RPC na host:port?)"`.
    public static func fldigiFailure(_ message: String?, host: String, port: Int) -> EntryStatus {
        let head = EntryStatus.verbatim("fldigi: ")
        let reason: EntryStatus = message.map { EntryStatus.verbatim($0) } ?? .tr("nedostupné")
        let tail = EntryStatus.verbatim(" (běží fldigi s XML-RPC na " + host + ":" + String(port) + "?)")
        return head.appending(reason).appending(tail)
    }

    /// `repeatLabel()`: `String.format(Locale.US, "%.1f s", repeatSeconds)`.
    public static func repeatLabel(_ seconds: Double) -> String {
        JavaFormat.format("%.1f s", .double(seconds))
    }

    /// `updateCqRepeat(on)`.
    public static func cqRepeat(_ on: Bool, seconds: Double) -> EntryStatus {
        on ? .tr("Opakování CQ po %s (Esc nebo psaní volačky zastaví, Ctrl+R změní)", .string(repeatLabel(seconds)))
            : .tr("Opakování CQ vypnuto")
    }

    /// `promptRepeatTime` success: `"Pauza mezi CQ ${repeatLabel()}"` (not translated).
    public static func repeatPause(_ seconds: Double) -> EntryStatus {
        .verbatim("Pauza mezi CQ " + repeatLabel(seconds))
    }

    /// `requestMove`'s place (`AS:1632`): `String.format(Locale.US, "%.0f", hz / 1000.0)` — whole kHz.
    public static func moveKHz(_ freqHz: Int64) -> String {
        JavaFormat.format("%.0f", .double(Double(freqHz) / 1000.0))
    }

    /// The F-keys in post-contest entry (`EP:719`).
    public static let postContest = EntryStatus.tr("Dodatečné zadání — nic se nevysílá (NOPOSTCONTEST ukončí)")
}
