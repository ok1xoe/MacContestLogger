import Foundation

/// Club Log Live Stream: login and enabling (N1MM / DXLog Club Log real-time).
/// Mirrors `ClubLogConfig.java`.
public struct ClubLogConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var email: String = ""
    /// Application password from Club Log → Settings → App Passwords (not the account password).
    public var appPassword: String = ""
    /// Logbook callsign on Club Log; empty = the station callsign.
    public var callsign: String = ""
    /// Application API key (Club Log issues it to developers / on request).
    public var apiKey: String = ""

    enum CodingKeys: String, CodingKey { case enabled, email, appPassword, callsign, apiKey }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClubLogConfig()
        enabled = c.value(.enabled, default: d.enabled)
        email = c.value(.email, default: d.email)
        appPassword = c.value(.appPassword, default: d.appPassword)
        callsign = c.value(.callsign, default: d.callsign)
        apiKey = c.value(.apiKey, default: d.apiKey)
    }

    /// Is everything needed to send to Club Log Live Stream filled in?
    public func configured() -> Bool {
        // Java `isBlank()`.
        enabled && !JavaText.isBlank(email) && !JavaText.isBlank(appPassword) && !JavaText.isBlank(apiKey)
    }
}
