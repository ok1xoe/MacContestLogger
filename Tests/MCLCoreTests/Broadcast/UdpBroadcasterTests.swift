import Foundation
import Testing
@testable import MCLCore

/// Port of `UdpBroadcasterTest.java` (3 tests). Sending (DNS) from its own thread.
@Suite(.ioSafetyNet) struct UdpBroadcasterTests {

    @Test func sendsUtf8PayloadToTarget() async throws {
        let receiver = UdpTestSocket()
        let b = try UdpBroadcaster()
        defer { b.close() }
        let port = Int32(receiver.port)
        await onOwnThread { b.send("<x>ěš</x>", [Target(host: "127.0.0.1", port: port)]) }
        let p = await onOwnThread { receiver.receive() }
        #expect(p.map { String(decoding: $0.bytes, as: UTF8.self) } == "<x>ěš</x>")
    }

    @Test func badTargetDoesNotThrow() async throws {
        let b = try UdpBroadcaster()
        defer { b.close() }
        // Swift `send` no longer throws by type; it is verified that it returns (an error goes only to the log).
        await onOwnThread { b.send("<x/>", [Target(host: "no.such.host.invalid.", port: 12_060)]) }
    }

    @Test func sendsRawBytesToLoopback() async throws {
        let rx = UdpTestSocket()
        let b = try UdpBroadcaster()
        defer { b.close() }
        let payload: [UInt8] = [1, 2, 3, 4]
        let port = Int32(rx.port)
        await onOwnThread { b.send(payload, [Target(host: "127.0.0.1", port: port)]) }
        #expect(await onOwnThread { rx.receive() }?.bytes == payload)
    }
}
