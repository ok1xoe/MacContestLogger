import Testing
@testable import MCLCore

/// Port of `command/RitCommandTest` (1).
@Suite struct RitCommandTests {

    private static func p(_ s: String) throws -> CallFieldCommand {
        try #require(try CallFieldCommands.parse(s, currentFreqHz: 14_025_000))
    }

    @Test func ritCommands() throws {
        #expect(try Self.p("RIT 120") == .rit(offsetHz: 120))
        #expect(try Self.p("rit +120") == .rit(offsetHz: 120))
        #expect(try Self.p("RIT -50") == .rit(offsetHz: -50))
        #expect(try Self.p("NORIT") == .rit(offsetHz: 0))
        #expect(try Self.p("RITCLEAR") == .rit(offsetHz: 0))
        guard case .invalid = try Self.p("RIT") else {
            Issue.record("RIT without an argument should be Invalid")
            return
        }
        guard case .invalid = try Self.p("RIT abc") else {
            Issue.record("RIT abc should be Invalid")
            return
        }
    }
}
