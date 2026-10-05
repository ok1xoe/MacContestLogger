import Foundation
import Testing
@testable import MCLCore

/// The repository-root `contest-data/` is what `DefinitionUpdater.defaultBase` serves to users;
/// it must stay byte-identical to the test fixture corpus.
@Suite struct PublishedContestDataTests {

    @Test func rootContestDataMatchesFixtureCorpus() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let published = repoRoot.appendingPathComponent("contest-data")
        guard FileManager.default.fileExists(atPath: published.path) else { return }  // source tree not available
        let fixture = try ContestDataLayoutTests.contestDataRoot()

        let publishedFiles = try ContestDataLayoutTests.relativeFiles(under: published)
        let fixtureFiles = try ContestDataLayoutTests.relativeFiles(under: fixture)
        #expect(publishedFiles == fixtureFiles)
        for path in publishedFiles where fixtureFiles.contains(path) {
            let a = try Data(contentsOf: published.appendingPathComponent(path))
            let b = try Data(contentsOf: fixture.appendingPathComponent(path))
            #expect(a == b, "\(path) differs between contest-data/ and the fixture corpus")
        }
    }
}
