import Foundation

/// WSJT-X UDP integration settings: receive (bind) and transmit (targets). Mirrors `WsjtxConfig.java`.
public struct WsjtxConfig: Codable, Equatable, Sendable {
    public var receiveEnabled: Bool = false
    public var receiveBind: String = "0.0.0.0:2237"
    public var sendEnabled: Bool = false
    public var sendTargets: String = ""

    /// N1MM: the decoded callers are coloured in WSJT-X's Band Activity by dupe / multiplier status (HighlightCallsign, message 13). Swift-only key.
    public var highlightCalls: Bool = true
    /// WSJT-X's DX Call goes into the entry window's call field (dupe and multiplier check). Swift-only key.
    public var mirrorDxCall: Bool = true
    /// The decode list is cleared when WSJT-X moves to another band. Swift-only key.
    public var clearDecodesOnBandChange: Bool = true
    /// JTDX „External logbook" over TCP: ADIF records logged by JTDX are received on `jtdxTcpBind`. Swift-only key.
    public var jtdxTcpEnabled: Bool = false
    /// Where JTDX's TCP logbook connection is accepted (`host:port`). Swift-only key.
    public var jtdxTcpBind: String = "127.0.0.1:52001"
    /// WSJT-X / JTDX application (Okno → Spustit WSJT-X / JTDX). Swift-only key.
    public var programPath: String = ""
    /// Extra arguments for the launched program. Swift-only key.
    public var programArgs: String = ""
    /// SO2R: the rig name of the second instance (`--rig-name`, WSJT-X's Id is „WSJT-X - <name>"); its DX Call goes to the VFO B / rig 2 entry window. Swift-only key.
    public var radio2Id: String = ""
    /// Launching WSJT-X / JTDX opens the decode list (N1MM). Swift-only key.
    public var openDecodesOnLaunch: Bool = true

    enum CodingKeys: String, CodingKey {
        case receiveEnabled, receiveBind, sendEnabled, sendTargets
        case highlightCalls, mirrorDxCall, clearDecodesOnBandChange, jtdxTcpEnabled, jtdxTcpBind, programPath
        case programArgs, radio2Id, openDecodesOnLaunch
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WsjtxConfig()
        receiveEnabled = c.value(.receiveEnabled, default: d.receiveEnabled)
        receiveBind = c.value(.receiveBind, default: d.receiveBind)
        sendEnabled = c.value(.sendEnabled, default: d.sendEnabled)
        sendTargets = c.value(.sendTargets, default: d.sendTargets)
        highlightCalls = c.value(.highlightCalls, default: d.highlightCalls)
        mirrorDxCall = c.value(.mirrorDxCall, default: d.mirrorDxCall)
        clearDecodesOnBandChange = c.value(.clearDecodesOnBandChange, default: d.clearDecodesOnBandChange)
        jtdxTcpEnabled = c.value(.jtdxTcpEnabled, default: d.jtdxTcpEnabled)
        jtdxTcpBind = c.value(.jtdxTcpBind, default: d.jtdxTcpBind)
        programPath = c.value(.programPath, default: d.programPath)
        programArgs = c.value(.programArgs, default: d.programArgs)
        radio2Id = c.value(.radio2Id, default: d.radio2Id)
        openDecodesOnLaunch = c.value(.openDecodesOnLaunch, default: d.openDecodesOnLaunch)
    }
}
