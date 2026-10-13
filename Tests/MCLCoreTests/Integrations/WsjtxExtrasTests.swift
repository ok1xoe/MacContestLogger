import Darwin
import Foundation
@testable import MCLCore
import Testing

/// WSJT-X extras: HighlightCallsign, the decode list's text filter / sort / mode names, the JTDX TCP logbook receiver
/// (loopback, ephemeral port) and the modes Q65 and FT2.
@Suite struct WsjtxExtrasTests {

    @Test func highlightCallsignLayout() throws {
        let bytes = WsjtxMessages.encodeHighlightCallsign(id: "WSJT-X", call: "K1ZZ",
                                                          background: WsjtxMessages.Rgb(0xE53935),
                                                          foreground: nil, highlightLast: true)
        var input = WsjtxDataInput(bytes)
        #expect(try input.readInt() == WsjtxProtocol.magic)
        #expect(try input.readInt() == WsjtxProtocol.schema)
        #expect(try input.readInt() == 13)
        #expect(try WsjtxCodec.readString(&input) == "WSJT-X")
        #expect(try WsjtxCodec.readString(&input) == "K1ZZ")
        // Background: spec RGB, alpha 0xFFFF, red 0xE5E5, green 0x3939, blue 0x3535, pad.
        let background: [UInt8] = Array(bytes[(bytes.count - 1 - 22)..<(bytes.count - 1 - 11)])
        #expect(background == [1, 0xFF, 0xFF, 0xE5, 0xE5, 0x39, 0x39, 0x35, 0x35, 0, 0])
        let foreground: [UInt8] = Array(bytes[(bytes.count - 1 - 11)..<(bytes.count - 1)])
        #expect(foreground == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "no colour = QColor invalid")
        #expect(bytes.last == 1)
    }

    @Test func highlightColoursFollowTheStatus() {
        #expect(WsjtxDecodes.highlight(dupe: true, newMultCount: 2).background == nil)
        #expect(WsjtxDecodes.highlight(dupe: false, newMultCount: 1).background == WsjtxMessages.Rgb(0xE53935))
        #expect(WsjtxDecodes.highlight(dupe: false, newMultCount: 3).background == WsjtxMessages.Rgb(0x43A047))
        #expect(WsjtxDecodes.highlight(dupe: false, newMultCount: 0).foreground == WsjtxMessages.Rgb(0x1E88E5))
    }

    private static func row(_ message: String, snr: Int32, df: Int32) throws -> WsjtxDecodes.Row {
        WsjtxDecodes.Row(
            decode: WsjtxMessages.Decode(id: "WSJT-X", isNew: true, timeMs: 0, snr: snr, deltaTime: 0,
                                         deltaFrequency: df, mode: "~", message: message, lowConfidence: false,
                                         offAir: false),
            from: try UdpEndpoint.resolve(host: "127.0.0.1", port: 45003), parsed: Ft8Message.parse(message),
            freqHz: 14_074_000 + Int64(df), dupe: false, newMultCount: 0)
    }

    @Test func textFilterAndSort() throws {
        let decodes = WsjtxDecodes(rows: [try Self.row("CQ K1ZZ FN42", snr: -5, df: 900),
                                          try Self.row("OK1ABC DL1AB 73", snr: 3, df: 1_500),
                                          try Self.row("CQ DX JA1XYZ PM95", snr: -15, df: 300)])
        let all = decodes.filtered(onlyCq: false, hideDupe: false, onlyMult: false, text: "", sort: .time)
        #expect(all.map(\.decode.snr) == [-5, 3, -15])
        #expect(decodes.filtered(onlyCq: false, hideDupe: false, onlyMult: false, text: " 73", sort: .time).count == 1)
        #expect(decodes.filtered(onlyCq: false, hideDupe: false, onlyMult: false, text: "", sort: .snr)
                    .map(\.decode.snr) == [3, -5, -15])
        #expect(decodes.filtered(onlyCq: false, hideDupe: false, onlyMult: false, text: "", sort: .frequency)
                    .map(\.decode.deltaFrequency) == [300, 900, 1_500])
        #expect(all.first?.band == .m20)
        #expect(WsjtxDecodes.modeName("+", statusMode: "FT8") == "FT4")
        #expect(WsjtxDecodes.modeName(":", statusMode: nil) == "Q65")
        #expect(WsjtxDecodes.modeName("?", statusMode: "FT2") == "FT2")
    }

    @Test func newModes() {
        #expect(Mode.from(adif: "q65") == .q65)
        #expect(Mode.from(adif: "FT2") == .ft2)
        #expect(Mode.q65.isDigital && Mode.ft2.isDigital)
        #expect(HamlibModeMapping(dataMode: .digital, rttyAfsk: false).toHamlib(.q65, freqHz: 50_275_000) == "PKTUSB")
        #expect(CabrilloExporter.modeCode(.ft2) == "DG")
        #expect(Mode.javaCases.count == 10)
    }

    // MARK: - JTDX TCP

    /// The received records; `next()` waits for the next one (a signal, no wall-clock wait).
    final class Records: @unchecked Sendable {
        let stream: AsyncStream<String>
        private let continuation: AsyncStream<String>.Continuation

        init() {
            (stream, continuation) = AsyncStream<String>.makeStream()
        }

        func add(_ s: String) {
            continuation.yield(s)
        }
    }

    @Test func tcpRecordsArriveSplitOrJoined() async throws {
        let records = Records()
        let listener = try AdifTcpListener(bindHost: "127.0.0.1", bindPort: 0) { records.add($0) }
        listener.start()
        let fd: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(listener.boundPort).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected: Int32 = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(connected == 0)
        let first = "<call:5>K1ZZZ <mode:3>FT8 <EO"
        let second = "R><call:6>DL1ABC <mode:3>FT4 <eor> garbage <eor>"
        _ = first.withCString { write(fd, $0, strlen($0)) }
        _ = second.withCString { write(fd, $0, strlen($0)) }
        close(fd)
        var iterator = records.stream.makeAsyncIterator()
        let one: String? = await iterator.next()
        let two: String? = await iterator.next()
        #expect(one?.contains("K1ZZZ") == true)
        #expect(two?.contains("DL1ABC") == true)
        listener.close()
        await listener.waitUntilStopped()
        #expect(AdifTcpListener.recordEnd(Array("abc<EoR>x".utf8)) == 8)
        #expect(AdifTcpListener.recordEnd(Array("<eo".utf8)) == nil)
    }
}
