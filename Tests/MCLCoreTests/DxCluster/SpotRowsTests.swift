import Foundation
import Testing
@testable import MCLCore

/// `SpotAnalyzer.spotRows` and its helpers, read from `ContestController.kt:577-607, 716-729` (v1.1.1); values
/// measured on the JVM (`SpotAnalysisJava`).
@Suite struct SpotRowsTests {

    typealias F = SpotAnalysisFixture

    @Test func rowsAreSortedByFrequencyAndSkipSpotsWithoutBand() throws {
        let a = try SpotAnalyzerTests.cqww()
        let rows = a.spotRows([
            F.spot("OK1RR", 14_010_000, "W1AW", ""),
            F.spot("OK1RR", 3_000_000, "OK1ABC", ""),
            F.spot("OK1RR", 14_010_000, "VE3ABC", "CW 7 dB"),
            F.spot("OK1ME", 3_510_000, "LU1ABC", "", true),
        ])
        #expect(rows.map(\.call) == ["LU1ABC", "W1AW", "VE3ABC"])   // stable for equal frequencies
        #expect(rows[0] == SpotRow(call: "LU1ABC", freqHz: 3_510_000, azimuth: 239, mode: "CW", newMultCount: 2,
                                   dupe: false, snr: nil, points: 3, spotter: "OK1ME"))
        #expect(rows[2].azimuth == nil && rows[2].snr == 7)          // Canada has no coordinates
    }

    @Test func offContestModeRowHasNoMultiplierAndNoDupe() throws {
        let a = try SpotAnalyzerTests.cqww()
        // `:590-601`: a phone spot in a CW contest keeps its points but loses mult and dupe.
        let row = try #require(a.spotRows([F.spot("OK1RR", 14_250_000, "LU1ABC", "SSB")]).first)
        #expect(row.mode == "SSB" && row.newMultCount == 0 && !row.dupe && !row.isMult && row.points == 3)
        let dupe = try #require(a.spotRows([F.spot("OK1RR", 14_025_000, "DL1ABC", "")]).first)
        #expect(dupe.dupe && dupe.points == 1)
    }

    @Test func blankCallsAndUnknownDxccStillMakeRows() throws {
        let a = try SpotAnalyzerTests.cqww()
        let rows = a.spotRows([F.spot("OK1RR", 14_015_000, "", ""), F.spot("OK1RR", 14_020_000, "ZZ9ZZ", "")])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.azimuth == nil && $0.points == 0 && $0.newMultCount == 0 })
    }

    @Test func outsideAContestThereAreNoRows() throws {
        #expect(try F.environment().analyzer().spotRows(F.cqww).isEmpty)
    }

    @Test func azimuthFromMyGrid() throws {
        let a = try SpotAnalyzerTests.cqww()
        #expect(a.azimuthTo(call: "JA1ABC") == 43)
        #expect(a.azimuthTo(call: "W1AW") == 309)
        #expect(a.azimuthTo(call: "VE3ABC") == nil)
        #expect(a.azimuthTo(call: "ZZ9ZZ") == nil)
    }

    @Test func snrIsTheFirstAsciiNumberBeforeDb() {
        #expect(SpotAnalyzer.parseSnr("CW 25 dB 28 WPM CQ") == 25)
        #expect(SpotAnalyzer.parseSnr("-12 dB") == 12)
        #expect(SpotAnalyzer.parseSnr("7 db") == nil)                // case-sensitive
        #expect(SpotAnalyzer.parseSnr("2147483648 dB") == nil)       // toIntOrNull overflow
        #expect(SpotAnalyzer.parseSnr("\u{0661}\u{0662} dB") == nil) // Java \d is ASCII
        #expect(SpotAnalyzer.parseSnr("12\u{00A0}dB") == nil)        // Java \s is ASCII
        #expect(SpotAnalyzer.parseSnr(nil) == nil)
    }
}
