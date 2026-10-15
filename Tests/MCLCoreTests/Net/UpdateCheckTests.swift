import Foundation
import Testing
@testable import MCLCore

/// The program version check (N1MM „Check for New Program Version"): the version order, the API answer and the
/// outcome for the running version.
@Suite struct UpdateCheckTests {

    @Test func versionsCompareNumericallyPartByPart() {
        #expect(UpdateCheck.compare("v0.10.0", "0.9.1") == 1)
        #expect(UpdateCheck.compare("v0.9.0", "0.9.0") == 0)
        #expect(UpdateCheck.compare("0.9", "0.9.0") == 0)
        #expect(UpdateCheck.compare("v1.0.0", "v1.0.1") == -1)
        #expect(UpdateCheck.compare("V2.0.0", "1.99.99") == 1)
        // A pre-release is older than its release.
        #expect(UpdateCheck.compare("v1.0.0-rc1", "1.0.0") == -1)
        #expect(UpdateCheck.compare("1.0.0", "1.0.0-rc2") == 1)
        #expect(UpdateCheck.compare("dev", "1.0.0") == nil)
        #expect(UpdateCheck.compare("1..0", "1.0.0") == nil)
        #expect(UpdateCheck.compare("", "1.0.0") == nil)
    }

    @Test func theReleaseIsReadFromTheApiAnswer() throws {
        let body = Data(#"{"tag_name":"v0.9.2","html_url":"https://github.com/ok1xoe/MacContestLogger/releases/tag/v0.9.2","draft":false}"#.utf8)
        let release = try #require(UpdateCheck.parse(body))
        #expect(release.tag == "v0.9.2")
        #expect(release.version == "0.9.2")
        #expect(release.pageUrl == "https://github.com/ok1xoe/MacContestLogger/releases/tag/v0.9.2")
        // A page outside the project's releases is never opened: the releases page instead.
        let foreign = Data(#"{"tag_name":"v1.0.0","html_url":"https://example.com/x"}"#.utf8)
        #expect(UpdateCheck.parse(foreign)?.pageUrl == UpdateCheck.releasesPageUrl)
        #expect(UpdateCheck.parse(Data("not json".utf8)) == nil)
        #expect(UpdateCheck.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"nightly"}"#.utf8)) == nil)
    }

    @Test func theOutcomeComparesWithTheRunningVersion() {
        let body = Data(#"{"tag_name":"v0.9.2","html_url":"https://github.com/ok1xoe/MacContestLogger/releases/tag/v0.9.2"}"#.utf8)
        let release = UpdateCheck.Release(tag: "v0.9.2",
                                          pageUrl: "https://github.com/ok1xoe/MacContestLogger/releases/tag/v0.9.2")
        #expect(UpdateCheck.evaluate(status: 200, body: body, current: "0.9.1") == .newer(release))
        #expect(UpdateCheck.evaluate(status: 200, body: body, current: "0.9.2") == .upToDate(release))
        #expect(UpdateCheck.evaluate(status: 200, body: body, current: "0.10.0") == .upToDate(release))
        // An unknown running version (a development build) is offered the release.
        #expect(UpdateCheck.evaluate(status: 200, body: body, current: nil) == .newer(release))
        #expect(UpdateCheck.evaluate(status: 404, body: Data(), current: "0.9.1") == .failed(status: 404))
        #expect(UpdateCheck.evaluate(status: 200, body: Data("<html>".utf8), current: "0.9.1") == .failed(status: nil))
    }

    @Test func theApiAndThePageArePublicGitHubAddresses() {
        #expect(UpdateCheck.latestReleaseUrl == "https://api.github.com/repos/ok1xoe/MacContestLogger/releases/latest")
        #expect(UpdateCheck.releasesPageUrl.hasPrefix(UpdateCheck.releasePagePrefix))
    }
}
