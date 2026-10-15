import Foundation
import Testing
@testable import MCLCore

/// The pure parts of the network tools: the setup text and its mismatches, the trace, the master's time.
@Suite struct NetworkToolsCoreTests {

    @Test func profileRoundTripsAndIgnoresUnknownLines() {
        let p = StationProfile(version: "0.9.0", contest: "CQ-WW-CW", category: "OPERATOR=MULTI-OP TRANSMITTER=ONE",
                               master: true)
        let decoded = StationProfile.decode(p.encoded(request: true) + "\nfuture=x\nnoequals")
        #expect(decoded.profile == p)
        #expect(decoded.request)
        #expect(!StationProfile.decode(p.encoded(request: false)).request)
        #expect(StationProfile.categoryText(["OPERATOR": " multi-op ", "TRANSMITTER": "N/A", "POWER": "HIGH"])
            == "OPERATOR=MULTI-OP")
    }

    @Test func mismatchesSkipBlankValues() {
        let own = StationProfile(version: "1", contest: "A", category: "X")
        #expect(own.mismatches(with: StationProfile(version: "", contest: "", category: ""), station: "OP2").isEmpty)
        let all = own.mismatches(with: StationProfile(version: "2", contest: "B", category: "Y"), station: "OP2")
        #expect(all.map(\.czech) == ["Stanice OP2 má jinou verzi programu (2, tato 1)",
                                     "Stanice OP2 má otevřený jiný závod (B, tato A)",
                                     "Stanice OP2 má jinou kategorii (Y, tato X)"])
    }

    @Test func traceIsCappedAndReadable() {
        var trace: [NetTraceLine] = []
        for i in 0..<(NetworkTools.traceCap + 5) {
            trace = NetworkTools.appending(trace, NetTraceLine(time: "12:00:00", outgoing: i % 2 == 0, type: "CHAT",
                                                               peer: "", text: "m\(i)"))
        }
        #expect(trace.count == NetworkTools.traceCap)
        #expect(trace.first?.text == "m5")
        #expect(NetTraceLine(time: "12:34:56", outgoing: false, type: "PASS", peer: "OP2", text: "DL1ABC\nx").row
            == "12:34:56 ← OP2 PASS DL1ABC x")
        let m = NetMessageWire(type: "PASS", id: "i", fromStation: "OP2", fromOperator: "", toStation: "", text: "u mě",
                               call: "DL1ABC", freqHz: 14_025_000, mode: "", timestampUtc: nil)
        #expect(NetworkTools.traceText(m) == "DL1ABC 14025.0 u mě")
    }

    @Test func masterTimeIsNtpStyle() {
        #expect(NetworkTools.masterOffsetMs(sentAtMs: 1_000, masterMs: 3_600, receivedAtMs: 1_200) == 2_500)
        #expect(NetworkTools.masterOffsetMs(sentAtMs: 1_000, masterMs: 900, receivedAtMs: 1_000) == -100)
        let answer = NetworkTools.timeAnswer(requestId: "a;b", masterMs: 1_800_000_000_123)
        #expect(NetworkTools.parseTimeAnswer(answer)?.requestId == "a;b")
        #expect(NetworkTools.parseTimeAnswer(answer)?.masterMs == 1_800_000_000_123)
        #expect(NetworkTools.parseTimeAnswer("x;abc") == nil)
        #expect(NetworkTools.parseTimeAnswer("nothing") == nil)
    }

    @Test func maxSentSerialSkipsDeleted() {
        var a = Qso(); a.serialSent = 12
        var b = Qso(); b.serialSent = 40; b.deleted = true
        let c = Qso()
        #expect(NetworkTools.maxSentSerial([a, b, c]) == 12)
        #expect(NetworkTools.maxSentSerial([]) == 0)
    }
}
