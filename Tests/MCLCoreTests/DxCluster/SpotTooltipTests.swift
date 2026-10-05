import Foundation
import Testing
@testable import MCLCore

/// `SpotAnalyzer.spotTooltip`, read from `ContestController.kt:700-714` (v1.1.1); Czech values measured on the JVM.
@Suite struct SpotTooltipTests {

    typealias F = SpotAnalysisFixture

    @Test func czechTooltipWithGridAndComment() throws {
        let a = try SpotAnalyzerTests.cqww()
        #expect(a.spotTooltip(F.spot("OK1RR", 28_020_000, "JA1ABC", "5 dB"))
                == "JA1ABC   28020.0 kHz\nMód: CW (CW, vyhodnocuje se)\nGrid: PM95 → pole PM\nSpotter: OK1RR\nKomentář: 5 dB")
        #expect(a.spotTooltip(F.spot("OK1RR", 14_074_000, "VE3ABC", ""))
                == "VE3ABC   14074.0 kHz\nMód: FT8 (DIGI, ignorováno)\nSpotter: OK1RR")
    }

    @Test func undeterminableCategoryAndBlankComment() throws {
        let a = try F.environment().analyzer()
        #expect(a.spotTooltip(F.spot("OK1RR", 3_000_000, "OK1ABC", " "))
                == "OK1ABC   3000.0 kHz\nMód: CW (neurčitelný, vyhodnocuje se)\nSpotter: OK1RR")
    }

    @Test func onlyKotlinTrTextsAreTranslated() throws {
        let a = try SpotAnalyzerTests.cqww()
        let english = LogTableEditTests.translator([
            "\nMód: ": "\nMode: ", "neurčitelný": "undeterminable", ", ignorováno": ", ignored",
            "\nKomentář: ": "\nComment: ",
        ])
        #expect(a.spotTooltip(F.spot("OK1RR", 14_250_000, "LU1ABC", "SSB"), translator: english)
                == "LU1ABC   14250.0 kHz\nMode: SSB (PHONE, ignored)\nSpotter: OK1RR\nComment: SSB")
        // `", vyhodnocuje se"`, `"\nGrid: "` and `" → pole "` have no `tr` in Kotlin.
        #expect(a.spotTooltip(F.spot("OK1RR", 14_010_000, "W1AW", ""), translator: english)
                == "W1AW   14010.0 kHz\nMode: CW (CW, vyhodnocuje se)\nGrid: FN31 → pole FN\nSpotter: OK1RR")
    }
}

/// QO-100 (post-port): a label only, the band stays 3 cm / 13 cm.
@Suite struct Qo100Tests {

    @Test func downlinkFrequenciesAreLabelled() {
        #expect(Qo100.label(freqHz: 10_489_500_000) == "QO-100")
        #expect(Qo100.label(freqHz: 10_489_750_000) == "QO-100")
        #expect(Qo100.label(freqHz: 10_490_000_000) == "QO-100")
        #expect(Qo100.label(freqHz: 10_491_000_000) == "QO-100")
        #expect(Qo100.label(freqHz: 10_495_000_000) == "QO-100")
        #expect(Qo100.label(freqHz: 10_499_000_000) == "QO-100")
        #expect(Qo100.label(freqHz: 10_490_000_001) == nil)
        #expect(Qo100.label(freqHz: 10_499_000_001) == nil)
        #expect(Qo100.label(freqHz: 10_368_100_000) == nil)
    }

    @Test func theUplinkNeedsTheFlag() {
        #expect(Qo100.label(freqHz: 2_400_250_000) == nil)
        #expect(Qo100.label(freqHz: 2_400_250_000, isUplink: true) == "QO-100")
        #expect(Qo100.label(freqHz: 2_450_000_001, isUplink: true) == nil)
        #expect(Qo100.label(freqHz: 1_296_200_000, isUplink: true) == nil)
    }

    @Test func theLnbIntermediateFrequencyAndTheGapHaveNoLabel() {
        #expect(Qo100.label(freqHz: 739_750_000) == nil)
        #expect(Qo100.label(freqHz: 1_427_750_000, isUplink: true) == nil)
    }

    @Test func theBandStaysTheMicrowaveOne() {
        #expect(Band.from(frequencyHz: 10_489_750_000) == .cm3)
        #expect(Band.from(frequencyHz: 2_400_250_000) == .cm13)
    }

    @Test func theJavaTableSwitchTurnsTheLabelOff() {
        Band.$javaV111Table.withValue(true) {
            #expect(Qo100.label(freqHz: 10_489_750_000) == nil)
        }
    }

    @Test func theTooltipNamesTheSatellite() throws {
        let a = try SpotAnalyzerTests.cqww()
        let spot = SpotAnalysisFixture.spot("OK1RR", 10_489_750_000, "A71BX", "")
        #expect(a.spotTooltip(spot).hasSuffix("\nSpotter: OK1RR\nSatelit: QO-100"))
        let english = LogTableEditTests.translator(["\nSatelit: ": "\nSatellite: "])
        #expect(a.spotTooltip(spot, translator: english).hasSuffix("\nSatellite: QO-100"))
        // An ordinary 3 cm spot has no such line.
        let plain = SpotAnalysisFixture.spot("OK1RR", 10_368_100_000, "OK2A", "")
        #expect(!a.spotTooltip(plain).contains("QO-100"))
    }
}
