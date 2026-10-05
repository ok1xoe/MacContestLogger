import Foundation

/// Transceiver connection parameters (CAT). Mirrors `RigConfig.java`.
///
/// - `mode`: start rigctld from the app, or connect to a running one.
/// - `model`: hamlib rig model number (from `rigctl -l`); 1 = Hamlib Dummy.
/// - `modelLabel`: readable model description for the UI.
/// - `device`: serial port (e.g. `/dev/cu.usbserial-XXXX`); empty for dummy/network rigs.
/// - `baud`: serial port baud rate.
/// - `host`/`port`: rigctld address (`host` is used only in `.connectRunning` mode).
///
/// Note: contrary to what this task's plan suggested, the Java original
/// carries no antenna or transverter lists — those (`antennas`, `transverters`)
/// are own fields of the root `AppConfig`, not of `RigConfig` (see `AppConfig`).
public struct RigConfig: Codable, Equatable, Sendable {
    public var mode: ConnectionMode = .launchDaemon
    public var model: Int = 1
    public var modelLabel: String = "1 — Hamlib Dummy"
    public var device: String = ""
    public var baud: Int = 9600
    public var host: String = "localhost"
    public var port: Int = 4532

    // Serial line parameters (applied when rigctld is started from the app)
    public var dataBits: Int = 8
    public var stopBits: Int = 1
    public var parity: SerialParity = .none
    public var flowControl: FlowControl = .auto
    public var dtr: PinState = .unset
    public var rts: PinState = .unset

    enum CodingKeys: String, CodingKey {
        case mode, model, modelLabel, device, baud, host, port
        case dataBits, stopBits, parity, flowControl, dtr, rts
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RigConfig()
        mode = c.value(.mode, default: d.mode)
        model = c.value(.model, default: d.model)
        modelLabel = c.value(.modelLabel, default: d.modelLabel)
        device = c.value(.device, default: d.device)
        baud = c.value(.baud, default: d.baud)
        host = c.value(.host, default: d.host)
        port = c.value(.port, default: d.port)
        dataBits = c.value(.dataBits, default: d.dataBits)
        stopBits = c.value(.stopBits, default: d.stopBits)
        parity = c.value(.parity, default: d.parity)
        flowControl = c.value(.flowControl, default: d.flowControl)
        dtr = c.value(.dtr, default: d.dtr)
        rts = c.value(.rts, default: d.rts)
    }
}
