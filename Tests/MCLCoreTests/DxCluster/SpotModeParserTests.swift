import Testing
@testable import MCLCore

/// Port of `dxcluster/SpotModeParserTest` (9).
@Suite struct SpotModeParserTests {

    @Test func cwFromRbnComment() {
        #expect(SpotModeParser.fromComment("CW 25 dB 20 WPM CQ") == "CW")
    }

    @Test func ft8Comment() {
        #expect(SpotModeParser.fromComment("FT8  -12 dB  1500 Hz") == "FT8")
    }

    @Test func ft4Comment() {
        #expect(SpotModeParser.fromComment("FT4 -08 dB") == "FT4")
    }

    @Test func rttyComment() {
        #expect(SpotModeParser.fromComment("RTTY 599 test") == "RTTY")
    }

    @Test func pskVariantsMapToPsk() {
        #expect(SpotModeParser.fromComment("PSK31 cq") == "PSK")
        #expect(SpotModeParser.fromComment("BPSK63") == "PSK")
    }

    @Test func phoneVariantsMapToSsb() {
        #expect(SpotModeParser.fromComment("USB nice signal") == "SSB")
        #expect(SpotModeParser.fromComment("calling LSB") == "SSB")
        #expect(SpotModeParser.fromComment("SSB 59") == "SSB")
        #expect(SpotModeParser.fromComment("PH contest") == "SSB")
    }

    @Test func noModeKeywordIsEmpty() {
        #expect(SpotModeParser.fromComment("tnx qso 73") == nil)
        #expect(SpotModeParser.fromComment("") == nil)
        #expect(SpotModeParser.fromComment(nil) == nil)
    }

    @Test func wordBoundaryAvoidsFalseMatch() {
        // "SCW" or "PHONE" inside a word must not wrongly match as CW/PH
        #expect(SpotModeParser.fromComment("WESCWOOD") == nil)
    }

    @Test func phoneWordMatches() {
        #expect(SpotModeParser.fromComment("phone qso") == "SSB")
    }
}
