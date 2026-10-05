import Foundation

/// Prevents a double import of the same QSO (repeated datagram / re-log in WSJT-X) — port of
/// `wsjtx/WsjtxDedup.java` (v1.1.1).
///
/// As in Java: callsign `equalsIgnoreCase` (by UTF-16), band `==` (both `nil` = match), the difference
/// `Duration.between(...).getSeconds()` (truncated toward −∞; `Double` noise in `Date` is tolerated as
/// in `WsjtxCodec.epochMillis`) in absolute value `<= windowSeconds`.
/// The callsign is non-optional in Swift (a deliberate divergence from Java v1.1.1): Java `null` (the QSO is skipped)
/// has no counterpart here, `""` behaves like Java `""`.
public enum WsjtxDedup {

    public static func isDuplicate(_ existing: [Qso], _ incoming: Qso, windowSeconds: Int64) -> Bool {
        guard let incomingTime = incoming.timestampUtc else { return false }
        for q in existing {
            guard let time = q.timestampUtc else { continue }
            let sameCall: Bool = JavaChar.equalsIgnoreCase(incoming.call, q.call)
            let sameBand: Bool = incoming.band == q.band
            let between: Double = incomingTime.timeIntervalSince(time)
            let seconds: Double = WsjtxCodec.floorIgnoringNoise(between, minimumTolerance: 0.000_000_5)
            let diff: Int64 = JavaMath.abs(WsjtxCodec.saturated(seconds))
            if sameCall && sameBand && diff <= windowSeconds {
                return true
            }
        }
        return false
    }
}
