import Testing
@testable import MCLCore

/// Port of `cat/RigctldPortTest` (3 tests) + `port.*` rows of the `ProbeRigctld` probe. Only 127.0.0.1 and its own
/// listener; a "free" port is the port of a released listener, invalid inputs do not connect at all.
@Suite(.ioSafetyNet) struct RigctldPortTests {

    @Test func occupiedPortIsDetected() async throws {
        let server = try LoopbackListener(name: "port-test") { _ in }
        defer { server.stop() }
        let port = server.port
        #expect(await onOwnThread { RigctldPort.isListening(host: "localhost", port: port) })
    }

    @Test func freePortIsNotReportedAsOccupied() async throws {
        let free = FreeLoopbackPort.take() // socket closed → port is free
        #expect(await onOwnThread { RigctldPort.isListening(host: "localhost", port: free) } == false)
    }

    /// Java has port 4532 here; here 4600, so that not even DNS with a wildcard / search domain could lead
    /// to a connection to the port of a shared `rigctld` (intent of the test — invalid host/port — unchanged).
    @Test func invalidHostOrPortReturnsFalse() async {
        let results: [Bool] = await onOwnThread {
            [
                RigctldPort.isListening(host: "localhost", port: 0),
                RigctldPort.isListening(host: "", port: 4600),
                RigctldPort.isListening(host: nil, port: 4600),
                RigctldPort.isListening(host: "host.ktery.neexistuje.invalid", port: 4600),
            ]
        }
        #expect(results == [false, false, false, false])
    }

    /// `port.*`: whitespace, port out of range, unknown host; listener via `localhost` and `127.0.0.1`.
    @Test func measuredRows() async throws {
        let server = try LoopbackListener(name: "port-test") { _ in }
        defer { server.stop() }
        let listening = server.port
        let free = FreeLoopbackPort.take()
        let rows: [(String, Bool)] = await onOwnThread {
            [
                ("port.free", RigctldPort.isListening(host: "localhost", port: free)),
                ("port.blank", RigctldPort.isListening(host: " \t", port: 4600)),
                ("port.max", RigctldPort.isListening(host: "localhost", port: 65_536)),
                ("port.neg", RigctldPort.isListening(host: "localhost", port: -1)),
                ("port.invalid", RigctldPort.isListening(host: "rig.neexistuje.invalid", port: 4600)),
                ("port.listening", RigctldPort.isListening(host: "localhost", port: listening)),
                ("port.listening127", RigctldPort.isListening(host: "127.0.0.1", port: listening)),
            ]
        }
        for (key, value) in rows {
            #expect(String(value) == RigctldProbeRows.rows[key], "\(key)")
        }
    }
}
