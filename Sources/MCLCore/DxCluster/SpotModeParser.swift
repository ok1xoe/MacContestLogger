/// A clearly labelled mode from a DX spot comment (Java `dxcluster.SpotModeParser`): `CW`, `SSB`, `RTTY`,
/// `FT8`, `FT4`, `PSK`, or `nil` when the comment states no unambiguous mode.
///
/// Case-insensitive match (ASCII) on word boundaries; order FT8 → FT4 → RTTY → PSK
/// (`[A-Z]?PSK\d*`) → CW → phone. `\b` is Java's (ASCII `\w`, measured, rows `SMP|`):
/// `éCW` and `CWé` **find** CW, `x_CW` does not (underscore is a word character), `FT8x` no, `SCW` no.
public enum SpotModeParser {

    private static let ft8: JavaRegex = word("FT8")
    private static let ft4: JavaRegex = word("FT4")
    private static let rtty: JavaRegex = word("RTTY")
    private static let psk: JavaRegex = DxClusterRegex.compile("(?i)\\b[A-Z]?PSK\\d*\\b")
    private static let cw: JavaRegex = word("CW")
    private static let phone: JavaRegex = DxClusterRegex.compile("(?i)\\b(?:SSB|USB|LSB|PH|PHONE)\\b")

    public static func fromComment(_ comment: String?) -> String? {
        guard let comment, !JavaText.isBlank(comment) else { return nil }
        if ft8.firstMatch(in: comment) != nil { return "FT8" }
        if ft4.firstMatch(in: comment) != nil { return "FT4" }
        if rtty.firstMatch(in: comment) != nil { return "RTTY" }
        if psk.firstMatch(in: comment) != nil { return "PSK" }
        if cw.firstMatch(in: comment) != nil { return "CW" }
        if phone.firstMatch(in: comment) != nil { return "SSB" }
        return nil
    }

    /// Java `Pattern.compile("\\b" + literal + "\\b", CASE_INSENSITIVE)`.
    private static func word(_ literal: String) -> JavaRegex {
        DxClusterRegex.compile("(?i)\\b" + literal + "\\b")
    }
}
