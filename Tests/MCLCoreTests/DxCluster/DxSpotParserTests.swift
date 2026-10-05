import Testing
@testable import MCLCore

/// Port of `dxcluster/DxSpotParserTest` (6).
@Suite struct DxSpotParserTests {

    @Test func parsesStandardSpotWithTrailingTime() throws {
        let s = try #require(DxSpotParser.parse("DX de OK1ABC:     14025.0  OH2AS         CQ up 2          1234Z"))
        #expect(s.spotter == "OK1ABC")
        #expect(s.freqHz == 14_025_000)
        #expect(s.dxCall == "OH2AS")
        #expect(s.comment == "CQ up 2")
        #expect(s.band == .m20)
    }

    @Test func parsesSpotWithoutComment() throws {
        let s = try #require(DxSpotParser.parse("DX de W1AW-#:   7005.5   DL1XYZ   0959Z"))
        #expect(s.spotter == "W1AW-#")
        #expect(s.freqHz == 7_005_500)
        #expect(s.dxCall == "DL1XYZ")
        #expect(s.comment == "")
    }

    @Test func ignoresNonSpotLines() {
        #expect(DxSpotParser.parse("WWV de VE7CC <18Z> : SFI=120") == nil)
        #expect(DxSpotParser.parse("") == nil)
        #expect(DxSpotParser.parse("Hello and welcome to the cluster") == nil)
    }

    @Test func uppercasesCallsigns() throws {
        let s = try #require(DxSpotParser.parse("DX de ok1abc: 3573.0 ja1abc ft8 2200Z"))
        #expect(s.spotter == "OK1ABC")
        #expect(s.dxCall == "JA1ABC")
    }

    @Test func parsesShowDxHistoryLine() throws {
        // output of the SH/DX command: [time] freq dxCall date time comment <spotter>
        let line = "20:24:36   21150.0  4U1UN       12-Jul-2026 1824Z  CW 13 dB 21 WPM NCDXF B      <ZF9CW-#>"
        let s = try #require(DxSpotParser.parse(line))
        #expect(s.dxCall == "4U1UN")
        #expect(s.freqHz == 21_150_000)
        #expect(s.spotter == "ZF9CW-#")
        #expect(s.comment.contains("NCDXF"))
    }

    @Test func parsesShowDxHistoryLineWithoutLeadingTime() throws {
        let line = "14028.0  EA2CAR      12-Jul-2026 1824Z  CW 21 dB 20 WPM CQ           <DC8YZ-#>"
        let s = try #require(DxSpotParser.parse(line))
        #expect(s.dxCall == "EA2CAR")
        #expect(s.freqHz == 14_028_000)
        #expect(s.spotter == "DC8YZ-#")
    }
}
