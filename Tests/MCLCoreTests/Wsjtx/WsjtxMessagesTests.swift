import Foundation
import Testing
@testable import MCLCore

/// Port of `WsjtxMessagesTest.java` (5 tests).
@Suite struct WsjtxMessagesTests {

    @Test func loggedAdifRoundTrip() throws {
        let bytes = WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: "<call:4>AA5A<eor>"))
        let msg = try WsjtxMessages.decode(bytes)
        guard case .loggedAdif(let adif) = msg else {
            Issue.record("expected LoggedAdif, got \(String(describing: msg))")
            return
        }
        #expect(adif.adif == "<call:4>AA5A<eor>")
    }

    @Test func loggedAdifEnvelopeBytesAreExact() {
        let bytes = WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: "X"))
        // magic ADBCCBDA + schema 2 + type 12 + id len 16 + "MacContestLogger" + adif len 1 + 'X'
        let head: [UInt8] = Array(bytes[0..<16])
        let expectedHead: [UInt8] = [
            0xAD, 0xBC, 0xCB, 0xDA,
            0, 0, 0, 2,
            0, 0, 0, 12,
            0, 0, 0, 16,
        ]
        #expect(head == expectedHead)
        #expect(String(decoding: bytes[16..<32], as: UTF8.self) == "MacContestLogger")
    }

    @Test func qsoLoggedRoundTrip() throws {
        let iso = ISO8601DateFormatter()
        let m = WsjtxMessages.QsoLogged(
            dateTimeOff: iso.date(from: "2026-07-03T06:40:26Z"), dxCall: "AA5A", dxGrid: "EM12", txFreqHz: 14_074_000,
            mode: "FT8", reportSent: "-05", reportRcvd: "+03", txPower: "50", comments: "hi", name: "Jan",
            dateTimeOn: iso.date(from: "2026-07-03T06:39:00Z"), opCall: "OK1XOE", myCall: "OK1XOE", myGrid: "JO70",
            exchangeSent: "001", exchangeRcvd: "002", propMode: "")
        let bytes = WsjtxMessages.encodeQsoLogged(m)
        #expect(try WsjtxMessages.decode(bytes) == .qsoLogged(m))
    }

    @Test func unknownTypeDecodesToNull() throws {
        // Heartbeat (type 0) — not imported.
        var bytes = WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: "x"))
        bytes[11] = 0 // overwrite type 12 → 0
        #expect(try WsjtxMessages.decode(bytes) == nil)
    }

    @Test func badMagicThrows() {
        var bytes = WsjtxMessages.encodeLoggedAdif(WsjtxMessages.LoggedAdif(adif: "x"))
        bytes[0] = 0
        #expect(throws: WsjtxError.badMagic(0x00BC_CBDA)) {
            try WsjtxMessages.decode(bytes)
        }
    }
}
