import Testing
@testable import MCLCore

/// N1MM: SH/DX typed in the call field goes to the DX cluster.
@Suite struct CallFieldClusterCommandTests {

    @Test func shDxAndItsArguments() {
        #expect(CallFieldClusterCommand.command("SH/DX") == "SH/DX")
        #expect(CallFieldClusterCommand.command(" sh/dx ") == "SH/DX")
        #expect(CallFieldClusterCommand.command("SH/DX/30") == "SH/DX/30")
        #expect(CallFieldClusterCommand.command("SH/DX 25") == "SH/DX 25")
        #expect(CallFieldClusterCommand.command("SH/DXX") == nil)
        #expect(CallFieldClusterCommand.command("OK1ABC") == nil)
        #expect(CallFieldClusterCommand.command("SH/WWV") == nil)
        #expect(CallFieldClusterCommand.command("") == nil)
    }
}
