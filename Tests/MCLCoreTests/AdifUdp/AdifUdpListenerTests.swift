import Foundation
import Testing
@testable import MCLCore

/// Port of `AdifUdpListenerTest.java` (2 tests). Dropping is verified by order (see `WsjtxListenerTests`), not
/// by waiting 500 ms.
@Suite(.ioSafetyNet) struct AdifUdpListenerTests {

    private static let fldigi: String = [
        "<CALL:6>II9WWA<MODE:2>CW<FREQ:9>14.028086<BAND:3>20m<QSO_DATE:8>20260703",
        "<TIME_ON:4>1733<RST_SENT:3>599<RST_RCVD:3>599<STX:3>000",
        "<OPERATOR:6>OK1XOE<STATION_CALLSIGN:6>OK1XOE<EOR>",
    ].joined()

    @Test func deliversBareAdif() async throws {
        let received = Inbox<String>()
        let listener = try AdifUdpListener(bindHost: "127.0.0.1", bindPort: 0) { received.offer($0) }
        defer { listener.close() }
        listener.start()
        UdpTestSocket().send(Array(Self.fldigi.utf8), toPort: listener.boundPort)
        let adif: String = try #require(await onOwnThread { received.take() })
        #expect(adif.contains("II9WWA"))
    }

    @Test func ignoresNonAdif() async throws {
        let received = Inbox<String>()
        let listener = try AdifUdpListener(bindHost: "127.0.0.1", bindPort: 0) { received.offer($0) }
        defer { listener.close() }
        listener.start()
        let tx = UdpTestSocket()
        tx.send(Array("hello world".utf8), toPort: listener.boundPort)
        tx.send(Array("<call:1>M<eor>".utf8), toPort: listener.boundPort)
        #expect(await onOwnThread { received.take() } == "<call:1>M<eor>")
        #expect(received.count == 0)
    }
}
