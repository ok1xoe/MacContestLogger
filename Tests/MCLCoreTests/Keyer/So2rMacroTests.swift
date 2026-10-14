import Foundation
@testable import MCLCore
import Testing

/// The N1MM two-radio, audio, OTRSP, contest swap and needed-QSO macros of the F-key messages.
@Suite struct So2rMacroTests {

    private static func context(otherHz: Int64) -> CwMessageBuilder.Context {
        var ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 1, rst: "599",
                                           exchange: "", cutNumbers: false, leadingZeros: false)
        ctx.otherFreqHz = otherHz
        ctx.frequencyR = true
        return ctx
    }

    @Test func otherRadioFrequency() {
        let ctx = Self.context(otherHz: 7_025_300)
        #expect(CwMessageBuilder.build("{OTHERFREQ}", ctx).plainText() == "7025R3")
        #expect(CwMessageBuilder.build("{OTHERFREQROUND}", ctx).plainText() == "7025")
        #expect(CwMessageBuilder.build("{OTHERBAND}", ctx).plainText() == "40")
        #expect(CwMessageBuilder.build("{OTHERMHZ}", ctx).plainText() == "7R0")
        #expect(CwMessageBuilder.build("{OTHERFREQCUT}", ctx).plainText() == "T25")
        #expect(CwMessageBuilder.build("{OTHERBAND}", Self.context(otherHz: 144_300_000)).plainText() == "144")
        #expect(CwMessageBuilder.build("{OTHERFREQ}", Self.context(otherHz: 0)).isEmpty)
        #expect(MacroFrequency.mhz(3_525_000, r: false) == "3.5")
    }

    @Test func actionsAndCommands() {
        let message = CwMessageBuilder.build(
            "TU{JUMPRX}{JUMPRXTX}{CONDJUMP}{STOPTX}{STEREOON}{STEREOOFF}{ACTIVEAUDIOTOGGLE}{INACTIVEAUDIOOFF}"
                + "{POPNEXTNEEDEDQ}{CTRLF9}{OTRSP RX1S}{OTRSPOTHER rx}{SWAPCONTESTS}{SWAPCONTESTS4}{SWAPCONTESTS WW CW}",
            Self.context(otherHz: 0))
        #expect(message.unknownMacros.isEmpty)
        #expect(message.actions == [.jumpRx, .jumpRxTx, .condJump, .stopTx, .stereoOn, .stereoOff, .activeAudioToggle,
                                    .inactiveAudioOff, .popNextNeeded])
        #expect(message.commands == [.otherRadioKey(8), .otrsp("RX1S", other: false), .otrsp("RX", other: true),
                                     .swapContests(2), .swapContests(4), .swapContest("WW CW")])
        #expect(MacroCommand.parse("{CTRLF13}") == nil)
        #expect(MacroCommand.parse("{SWAPCONTESTS7}") == nil)
        #expect(MacroCommand.parse("{CTRLHOME}") == nil)
    }

    @Test func voiceMessagesKnowThem() throws {
        #expect(VoiceMessagePlanner.isControlMacro("{JUMPRXTX}"))
        #expect(VoiceMessagePlanner.isControlMacro("{STEREOON}"))
    }
}
