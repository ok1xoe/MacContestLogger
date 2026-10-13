import Foundation
@testable import MCLCore
import Testing

/// The digital message macros (N1MM): `{TX}`/`{RX}`, `{ENTERLF}`, `{CLRRX}`/`{CLRTX}`, `{ALT-T}`/`{ALT-Q}`,
/// `{FILE:x}`, `{DI1}`…`{DI24}`, `{NAME}`, the Digital Interface buttons and `.mc` files.
@Suite struct DigitalMessageTests {

    private static func context(_ ctx: (inout CwMessageBuilder.Context) -> Void = { _ in }) -> CwMessageBuilder.Context {
        var base = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 7, rst: "599",
                                            exchange: "15", cutNumbers: false, leadingZeros: false, now: nil)
        ctx(&base)
        return base
    }

    @Test func enterLfIsALineBreakInDigitalAndASpaceInCw() {
        let message = CwMessageBuilder.build("{TX}{ENTERLF}! TU {ENTER}* QRZ {RX}", Self.context())
        #expect(message.actions == [.digitalTx, .digitalRx])
        #expect(message.plainText() == "DL1ABC TU \nOK1XOE QRZ")
        #expect(!message.withoutNewlines.plainText().contains("\n"))
    }

    @Test func fileNameAndButtons() {
        let ctx = Self.context { ctx in
            ctx.hisName = "HANS"
            ctx.digitalButtons = ["", "TEST {NAME}"]
            ctx.fileText = { name in name == "intro.txt" ? "LINE ONE\nLINE TWO" : nil }
        }
        #expect(CwMessageBuilder.build("CQ {di2}", ctx).plainText() == "CQ TEST HANS")
        let file = CwMessageBuilder.build("{FILE:intro.txt}", ctx)
        #expect(file.plainText() == "LINE ONE \n LINE TWO" || file.plainText() == "LINE ONE\nLINE TWO")
        #expect(CwMessageBuilder.build("{FILE:missing.txt}", ctx).unknownMacros == ["{FILE:MISSING.TXT}"])
        #expect(CwMessageBuilder.build("{CLRRX}{CLRTX}{ALT-T}{ALT-Q}", ctx).actions
                == [.clearRx, .clearTx, .toggleTx, .jumpCq])
    }

    private static func keyContext(_ text: String, mode: Mode) -> FunctionKeyContext {
        var keys: [FunctionKeyMessage] = (0..<12).map { FunctionKeyMessage(label: "F\($0 + 1)", text: "") }
        keys[0] = FunctionKeyMessage(label: "X", text: text)
        let set = FunctionKeySet(run: keys, sp: keys)
        return FunctionKeyContext(mode: mode, digitalReady: true, postContest: false, run: true, call: "DL1ABC",
                                  rstSent: "599", freqHz: 14_080_000, progress: .empty, stationCall: "OK1XOE",
                                  voice: set, cw: set, digital: set, cwBase: Self.context())
    }

    @Test func txWithoutRxKeepsTransmitting() {
        let held = FunctionKeyRouter.send([0], context: Self.keyContext("{TX} CQ TEST", mode: .rtty))
        #expect(held.transmission == .digital(text: "CQ TEST", index: 0, returnToRx: false))
        #expect(held.actions.isEmpty)
        let both = FunctionKeyRouter.send([0], context: Self.keyContext("{TX} CQ TEST {RX}", mode: .rtty))
        #expect(both.transmission == .digital(text: "CQ TEST", index: 0, returnToRx: true))
        let plain = FunctionKeyRouter.send([0], context: Self.keyContext("CQ TEST", mode: .rtty))
        #expect(plain.transmission == .digital(text: "CQ TEST", index: 0))
        let alone = FunctionKeyRouter.send([0], context: Self.keyContext("{RX}", mode: .rtty))
        #expect(alone.transmission == nil)
        #expect(alone.actions == [.digitalRx])
        // CW ignores the digital controls.
        let cw = FunctionKeyRouter.send([0], context: Self.keyContext("{TX} CQ {CLRRX}{RX}", mode: .cw))
        #expect(cw.actions == [.clearRx])
    }

    @Test func digitalButtonTemplate() {
        let out = FunctionKeyRouter.sendDigitalTemplate("{TX} ! 599 {RX}", context: Self.keyContext("", mode: .rtty))
        #expect(out.transmission == .digital(text: "DL1ABC 599", index: -1, returnToRx: true))
        let cw = FunctionKeyRouter.sendDigitalTemplate("CQ", context: Self.keyContext("", mode: .cw))
        #expect(cw.transmission == nil && cw.status != nil)
    }

    @Test func mcFiles() {
        let messages = McMessages.parse("# comment\nCQ,{TX} CQ TEST * {RX}\n\nTU, TU ! QRZ\nEmpty\n")
        #expect(messages == [FunctionKeyMessage(label: "CQ", text: "{TX} CQ TEST * {RX}"),
                             FunctionKeyMessage(label: "TU", text: "TU ! QRZ"),
                             FunctionKeyMessage(label: "Empty", text: "")])
        #expect(McMessages.parse(McMessages.format(messages)) == messages)
        #expect(DigitalConfig.buttonCount(17) == 16 && DigitalConfig.buttonCount(99) == 24
                && DigitalConfig.buttonCount(-3) == 0)
    }
}
