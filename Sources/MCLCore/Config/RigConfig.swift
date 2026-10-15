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

    // N1MM per-radio options (Swift-only keys)
    /// N1MM „Icom Addr (hex)": the rig's CI-V address without the `H` suffix (`94`); empty = hamlib's default.
    /// Passed to a `rigctld` the app starts as `civaddr`.
    public var civAddress: String = ""
    /// N1MM „Radio polling rate": normal, 50 % or 100 % slower.
    public var pollRate: PollRate = .normal
    /// N1MM „Use Reverse CW": the rig is put into CW-R instead of CW whenever the app selects CW.
    public var reverseCw: Bool = false
    /// N1MM „Mute mic on supported radios": the rig's microphone gain is set to 0 while a voice message keys it
    /// over CAT and restored afterwards (hamlib `MICGAIN`; opt-in).
    public var muteMicOnVoice: Bool = false
    /// N1MM „Sub receiver always on": hamlib `DUAL_WATCH` is switched on whenever the rig connects.
    public var subReceiverOn: Bool = false
    /// N1MM band map „Transceiver timeout": seconds without contact with the rig before the band map shows the
    /// radio problem alert; 0 = no alert.
    public var timeoutSeconds: Int = 15

    enum CodingKeys: String, CodingKey {
        case mode, model, modelLabel, device, baud, host, port
        case dataBits, stopBits, parity, flowControl, dtr, rts
        case civAddress, pollRate, reverseCw, muteMicOnVoice, subReceiverOn, timeoutSeconds
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
        civAddress = c.value(.civAddress, default: d.civAddress)
        pollRate = c.value(.pollRate, default: d.pollRate)
        reverseCw = c.value(.reverseCw, default: d.reverseCw)
        muteMicOnVoice = c.value(.muteMicOnVoice, default: d.muteMicOnVoice)
        subReceiverOn = c.value(.subReceiverOn, default: d.subReceiverOn)
        timeoutSeconds = c.value(.timeoutSeconds, default: d.timeoutSeconds)
    }

    /// The CI-V address as hamlib takes it (`0x94`), `nil` when empty or not a hex byte. Accepts `94`, `94H`,
    /// `0x94` in any case.
    public var civAddressHamlib: String? {
        Self.civAddressHamlib(civAddress)
    }

    public static func civAddressHamlib(_ text: String) -> String? {
        var t: String = text.trimmingCharacters(in: .whitespaces).uppercased()
        if t.hasPrefix("0X") { t.removeFirst(2) }
        if t.hasSuffix("H") { t.removeLast() }
        guard (1...2).contains(t.count), let value = UInt8(t, radix: 16) else { return nil }
        return "0x" + String(format: "%02x", value)
    }

    /// The model label names an Icom rig (the CI-V address field is offered for it).
    public var isIcom: Bool {
        modelLabel.range(of: "icom", options: .caseInsensitive) != nil
    }
}

/// N1MM „Radio polling rate": how often the rig is read.
public enum PollRate: String, Codable, Equatable, Sendable, CaseIterable {
    case normal = "NORMAL"
    case slower50 = "SLOWER_50"
    case slower100 = "SLOWER_100"

    /// The poll interval for the base one (50 % slower = 1.5×, 100 % slower = 2×).
    public func interval(base ms: Int64) -> Int64 {
        switch self {
        case .normal: ms
        case .slower50: ms + ms / 2
        case .slower100: ms * 2
        }
    }

    /// The UI label (Czech key, translated by the view).
    public var label: String {
        switch self {
        case .normal: "Normální"
        case .slower50: "O 50 % pomalejší"
        case .slower100: "O 100 % pomalejší"
        }
    }
}
