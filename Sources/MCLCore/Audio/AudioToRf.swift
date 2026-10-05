/// Conversion of a frequency in the receiver audio to a frequency on the band according to the rig mode (Java `audio/AudioToRf`;
/// waterfall, CW decoder). In CW the signal on the display frequency is heard as a tone `pitch`; in LSB and CW-R the
/// audio is inverted.
///
/// As in Java: `Math.round(audioHz)` (`NaN` → 0, out of range → the `long` edge), addition overflows silently
/// (`&+`/`&-`), mode via Java `toUpperCase()` by UTF-16 units (`lſb` is `LSB` — measured; a full
/// mapping like `ß` → `SS` cannot be produced by any of the compared modes).
public enum AudioToRf {

    public static let defaultCwPitch: Int32 = 600

    /// Frequency on the band (Hz) for tone `audioHz` at display `dialHz`.
    public static func rfHz(dialHz: Int64, rawMode: String?, audioHz: Double, cwPitch: Int32) -> Int64 {
        let mode = String(decoding: (rawMode ?? "").utf16.map(JavaChar.toUpperCase), as: UTF16.self)
        let a = JavaMath.round(audioHz)
        let pitch = Int64(cwPitch)
        switch mode {
        case "CW": return dialHz &+ a &- pitch
        case "CWR": return dialHz &- (a &- pitch)
        case "LSB", "PKTLSB", "RTTY": return dialHz &- a
        default: return dialHz &+ a
        }
    }
}
