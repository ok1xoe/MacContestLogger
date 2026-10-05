import Testing
@testable import MCLCore

/// Port of `command/ScriptCommandTest` (1).
@Suite struct ScriptCommandTests {

    @Test func scriptCommand() throws {
        #expect(try CallFieldCommands.parse("script run20", currentFreqHz: 0) == .runScript(name: "RUN20"))
        guard case .invalid = try #require(try CallFieldCommands.parse("SCRIPT", currentFreqHz: 0)) else {
            Issue.record("SCRIPT without a name should be Invalid")
            return
        }
    }
}
