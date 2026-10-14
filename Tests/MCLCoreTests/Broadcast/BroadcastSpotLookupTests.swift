import Foundation
import Testing
@testable import MCLCore

/// N1MM „Spots", „Lookup" and „All QSOs" packets and the shared receive port (Swift-only).
@Suite(.ioSafetyNet) struct BroadcastSpotLookupTests {

    @Test func spotPacketHasN1mmTags() {
        let s = BroadcastXml.SpotData(stationName: "OK1XOE", dxCall: "AL3CDE", freqHz: 7_061_200, spotter: "K2PO/7-#",
                                      timestamp: Date(timeIntervalSince1970: 0), action: "add", mode: "CW",
                                      comment: "CW 9 DB CQ", status: "single mult", statusList: "single mult,cq")
        let xml = BroadcastXml.spot(s)
        var expected = "<spot><app>MacContestLogger</app><StationName>OK1XOE</StationName><dxcall>AL3CDE</dxcall>"
        expected += "<frequency>7061.2</frequency><spottercall>K2PO/7-#</spottercall>"
        expected += "<timestamp>1970-01-01 00:00:00</timestamp><action>add</action><mode>CW</mode>"
        expected += "<comment>CW 9 DB CQ</comment><status>single mult</status><statuslist>single mult,cq</statuslist></spot>"
        #expect(xml == expected)
    }

    @Test func spotStatusWords() {
        #expect(BroadcastXml.spotStatus(dupe: true, newMults: 2, isCq: false) == ("dupe", "dupe"))
        #expect(BroadcastXml.spotStatus(dupe: false, newMults: 1, isCq: true) == ("single mult", "single mult,cq"))
        #expect(BroadcastXml.spotStatus(dupe: false, newMults: 2, isCq: false).status == "double mult")
        #expect(BroadcastXml.spotStatus(dupe: false, newMults: 5, isCq: false).status == "triple mult")
        #expect(BroadcastXml.spotStatus(dupe: false, newMults: 0, isCq: false).status == "new qso")
    }

    @Test func forwardedContactIsNotOriginalAndIsNotForwardedAgain() {
        let original = "<contactinfo><call>W1AW</call><IsOriginal>True</IsOriginal></contactinfo>"
        let forwarded = BroadcastXml.forwarded(original)
        #expect(forwarded == "<contactinfo><call>W1AW</call><IsOriginal>False</IsOriginal></contactinfo>")
        #expect(BroadcastXml.isOriginal(original))
        #expect(!BroadcastXml.isOriginal(forwarded))
        let bare = "<contactinfo><call>W1AW</call></contactinfo>"
        #expect(BroadcastXml.forwarded(bare) == "<contactinfo><call>W1AW</call><IsOriginal>False</IsOriginal></contactinfo>")
    }

    private static func appInfo() -> BroadcastXml.AppInfoData {
        BroadcastXml.AppInfoData(dbName: nil, contestNr: 0, contestName: nil, stationName: nil, myCall: nil)
    }

    private static func contact() -> BroadcastXml.ContactData {
        BroadcastXml.ContactData(contestName: "", contestNr: 1, timestamp: nil, myCall: "OK1XOE", rxFreqHz: 14_000_000,
                                 txFreqHz: 14_000_000, mode: "CW", call: "W1AW", continent: "NA", snt: nil,
                                 sntNr: nil, rcv: nil, rcvNr: nil, points: 0, isMultiplier: false, id: "x",
                                 stationName: "OK1XOE")
    }

    /// Every new type is off by default; on, it goes only to its own targets.
    @Test func newTypesAreOptInAndUseTheirTargets() {
        let off = BroadcastServiceTests.FakeBroadcaster()
        let none = BroadcastService(config: BroadcastConfig(), broadcaster: off, radioProvider: { nil },
                                    scoreProvider: { nil }, appInfoProvider: { Self.appInfo() })
        let spot = BroadcastXml.SpotData(stationName: nil, dxCall: "W1AW", freqHz: 14_000_000, spotter: "K1",
                                         timestamp: nil, action: "add", mode: "", comment: "", status: "", statusList: "")
        none.sendSpot(spot)
        none.sendLookup(Self.contact())
        none.forwardContact(Self.contact())
        none.forwardContact(xml: "<contactinfo><call>W1AW</call></contactinfo>")
        #expect(off.sent.isEmpty)
        #expect(!BroadcastConfig().spotsEnabled && !BroadcastConfig().lookupEnabled && !BroadcastConfig().allQsosEnabled)

        var cfg = BroadcastConfig()
        cfg.contactsEnabled = true
        cfg.contactsTargets = "127.0.0.1:1"
        cfg.spotsEnabled = true
        cfg.spotsTargets = "127.0.0.1:2"
        cfg.lookupEnabled = true
        cfg.lookupTargets = "127.0.0.1:3"
        let fake = BroadcastServiceTests.FakeBroadcaster()
        let s = BroadcastService(config: cfg, broadcaster: fake, radioProvider: { nil }, scoreProvider: { nil },
                                 appInfoProvider: { Self.appInfo() })
        s.sendSpot(spot)
        s.sendLookup(Self.contact())
        s.forwardContact(Self.contact())  // All QSOs off: nothing
        #expect(fake.sent.map { $0.1.first?.port } == [2, 3])
        #expect(fake.sent[0].0.hasPrefix("<spot>"))
        #expect(fake.sent[1].0.hasPrefix("<lookupinfo>"))

        cfg.allQsosEnabled = true
        let all = BroadcastServiceTests.FakeBroadcaster()
        let forwarding = BroadcastService(config: cfg, broadcaster: all, radioProvider: { nil },
                                          scoreProvider: { nil }, appInfoProvider: { Self.appInfo() })
        forwarding.forwardContact(Self.contact())
        forwarding.forwardContact(xml: "<contactinfo><IsOriginal>False</IsOriginal></contactinfo>")
        forwarding.forwardContact(xml: "<contactinfo><IsOriginal>True</IsOriginal></contactinfo>")
        #expect(all.sent.count == 2)
        #expect(all.sent[0].0.contains("<IsOriginal>False</IsOriginal>"))
        #expect(all.sent[1].0 == "<contactinfo><IsOriginal>False</IsOriginal></contactinfo>")
        #expect(all.sent.allSatisfy { $0.1.first?.port == 1 })
    }

    /// The shared receive port: two receivers bind the same loopback port only when both share it.
    @Test func sharedPortLetsTwoReceiversBind() throws {
        let first = try UdpReceiver.unicast(host: "127.0.0.1", port: 0, share: true)
        defer { first.close() }
        let port: Int = first.boundPort
        let second = try UdpReceiver.unicast(host: "127.0.0.1", port: port, share: true)
        second.close()
        #expect(throws: (any Error).self) {
            let plain = try UdpReceiver.unicast(host: "127.0.0.1", port: port)
            plain.close()
        }
        let n1mm = try N1mmListener(bindHost: "127.0.0.1", bindPort: port, sharePort: true, handler: { _ in })
        n1mm.close()
        let adif = try AdifUdpListener(bindHost: "127.0.0.1", bindPort: port, sharePort: true, handler: { _ in })
        adif.close()
        #expect(!N1mmRecvConfig().sharePort && !AdifUdpConfig().sharePort)
    }
}
