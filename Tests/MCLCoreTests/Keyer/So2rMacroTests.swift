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

    @Test func perRadioMessageSelection() {
        #expect(RadioMessageMacro.select("{FKEY(F1%F9)}", radio: 1) == "{F1}")
        #expect(RadioMessageMacro.select("{fkey(3 % 12)}", radio: 2) == "{F12}")
        #expect(RadioMessageMacro.select("TU {FKEY(CQ {MYCALL} UP%CQ {MYCALL} TEST)} X", radio: 2)
            == "TU CQ {MYCALL} TEST X")
        #expect(RadioMessageMacro.select("{FKEY(A%B)}{FKEY(C%D)}", radio: 1) == "AC")
        // A missing radio 2 part sends nothing on radio 2; F13 / F0 are text, not keys.
        #expect(RadioMessageMacro.select("{FKEY(CQ)}", radio: 2) == "")
        #expect(RadioMessageMacro.select("{FKEY(F13%F0)}", radio: 1) == "F13")
        #expect(RadioMessageMacro.select("{FKEY(F13%F0)}", radio: 2) == "F0")
        // Without the closing `)}` the text stays as written.
        #expect(RadioMessageMacro.select("CQ {FKEY(F1%F2", radio: 1) == "CQ {FKEY(F1%F2")
        #expect(RadioMessageMacro.select("CQ TEST", radio: 2) == "CQ TEST")
    }

    @Test func perRadioMessageThroughTheRouter() {
        let base = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 7, rst: "",
                                            exchange: "#", cutNumbers: false, leadingZeros: false, now: nil)
        let run: [FunctionKeyMessage] = ["{FKEY(F2%F3)}", "CQ ONE", "CQ TWO", "{FKEY(TU%TU {CTRLF1})}"]
            .enumerated().map { FunctionKeyMessage(label: "F\($0.offset + 1)", text: $0.element) }
        var context = FunctionKeyContext(
            mode: .cw, digitalReady: false, postContest: false, run: true, call: "", rstSent: "", freqHz: 14_025_000,
            progress: .empty, stationCall: "OK1XOE", voice: FunctionKeySet(run: [], sp: []),
            cw: FunctionKeySet(run: run, sp: []), digital: FunctionKeySet(run: [], sp: []), cwBase: base)
        func sent(_ index: Int) -> (String, [MacroCommand]) {
            let out = FunctionKeyRouter.send([index], context: context)
            guard case .cw(let message, _)? = out.transmission else { return ("", out.commands) }
            return (message.plainText().trimmingCharacters(in: .whitespaces), out.commands)
        }
        #expect(sent(0).0 == "CQ ONE")
        #expect(sent(3).1.isEmpty)
        context.radio = 2
        #expect(sent(0).0 == "CQ TWO")
        #expect(sent(3).1 == [.otherRadioKey(0)])
    }
}
