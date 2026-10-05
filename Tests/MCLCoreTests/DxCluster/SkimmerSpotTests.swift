import Foundation
import Testing
@testable import MCLCore

/// Port of `dxcluster/SkimmerSpotTest` (3).
@Suite struct SkimmerSpotTests {

    private static let noon = dxInstant("2026-11-28T12:00:00Z")

    @Test func recognizesSkimmerSpots() {
        #expect(SkimmerSpot.isSkimmer(DxSpot(spotter: "DK9IP-#", freqHz: 14_025_000, dxCall: "OK1XOE",
                                             comment: "CW 19 dB 28 WPM CQ")))
        #expect(SkimmerSpot.isSkimmer(DxSpot(spotter: "W3LPL", freqHz: 14_025_000, dxCall: "OK1XOE",
                                             comment: "12 dB 25 WPM CQ")))
        #expect(!SkimmerSpot.isSkimmer(DxSpot(spotter: "OK2ABC", freqHz: 14_025_000, dxCall: "OK1XOE",
                                              comment: "tnx qso 599")))
    }

    @Test func countsDistinctSkimmersAndFilters() {
        let b = SpotBuffer(maxAgeMinutes: 30, clock: { Self.noon })
        b.add(DxSpot(spotter: "DK9IP-#", freqHz: 14_025_000, dxCall: "OK1XOE", comment: "19 dB 28 WPM CQ"))
        b.add(DxSpot(spotter: "OH6BG-#", freqHz: 14_025_100, dxCall: "OK1XOE", comment: "12 dB 28 WPM CQ"))
        b.add(DxSpot(spotter: "DK9IP-#", freqHz: 14_025_000, dxCall: "OK1XOE", comment: "20 dB 28 WPM CQ")) // the same skimmer again
        b.add(DxSpot(spotter: "DK9IP-#", freqHz: 7_010_000, dxCall: "DL1ABC", comment: "10 dB 30 WPM CQ"))
        b.add(DxSpot(spotter: "OK2ABC", freqHz: 21_010_000, dxCall: "W1AW", comment: "loud"))

        #expect(b.skimmerCount("OK1XOE") == 2)
        #expect(b.snapshot().count == 3)

        b.setMinSkimmers(2)
        #expect(b.snapshot().map(\.dxCall).sorted() == ["OK1XOE", "W1AW"])

        b.setMinSkimmers(0)
        #expect(b.snapshot().map(\.dxCall) == ["W1AW"], "only spots from humans")
    }

    @Test func farQsyStartsNewCount() {
        let b = SpotBuffer(maxAgeMinutes: 30, clock: { Self.noon })
        b.add(DxSpot(spotter: "DK9IP-#", freqHz: 14_025_000, dxCall: "OK1XOE", comment: "19 dB 28 WPM CQ"))
        b.add(DxSpot(spotter: "OH6BG-#", freqHz: 14_035_000, dxCall: "OK1XOE", comment: "12 dB 28 WPM CQ"))
        #expect(b.skimmerCount("OK1XOE") == 1)
    }
}
