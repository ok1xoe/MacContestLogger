/// Jump to the next spot in the bandmap (N1MM Ctrl+↑/↓, Ctrl+Alt+↑/↓ multipliers only,
/// Shift+Alt+↑/↓ self-spots only): the nearest spot above / below the current frequency
/// on the same band that passes the filter. Mirrors the Java `radio.SpotNavigator`.
public enum SpotNavigator {

    /// Spots closer than this to the current frequency count as "here" and are skipped.
    static let sameSpotHz: Int = 50

    /// - Parameters:
    ///   - direction: +1 = up (Ctrl+↓ in N1MM, Cmd+↓ here), −1 = down (Ctrl+↑ / Cmd+↑); anything ≤ 0 is "down".
    /// - Returns: the nearest matching spot; on equal distance the **first in the order** of `spots`
    ///   (Java `Stream.min`).
    ///
    /// Outside bands (`Band.from` = `nil`) the band is not filtered at all. The arithmetic is a Java
    /// `long`: `freqHz ± 50` and the distance wrap and `Math.abs(Long.MIN_VALUE)` stays
    /// negative — measured in a maintainer-only probe (rows `SN.next`).
    public static func next(
        _ spots: [DxSpot], freqHz: Int, direction: Int, where filter: (DxSpot) -> Bool
    ) -> DxSpot? {
        let band = Band.from(frequencyHz: freqHz)
        let upper = freqHz &+ sameSpotHz
        let lower = freqHz &- sameSpotHz
        var best: DxSpot?
        var bestDistance: Int64 = 0
        for spot in spots {
            if band != nil && spot.band != band { continue }
            if !filter(spot) { continue }
            let beyond = direction > 0 ? spot.freqHz > upper : spot.freqHz < lower
            if !beyond { continue }
            let distance = JavaMath.abs(Int64(spot.freqHz &- freqHz))
            if best == nil || distance < bestDistance {
                best = spot
                bestDistance = distance
            }
        }
        return best
    }
}
