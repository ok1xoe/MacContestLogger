import Foundation

/// UDP broadcast settings (N1MM format). Per type: enabled + targets "host:port …".
/// Mirrors `BroadcastConfig.java`.
public struct BroadcastConfig: Codable, Equatable, Sendable {
    public var contactsEnabled: Bool = false
    public var contactsTargets: String = ""
    public var radioEnabled: Bool = false
    public var radioTargets: String = ""
    public var scoreEnabled: Bool = false
    public var scoreTargets: String = ""
    public var appInfoEnabled: Bool = false
    public var appInfoTargets: String = ""

    enum CodingKeys: String, CodingKey {
        case contactsEnabled, contactsTargets, radioEnabled, radioTargets
        case scoreEnabled, scoreTargets, appInfoEnabled, appInfoTargets
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BroadcastConfig()
        contactsEnabled = c.value(.contactsEnabled, default: d.contactsEnabled)
        contactsTargets = c.value(.contactsTargets, default: d.contactsTargets)
        radioEnabled = c.value(.radioEnabled, default: d.radioEnabled)
        radioTargets = c.value(.radioTargets, default: d.radioTargets)
        scoreEnabled = c.value(.scoreEnabled, default: d.scoreEnabled)
        scoreTargets = c.value(.scoreTargets, default: d.scoreTargets)
        appInfoEnabled = c.value(.appInfoEnabled, default: d.appInfoEnabled)
        appInfoTargets = c.value(.appInfoTargets, default: d.appInfoTargets)
    }
}
