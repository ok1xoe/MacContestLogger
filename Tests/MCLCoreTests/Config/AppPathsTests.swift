import Foundation
import Testing
@testable import MCLCore

@Suite struct AppPathsTests {
    @Test func dataDirIsUnderLibraryApplicationSupport() {
        let p = AppPaths.resolveDataDir(userHome: URL(fileURLWithPath: "/Users/op"))
        #expect(p.path == "/Users/op/Library/Application Support/MacContestLogger")
    }

    @Test func configFileSitsInDataDir() {
        #expect(AppPaths.configFile().lastPathComponent == "config.json")
    }

    @Test func logbookFileSitsInDataDir() {
        #expect(AppPaths.logbookFile().lastPathComponent == "logbook.sqlite")
    }
}

@Suite struct AppPathsOverrideTests {
    @Test func dataDirOverrideReplacesTheWholeRoot() {
        let p = AppPaths.resolveDataDir(
            userHome: URL(fileURLWithPath: "/Users/op"), environment: ["MCL_DATA_DIR": "/tmp/mcl-data"])
        #expect(p.path == "/tmp/mcl-data")
    }

    @Test func emptyOrMissingOverrideKeepsTheDefault() {
        let home = URL(fileURLWithPath: "/Users/op")
        let expected = "/Users/op/Library/Application Support/MacContestLogger"
        #expect(AppPaths.resolveDataDir(userHome: home, environment: ["MCL_DATA_DIR": ""]).path == expected)
        #expect(AppPaths.resolveDataDir(userHome: home, environment: ["HOME": "/tmp/x"]).path == expected)
    }
}
