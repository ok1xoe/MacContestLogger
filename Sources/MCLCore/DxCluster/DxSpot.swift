/// Parsed DX spot (one reported station) — Java record `dxcluster.DxSpot`.
/// The receive time is held by `SpotBuffer`, not by the spot itself — a spot is just bare parsed data.
///
/// Created in `DxSpotParser` (cluster lines), `BeaconFile` (beacons) and manually (self-spot);
/// `SpotBuffer.snapshot()` passes it to `SpotNavigator` in insertion order.
public struct DxSpot: Equatable, Hashable, Sendable {
    /// Callsign of the station that sent the spot.
    public let spotter: String
    /// Spot frequency in Hz (Java `long`).
    public let freqHz: Int
    /// Callsign of the spotted (heard) station.
    public let dxCall: String
    /// Free comment from the spot line (without the trailing time).
    public let comment: String
    /// `true` = entered manually by the user (self-spot), `false` = from the DX cluster network.
    public let selfSpotted: Bool

    /// Canonical record constructor; without `selfSpotted` it is the Java network constructor
    /// with four fields (`selfSpotted = false`).
    public init(spotter: String, freqHz: Int, dxCall: String, comment: String, selfSpotted: Bool = false) {
        self.spotter = spotter
        self.freqHz = freqHz
        self.dxCall = dxCall
        self.comment = comment
        self.selfSpotted = selfSpotted
    }

    /// Band derived from the spot frequency (Java `band()`); `nil` outside the bands.
    public var band: Band? {
        Band.from(frequencyHz: freqHz)
    }
}
