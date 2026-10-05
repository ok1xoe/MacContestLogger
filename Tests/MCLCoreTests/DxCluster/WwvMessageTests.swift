import Testing
@testable import MCLCore

/// Port of `dxcluster/WwvMessageTest` (5).
@Suite struct WwvMessageTests {

    @Test func parsesStandardClusterWwvLine() throws {
        let m = try #require(try WwvMessage.parse("WWV de VE7CC <18Z> :   SFI=142, A=8, K=3, No Storms -> No Storms"))

        #expect(m.spotter == "VE7CC")
        #expect(m.hourUtc == 18)
        #expect(m.sfi == 142)
        #expect(m.aIndex == 8)
        #expect(m.kIndex == 3)
        #expect(m.conditions == "No Storms -> No Storms")
    }

    @Test func toleratesSpacingAndLowercase() throws {
        let m = try #require(try WwvMessage.parse("wwv de w0mu <5z> : sfi=70,a=4,k=2,quiet -> quiet"))

        #expect(m.spotter == "W0MU")
        #expect(m.hourUtc == 5)
        #expect(m.sfi == 70)
        #expect(m.aIndex == 4)
        #expect(m.kIndex == 2)
        #expect(m.conditions == "quiet -> quiet")
    }

    @Test func wcyLineIsNotAWwvMessage() throws {
        // WCY is a different format (geomagnetic messages from DK0WCY) — it does not belong here.
        #expect(try WwvMessage.parse("WCY de DK0WCY <18> : K=2 expK=2 A=6 R=95") == nil)
    }

    @Test func ordinarySpotIsNotAWwvMessage() throws {
        #expect(try WwvMessage.parse("DX de OK1XOE:  14025.0  DL1ABC  cq test  1234Z") == nil)
        #expect(try WwvMessage.parse("") == nil)
        #expect(try WwvMessage.parse(nil) == nil)
    }

    @Test func lineWithoutIndicesIsRejectedRatherThanGuessed() throws {
        // Without SFI/A/K the row would carry zero values that would look like data.
        #expect(try WwvMessage.parse("WWV de VE7CC <18Z> :  nic tu není") == nil)
    }
}
