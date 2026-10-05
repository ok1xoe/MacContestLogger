import Foundation
import Testing
@testable import MCLCore

/// The datagram filter of the Java `AdifUdpListener` without a socket. The Java `AdifUdpListenerTest` (2) go through a UDP
/// socket and are ported with the receiver; here are their datagrams and edges measured by the generator
/// (`adifudp.FILT` in a maintainer-only probe). The names deliberately differ from the Java ones
/// (`deliversBareAdif`, `ignoresNonAdif`), those are taken by the ported socket tests.
@Suite struct AdifUdpFilterTests {

    private static let fldigi: String = "<CALL:6>II9WWA<MODE:2>CW<FREQ:9>14.028086<BAND:3>20m<QSO_DATE:8>20260703"
        + "<TIME_ON:4>1733<RST_SENT:3>599<RST_RCVD:3>599<STX:3>000<OPERATOR:6>OK1XOE<STATION_CALLSIGN:6>OK1XOE<EOR>"

    private func filter(_ text: String) -> String? {
        AdifUdpFilter.adif(from: Array(text.utf8))
    }

    @Test func bareAdifDatagramPasses() {
        let adif: String? = filter(Self.fldigi)
        #expect(adif?.contains("II9WWA") == true)
    }

    @Test func nonAdifDatagramIsDropped() {
        #expect(filter("hello world") == nil)
    }

    @Test func measuredEdges() {
        #expect(filter("<CaLl:4>OK1A<EoR>") == "<CaLl:4>OK1A<EoR>")
        #expect(filter("<call:4>OK1A") == nil)
        #expect(filter("<eor ><call") == nil)
        // `İ` shrinks to `i̇` in Java (two units), the search is not broken by it.
        #expect(filter("\u{0130}<call<eor>") == "\u{0130}<call<eor>")
        // A combining character after `>`: Java searches by UTF-16 units and finds `<eor>`.
        #expect(filter("<call<eor>\u{0301}") == "<call<eor>\u{0301}")
        // Bad UTF-8 inside a tag → U+FFFD and the tag is not found.
        let broken: [UInt8] = [0x3C, 0x63, 0x61, 0xFF, 0x6C, 0x6C, 0x3C, 0x65, 0x6F, 0x72, 0x3E]
        #expect(AdifUdpFilter.adif(from: broken) == nil)
    }
}
