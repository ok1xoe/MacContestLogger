import Foundation
@testable import MCLCore
import Testing

/// The built-in modem's macros (N1MM / MMTTY): `{PROFILEn}`, `{ESC}` and `{Hxx}` / `{Hxxxx}`.
@Suite struct BuiltinModemMacroTests {

    static let context = CwMessageBuilder.Context(
        myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 1, rst: "599", exchange: "15",
        cutNumbers: false, leadingZeros: false)

    @Test func profileEscapeAndHexCharacters() {
        let message = CwMessageBuilder.build("{ESC}{PROFILE3}{h41}B{H0043} {H00}{H7}{PROFILE17}", Self.context)
        #expect(message.actions == [.escape])
        #expect(message.commands == [.modemProfile(2)])
        #expect(message.parts == [.text("ABC ")])
        #expect(message.unknownMacros == ["{H00}", "{H7}", "{PROFILE17}"])
        #expect(MacroCommand.parse("{PROFILE16}") == .modemProfile(15))
        #expect(MacroCommand.parse("{PROFILE0}") == nil)
        #expect(CwMessageBuilder.hexCharacter("{H000A}") == 0x0A)
        #expect(CwMessageBuilder.hexCharacter("{HEXCH}") == nil)
    }
}
