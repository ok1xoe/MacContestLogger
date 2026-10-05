import Foundation
import Testing
@testable import MCLCore

/// F-keys of the entry window (`functionKeys`, `EP:719-755`; key branch `EP:953-964`; `AS:1315-1350, 1465-1578`).
@Suite struct FunctionKeyRouterTests {

    private static func msgs(_ prefix: String, _ texts: [String]) -> [FunctionKeyMessage] {
        texts.enumerated().map { FunctionKeyMessage(label: prefix + String($0.offset + 1), text: $0.element) }
    }

    private static let cwRun = msgs("R", ["CQ {MYCALL} TEST", "{CALL} 5NN {EXCH}", "TU {LOG}", "", "{CALL}", "{FOO} X"])
    private static let cwSp = msgs("S", ["", "5NN {EXCH}", "TU", "{MYCALL}", "{CALL}"])

    private static func context(mode: Mode = .cw, run: Bool = true, call: String = " w1aw ", postContest: Bool = false,
                                digitalReady: Bool = false) -> FunctionKeyContext {
        let base = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 7, rst: "",
                                            exchange: "#", cutNumbers: true, leadingZeros: true, now: nil)
        return FunctionKeyContext(
            mode: mode, digitalReady: digitalReady, postContest: postContest, run: run, call: call, rstSent: "",
            freqHz: 14_025_000, progress: .empty, stationCall: "OK1XOE",
            voice: FunctionKeySet(run: msgs("VR", ["cq.wav"]), sp: msgs("VS", ["sp.wav"])),
            cw: FunctionKeySet(run: cwRun, sp: cwSp),
            digital: FunctionKeySet(run: msgs("DR", ["CQ {MYCALL}", "{CALL} 599 {EXCH} {LOG}"]), sp: msgs("DS", ["x"])),
            cwBase: base)
    }

    @Test func postContestRefusesBeforeAnything() {
        let out = FunctionKeyRouter.press(index: 0, shift: false, ctrlShift: false, context: Self.context(postContest: true))
        var expected = FunctionKeyOutcome()
        expected.status = .tr("Dodatečné zadání — nic se nevysílá (NOPOSTCONTEST ukončí)")
        #expect(out == expected)
        #expect(!out.refocus)
    }

    /// F1 in CW: CQ sent, ESM progress, last keys, `onCqSent`, refocus.
    @Test func cwF1() {
        let out = FunctionKeyRouter.press(index: 0, shift: false, ctrlShift: false, context: Self.context())
        #expect(out.status == nil)
        #expect(out.progress == EsmProgress.empty.afterSent([0], " w1aw "))
        #expect(out.lastSentKeys == [0])
        let message = CwMessageBuilder.build("CQ {MYCALL} TEST", Self.builtContext(Self.cwRun))
        #expect(out.transmission == .cw(message, index: 0))
        #expect(out.actions.isEmpty)
        #expect(out.cqSentFreqHz == 14_025_000)
        #expect(out.refocus)
    }

    private static func builtContext(_ set: [FunctionKeyMessage], digital: Bool = false) -> CwMessageBuilder.Context {
        var ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "W1AW", lastLogged: "", serial: 7, rst: "599",
                                           exchange: "#", cutNumbers: !digital, leadingZeros: !digital, now: nil)
        ctx.functionKeys = set.map(\.text)
        return ctx
    }

    /// ESM F5+F2 as one message joined by a space; macro actions come back (`{LOG}`).
    @Test func cwSeveralKeysAndActions() {
        let out = FunctionKeyRouter.send([4, 1, 2], refocus: false, context: Self.context())
        let message = CwMessageBuilder.build("{CALL} {CALL} 5NN {EXCH} TU {LOG}", Self.builtContext(Self.cwRun))
        #expect(out.transmission == .cw(message, index: 2))
        #expect(out.actions == [.log])
        #expect(out.cqSentFreqHz == nil)
        #expect(!out.refocus)
        #expect(out.progress?.exchangeSent == true)
    }

    /// Shift = the opposite set; an empty message is not sent, unknown macros are reported (CW only).
    @Test func shiftEmptyAndUnknownMacros() {
        let sp = FunctionKeyRouter.press(index: 0, shift: true, ctrlShift: false, context: Self.context())
        #expect(sp.transmission == nil)
        #expect(sp.lastSentKeys == [0])
        #expect(sp.cqSentFreqHz == 14_025_000)
        let unknown = FunctionKeyRouter.press(index: 5, shift: false, ctrlShift: false, context: Self.context())
        #expect(unknown.status == .tr("%s: makra %s zatím neumím — vynechána", "F6", "{FOO}"))
        // S&P run mode: Shift picks the Run set.
        let other = FunctionKeyRouter.press(index: 0, shift: true, ctrlShift: false, context: Self.context(run: false))
        #expect(other.transmission != nil)
        let outOfRange = FunctionKeyRouter.press(index: 11, shift: false, ctrlShift: false, context: Self.context())
        #expect(outOfRange.transmission == nil)
        #expect(outOfRange.lastSentKeys == [11])
    }

    @Test func phoneGoesToTheVoiceKeyer() {
        let out = FunctionKeyRouter.press(index: 2, shift: true, ctrlShift: false, context: Self.context(mode: .ssb))
        #expect(out.transmission == .voice(indices: [2], hisCall: "w1aw", freqHz: 14_025_000, opposite: true))
        #expect(out.actions.isEmpty)
        #expect(out.refocus)
    }

    @Test func digitalReadyUsesFldigiWithoutCut() {
        let out = FunctionKeyRouter.press(index: 1, shift: false, ctrlShift: false,
                                          context: Self.context(mode: .rtty, digitalReady: true))
        let set = Self.msgs("DR", ["CQ {MYCALL}", "{CALL} 599 {EXCH} {LOG}"])
        let message = CwMessageBuilder.build("{CALL} 599 {EXCH} {LOG}", Self.builtContext(set, digital: true))
        #expect(out.transmission == .digital(text: message.plainText(), index: 1))
        #expect(out.actions == [.log])
        #expect(out.status == nil)
    }

    /// Modes that send nothing (`EP:747-748`): no ESM progress, no `onCqSent`, still refocus.
    @Test func notReadyTexts() {
        let rtty = FunctionKeyRouter.press(index: 0, shift: false, ctrlShift: false, context: Self.context(mode: .rtty))
        #expect(rtty.status == .tr("F%s: pro %s nastav fldigi (Nastavení → Digitální módy)", 1, "RTTY"))
        #expect(rtty.progress == nil)
        #expect(rtty.lastSentKeys == nil)
        #expect(rtty.cqSentFreqHz == nil)
        #expect(rtty.refocus)
        let ft8 = FunctionKeyRouter.press(index: 3, shift: false, ctrlShift: false, context: Self.context(mode: .ft8))
        #expect(ft8.status == .tr("F%s: pro %s nastav fldigi (Nastavení → Digitální módy)", 4, "FT8"))
        // Every mode is phone, CW or digital in v1.1.1, so the "v módu %s zatím nic nevysílá" branch is unreachable
        // through `Mode`; it stays for parity.
        #expect(Mode.allCases.allSatisfy { EsmFlow.isPhone($0) || $0 == .cw || $0.isDigital })
    }

    @Test func ctrlShiftRecordsOnlyInPhone() {
        let phone = FunctionKeyRouter.press(index: 3, shift: true, ctrlShift: true, context: Self.context(mode: .am))
        var expected = FunctionKeyOutcome()
        expected.recordKey = 3
        #expect(phone == expected)
        let cw = FunctionKeyRouter.press(index: 3, shift: true, ctrlShift: true, context: Self.context(postContest: true))
        var refused = FunctionKeyOutcome()
        refused.status = .tr("Nahrávání zpráv (Ctrl+Shift+F) je jen pro fone")
        #expect(cw == refused)
    }

    /// Button labels (`EP:1335-1341`): CW / ready digital / voice set, `{MYCALL}`, Shift = opposite set.
    @Test func labels() {
        let cw = Self.context()
        #expect(FunctionKeyRouter.label(index: 0, shift: false, context: cw) == "R1")
        #expect(FunctionKeyRouter.label(index: 0, shift: true, context: cw) == "S1")
        #expect(FunctionKeyRouter.label(index: 11, shift: false, context: cw) == "")
        #expect(FunctionKeyRouter.label(index: 0, shift: false, context: Self.context(mode: .rtty)) == "VR1")
        #expect(FunctionKeyRouter.label(index: 0, shift: false, context: Self.context(mode: .rtty, digitalReady: true))
                == "DR1")
        var mine = Self.context()
        mine.cw = FunctionKeySet(run: [FunctionKeyMessage(label: "{MYCALL} {MYCALL}", text: "")], sp: [])
        #expect(FunctionKeyRouter.label(index: 0, shift: false, context: mine) == "OK1XOE OK1XOE")
        mine.stationCall = " "
        #expect(FunctionKeyRouter.label(index: 0, shift: false, context: mine) == "Me Me")
        #expect(FunctionKeyRouter.buttonText(index: 0, label: "CQ", recording: false) == "F1 CQ")
        #expect(FunctionKeyRouter.buttonText(index: 11, label: "", recording: true) == "● F12 ")
        #expect(FunctionKeyRouter.keysLabel([4, 1]) == "F5+F2")
    }
}
