import Foundation
import Testing
@testable import MCLCore

/// Course of `lookup` of the HamQTH and QRZ clients over a network stand-in (`FakeHttpGetter`). Values measured on Java
/// v1.1.1 (a `HttpClient` stand-in slipped into the `http` field, like the section `hamqth.FLOW` of the generator
/// a maintainer-only probe); the timestamp of log rows cut off.
@Suite struct CallbookLookupTests {

    private func logLines(_ log: HamQthLog) -> [String] {
        log.snapshot().map { String($0.dropFirst(10)) }
    }

    private func record(_ grid: String, _ name: String, _ cq: String, _ itu: String) -> HamQthRecord {
        HamQthRecord(grid: grid, name: name, cqZone: cq, ituZone: itu)
    }

    @Test func hamQthRelogsOnceAfterSessionError() throws {
        let fake = FakeHttpGetter([
            FakeHttpGetter.ok("<HamQTH><session><session_id>s1</session_id></session></HamQTH>"),
            FakeHttpGetter.ok("<HamQTH><session><error>Session does not exist or expired</error></session></HamQTH>"),
            FakeHttpGetter.ok("<HamQTH><session><session_id>s2</session_id></session></HamQTH>"),
            FakeHttpGetter.ok("<HamQTH><search><nick>Tomas</nick><grid>JO70fd</grid><cq>15</cq><itu>28</itu></search></HamQTH>"),
        ])
        let log = HamQthLog()
        let client = HamQthClient(username: " user1 ", password: "p w&x", log: log, http: fake)
        #expect(try client.lookup(" ok1xoe ") == record("JO70fd", "Tomas", "15", "28"))
        let login = "https://www.hamqth.com/xml.php?u=user1&p=p+w%26x"
        let query1 = "https://www.hamqth.com/xml.php?id=s1&callsign=ok1xoe&prg=MacContestLogger"
        let query2 = "https://www.hamqth.com/xml.php?id=s2&callsign=ok1xoe&prg=MacContestLogger"
        #expect(fake.urls == [login, query1, login, query2])
        let masked = "\u{2192} GET https://www.hamqth.com/xml.php?u=user1&p=***"
        let expected: [String] = [
            "\u{00B7} Dohledávám údaje pro OK1XOE",
            masked,
            "\u{2190} [200]\n<HamQTH><session><session_id>s1</session_id></session></HamQTH>",
            "\u{2192} GET " + query1,
            "\u{2190} [200]\n<HamQTH><session><error>Session does not exist or expired</error></session></HamQTH>",
            "\u{00B7} Bez výsledku, obnovuji session a zkouším znovu",
            masked,
            "\u{2190} [200]\n<HamQTH><session><session_id>s2</session_id></session></HamQTH>",
            "\u{2192} GET " + query2,
            "\u{2190} [200]\n<HamQTH><search><nick>Tomas</nick><grid>JO70fd</grid><cq>15</cq><itu>28</itu></search></HamQTH>",
            "\u{00B7} OK1XOE: grid=JO70fd cq=15 itu=28 jméno=Tomas",
        ]
        #expect(logLines(log) == expected)
    }

    @Test func hamQthWithoutCredentialsNeverCallsNetwork() throws {
        let fake = FakeHttpGetter([])
        let client = HamQthClient(username: "user1", password: "", http: fake)
        #expect(!client.configured)
        #expect(try client.lookup("ok1xoe") == HamQthRecord.empty)
        #expect(try client.lookupGrid("ok1xoe") == nil)
        #expect(fake.urls.isEmpty)
    }

    @Test func hamQthNetworkErrorAndBadStatusEndEmpty() throws {
        let fake = FakeHttpGetter([.failure(nil), .response(500, Data("  oops \n".utf8))])
        let log = HamQthLog()
        let client = HamQthClient(username: "user1", password: "pw", log: log, http: fake)
        #expect(try client.lookup("w1aw") == HamQthRecord.empty)
        let login = "https://www.hamqth.com/xml.php?u=user1&p=pw"
        #expect(fake.urls == [login, login])
        let expected: [String] = [
            "\u{00B7} Dohledávám údaje pro W1AW",
            "\u{2192} GET https://www.hamqth.com/xml.php?u=user1&p=***",
            "\u{00B7} Chyba requestu: null",
            "\u{00B7} Bez výsledku, obnovuji session a zkouším znovu",
            "\u{2192} GET https://www.hamqth.com/xml.php?u=user1&p=***",
            "\u{2190} [500]\noops",
            "\u{00B7} Údaje pro W1AW nenalezeny",
        ]
        #expect(logLines(log) == expected)
    }

    @Test func qrzNotFoundDoesNotRetry() throws {
        let fake = FakeHttpGetter([
            FakeHttpGetter.ok("<QRZDatabase><Session><Key>k1</Key></Session></QRZDatabase>"),
            FakeHttpGetter.ok("<QRZDatabase><Session><Error>Not found: XX1A</Error><Key>k1</Key></Session></QRZDatabase>"),
        ])
        let log = HamQthLog()
        let client = QrzClient(username: "user1", password: "pw;x", log: log, http: fake)
        #expect(try client.lookup("xx1a") == HamQthRecord.empty)
        let login = "https://xmldata.qrz.com/xml/current/?username=user1;password=pw%3Bx;agent=MacContestLogger"
        let query = "https://xmldata.qrz.com/xml/current/?s=k1;callsign=xx1a"
        #expect(fake.urls == [login, query])
        let expected: [String] = [
            "\u{00B7} QRZ: dohledávám údaje pro XX1A",
            "\u{2192} GET https://xmldata.qrz.com/xml/current/?username=user1;password=***;agent=MacContestLogger",
            "\u{2190} [200]\n<QRZDatabase><Session><Key>k1</Key></Session></QRZDatabase>",
            "\u{2192} GET " + query,
            "\u{2190} [200]\n<QRZDatabase><Session><Error>Not found: XX1A</Error><Key>k1</Key></Session></QRZDatabase>",
            "\u{00B7} QRZ: údaje pro XX1A nenalezeny",
        ]
        #expect(logLines(log) == expected)
    }

    @Test func qrzSessionTimeoutRelogsOnce() throws {
        let fake = FakeHttpGetter([
            FakeHttpGetter.ok("<QRZDatabase><Session><Key>k1</Key></Session></QRZDatabase>"),
            FakeHttpGetter.ok("<QRZDatabase><Session><Error>Session Timeout</Error></Session></QRZDatabase>"),
            FakeHttpGetter.ok("<QRZDatabase><Session><Key>k2</Key></Session></QRZDatabase>"),
            FakeHttpGetter.ok("<QRZDatabase><Callsign><fname>Tomas</fname><grid>JO70fd</grid><cqzone>15</cqzone>"
                                + "<ituzone>28</ituzone></Callsign></QRZDatabase>"),
        ])
        let log = HamQthLog()
        let client = QrzClient(username: "user1", password: "pw", log: log, http: fake)
        #expect(try client.lookup("ok1xoe") == record("JO70fd", "Tomas", "15", "28"))
        let login = "https://xmldata.qrz.com/xml/current/?username=user1;password=pw;agent=MacContestLogger"
        #expect(fake.urls == [login, "https://xmldata.qrz.com/xml/current/?s=k1;callsign=ok1xoe", login,
                              "https://xmldata.qrz.com/xml/current/?s=k2;callsign=ok1xoe"])
        #expect(logLines(log).last == "\u{00B7} QRZ OK1XOE: grid=JO70fd cq=15 itu=28")
        #expect(logLines(log).count == 10)
    }

    @Test func negativeLogCapacityThrowsLikeJava() {
        // Java: `new HamQthLog(-1).info("x")` → NoSuchElementException, buffer empty.
        let log = HamQthLog(maxLines: -1)
        #expect(throws: JavaNoSuchElementError.self) { try log.info("x") }
        #expect(log.snapshot().isEmpty)
        let client = HamQthClient(username: "u", password: "p", log: log, http: FakeHttpGetter([]))
        #expect(throws: JavaNoSuchElementError.self) { try client.lookup("ok1xoe") }
    }
}
