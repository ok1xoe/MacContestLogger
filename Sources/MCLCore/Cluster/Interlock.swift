import Foundation

/// TX interlock (N1MM "Interlock", DXLog "Interlock and inband operation"): while
/// another station of the network log transmits, this one does not — either at all (one signal
/// in the category), or only on the same band (inband). Mirrors the Java `cluster.Interlock`
/// (`final class` with a private constructor — a stateless utility, hence a caseless enum,
/// the same pattern as `AppPaths`/`WindowPlacement`).
public enum Interlock {

    /// Interlock scope: nothing (`NONE`), the whole category (`ALL`), or only the same
    /// band (`SAME_BAND`). Mirrors `cluster.Interlock.Scope` — no `@JsonValue`
    /// annotation in Java, so Jackson serialises by constant name.
    public enum Scope: String, Codable, Equatable, Sendable {
        case none = "NONE"
        case all = "ALL"
        case sameBand = "SAME_BAND"
    }

    /// The station that blocks transmitting, or `nil` = may transmit (`lockedBy(peers, scope, myBand)`).
    /// The first peer in list order that is online and transmitting blocks — always for `ALL`, for `SAME_BAND` only
    /// with a band equal to `myBand` ignoring case (`equalsIgnoreCase`; an empty or blank
    /// `myBand` blocks nothing). Java returns `Optional.of(stationId)`; a `null` ID would be a
    /// `NullPointerException` there, but `StationNetwork` never records peers without an ID.
    public static func lockedBy(_ peers: [StationNetwork.Peer], _ scope: Scope?, _ myBand: String?) -> String? {
        guard let scope, scope != .none else { return nil }
        for p in peers {
            guard p.online, p.status.transmitting else { continue }
            if scope == .all {
                return p.status.stationId
            }
            if let myBand, !JavaText.isBlank(myBand), JavaChar.equalsIgnoreCase(myBand, p.status.band) {
                return p.status.stationId
            }
        }
        return nil
    }
}
