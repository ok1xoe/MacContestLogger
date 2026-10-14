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
    /// N1MM „Spots": every cluster spot added to or removed from the band map, with its status. Swift-only key.
    public var spotsEnabled: Bool = false
    public var spotsTargets: String = ""
    /// N1MM „Lookup": the call typed in the entry window when Space/Tab leaves it, before logging. Swift-only key.
    public var lookupEnabled: Bool = false
    public var lookupTargets: String = ""
    /// N1MM „All QSOs": contacts received from other stations (N1MM receive) are forwarded to the contact targets
    /// with `IsOriginal` False. Swift-only key.
    public var allQsosEnabled: Bool = false

    enum CodingKeys: String, CodingKey {
        case contactsEnabled, contactsTargets, radioEnabled, radioTargets
        case scoreEnabled, scoreTargets, appInfoEnabled, appInfoTargets
        case spotsEnabled, spotsTargets, lookupEnabled, lookupTargets, allQsosEnabled
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
        spotsEnabled = c.value(.spotsEnabled, default: d.spotsEnabled)
        spotsTargets = c.value(.spotsTargets, default: d.spotsTargets)
        lookupEnabled = c.value(.lookupEnabled, default: d.lookupEnabled)
        lookupTargets = c.value(.lookupTargets, default: d.lookupTargets)
        allQsosEnabled = c.value(.allQsosEnabled, default: d.allQsosEnabled)
    }
}
