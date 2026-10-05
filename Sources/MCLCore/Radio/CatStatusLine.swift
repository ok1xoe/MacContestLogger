/// The CAT status line of a connected rig (Kotlin `CatConnection.format`, `CC:160-163`):
/// `String.format(Locale.US, "TRX: %.1f kHz  %s", freqKHz, mode?.name ?: rawMode)` — two spaces before the mode,
/// HALF_UP rounding of the kilohertz, the raw hamlib mode when the mode cannot be mapped.
public enum CatStatusLine {

    public static func format(_ state: RigState) -> String {
        let mode: String = state.mode?.rawValue ?? state.rawMode
        return JavaFormat.format("TRX: %.1f kHz  %s", .double(state.freqKHz), .string(mode))
    }

    /// `AppState.khz` (`AS:2235`): `String.format(Locale.US, "%.1f kHz", freqHz / 1000.0)`.
    public static func khz(_ freqHz: Int64) -> String {
        JavaFormat.format("%.1f kHz", .double(Double(freqHz) / 1000.0))
    }

    /// The frequency field text (`EP:612`, `:801`, `:1039`): `String.format(Locale.US, "%.2f", hz / 1000.0)`.
    public static func fieldText(_ freqHz: Int64) -> String {
        JavaFormat.format("%.2f", .double(Double(freqHz) / 1000.0))
    }
}
