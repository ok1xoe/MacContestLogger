/// Rotator control via the N1MM Rotor UDP protocol (Java `rotator/N1mmRotorUdp`; PstRotator, ARSVCOM,
/// default port 12040): `<N1MMRotor>` XML messages with a target azimuth (`goazi`) or a stop (`stop`).
/// Sending is one UDP datagram with the UTF-8 bytes of the message (`UdpSender`, Java `DatagramSocket.send`).
///
/// As in Java: `goazi` is `%.1f` of `RotctldClient.normalize` (`-30` → `330.0`, `-0.0` → `-0.0`, `NaN`),
/// the rotator name is escaped only for `& < >`, `nil` → empty.
public enum N1mmRotorUdp {

    public static let defaultPort: Int32 = 12040

    /// "Turn to azimuth" message for rotator `rotor` (band in MHz, 0 = unknown).
    public static func turnMessage(rotor: String?, azimuth: Double, bandMhz: Int32) -> String {
        JavaFormat.format(
            "<N1MMRotor><rotor>%s</rotor><goazi>%.1f</goazi><offset>0</offset><bidirectional>0</bidirectional>"
                + "<freqband>%d</freqband></N1MMRotor>",
            .string(esc(rotor)), .double(RotctldClient.normalize(azimuth)), .int(Int(bandMhz)))
    }

    public static func stopMessage(rotor: String?) -> String {
        "<N1MMRotor><stop>" + esc(rotor) + "</stop></N1MMRotor>"
    }

    /// Sends the message as a UDP datagram (Java `send(host, port, message)`: `getBytes(UTF_8)`, `DatagramSocket`).
    /// Errors as Java (`JavaSocketError`, `JavaIllegalArgumentError`; probe `radio-io/`, rows `udp.*`).
    /// Blocking (DNS) — call from your own thread.
    public static func send(host: String?, port: Int, message: String) throws {
        try UdpSender.send(Array(message.utf8), host: host, port: port)
    }

    private static func esc(_ text: String?) -> String {
        guard let text else { return "" }
        return XmlRpc.escape(text)
    }
}
