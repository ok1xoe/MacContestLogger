/// The two online callbooks a call can be looked up on by hand (the entry window's button, the log and band map
/// menus). The raw value is the `preferredCallbook` config key.
public enum CallbookService: String, CaseIterable, Sendable {
    case hamQth = "hamqth"
    case qrz = "qrz"

    /// The service named by a config value; anything unknown is HamQTH (the default).
    public init(configValue: String) {
        self = CallbookService(rawValue: configValue.lowercased()) ?? .hamQth
    }

    /// The name shown on buttons and in menus (a proper name, not translated).
    public var displayName: String {
        switch self {
        case .hamQth: return "HamQTH"
        case .qrz: return "QRZ.com"
        }
    }

    /// The service's page of a call, opened in the browser.
    public func pageURL(call: String) -> String {
        switch self {
        case .hamQth: return "https://www.hamqth.com/" + CallbookPolicy.key(call)
        case .qrz: return "https://www.qrz.com/db/" + CallbookPolicy.key(call)
        }
    }
}
