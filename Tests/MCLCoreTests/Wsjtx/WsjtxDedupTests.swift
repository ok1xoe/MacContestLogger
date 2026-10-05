import Foundation
import Testing
@testable import MCLCore

/// Port `WsjtxDedupTest.java` (3 testy).
@Suite struct WsjtxDedupTests {

    private static func qso(_ call: String, _ band: Band, _ t: String) -> Qso {
        var q = Qso()
        q.call = call
        q.band = band
        q.timestampUtc = ISO8601DateFormatter().date(from: t)
        return q
    }

    @Test func duplicateWithinWindowSameCallBand() {
        let existing = Self.qso("AA5A", .m20, "2026-07-03T06:40:00Z")
        let incoming = Self.qso("AA5A", .m20, "2026-07-03T06:41:00Z")
        #expect(WsjtxDedup.isDuplicate([existing], incoming, windowSeconds: 120))
    }

    @Test func notDuplicateOutsideWindow() {
        let existing = Self.qso("AA5A", .m20, "2026-07-03T06:40:00Z")
        let incoming = Self.qso("AA5A", .m20, "2026-07-03T06:45:00Z")
        #expect(!WsjtxDedup.isDuplicate([existing], incoming, windowSeconds: 120))
    }

    @Test func notDuplicateDifferentCall() {
        let existing = Self.qso("AA5A", .m20, "2026-07-03T06:40:00Z")
        let incoming = Self.qso("KA5A", .m20, "2026-07-03T06:40:30Z")
        #expect(!WsjtxDedup.isDuplicate([existing], incoming, windowSeconds: 120))
    }
}
