import Foundation
import Testing
@testable import MCLCore

/// Port of `WsjtxDecodeTest.java` (4 tests; `listenerDeliversDecodeWithSenderAddress` = UDP in both directions via
/// `WsjtxListener`, tested elsewhere).
@Suite(.ioSafetyNet) struct WsjtxDecodeTests {

    static let decode = WsjtxMessages.Decode(
        id: "WSJT-X", isNew: true, timeMs: 12 * 3_600_000 + 15_000, snr: -12, deltaTime: 0.2, deltaFrequency: 1234,
        mode: "~", message: "CQ DX K1ABC FN42", lowConfidence: false, offAir: false)

    @Test func listenerDeliversDecodeWithSenderAddress() async throws {
        let got = Inbox<UdpEndpoint>()
        let decoded = Inbox<WsjtxMessages.Decode>()
        let handler = WsjtxListener.Handler(onLoggedAdif: { _ in }, onDecode: { d, from in
            decoded.offer(d)
            got.offer(from)
        })
        let listener = try WsjtxListener(bindHost: "127.0.0.1", bindPort: 0, handler: handler)
        defer { listener.close() }
        let wsjtx = UdpTestSocket()
        listener.start()
        wsjtx.send(WsjtxMessages.encodeDecode(Self.decode), toPort: listener.boundPort)
        #expect(await onOwnThread { decoded.take() } == Self.decode)
        let from: UdpEndpoint = try #require(await onOwnThread { got.take() })
        #expect(from.port == wsjtx.port)

        // the reply comes back to the WSJT-X socket
        try listener.send(WsjtxMessages.encodeReply(Self.decode, modifiers: 0), to: from)
        let reply = await onOwnThread { wsjtx.receive() }
        #expect((reply?.bytes.count ?? 0) > 20)
    }

    @Test func decodeRoundTrip() throws {
        let m = try WsjtxMessages.decode(WsjtxMessages.encodeDecode(Self.decode))
        #expect(m == .decode(Self.decode))
    }

    @Test func replyCarriesDecodeFields() throws {
        let r: [UInt8] = WsjtxMessages.encodeReply(Self.decode, modifiers: 0)
        var input = WsjtxDataInput(r)
        #expect(try input.readInt() == WsjtxProtocol.magic)
        _ = try input.readInt()
        #expect(try input.readInt() == WsjtxProtocol.reply)
        #expect(try WsjtxCodec.readString(&input) == "WSJT-X")
        #expect(try input.readInt() == Self.decode.timeMs)
        #expect(try input.readInt() == -12)
        #expect(try input.readDouble() == 0.2)
        #expect(try input.readInt() == 1234)
        #expect(try WsjtxCodec.readString(&input) == "~")
        #expect(try WsjtxCodec.readString(&input) == "CQ DX K1ABC FN42")
        #expect(try input.readBoolean() == false)
        #expect(try input.readUnsignedByte() == 0)
    }

    @Test func parsesFt8Messages() {
        #expect(Ft8Message.parse("CQ DX K1ABC FN42") == Ft8Message(caller: "K1ABC", target: "", cq: true, grid: "FN42"))
        #expect(Ft8Message.parse("CQ K1ABC FN42") == Ft8Message(caller: "K1ABC", target: "", cq: true, grid: "FN42"))
        #expect(Ft8Message.parse("CQ TEST OK1XOE") == Ft8Message(caller: "OK1XOE", target: "", cq: true, grid: ""))
        #expect(Ft8Message.parse("OK1XOE K1ABC -12") == Ft8Message(caller: "K1ABC", target: "OK1XOE", cq: false, grid: ""))
        #expect(Ft8Message.parse("OK1XOE <K1ABC> RR73")
            == Ft8Message(caller: "K1ABC", target: "OK1XOE", cq: false, grid: ""))
        #expect(Ft8Message.parse("K1ABC DL1ABC JO62")
            == Ft8Message(caller: "DL1ABC", target: "K1ABC", cq: false, grid: "JO62"))
    }
}
