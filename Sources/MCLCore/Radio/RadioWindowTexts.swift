/// Texts and input rules of the radio tool windows of v1.1.1 (`RotatorWindow.kt`, `CwReaderWindow.kt`,
/// `WaterfallWindow.kt`, `DigitalInterfaceWindow.kt`): what the windows show and how their small input fields filter
/// what is typed. `tr` texts are `EntryStatus.tr` (translated when shown), literals stay as Kotlin writes them.
public enum RadioWindowTexts {

    // MARK: - input fields

    /// Kotlin `text.filter { it.isDigit() }.take(limit)`: Unicode decimal digits (Java `Character.isDigit` per UTF-16
    /// unit), at most `limit` units.
    public static func digits(_ text: String, limit: Int) -> String {
        let kept: [UInt16] = text.utf16.filter { JavaChar.isDigit($0) }
        return JavaChar.string(Array(kept.prefix(Swift.max(0, limit))))
    }

    /// The CW reader's tone field (`CwReaderWindow.kt:83-86`): `pitchText.toIntOrNull()?.takeIf { it in 200..3000 }`.
    public static func readerTone(_ digits: String) -> Int? {
        guard let value = JavaInteger.parseInt(digits), value >= 200, value <= 3000 else { return nil }
        return Int(value)
    }

    /// The rotator's azimuth field (`RotatorWindow.kt:84`): `manual.toDoubleOrNull()` (Java `Double.parseDouble` after
    /// Kotlin's screening — ASCII digits only; the field holds only digits).
    public static func rotatorFieldAzimuth(_ digits: String) -> Double? {
        guard digits.utf16.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return JavaDouble.parseDouble(digits)
    }

    // MARK: - rotator

    /// The big azimuth (`RotatorWindow.kt:70`): `az?.let { "${it.toInt()}°" } ?: "—"` (truncation, NaN → 0).
    public static func rotatorAzimuth(_ azimuth: Double?) -> String {
        guard let azimuth else { return "—" }
        return String(JavaMath.d2i(azimuth)) + "°"
    }

    /// The call line (`RotatorWindow.kt:73-76`): `"$call: $target°"`, `"$call: " + tr("azimut neznámý")`, or the
    /// untranslated `"Volačka z pole: —"`.
    public static func rotatorCallLine(call: String, target: Int?) -> EntryStatus {
        guard !KotlinStrings.isBlank(call) else { return .verbatim("Volačka z pole: —") }
        let head: EntryStatus = .verbatim(call + ": ")
        guard let target else { return head.appending(.tr("azimut neznámý")) }
        return head.appending(.verbatim(String(target) + "°"))
    }

    // MARK: - CW reader

    /// `"~$wpm WPM"`.
    public static func readerWpm(_ wpm: Int) -> String {
        "~" + String(wpm) + " WPM"
    }

    /// The text shown before anything was decoded.
    public static func readerPlaceholder(_ pitchText: String) -> EntryStatus {
        .tr("Čekám na CW na %s Hz… (zdroj zvuku: Nastavení → Audio → Příjem)", .string(pitchText))
    }

    /// The audio error line (`"Zvuk: $it"`, not translated).
    public static func readerAudioError(_ message: String) -> String {
        "Zvuk: " + message
    }

    // MARK: - waterfall

    /// The hover text (`WaterfallWindow.kt:85-86`): `String.format(Locale.US, "audio %.0f Hz → %.2f kHz", hz,
    /// rfHz / 1000.0)`.
    public static func waterfallHover(audioHz: Double, rfHz: Int64) -> String {
        JavaFormat.format("audio %.0f Hz → %.2f kHz", .double(audioHz), .double(Double(rfHz) / 1000.0))
    }

    /// The info line without hover (`WaterfallWindow.kt:87`): the raw mode (`?` when blank) and the CW pitch.
    public static func waterfallInfo(rawMode: String, pitchHz: Int) -> EntryStatus {
        let mode: String = KotlinStrings.isBlank(rawMode) ? "?" : rawMode
        return .tr("0–3 kHz audia přijímače · mód %s · CW tón %s Hz", .string(mode), .string(String(pitchHz)))
    }

    /// The audio error instead of the info line (`WaterfallWindow.kt:88`).
    public static func waterfallError(_ message: String) -> EntryStatus {
        .tr("Zvukový vstup: %s (Nastavení → Audio → Vstup přijímače)", .string(message))
    }

    /// The CW pitch line is drawn only when the rig's raw mode starts with `CW` (`raw.uppercase().startsWith("CW")`).
    public static func showsPitchLine(rawMode: String) -> Bool {
        JavaText.toUpperCase(rawMode).hasPrefix("CW")
    }

    // MARK: - digital interface

    /// No modem configured (`DigitalInterfaceWindow.kt:81`).
    public static let digitalNoModem = EntryStatus.tr(
        "Modem není nastavený — Nastavení → Digitální módy → Modem pro RTTY / PSK.")

    /// fldigi did not answer (`DigitalInterfaceWindow.kt:103`): `tr("fldigi nedostupné (%s:%s): %s", host, port,
    /// e.message)`.
    public static func fldigiUnavailable(host: String, port: Int, message: String?) -> EntryStatus {
        .tr("fldigi nedostupné (%s:%s): %s", .string(host), .string(String(port)), .string(message ?? "null"))
    }

    /// The modem status (`"${poll.modem} · ${poll.trx}"`).
    public static func digitalStatus(modem: String, trx: String) -> String {
        modem + " · " + trx
    }
}
