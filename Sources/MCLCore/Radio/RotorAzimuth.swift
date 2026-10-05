/// Rotator azimuth and texts of v1.1.1 (`AppState.azimuthTo` `AS:800-806`, `turnRotorTo`/`turnRotorToCall`/`stopRotor`
/// and the 2 s poll status `AS:667-763`).
public enum RotorAzimuth {

    /// `azimuthTo(call)`: `nil` for a blank call, a station grid without a centre, an unknown entity or one without
    /// coordinates; otherwise `Math.round(GreatCircle.bearingDeg(...)).toInt()` (so 360 is possible).
    public static func to(call: String, grid: String?, dxcc: (any DxccLookup)?) -> Int? {
        if KotlinStrings.isBlank(call) { return nil }
        return GreatCircle.azimuth(from: Maidenhead.centerLatLon(grid), toCall: call, dxcc: dxcc)
    }

    /// `turnRotorToCall`: the call from the field, otherwise the last QSO's (`call.ifBlank { qsos.lastOrNull()?.call.orEmpty() }`).
    public static func target(call: String, lastQsoCall: String?) -> String {
        KotlinStrings.isBlank(call) ? (lastQsoCall ?? "") : call
    }

    /// The azimuth to turn to: the short path, or `RotctldClient.longPath` (Ctrl+Alt+J).
    public static func heading(_ azimuth: Int, longPath: Bool) -> Double {
        longPath ? RotctldClient.longPath(Double(azimuth)) : Double(azimuth)
    }

    /// The whole degrees in the texts: `RotctldClient.normalize(azimuth).toInt()` (truncation, NaN → 0).
    public static func degrees(_ azimuth: Double) -> Int {
        Int(JavaMath.d2i(RotctldClient.normalize(azimuth)))
    }

    /// The band of the N1MM rotor UDP message: `currentBand?.let { (it.lowHz() / 1_000_000).toInt() } ?: 0`.
    public static func udpBandMhz(_ band: Band?) -> Int {
        guard let band else { return 0 }
        return band.lowHz / 1_000_000
    }

    // MARK: - texts

    /// The default status before the first poll (`rotatorStatus` getter).
    public static let notConfigured = EntryStatus.tr("Rotátor nenastaven")

    /// The 2 s poll status: no host / no azimuth / connected.
    public static func pollStatus(host: String, port: Int, azimuth: Double?) -> EntryStatus {
        if KotlinStrings.isBlank(host) {
            return .tr("Rotátor nenastaven (Nastavení → Antennas)")
        }
        guard azimuth != nil else {
            return .tr("Rotátor nedostupný (%s:%s)", .string(host), .int(port))
        }
        return .tr("Rotátor %s:%s", .string(host), .int(port))
    }

    /// Only UDP is configured: `tr("Rotátor (UDP) → %s°", normalize(az).toInt())`.
    public static func udpTurned(_ azimuth: Double) -> EntryStatus {
        .tr("Rotátor (UDP) → %s°", .int(degrees(azimuth)))
    }

    /// rotctld turned: `tr("Rotátor → %s°", normalize(az).toInt())`.
    public static func turned(_ azimuth: Double) -> EntryStatus {
        .tr("Rotátor → %s°", .int(degrees(azimuth)))
    }

    /// The message of the error thrown when there is no rotctld client (`error(tr(...))`).
    public static let noClient = "rotátor není nastavený nebo dostupný"

    /// A rotctld failure (turn or stop): `tr("Rotátor: %s", it.message)`.
    public static func failure(_ message: String?) -> EntryStatus {
        .tr("Rotátor: %s", .string(message))
    }

    /// `turnRotorToCall` without an azimuth.
    public static func unknownAzimuth(_ target: String) -> EntryStatus {
        .tr("Rotátor: azimut k „%s“ neznám (chybí lokátor stanice nebo země)", .string(target))
    }

    /// `sendRotorUdp` failure.
    public static func udpFailure(_ message: String?) -> EntryStatus {
        .tr("Rotátor UDP: %s", .string(message))
    }

    public static let udpStopped = EntryStatus.tr("Rotátor (UDP) zastaven")
    public static let stopped = EntryStatus.tr("Rotátor zastaven")
}
