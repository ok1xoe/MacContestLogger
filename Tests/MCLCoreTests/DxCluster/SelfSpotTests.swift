import Foundation
import Testing
@testable import MCLCore

/// Port of `dxcluster/SelfSpotTest` (8).
@Suite struct SelfSpotTests {

    private static let at = dxInstant("2026-08-19T12:00:00Z")

    private func spot(_ spotter: String, _ dxCall: String, _ comment: String) -> DxSpot {
        DxSpot(spotter: spotter, freqHz: 14_025_000, dxCall: dxCall, comment: comment)
    }

    @Test func humanSpotOfOwnCallIsDetected() throws {
        let s = try #require(try SelfSpot.detect(spot("DL1ABC", "OK1K", "cq test 599"), myCall: "OK1K", at: Self.at))

        #expect(s.spotter == "DL1ABC")
        #expect(s.freqHz == 14_025_000)
        #expect(!s.rbn)
        #expect(s.snrDb == nil)
        #expect(s.wpm == nil)
    }

    @Test func skimmerSpotIsRecognisedByTheHashSuffixAndCarriesSnrAndSpeed() throws {
        // RBN skimmers have the suffix -# in the callsign and the comment carries SNR and speed.
        let s = try #require(try SelfSpot.detect(spot("VE7CC-#", "OK1K", "CW 21 dB 25 WPM CQ"),
                                                 myCall: "OK1K", at: Self.at))

        #expect(s.rbn)
        #expect(s.snrDb == 21)
        #expect(s.wpm == 25)
    }

    @Test func negativeSnrIsKept() throws {
        // Digital modes also report negative SNR; it must not be lost or flipped to positive.
        let s = try #require(try SelfSpot.detect(spot("DK9IP-#", "OK1K", "FT8 -12 dB 15 WPM CQ"),
                                                 myCall: "OK1K", at: Self.at))

        #expect(s.snrDb == -12)
    }

    @Test func skimmerWithoutHashSuffixIsStillRecognisedByItsComment() throws {
        let s = try #require(try SelfSpot.detect(spot("OH6BG", "OK1K", "CW 9 dB 28 WPM CQ"),
                                                 myCall: "OK1K", at: Self.at))

        #expect(s.rbn)
        #expect(s.snrDb == 9)
    }

    @Test func someoneElsesCallIsNotSelfSpot() throws {
        #expect(try SelfSpot.detect(spot("DL1ABC", "OM3XYZ", "cq"), myCall: "OK1K", at: Self.at) == nil)
    }

    @Test func matchingIsCaseInsensitiveAndIgnoresSpacing() throws {
        #expect(try SelfSpot.detect(spot("DL1ABC", "ok1k", "cq"), myCall: "  OK1K ", at: Self.at) != nil)
    }

    @Test func withoutOwnCallNothingIsDetected() throws {
        #expect(try SelfSpot.detect(spot("DL1ABC", "OK1K", "cq"), myCall: "", at: Self.at) == nil)
        #expect(try SelfSpot.detect(spot("DL1ABC", "OK1K", "cq"), myCall: nil, at: Self.at) == nil)
    }

    @Test func portableSuffixIsNotTheSameStation() throws {
        // OK1K/P is a different callsign; reporting it as "you were spotted" would be misleading.
        #expect(try SelfSpot.detect(spot("DL1ABC", "OK1K/P", "cq"), myCall: "OK1K", at: Self.at) == nil)
    }
}
