/// Parser of DX cluster lines (Java `dxcluster.DxSpotParser`). Two formats:
/// - real-time: `DX de SPOTTER:  14025.0  DXCALL  comment  1234Z`,
/// - output of the `SH/DX` command: `[20:24:36]  21150.0  DXCALL  12-Jul-2026 1824Z  comment  <SPOTTER>`.
///
/// Unrecognized lines (WWV, announcements, prompt) return `nil`. Java edge cases (measured on Java v1.1.1, `misc-probe.txt`
/// rows `DSP|`): `DX de` is case-sensitive, whitespace must sit between `:` and the frequency, callsigns only
/// `[A-Za-z0-9/#-]`; frequency `Math.round(Double.parseDouble(s) * 1000.0)` with saturation
/// (`JavaMath.round`); the trailing time is trimmed only if 3–4 digits; `\s`, `\d` and `.` are Java's (ASCII,
/// `.` does not match line terminators) thanks to `JavaRegex`. The line is trimmed with Java `trim()`.
public enum DxSpotParser {

    private static let spotPattern: JavaRegex = DxClusterRegex.compile(
        "^DX de\\s+([A-Za-z0-9/#\\-]+):\\s+([0-9]+(?:\\.[0-9]+)?)\\s+([A-Za-z0-9/#\\-]+)\\s*(.*)$")
    private static let trailingTime: JavaRegex = DxClusterRegex.compile("\\s*\\d{3,4}Z\\s*$")
    private static let showDxPattern: JavaRegex = DxClusterRegex.compile(showDxSource())

    private static func showDxSource() -> String {
        var source = "^(?:\\d{1,2}:\\d{2}:\\d{2}\\s+)?"                 // optional receive time
        source += "([0-9]+(?:\\.[0-9]+)?)\\s+"                          // frequency
        source += "([A-Za-z0-9/#\\-]+)\\s+"                             // dxCall
        source += "\\d{1,2}-[A-Za-z]{3}-\\d{2,4}\\s+\\d{3,4}Z\\s+"      // date + spot time
        source += "(.*?)\\s*"                                           // comment
        source += "<([A-Za-z0-9/#\\-]+)>\\s*$"                          // spotter in <>
        return source
    }

    public static func parse(_ line: String?) -> DxSpot? {
        guard let line else { return nil }
        let s = JavaText.trim(line)
        if let m = spotPattern.wholeMatch(s) {
            let freqHz = kiloHertzToHz(m.group(2) ?? "")
            // The pattern finds at most one match (it ends with `$` after `.*` with no line terminator),
            // so Java `replaceAll` is `replaceFirst` here.
            let comment = JavaText.trim(trailingTime.replaceFirst(in: m.group(4) ?? "", with: ""))
            return DxSpot(spotter: (m.group(1) ?? "").uppercased(), freqHz: freqHz,
                          dxCall: (m.group(3) ?? "").uppercased(), comment: comment)
        }
        if let h = showDxPattern.wholeMatch(s) {
            let freqHz = kiloHertzToHz(h.group(1) ?? "")
            return DxSpot(spotter: (h.group(4) ?? "").uppercased(), freqHz: freqHz,
                          dxCall: (h.group(2) ?? "").uppercased(), comment: JavaText.trim(h.group(3) ?? ""))
        }
        return nil
    }

    /// `Math.round(Double.parseDouble(text) * 1000.0)`; the text is always `[0-9]+(\.[0-9]+)?`, so
    /// `parseDouble` does not fail (a long number gives a large `double`, `round` saturates to `Long.MAX_VALUE`).
    private static func kiloHertzToHz(_ text: String) -> Int {
        let khz: Double = JavaDouble.parseDouble(text) ?? 0
        return Int(JavaMath.round(khz * 1000.0))
    }
}
