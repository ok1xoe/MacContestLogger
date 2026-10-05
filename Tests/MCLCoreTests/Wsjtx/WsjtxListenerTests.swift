import Foundation
import Testing
@testable import MCLCore

/// Port of `WsjtxListenerTest.java` (2 tests). Only 127.0.0.1; waiting for the handler from its own thread.
///
/// For a dropped datagram Java waits 500 ms for `null`. Here deterministically: after a bad datagram
/// a valid one goes out from the same socket and the handler must receive the valid one as the **first** (UDP over loopback
/// from one socket to one socket keeps order).
@Suite(.ioSafetyNet) struct WsjtxListenerTests {

    @Test func deliversLoggedAdifToHandler() async throws {
        let received = Inbox<String>()
        let listener = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0,
                                         handler: .init(onLoggedAdif: { received.offer($0 ?? "null") }))
        defer { listener.close() }
        listener.start()
        let port = listener.boundPort
        let msg: [UInt8] = WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: "<call:4>AA5A<eor>"))
        let tx = UdpTestSocket()
        tx.send(msg, toPort: port)
        let adif: String? = await onOwnThread { received.take() }
        #expect(adif == "<call:4>AA5A<eor>")
    }

    @Test func ignoresGarbageDatagram() async throws {
        let received = Inbox<String>()
        let listener = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0,
                                         handler: .init(onLoggedAdif: { received.offer($0 ?? "null") }))
        defer { listener.close() }
        listener.start()
        let port = listener.boundPort
        let tx = UdpTestSocket()
        tx.send([1, 2, 3, 4, 5], toPort: port)
        let marker: [UInt8] = WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: "marker"))
        tx.send(marker, toPort: port)
        let first: String? = await onOwnThread { received.take() }
        #expect(first == "marker", "a bad datagram is dropped")
        #expect(received.count == 0)
    }
}
