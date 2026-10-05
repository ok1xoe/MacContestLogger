import Testing
@testable import MCLCore

/// Port of `dxcluster/RbnLinkTest` (4).
@Suite struct RbnLinkTests {

    @Test func buildsSpotSearchForOwnStation() {
        #expect(RbnLink.spotsOfStation("OK1K") == "https://www.reversebeacon.net/dxsd1/dxsd1.php?f=0&c=OK1K&t=dx")
    }

    @Test func callsignIsUppercasedAndTrimmed() {
        #expect(RbnLink.spotsOfStation("  ok1xoe ") == "https://www.reversebeacon.net/dxsd1/dxsd1.php?f=0&c=OK1XOE&t=dx")
    }

    @Test func slashInPortableCallIsEncoded() {
        // An unencoded slash would break the address into a path.
        #expect(RbnLink.spotsOfStation("OK1K/P") == "https://www.reversebeacon.net/dxsd1/dxsd1.php?f=0&c=OK1K%2FP&t=dx")
    }

    @Test func withoutCallsignThereIsNothingToOpen() {
        #expect(RbnLink.spotsOfStation("") == nil)
        #expect(RbnLink.spotsOfStation(nil) == nil)
    }
}
