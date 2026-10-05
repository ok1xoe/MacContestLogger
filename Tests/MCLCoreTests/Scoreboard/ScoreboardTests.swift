import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `scoreboard/ScoreboardTest`; `postsFormEncodedXml` posts to a local server `127.0.0.1`.
@Suite struct ScoreboardTests {

    private let st = ScoreXml.Station(call: "OK1XOE", ops: "OK1XOE", club: "OK1KHL", cqZone: "15", ituZone: "28",
                                      grid: "JO70FC",
                                      category: ["POWER": "HIGH", "OPERATOR": "SINGLE-OP", "MODE": "CW"])

    @Test func xmlContainsScoreAndClass() {
        let score = ScoreState(qsoCount: 100, qsoPoints: 250, multTotal: 40, multByGroup: JavaLinkedMap(),
                               bonusPoints: 0, qtcPoints: 0, total: 10_000)
        // 2026-11-28T12:00:00Z
        let now = Date(timeIntervalSince1970: 1_795_867_200)
        let xml = ScoreXml.build(contestName: "CQ-WW-CW", station: st, score: score, breakdown: nil,
                                 withBreakdown: false, version: "1.2.3", now: now)
        #expect(xml.contains("<contest>CQ-WW-CW</contest>"))
        #expect(xml.contains("power=\"HIGH\""))
        #expect(xml.contains("<qso band=\"total\" mode=\"ALL\">100</qso>"))
        #expect(xml.contains("<score>10000</score>"))
        #expect(xml.contains("<timestamp>2026-11-28 12:00:00</timestamp>"))
        #expect(ScoreXml.esc("a & <b>") == "a &amp; &lt;b&gt;")
    }

    @Test func postsFormEncodedXml() async throws {
        let server = try FakeHttpServer(response: .init(status: 200))
        defer { server.stop() }
        // Java test: `new ScorePoster()` (connect 10 s, NORMAL); the request timeout as a generous guard.
        let poster = ScorePoster(http: JavaHttpClient(connectTimeout: ScorePoster.connectTimeout, redirect: .normal),
                                 requestTimeout: 120)
        let url = "http://127.0.0.1:\(server.port)/post/"
        let code = try await onOwnThread { try poster.post(url, xml: "<x>1</x>") }
        #expect(code == 200)
        #expect(FakeHttpServer.formDecoded(server.body(0)) == "xml=<x>1</x>")
    }
}
