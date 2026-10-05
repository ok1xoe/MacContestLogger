import Foundation
import Testing
@testable import MCLCore

@Suite struct CoreResourcesTests {
    @Test func appLooksInContentsResourcesFirstThenBesideTheBundle() {
        let app = URL(fileURLWithPath: "/Applications/MacContestLogger.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let paths: [String] = CoreResources.candidates(mainBundleURL: app, mainResourceURL: resources).map(\.path)
        #expect(paths == [
            "/Applications/MacContestLogger.app/Contents/Resources/MacContestLogger_MCLCore.bundle",
            "/Applications/MacContestLogger.app/MacContestLogger_MCLCore.bundle",
        ])
    }

    @Test func commandLineToolHasOneCandidateBesideTheExecutable() {
        let dir = URL(fileURLWithPath: "/opt/mcl/bin", isDirectory: true)
        let paths: [String] = CoreResources.candidates(mainBundleURL: dir, mainResourceURL: dir).map(\.path)
        #expect(paths == ["/opt/mcl/bin/MacContestLogger_MCLCore.bundle"])
    }

    @Test func onlyDotAppIsAnApplication() {
        #expect(CoreResources.isApp(URL(fileURLWithPath: "/x/MacContestLogger.app")))
        #expect(CoreResources.isApp(URL(fileURLWithPath: "/x/Other.APP")))
        #expect(!CoreResources.isApp(URL(fileURLWithPath: "/x/.build/debug")))
    }

    @Test func locateSkipsMissingCandidatesAndPlainFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcl-core-resources-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        // A plain file of the bundle's name in Contents/Resources is not a bundle.
        try Data().write(to: resources.appendingPathComponent(CoreResources.bundleName))
        #expect(CoreResources.locate(mainBundleURL: root, mainResourceURL: resources) == nil)
        let beside = root.appendingPathComponent(CoreResources.bundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: beside, withIntermediateDirectories: true)
        #expect(CoreResources.locate(mainBundleURL: root, mainResourceURL: resources)?.path == beside.path)
    }

    @Test func outsideAnAppTheBundleIsFound() {
        // Tests run outside an `.app`, so the lookup falls back to `Bundle.module` as before.
        #expect(CoreResources.bundle != nil)
        #expect(CoreResources.bundle?.url(forResource: "menu", withExtension: "json") != nil)
    }
}
