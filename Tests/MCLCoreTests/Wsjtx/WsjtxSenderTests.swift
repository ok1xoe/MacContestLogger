import Foundation
import Testing
@testable import MCLCore

/// Port of `WsjtxSenderTest.java` (2 tests).
@Suite struct WsjtxSenderTests {

    /// `Broadcaster` is `Sendable` (shared by threads) — a capture with a lock.
    private final class CapturingBroadcaster: Broadcaster, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [[UInt8]] = []
        var sent: [[UInt8]] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
        func send(_ xml: String, _ targets: [Target]) {}
        func send(_ data: [UInt8], _ targets: [Target]) {
            lock.lock()
            items.append(data)
            lock.unlock()
        }
        func close() {}
    }

    private static func sampleQso() -> Qso {
        var q = Qso()
        q.call = "AA5A"
        q.freqHz = 14_074_000
        q.mode = .ft8
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-07-03T06:40:26Z")
        q.rstSent = "-05"
        q.rstRcvd = "+03"
        return q
    }

    @Test func sendsBothQsoLoggedAndLoggedAdif() throws {
        let cap = CapturingBroadcaster()
        let sender = WsjtxSender(cap, [Target(host: "127.0.0.1", port: 2237)])
        sender.send(Self.sampleQso(), Station(call: "OK1XOE", operator: "OK1XOE", gridSquare: "JO70", name: "Jan"))

        #expect(cap.sent.count == 2)
        let first = try WsjtxMessages.decode(cap.sent[0])
        let second = try WsjtxMessages.decode(cap.sent[1])
        guard case .qsoLogged(let logged) = first else {
            Issue.record("first = type 5")
            return
        }
        guard case .loggedAdif(let adif) = second else {
            Issue.record("second = type 12")
            return
        }
        #expect(logged.dxCall == "AA5A")
        #expect((adif.adif ?? "").uppercased().contains("AA5A"))
    }

    @Test func qsoLoggedMapsCoreFields() {
        let m = WsjtxSender.toQsoLogged(Self.sampleQso(),
                                        Station(call: "OK1XOE", operator: "OP", gridSquare: "JO70", name: "Jan"))
        #expect(m.dxCall == "AA5A")
        #expect(m.txFreqHz == 14_074_000)
        #expect(m.mode == "FT8")
        #expect(m.reportSent == "-05")
        #expect(m.reportRcvd == "+03")
        #expect(m.myCall == "OK1XOE")
        #expect(m.opCall == "OP")
        #expect(m.myGrid == "JO70")
    }
}
