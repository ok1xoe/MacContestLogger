import Testing
@testable import MCLCore

/// Port of the Java `n1mmrecv/N1mmContactParserTest`.
@Suite struct N1mmContactParserTests {

    /// A real sample from RUMlogNG (sniffed on 12060).
    private static let rumlog: String = {
        var s = "<contactinfo><contestname>Rag Chewing</contestname><timestamp>2026-07-03 06:37:25</timestamp>"
        s += "<mycall></mycall><band>14</band><txfreq>1421700</txfreq><mode>SSB</mode><call>AA5A</call>"
        s += "<countryprefix>K</countryprefix><wpxprefix>AA5</wpxprefix><continent>NA</continent>"
        s += "<snt>59</snt><rcv>59</rcv><gridsquare></gridsquare>"
        s += "<StationName>Tom - MacBook Pro</StationName><dxcc>291</dxcc></contactinfo>"
        return s
    }()

    /// MacContestLogger's own broadcast (has `<app>` and our callsign).
    private static let own: String = {
        var s = "<contactinfo><app>MacContestLogger</app><timestamp>2026-07-03 06:40:26</timestamp>"
        s += "<mycall>OK1XOE</mycall><band></band><rxfreq>0</rxfreq><txfreq>0</txfreq><mode>SSB</mode>"
        s += "<call>AW5A</call><snt>59</snt><sntnr>5</sntnr><rcv>59</rcv><rcvnr></rcvnr>"
        s += "<StationName>OK1XOE</StationName></contactinfo>"
        return s
    }()

    @Test func parsesRumlogContact() throws {
        let pc = try #require(N1mmContactParser.parse(Self.rumlog))
        #expect(pc.qso.call == "AA5A")
        #expect(pc.qso.mode == .ssb)
        #expect(pc.qso.freqHz == 14_217_000) // 1421700 × 10
        #expect(pc.qso.rstSent == "59")
        #expect(pc.qso.rstRcvd == "59")
        #expect(pc.app == nil) // RUMlog contactinfo has no <app>
        #expect(pc.stationName == "Tom - MacBook Pro")
    }

    @Test func exposesExchangeFieldsAdifStyle() throws {
        let pc = try #require(N1mmContactParser.parse(Self.rumlog))
        #expect(pc.fields["rst_rcvd"] == "59")
    }

    @Test func extractsAppForEchoFilter() throws {
        let pc = try #require(N1mmContactParser.parse(Self.own))
        #expect(pc.app == "MacContestLogger")
        #expect(pc.stationName == "OK1XOE")
    }

    @Test func nullWhenNoCall() {
        #expect(N1mmContactParser.parse("<contactinfo><band>14</band></contactinfo>") == nil)
    }
}
