import Testing
@testable import MCLCore

/// Port of `hamqth/HamQthLogTest` (2) — password mask in the URL.
@Suite struct HamQthLogTests {

    @Test func masksPasswordInUrl() {
        let masked = HamQthLog.mask("https://www.hamqth.com/xml.php?u=ok1xoe&p=secret123")
        #expect(!masked.contains("secret123"), "the password must not stay in the log")
        #expect(masked == "https://www.hamqth.com/xml.php?u=ok1xoe&p=***")
    }

    @Test func leavesLookupUrlUntouched() {
        let url = "https://www.hamqth.com/xml.php?id=abc&callsign=OK1XOE&prg=MacContestLogger"
        #expect(HamQthLog.mask(url) == url)
    }
}
