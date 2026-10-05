/// Recognition of a spot from CW Skimmer / Reverse Beacon Network (Java `dxcluster.SkimmerSpot`):
/// the spotter ends with `-#` (RBN and CW Skimmer Server convention), or the comment has the skimmer form
/// "19 dB 28 WPM CQ".
///
/// Edges (`misc-probe.txt` rows `SKIM|`): `-5dB 30wpm` yes, `5 db 100 bps` yes,
/// `19dB28WPM` no (ASCII `\b` between `B` and `2` is missing), `123 dB` no (SNR at most two digits); spotter after
/// Java `trim()`; a self-spot is never a skimmer.
public enum SkimmerSpot {

    private static let commentPattern: JavaRegex =
        DxClusterRegex.compile("(?i)\\b-?\\d{1,2}\\s*dB\\b.*\\b\\d{1,3}\\s*(WPM|BPS)\\b")

    public static func isSkimmer(_ spot: DxSpot?) -> Bool {
        guard let spot, !spot.selfSpotted else { return false }
        let spotter = JavaText.trim(spot.spotter)
        if DxClusterRegex.endsWith(spotter, "-#") {
            return true
        }
        return commentPattern.firstMatch(in: spot.comment) != nil
    }
}
