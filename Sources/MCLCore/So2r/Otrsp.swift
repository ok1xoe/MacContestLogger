/// SO2R controller via the OTRSP protocol (Java `so2r/Otrsp`; SO2RDuino, YCCC SO2R Box+, microHAM in OTRSP
/// mode): text commands terminated by CR on a 9600 8N1 serial line.
/// - `TX1`/`TX2` — which rig transmits (key, microphone, PTT),
/// - `RX1`/`RX2` — headphones mono from rig 1/2, `RX1S`/`RX2S` stereo,
/// - `AUX1n`/`AUX2n` — BCD output for the antenna switch / band decoder.
///
/// Over a `sink` (command without CR) or over a serial port (`open`: 9600 8N1, command + `\r` in US-ASCII,
/// a write error is ignored like Java `writeBytes`, the write blocks the caller). Validation
/// happens before anything is sent (`rx(0)` throws and sends nothing; for `aux` the value is checked before the
/// rig); `focus` sends `TX`, then `RX`.
public final class Otrsp: Sendable {

    private let sink: @Sendable (String) -> Void
    private let closer: @Sendable () throws -> Void

    /// For tests and other transports: commands go to `sink`.
    public init(sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
        self.closer = {}
    }

    init(sink: @escaping @Sendable (String) -> Void, closer: @escaping @Sendable () throws -> Void) {
        self.sink = sink
        self.closer = closer
    }

    /// Opens the controller on a serial port (Java `open(portPath)`, 9600 8N1).
    ///
    /// - Throws: `SerialPortInvalidPortError` (path does not exist — Java `getCommPort`),
    ///   `JavaIOError("OTRSP: nelze otevřít port <portPath>")` (opening failed).
    public static func open(portPath: String) throws -> Otrsp {
        try open(portPath: portPath, modem: SerialPort.PosixModemControl())
    }

    /// Line setup (Java `setComPortParameters(9600, 8, ONE_STOP_BIT, NO_PARITY)`).
    static let serialSettings = SerialPort.Settings(baud: 9_600, dataBits: 8, stopBits: 1, parity: .none)

    /// For tests: replacement for the modem lines (a pseudoterminal does not support them).
    static func open(portPath: String, modem: any SerialPort.ModemControl) throws -> Otrsp {
        guard let port = try SerialPort.openLikeJSerialComm(portPath: portPath, settings: serialSettings, modem: modem) else {
            throw JavaIOError("OTRSP: nelze otevřít port " + portPath)
        }
        return Otrsp(sink: { command in
            try? port.write(LineSocket.encodeAscii(command + "\r"))
        }, closer: {
            try port.close()
        })
    }

    /// Transmit on rig 1 or 2.
    public func tx(_ radio: Int32) throws(JavaIllegalArgumentError) {
        sink("TX" + String(try Self.check(radio)))
    }

    /// Listen to rig `radio`; stereo = both rigs (each in one ear).
    public func rx(_ radio: Int32, stereo: Bool) throws(JavaIllegalArgumentError) {
        sink("RX" + String(try Self.check(radio)) + (stereo ? "S" : ""))
    }

    /// Focus on a rig: transmit and listen.
    public func focus(_ radio: Int32, stereo: Bool) throws(JavaIllegalArgumentError) {
        try tx(radio)
        try rx(radio, stereo: stereo)
    }

    /// BCD value for the antenna switch / band decoder of rig `radio` (0–15).
    public func aux(_ radio: Int32, value: Int32) throws(JavaIllegalArgumentError) {
        if value < 0 || value > 15 {
            throw JavaIllegalArgumentError(message: "AUX hodnota 0\u{2013}15: " + String(value))
        }
        sink("AUX" + String(try Self.check(radio)) + String(value))
    }

    private static func check(_ radio: Int32) throws(JavaIllegalArgumentError) -> Int32 {
        if radio != 1 && radio != 2 {
            throw JavaIllegalArgumentError(message: "Rig 1 nebo 2: " + String(radio))
        }
        return radio
    }

    public func close() {
        try? closer()
    }
}
