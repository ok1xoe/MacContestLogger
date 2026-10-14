import Foundation

/// Settings for receiving bare ADIF over UDP (QSO import from fldigi etc.). Mirrors
/// `AdifUdpConfig.java`.
public struct AdifUdpConfig: Codable, Equatable, Sendable {
    public var receiveEnabled: Bool = false
    public var receiveBind: String = "0.0.0.0:2333"

    /// Share the receive port with other applications (`SO_REUSEADDR`/`SO_REUSEPORT` on a unicast bind, N1MM's
    /// shared UDP port): every application on the port gets broadcast datagrams. Swift-only key.
    public var sharePort: Bool = false

    enum CodingKeys: String, CodingKey { case receiveEnabled, receiveBind, sharePort }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdifUdpConfig()
        receiveEnabled = c.value(.receiveEnabled, default: d.receiveEnabled)
        receiveBind = c.value(.receiveBind, default: d.receiveBind)
        sharePort = c.value(.sharePort, default: d.sharePort)
    }
}
