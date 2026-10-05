import Foundation

/// ESM – Enter Sends Message (N1MM Config → ESM, Configurer → Function Keys).
public struct EsmConfig: Codable, Equatable, Sendable {
    /// ESM enabled: Enter transmits a message according to the entry window state.
    public var enabled: Bool = false
    /// „Big Gun": in S&P, Enter sends my callsign only once and the cursor goes to the exchange.
    public var spCallOnce: Bool = false
    /// In Run a dupe is worked as a new QSO (N1MM recommends enabled).
    public var workDupes: Bool = true

    enum CodingKeys: String, CodingKey { case enabled, spCallOnce, workDupes }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EsmConfig()
        enabled = c.value(.enabled, default: d.enabled)
        spCallOnce = c.value(.spCallOnce, default: d.spCallOnce)
        workDupes = c.value(.workDupes, default: d.workDupes)
    }
}
