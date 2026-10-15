import Foundation
@testable import MCLCore
import Testing

/// N1MM's multi-user macros `{MESSAGE}`, `{PASS …}`, `{PASSMSG …}`, `{LASTPASSEDFREQ}`: substituted only with the
/// network log connected; the text after `{MESSAGE}` is never keyed.
@Suite struct MultiUserMacroTests {

    static let targets: [MacroPassTarget] = [
        MacroPassTarget(station: "OP2", freqHz: 14_025_000, passHz: 0, run: false),
        MacroPassTarget(station: "OP3", freqHz: 14_250_000, passHz: 14_190_400, run: false),
        MacroPassTarget(station: "OP4", freqHz: 7_010_000, passHz: 7_035_000, run: true),
        MacroPassTarget(station: "OP5", freqHz: 7_040_000, passHz: 0, run: false),
    ]

    private static func context(multiUser: Bool) -> CwMessageBuilder.Context {
        var ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 7, rst: "599",
                                           exchange: "", cutNumbers: false, leadingZeros: false)
        ctx.multiUser = multiUser
        ctx.passTargets = targets
        ctx.lastPassedFreqHz = 21_025_500
        return ctx
    }

    @Test func targetsByNameOrBand() {
        #expect(MultiUserMacro.target("op2", in: Self.targets)?.station == "OP2")
        // 20 m: no run station, the one with a pass frequency first.
        #expect(MultiUserMacro.target("14000", in: Self.targets)?.station == "OP3")
        // 40 m: the run station.
        #expect(MultiUserMacro.target("7000", in: Self.targets)?.station == "OP4")
        #expect(MultiUserMacro.target("21000", in: Self.targets) == nil)
        #expect(MultiUserMacro.target("OP9", in: Self.targets) == nil)
        #expect(MultiUserMacro.target(" ", in: Self.targets) == nil)
        #expect(Self.targets[0].targetHz == 14_025_000)
        #expect(Self.targets[1].targetHz == 14_190_400)
    }

    @Test func messageTargets() {
        #expect(MultiUserMacro.messageTarget("OP2 need 20m", stations: ["OP2"]) == ("OP2", "need 20m"))
        #expect(MultiUserMacro.messageTarget("- to all", stations: ["OP2"]) == ("", "to all"))
        #expect(MultiUserMacro.messageTarget("hello OP2", stations: ["OP2"]) == ("", "hello OP2"))
        #expect(MultiUserMacro.messageTarget("  ", stations: []) == ("", ""))
    }

    @Test func messageTextIsNeverKeyed() {
        let on = CwMessageBuilder.build("TU {MESSAGE} OP2 pass ! on {PASS 14000} ~ok", Self.context(multiUser: true))
        #expect(on.plainText() == "TU")
        #expect(on.commands == [.passAlert(station: "OP3", hz: 14_190_400), .networkMessage("OP2 pass DL1ABC on 14190 ~ok")])
        let off = CwMessageBuilder.build("TU {MESSAGE} OP2 pass !", Self.context(multiUser: false))
        #expect(off.plainText() == "TU")
        #expect(off.commands.isEmpty)
        #expect(off.unknownMacros.isEmpty)
    }

    @Test func passMacrosNeedTheNetwork() {
        let on = CwMessageBuilder.build("QSY {PASS 7000} {LASTPASSEDFREQ}{PASSMSG OP2}", Self.context(multiUser: true))
        #expect(on.plainText() == "QSY 7035 21025R5")
        #expect(on.commands == [.passAlert(station: "OP4", hz: 7_035_000), .passLastQso("OP2")])
        let off = CwMessageBuilder.build("QSY {PASS 7000} {LASTPASSEDFREQ}{PASSMSG OP2}", Self.context(multiUser: false))
        #expect(off.plainText() == "QSY")
        #expect(off.commands.isEmpty)
        #expect(off.unknownMacros.isEmpty)
    }
}
