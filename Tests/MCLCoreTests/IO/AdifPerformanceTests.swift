import Foundation
import Testing
@testable import MCLCore

/// A large log (performance check): write and read back 10,000 QSOs. The times are only
/// printed (debug build); it is verified that the read returns the same as was written.
@Suite struct AdifPerformanceTests {

    @Test func tenThousandQsosRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_781_654_400)
        let qsos: [Qso] = (0..<10_000).map { i in
            var q = Qso()
            q.timestampUtc = start.addingTimeInterval(TimeInterval(i * 7))
            q.call = "OK" + String(i % 10) + "T" + String(i)
            q.freqHz = 14_000_000 + (i % 350) * 1_000 + 50
            q.mode = i % 2 == 0 ? .cw : .ssb
            q.rstSent = "599"
            q.rstRcvd = "599"
            q.serialSent = i + 1
            q.serialRcvd = i % 977
            q.exchangeSent = "599 " + String(i + 1)
            q.exchangeRcvd = "599 " + String(i % 977)
            q.comment = i % 10 == 0 ? "Tom\u{00E1}\u{0161} \u{1F600}" : ""
            return q
        }
        let clock = ContinuousClock()
        var adif = ""
        let writeTime = clock.measure { adif = AdifWriter(contestId: "CQ-WW-CW").toAdif(qsos) }
        var back: [Qso] = []
        let readTime = try clock.measure { back = try AdifReader().read(adif) }
        print("AdifPerformance: 10,000 QSOs, \(adif.utf8.count) B — write \(writeTime), read \(readTime)")
        #expect(back.count == qsos.count)
        for (a, b) in zip(qsos, back) where a.call != b.call || a.freqHz != b.freqHz
            || a.timestampUtc != b.timestampUtc || a.serialRcvd != b.serialRcvd
            || a.exchangeRcvd != "599 " + b.exchangeRcvd || a.comment != b.comment {
            Issue.record("mismatch \(a.call)")
            break
        }
    }
}
