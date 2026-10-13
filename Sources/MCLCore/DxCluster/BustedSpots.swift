import Foundation

/// N1MM+ "Remove Busted Spots" (Telnet window, Filters tab): a spot whose call differs by one character — or, with
/// "Two Character Errors", by two — from another call spotted near the same frequency (within the tuning tolerance of
/// the mode) is a busted copy of it, typically a skimmer's wrong decode. The call reported fewer times is the busted
/// one; on a tie the spot that arrived later loses (the busted call may arrive before or after the correct one, but
/// with equal support the first one stays). Own spots (Mark, Store, self-spots) are never busted and never make another
/// call busted.
///
/// Read-time and pure: the buffer keeps every spot, so switching the option off brings them back.
public enum BustedSpots {

    /// Calls shorter than this are never compared (in a 1x1 call such as K1A one character makes another station).
    public static let minimumLength = 4

    /// The upper-case calls to hide.
    /// - Parameters:
    ///   - spots: the live spots in arrival order (`SpotBuffer.snapshot()`)
    ///   - reports: how many times the call was reported (spots and skimmers)
    ///   - toleranceHz: the tuning tolerance of the spot's mode
    ///   - twoCharacters: also two-character differences
    public static func busted(_ spots: [DxSpot], reports: (String) -> Int, toleranceHz: (DxSpot) -> Int,
                              twoCharacters: Bool) -> Set<String> {
        let maxDistance: Int = twoCharacters ? 2 : 1
        let candidates: [(order: Int, spot: DxSpot, call: String)] = spots.enumerated().compactMap { index, spot in
            let call: String = JavaText.trim(spot.dxCall).uppercased()
            guard !spot.selfSpotted, call.count >= minimumLength else { return nil }
            return (index, spot, call)
        }
        let byFrequency = candidates.sorted { $0.spot.freqHz != $1.spot.freqHz
            ? $0.spot.freqHz < $1.spot.freqHz : $0.order < $1.order }
        let maxTolerance: Int = byFrequency.map { toleranceHz($0.spot) }.max() ?? 0
        var out: Set<String> = []
        for i in byFrequency.indices {
            let a = byFrequency[i]
            var j: Int = i + 1
            while j < byFrequency.count, byFrequency[j].spot.freqHz - a.spot.freqHz <= maxTolerance {
                let b = byFrequency[j]
                j += 1
                guard a.call != b.call else { continue }
                let tolerance: Int = Swift.min(toleranceHz(a.spot), toleranceHz(b.spot))
                guard b.spot.freqHz - a.spot.freqHz <= tolerance,
                      distance(a.call, b.call, limit: maxDistance) <= maxDistance else { continue }
                let reportsA: Int = reports(a.call)
                let reportsB: Int = reports(b.call)
                let loser: String
                if reportsA != reportsB {
                    loser = reportsA < reportsB ? a.call : b.call
                } else {
                    loser = a.order > b.order ? a.call : b.call
                }
                out.insert(loser)
            }
        }
        return out
    }

    /// The edit distance (substitution, insertion, deletion) of two calls, or `limit + 1` once it exceeds `limit`.
    public static func distance(_ a: String, _ b: String, limit: Int) -> Int {
        let x: [Character] = Array(a)
        let y: [Character] = Array(b)
        if abs(x.count - y.count) > limit { return limit + 1 }
        var previous: [Int] = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var current: [Int] = [i] + Array(repeating: 0, count: y.count)
            var rowMin: Int = current[0]
            for k in stride(from: 1, through: y.count, by: 1) {
                let cost: Int = x[i - 1] == y[k - 1] ? 0 : 1
                current[k] = Swift.min(previous[k] + 1, current[k - 1] + 1, previous[k - 1] + cost)
                rowMin = Swift.min(rowMin, current[k])
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return Swift.min(previous[y.count], limit + 1)
    }
}
