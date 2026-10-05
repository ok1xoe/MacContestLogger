import Testing
@testable import MCLCore

/// Port of `command/OperatorCommandTest` (5).
@Suite struct OperatorCommandTests {

    @Test func bareOponAsksForTheOperator() throws {
        let cmd: OperatorCommand = try #require(OperatorCommand.parse("OPON"))

        #expect(cmd.operator.isEmpty)   // empty = ask via a dialog
    }

    @Test func oponWithCallSetsItStraightAway() {
        #expect(OperatorCommand.parse("OPON OK1XOE")?.operator == "OK1XOE")
    }

    @Test func commandIsCaseInsensitiveAndTolerantToSpacing() {
        #expect(OperatorCommand.parse("  opon   ok1k  ")?.operator == "OK1K")
    }

    @Test func ordinaryCallsignIsNotACommand() {
        #expect(OperatorCommand.parse("OK1XOE") == nil)
        #expect(OperatorCommand.parse("") == nil)
        #expect(OperatorCommand.parse(nil) == nil)
    }

    @Test func callsignStartingWithOponIsNotACommand() {
        // OPONX is a callsign, not a command — otherwise it could not be logged.
        #expect(OperatorCommand.parse("OPONX") == nil)
    }
}
