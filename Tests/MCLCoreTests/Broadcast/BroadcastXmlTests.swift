import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `broadcast/BroadcastXmlTest`.
@Suite struct BroadcastXmlTests {

    /// 2026-07-02T13:45:00Z
    private static let ts = Date(timeIntervalSince1970: 1_782_999_900)

    private func contact() -> BroadcastXml.ContactData {
        BroadcastXml.ContactData(contestName: "CQ WW", contestNr: 7, timestamp: Self.ts, myCall: "OK1XOE",
                                 rxFreqHz: 3_525_190, txFreqHz: 3_525_190, mode: "CW", call: "A&B", continent: "EU",
                                 snt: "599", sntNr: 1, rcv: "599", rcvNr: 28, points: 3,
                                 isMultiplier: true, id: "uuid-123", stationName: "OK1XOE")
    }

    @Test func contactInfoHasTagsFreqTensAndEscape() {
        let x = BroadcastXml.contactInfo(contact())
        #expect(x.hasPrefix("<contactinfo>"), "\(x)")
        #expect(x.contains("<app>MacContestLogger</app>"))
        #expect(x.contains("<timestamp>2026-07-02 13:45:00</timestamp>"))
        #expect(x.contains("<rxfreq>352519</rxfreq>"), "freq must be tens of Hz")
        #expect(x.contains("<mode>CW</mode>"))
        #expect(x.contains("<call>A&amp;B</call>"), "XML escape")
        #expect(x.contains("<band>3.5</band>"))
        #expect(x.contains("<ID>uuid-123</ID>"))
        #expect(x.contains("<ismultiplier1>1</ismultiplier1>"))
    }

    @Test func contactReplaceHasOldFields() {
        let x = BroadcastXml.contactReplace(contact(), oldCall: "OLDCALL", oldTs: Self.ts)
        #expect(x.hasPrefix("<contactreplace>"))
        #expect(x.contains("<oldcall>OLDCALL</oldcall>"))
        #expect(x.contains("<oldtimestamp>2026-07-02 13:45:00</oldtimestamp>"))
    }

    @Test func contactDeleteIsSubset() {
        let x = BroadcastXml.contactDelete(contact())
        #expect(x.hasPrefix("<contactdelete>"))
        #expect(x.contains("<ID>uuid-123</ID>"))
        #expect(x.contains("<call>A&amp;B</call>"))
        #expect(!x.contains("<rxfreq>"), "delete is a subset, no freq")
    }

    @Test func radioInfoFreqTensAndRunning() {
        let x = BroadcastXml.radioInfo(BroadcastXml.RadioData(stationName: "OK1XOE", freqHz: 14_025_400, mode: "CW",
                                                              opCall: "OK1XOE", isRunning: true))
        #expect(x.hasPrefix("<RadioInfo>"))
        #expect(x.contains("<Freq>1402540</Freq>"))
        #expect(x.contains("<IsRunning>True</IsRunning>"))
    }

    @Test func radioInfoRunningFalse() {
        let x = BroadcastXml.radioInfo(BroadcastXml.RadioData(stationName: "S", freqHz: 1, mode: "SSB",
                                                              opCall: "OP", isRunning: false))
        #expect(x.contains("<IsRunning>False</IsRunning>"))
    }

    @Test func dynamicResultsHasScore() {
        let x = BroadcastXml.dynamicResults(BroadcastXml.ScoreData(contest: "CQ WW", call: "OK1XOE", ops: "OK1XOE",
                                                                   score: 12345, timestamp: Self.ts))
        #expect(x.hasPrefix("<dynamicresults>"))
        #expect(x.contains("<score>12345</score>"))
        #expect(x.contains("<contest>CQ WW</contest>"))
    }

    @Test func appInfoHasMycall() {
        let x = BroadcastXml.appInfo(BroadcastXml.AppInfoData(dbName: "logbook.sqlite", contestNr: 7, contestName: "CQ WW",
                                                              stationName: "OK1XOE", myCall: "OK1XOE"))
        #expect(x.hasPrefix("<AppInfo>"))
        #expect(x.contains("<mycall>OK1XOE</mycall>"))
    }

    @Test func n1mmBandRanges() {
        let c = BroadcastXml.ContactData(contestName: "", contestNr: 0, timestamp: Self.ts, myCall: "M",
                                         rxFreqHz: 14_025_400, txFreqHz: 14_025_400, mode: "CW", call: "C", continent: "",
                                         snt: "", sntNr: nil, rcv: "", rcvNr: nil, points: 0,
                                         isMultiplier: false, id: "id", stationName: "S")
        #expect(BroadcastXml.contactInfo(c).contains("<band>14</band>"))
    }
}
