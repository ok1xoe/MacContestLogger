import Foundation

/// Settings for receiving N1MM contactinfo (importing QSOs from other loggers over UDP). Mirrors
/// `N1mmRecvConfig.java`.
public struct N1mmRecvConfig: Codable, Equatable, Sendable {
    public var receiveEnabled: Bool = false
    public var receiveBind: String = "0.0.0.0:12061"

    enum CodingKeys: String, CodingKey { case receiveEnabled, receiveBind }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = N1mmRecvConfig()
        receiveEnabled = c.value(.receiveEnabled, default: d.receiveEnabled)
        receiveBind = c.value(.receiveBind, default: d.receiveBind)
    }
}
