// Vendored from RYRY (https://github.com/ok1xoe/RYRY). Copyright 2026 OK1XOE, GNU LGPL v3 (third-party/MMTTY/NOTICE.md).
/// Modem mode (e.g. RTTY-45) including the ADIF designation for the log.
public struct ModeDescriptor: Sendable, Hashable, Codable {
    public let id: String
    public let displayName: String
    public let adifMode: String
    public let adifSubmode: String?

    public init(id: String, displayName: String, adifMode: String, adifSubmode: String? = nil) {
        self.id = id; self.displayName = displayName
        self.adifMode = adifMode; self.adifSubmode = adifSubmode
    }
}
