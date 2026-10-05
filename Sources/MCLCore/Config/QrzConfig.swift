import Foundation

/// Credentials and lookup settings for the QRZ.com XML API (analogous to `HamQthConfig`).
/// Mirrors `QrzConfig.java`.
public struct QrzConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var username: String = ""
    public var password: String = ""
    /// Operating categories (CW/PHONE/DIGI) for which QRZ is called. Empty = for all.
    public var callModes: [String] = ["DIGI"]
    /// Which data from QRZ to use for prediction (grid, cqZone, ituZone, name).
    public var fetchFields: [String] = ["grid", "cqZone", "ituZone", "name"]

    enum CodingKeys: String, CodingKey { case enabled, username, password, callModes, fetchFields }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = QrzConfig()
        enabled = c.value(.enabled, default: d.enabled)
        username = c.value(.username, default: d.username)
        password = c.value(.password, default: d.password)
        callModes = c.value(.callModes, default: d.callModes)
        fetchFields = c.value(.fetchFields, default: d.fetchFields)
    }
}
