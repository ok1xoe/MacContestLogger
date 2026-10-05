import Testing
@testable import MCLCore

@Suite struct SmokeTests {
    @Test func moduleIdentity() {
        #expect(MCLCore.moduleName == "MCLCore")
    }
}
