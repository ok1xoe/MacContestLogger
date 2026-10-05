import Foundation

/// One record of an established contact. Created gradually during entry and can be edited
/// in the logbook window. Besides the basic fields it carries contest data (exchange, serial number,
/// points, multiplier), fields derived via the DXCC resolver and fields for network replication.
public struct Qso: Equatable, Sendable {

    /// `nil` until saved.
    public var id: Int64?
    public var timestampUtc: Date?

    /// Always trimmed and upper-case.
    ///
    /// The trim is **Java `trim()`** (`JavaText.trim`), not Swift
    /// `.whitespacesAndNewlines` — they are different character sets and whether the QSO gets a country
    /// depends on that difference. Measured on Java v1.1.1:
    /// - `\u{00A0}OK1XOE` (no-break space — comes from cluster spots and the web)
    ///   stays with it, so the DXCC resolver **does not resolve** it and the QSO goes out without a
    ///   country. A Swift trim would drop it and we would write 503 / Czech
    ///   Republic / EU where Java writes nothing. The same holds for U+2007
    ///   and U+202F.
    /// - `\u{0001}OK1XOE` (a control character) on the contrary **must** be trimmed — `trim()`
    ///   drops everything ≤ U+0020, a Swift trim leaves control characters in the value,
    ///   and it would then even be stored in the logbook.
    public var call: String = "" {
        didSet {
            let normalized = JavaText.trim(call).uppercased()
            if normalized != call { call = normalized }
        }
    }

    /// Setting the frequency derives the band; outside an amateur segment the band stays unchanged.
    public var freqHz: Int = 0 {
        didSet {
            if let derived = Band.from(frequencyHz: freqHz) { band = derived }
        }
    }

    public var band: Band?
    public var mode: Mode?

    public var rstSent: String = ""
    public var rstRcvd: String = ""
    public var exchangeSent: String = ""
    public var exchangeRcvd: String = ""
    public var serialSent: Int?
    public var serialRcvd: Int?

    public var points: Int = 0
    public var multiplier: Bool = false
    public var runMode: RunMode = .run

    public var `operator`: String = ""
    public var comment: String = ""

    // Derived fields (DXCC resolver) — filled in when logging.
    public var dxccEntity: Int?
    public var dxccName: String = ""
    public var continent: String = ""

    // Fields for network replication (cluster sync). Unused in single-station mode.
    /// Global merge key across the cluster.
    public var uuid: String = ""
    /// Stable identifier of the logging station.
    public var stationId: String = ""
    /// Monotonic version assigned by the server (LWW).
    public var version: Int64 = 0
    /// Time of the last change (decides at an equal version).
    public var updatedAtUtc: Date?
    /// Tombstone flag.
    public var deleted: Bool = false
    /// X-QSO: in the logbook, but not counted in the score (Cabrillo `X-QSO:`).
    public var xqso: Bool = false

    /// Which contest the QSO belongs to. Local partitioning, not synchronised.
    public var contestId: String = ""

    /// Origin of the QSO on import from the network (WSJT-X / N1MM). Not persisted — prevents an echo,
    /// so that an imported QSO is not sent back.
    public var imported: Bool = false

    public init() {}
}
