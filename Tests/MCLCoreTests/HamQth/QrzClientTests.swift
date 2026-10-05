import Testing
@testable import MCLCore

/// Port of `hamqth/QrzClientTest` (3) — parsers of QRZ.com XML responses.
@Suite struct QrzClientTests {

    @Test func parsesSessionKey() {
        var xml = "<?xml version=\"1.0\"?><QRZDatabase><Session><Key>abc123</Key>"
        xml += "<Count>1</Count></Session></QRZDatabase>"
        #expect(QrzClient.parseKey(xml) == "abc123")
    }

    @Test func parsesError() {
        let xml = "<QRZDatabase><Session><Error>Not found: XX</Error></Session></QRZDatabase>"
        #expect(QrzClient.parseError(xml) == "Not found: XX")
        #expect(QrzClient.parseError("<QRZDatabase><Session><Key>x</Key></Session></QRZDatabase>") == nil)
    }

    @Test func parsesRecord() {
        var xml = "<QRZDatabase><Callsign><call>OK1XOE</call>"
        xml += "<fname>Tomas</fname><name>Kaplan</name>"
        xml += "<grid>JO70fd</grid><cqzone>15</cqzone><ituzone>28</ituzone></Callsign></QRZDatabase>"
        let r = QrzClient.parseRecord(xml)
        #expect(r.grid == "JO70fd")
        #expect(r.cqZone == "15")
        #expect(r.ituZone == "28")
        #expect(r.name == "Tomas")
    }
}
