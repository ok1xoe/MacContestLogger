import Testing
@testable import MCLCore

/// Port of `hamqth/HamQthClientTest` (6) — parsers of HamQTH XML responses.
@Suite struct HamQthClientTests {

    @Test func parsesSessionId() {
        var xml = "<?xml version=\"1.0\"?><HamQTH><session>"
        xml += "<session_id>09b0ae90050be03c452ad235a1f2915ad684393c</session_id>"
        xml += "</session></HamQTH>"
        #expect(HamQthClient.parseSessionId(xml) == "09b0ae90050be03c452ad235a1f2915ad684393c")
    }

    @Test func parsesError() {
        let xml = "<HamQTH><session><error>Wrong user name or password</error></session></HamQTH>"
        #expect(HamQthClient.parseError(xml) == "Wrong user name or password")
        #expect(HamQthClient.parseError("<HamQTH><session><session_id>x</session_id></session></HamQTH>") == nil)
    }

    @Test func parsesGrid() {
        var xml = "<HamQTH><search><callsign>ok1xoe</callsign>"
        xml += "<grid>JO70fd</grid><country>Czech Republic</country></search></HamQTH>"
        #expect(HamQthClient.parseGrid(xml) == "JO70fd")
    }

    @Test func missingGridIsEmpty() {
        let xml = "<HamQTH><search><callsign>xx</callsign></search></HamQTH>"
        #expect(HamQthClient.parseGrid(xml) == nil)
        #expect(HamQthClient.parseGrid(nil) == nil)
        #expect(HamQthClient.parseGrid("<HamQTH><search><grid></grid></search></HamQTH>") == nil)
    }

    @Test func parsesFullRecord() {
        var xml = "<HamQTH><search><callsign>ok1xoe</callsign>"
        xml += "<nick>Tomas</nick><grid>JO70fd</grid><cq>15</cq><itu>28</itu>"
        xml += "<adr_name>Tomas Kaplan</adr_name></search></HamQTH>"
        let r = HamQthClient.parseRecord(xml)
        #expect(r.grid == "JO70fd")
        #expect(r.name == "Tomas")
        #expect(r.cqZone == "15")
        #expect(r.ituZone == "28")
    }

    @Test func recordFallsBackToAdrNameWhenNoNick() {
        let xml = "<HamQTH><search><adr_name>Jan Novak</adr_name><grid>JN99</grid></search></HamQTH>"
        #expect(HamQthClient.parseRecord(xml).name == "Jan Novak")
    }
}
