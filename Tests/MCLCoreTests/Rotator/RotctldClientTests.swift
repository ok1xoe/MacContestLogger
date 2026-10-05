import Testing
@testable import MCLCore

/// `rotator/RotctldClientTest` (2, same names; `turnReadAndStop` over `FakeLineServer` on 127.0.0.1) and the whole
/// table `ROT.normalize`: `normalize`, the command `P %.1f 0`, `longPath`, `(int)`.
/// The conversation against the Java probe is `RotctldClientMeasuredTests`.
@Suite(.ioSafetyNet) struct RotctldClientTests {

    /// Java mock server: `p` → azimuth and elevation, anything else `RPRT 0`.
    @Test func turnReadAndStop() async throws {
        let server = try FakeLineServer(lines: ["p": ["123.500000", "0.000000"]], fallback: ["RPRT 0"])
        defer { server.stop() }
        let port = server.port
        let azimuth: Double = try await onOwnThread {
            let c = try RotctldClient(host: "localhost", port: port)
            defer { c.close() }
            let az = try c.azimuth()
            try c.turnTo(-30)
            try c.stop()
            return az
        }
        #expect(abs(azimuth - 123.5) <= 1e-9)
        // The server records the command on receipt; the client got the last reply only after the write, so it is already there.
        #expect(server.allCommands == ["p", "P 330.0 0", "S"])
    }

    @Test func longPath() {
        #expect(abs(RotctldClient.longPath(45) - 225) <= 1e-9)
        #expect(abs(RotctldClient.longPath(190) - 10) <= 1e-9)
    }

    @Test func normalizeMatchesJava() {
        let rows = ProbeRows.rows(VoiceAudioMeasured.research, "ROT.normalize")
        #expect(rows.count == 19)
        for row in rows {
            let azimuth = JavaDouble.parseDouble(row[0])!
            let normalized = RotctldClient.normalize(azimuth)
            #expect(JavaDouble.toString(normalized) == row[1], "\(row)")
            #expect(RotctldClient.turnCommand(azimuth) == row[2], "\(row)")
            #expect(JavaDouble.toString(RotctldClient.longPath(azimuth)) == row[3], "\(row)")
            #expect(String(JavaMath.d2i(normalized)) == row[4], "\(row)")
            #expect(N1mmRotorUdp.turnMessage(rotor: "R", azimuth: azimuth, bandMhz: 14) == row[5], "\(row)")
        }
    }

    /// Java `-30` → `P 330.0 0` (`RotctldClientTest.turnReadAndStop`, only the command line).
    @Test func turnCommandFormatsLikeJava() {
        #expect(RotctldClient.turnCommand(-30) == "P 330.0 0")
    }
}
