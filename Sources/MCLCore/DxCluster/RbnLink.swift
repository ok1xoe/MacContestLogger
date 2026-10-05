/// Link to a station's spot overview on the Reverse Beacon Network (Java `dxcluster.RbnLink`) — the option
/// „Zobrazit RBN spoty této stanice" from the Info window. `t=dx` = "who hears this station", `f=0` = no
/// band restriction.
public enum RbnLink {

    private static let base = "https://www.reversebeacon.net/dxsd1/dxsd1.php"

    /// URL of the given station's spot overview; `nil` without a callsign (Java `isBlank`). The callsign is trimmed
    /// with Java `trim()`, uppercased and encoded like `URLEncoder` (`OK1K/P` → `OK1K%2FP`).
    public static func spotsOfStation(_ call: String?) -> String? {
        guard let call, !JavaText.isBlank(call) else { return nil }
        let encoded = JavaUrlEncoder.encode(JavaText.trim(call).uppercased())
        var url = base
        url += "?f=0&c="
        url += encoded
        url += "&t=dx"
        return url
    }
}
