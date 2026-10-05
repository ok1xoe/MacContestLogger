import Testing
@testable import MCLCore

/// `rotator/N1mmRotorUdpTest` (2, same names; `sendsDatagram` to its own UDP receiver on 127.0.0.1)
/// + escaping (`ROT.udp`) + sending against the `radio-io/` probe (rows `udp.*`).
@Suite(.ioSafetyNet) struct N1mmRotorUdpTests {

    @Test func sendsDatagram() async throws {
        let rx = UdpSenderTests.Receiver()
        let port = rx.port
        try await onOwnThread { try N1mmRotorUdp.send(host: "127.0.0.1", port: port, message: N1mmRotorUdp.stopMessage(rotor: "R")) }
        let bytes: [UInt8] = await onOwnThread { rx.receive() }
        #expect(String(decoding: bytes, as: UTF8.self) == "<N1MMRotor><stop>R</stop></N1MMRotor>")
    }

    /// Datagram bytes (UTF-8 including non-BMP, an empty message, `localhost`) and errors like Java.
    @Test func sendMatchesJava() async throws {
        let rx = UdpSenderTests.Receiver()
        let port = rx.port
        let cases: [(String, String?, String)] = [
            ("stop", "127.0.0.1", N1mmRotorUdp.stopMessage(rotor: "R")),
            ("turn", "127.0.0.1", N1mmRotorUdp.turnMessage(rotor: "Yagi \u{17E}\u{1F600} <&>", azimuth: -30, bandMhz: 14)),
            ("empty", "127.0.0.1", ""),
            ("localhost", "localhost", "x"),
        ]
        for (key, host, message) in cases {
            let result: String = await onOwnThread {
                RadioIoProbe.result {
                    try N1mmRotorUdp.send(host: host, port: port, message: message)
                    return RadioIoProbe.hex(rx.receive())
                }
            }
            #expect(result == RadioIoProbe.row("udp." + key), "\(key)")
        }
        let errors: [(String, String?, Int)] = [
            ("port0", "127.0.0.1", 0), ("range", "127.0.0.1", 70_000), ("unknownHost", "rot.neexistuje.invalid", 12_040),
        ]
        for (key, host, target) in errors {
            let result: String = await onOwnThread {
                RadioIoProbe.result {
                    try N1mmRotorUdp.send(host: host, port: target, message: "x")
                    return "ok"
                }
            }
            #expect(RadioIoProbe.esc(result) == RadioIoProbe.row("udp." + key), "\(key)")
        }
    }

    @Test func messages() {
        #expect(N1mmRotorUdp.turnMessage(rotor: "Yagi 20", azimuth: -30, bandMhz: 14)
            == "<N1MMRotor><rotor>Yagi 20</rotor><goazi>330.0</goazi><offset>0</offset>"
            + "<bidirectional>0</bidirectional><freqband>14</freqband></N1MMRotor>")
        #expect(N1mmRotorUdp.stopMessage(rotor: "Yagi 20") == "<N1MMRotor><stop>Yagi 20</stop></N1MMRotor>")
    }

    @Test func escapingMatchesJava() {
        let row = ProbeRows.rows(VoiceAudioMeasured.research, "ROT.udp")[0]
        #expect(N1mmRotorUdp.turnMessage(rotor: "a&b<c>\"'\u{17E}", azimuth: 1.0, bandMhz: 0) == row[0])
        #expect(N1mmRotorUdp.stopMessage(rotor: nil) == row[1])
        #expect(N1mmRotorUdp.defaultPort == 12040)
    }
}
