import Foundation
import Testing
@testable import MCLCore

/// Values measured on Java v1.1.1 (maintainer-only probe: `BX.*`, `TGT`, `N1MM|`;
/// sections `broadcast.*`, `n1mmrecv.N1MM`, `scoreboard.SXML` of the maintainer-only generator).
/// They supplement the ported tests with edges that the Java tests do not assert.
@Suite struct BroadcastMeasuredTests {

    @Test func timestampYearOfEra() {
        // +12026-01-01T00:00:00Z a -0001-06-01T00:00:00Z
        let big = BroadcastXml.ScoreData(contest: "c", call: "x", ops: "o", score: 1,
                                         timestamp: Date(timeIntervalSince1970: 317_336_745_600))
        var expected = "<dynamicresults><contest>c</contest><call>x</call><ops>o</ops><score>1</score>"
        expected += "<timestamp>+12026-01-01 00:00:00</timestamp></dynamicresults>"
        #expect(BroadcastXml.dynamicResults(big) == expected)
        let neg = BroadcastXml.ScoreData(contest: "c", call: "x", ops: "o", score: 1,
                                         timestamp: Date(timeIntervalSince1970: -62_185_708_800))
        #expect(BroadcastXml.dynamicResults(neg).contains("<timestamp>0002-06-01 00:00:00</timestamp>"))
    }

    @Test func radioNegativeFrequencyTruncatesTowardZero() {
        let x = BroadcastXml.radioInfo(BroadcastXml.RadioData(stationName: "s", freqHz: -15, mode: "CW", opCall: "o",
                                                              isRunning: true))
        var expected = "<RadioInfo><app>MacContestLogger</app><StationName>s</StationName><RadioNr>1</RadioNr>"
        expected += "<Freq>-1</Freq><TXFreq>-1</TXFreq><Mode>CW</Mode><OpCall>o</OpCall><IsRunning>True</IsRunning>"
        expected += "<FocusRadioNr>1</FocusRadioNr><ActiveRadioNr>1</ActiveRadioNr><IsTransmitting>False</IsTransmitting>"
        expected += "<IsStereo>False</IsStereo><IsSplit>False</IsSplit></RadioInfo>"
        #expect(x == expected)
    }

    @Test func escapesApostropheAndNullIsEmptyTag() {
        let x = BroadcastXml.appInfo(BroadcastXml.AppInfoData(dbName: nil, contestNr: -1, contestName: "it's \"<&>\"",
                                                              stationName: "", myCall: nil))
        var expected = "<AppInfo><app>MacContestLogger</app><dbname></dbname><contestnr>-1</contestnr>"
        expected += "<contestname>it&apos;s &quot;&lt;&amp;&gt;&quot;</contestname><StationName></StationName>"
        expected += "<mycall></mycall></AppInfo>"
        #expect(x == expected)
        #expect(ScoreXml.esc("it's") == "it's")
    }

    @Test func targetEdges() {
        let t = Target.parseAll(" a:1,b:2  [::1]:2237 c: :5 d:0 e:65536 f:+3 g:-1 h:\u{0663} 127.0.0.1:2333")
        let expected = [Target(host: "a", port: 1), Target(host: "b", port: 2), Target(host: "[::1]", port: 2237),
                        Target(host: "f", port: 3), Target(host: "h", port: 3), Target(host: "127.0.0.1", port: 2333)]
        #expect(t == expected)
        #expect(Target.parseAll("a:1\u{00A0}b:2") == [Target(host: "a:1\u{00A0}b", port: 2)])
        #expect(Target.parseAll("\u{2003}").isEmpty)
    }

    @Test func contactSmartTimesAndNumbers() throws {
        var feb = "<contactinfo><call>K1ABC</call><timestamp>2026-02-30 12:00:00</timestamp><txfreq>1402500</txfreq>"
        feb += "<mode>CW</mode><snt>599</snt><sntnr>99999999999</sntnr></contactinfo>"
        let a = try #require(N1mmContactParser.parse(feb))
        #expect(a.qso.timestampUtc == Date(timeIntervalSince1970: 1_772_280_000)) // 2026-02-28T12:00Z
        #expect(a.qso.freqHz == 14_025_000)
        #expect(a.qso.band == .m20)
        #expect(a.qso.mode == .cw)
        #expect(a.qso.serialSent == nil)

        let lower = "<contactinfo><CALL >k1abc</CALL><timestamp>2026-1-01 12:00:00</timestamp><rxfreq> 1402500 </rxfreq><rcvnr>+5</rcvnr></contactinfo>"
        let b = try #require(N1mmContactParser.parse(lower))
        #expect(b.qso.call == "K1ABC")
        #expect(b.qso.timestampUtc == nil)
        #expect(b.qso.serialRcvd == 5)
        #expect(b.fields.entries.map { $0.key } == ["srx_string"])
        #expect(b.fields["srx_string"] == "+5")

        let entity = try #require(N1mmContactParser.parse("<call>A&amp;B</call><timestamp>2026-10-01 24:00:00</timestamp>"))
        #expect(entity.qso.call == "A&AMP;B")
        #expect(entity.qso.timestampUtc == Date(timeIntervalSince1970: 1_790_899_200)) // 2026-10-02T00:00Z

        let cases: [(String, Date?)] = [
            ("2026-02-30 24:00:00", Date(timeIntervalSince1970: 1_772_323_200)),
            ("2026-12-31 12:00:60", nil), ("0000-01-01 00:00:00", nil), ("999999999-12-31 23:59:59", nil),
            ("2026-12-31T12:00:00", nil), ("2026-12-31  12:00:00", nil),
        ]
        for (ts, expected) in cases {
            let pc = try #require(N1mmContactParser.parse("<call>x</call><timestamp>" + ts + "</timestamp>"))
            #expect(pc.qso.timestampUtc == expected, "\(ts)")
        }
        let digits = try #require(N1mmContactParser.parse("<call>x</call><txfreq>\u{0661}\u{0662}</txfreq>"))
        #expect(digits.qso.freqHz == 120)
        let wrap = try #require(N1mmContactParser.parse("<call>x</call><txfreq>922337203685477580</txfreq>"))
        #expect(wrap.qso.freqHz == 9_223_372_036_854_775_800)
        #expect(N1mmContactParser.parse("<call>\u{2003}</call>") == nil)
        #expect(N1mmContactParser.parse("<call>\u{00A0}</call>")?.qso.call == "\u{00A0}")
        #expect(N1mmContactParser.parse("<CaLl>x</cAlL>")?.qso.call == "X")
    }
}
