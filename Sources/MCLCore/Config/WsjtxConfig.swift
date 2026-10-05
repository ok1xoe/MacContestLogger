import Foundation

/// WSJT-X UDP integration settings: receive (bind) and transmit (targets). Mirrors `WsjtxConfig.java`.
public struct WsjtxConfig: Codable, Equatable, Sendable {
    public var receiveEnabled: Bool = false
    public var receiveBind: String = "0.0.0.0:2237"
    public var sendEnabled: Bool = false
    public var sendTargets: String = ""

    enum CodingKeys: String, CodingKey { case receiveEnabled, receiveBind, sendEnabled, sendTargets }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WsjtxConfig()
        receiveEnabled = c.value(.receiveEnabled, default: d.receiveEnabled)
        receiveBind = c.value(.receiveBind, default: d.receiveBind)
        sendEnabled = c.value(.sendEnabled, default: d.sendEnabled)
        sendTargets = c.value(.sendTargets, default: d.sendTargets)
    }
}
