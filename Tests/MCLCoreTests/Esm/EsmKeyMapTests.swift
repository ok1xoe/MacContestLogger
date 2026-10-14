@testable import MCLCore
import Testing

/// N1MM ESM key assignments, partial calls and the call / exchange separator.
@Suite struct EsmKeyMapTests {

    private static let remapped = EsmKeyMap(keys: [10, 6, 8, 3, 9, 5, 11])

    private static func input(run: Bool, call: String, valid: Bool = false,
                              progress: EsmProgress = .empty) -> EsmFlow.Input {
        EsmFlow.Input(progress: progress, run: run, call: call, dupe: false, exchangeValid: valid,
                      options: EsmEngine.Options(spCallOnce: false, workDupes: true), keyMap: remapped)
    }

    @Test func storedListAndDefaults() {
        #expect(EsmKeyMap.n1mm.keys == [0, 1, 2, 3, 4, 5, 7])
        #expect(EsmKeyMap(keys: []).keys == EsmKeyMap.n1mm.keys)
        #expect(EsmKeyMap(keys: [3, 99, -1]).keys == [3, 1, 2, 3, 4, 5, 7])
        var config = EsmConfig()
        config.keyMap = [1]
        #expect(config.keyMap == [1, 1, 2, 3, 4, 5, 7])
    }

    /// ESM sends the assigned keys and its progress follows them.
    @Test func esmUsesTheAssignedKeys() {
        #expect(EsmFlow.enter(Self.input(run: true, call: "")).keys == [10])
        #expect(EsmFlow.enter(Self.input(run: true, call: "DL1ABC")).keys == [9, 6])
        #expect(EsmFlow.enter(Self.input(run: false, call: "")).keys == [3])
        let sent: EsmProgress = EsmProgress.empty.afterSent([9, 6], "DL1ABC", map: Self.remapped)
        #expect(sent.exchangeSent && sent.sentCall == "DL1ABC")
        let end = EsmFlow.enter(Self.input(run: true, call: "DL1ABC", valid: true, progress: sent))
        #expect(end.keys == [8] && end.log)
        let corrected = EsmFlow.enter(Self.input(run: true, call: "DL1ABD", valid: true, progress: sent))
        #expect(corrected.keys == [9, 8])
        #expect(EsmFlow.shortcutKeys(.sendCallExchange, canTransmit: true, esmActive: true, exchangeValid: false,
                                     keyMap: Self.remapped) == [9, 6])
        // The Next Call key replaces the assigned end key.
        var next = Self.input(run: true, call: "DL1ABC", valid: true, progress: sent)
        next.nextCallKey = 11
        #expect(EsmFlow.enter(next).keys == [11])
    }

    @Test func partialCalls() {
        #expect(PartialCall.part(sent: "OK1XOF", call: "OK1XOE") == "XOE")
        #expect(PartialCall.part(sent: "OK2XOE", call: "OK1XOE") == "OK1")
        #expect(PartialCall.part(sent: "DL2XYZ", call: "OK1XOE") == "OK1XOE")
        #expect(PartialCall.part(sent: "OK1XOE/P", call: "OK1XOE") == "OK1XOE")
        #expect(PartialCall.part(sent: "OK1XOE", call: "ok1xoe") == nil)
        #expect(PartialCall.part(sent: nil, call: "OK1XOE") == nil)
    }

    private static func context(_ cw: [String]) -> FunctionKeyContext {
        let set: [FunctionKeyMessage] = cw.map { FunctionKeyMessage(label: "K", text: $0) }
        let base = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 1, rst: "",
                                            exchange: "15", cutNumbers: false, leadingZeros: false)
        return FunctionKeyContext(mode: .cw, digitalReady: false, postContest: false, run: true, call: "OK1XOE",
                                  rstSent: "599", freqHz: 14_025_000, progress: .empty, stationCall: "OK1XOE",
                                  voice: FunctionKeySet(run: set, sp: set), cw: FunctionKeySet(run: set, sp: set),
                                  digital: FunctionKeySet(run: set, sp: set), cwBase: base)
    }

    private static func text(_ outcome: FunctionKeyOutcome) -> String? {
        if case .cw(let message, _) = outcome.transmission {
            return message.plainText()
        }
        return nil
    }

    @Test func separatorAndPartialCallInTheMessage() {
        var context = Self.context(["CQ", "{EXCH}", "TU", "*", "!", "", "", "AGN"])
        context.callExchangeSeparator = " 5NN "
        #expect(Self.text(FunctionKeyRouter.send([4, 1], context: context)) == "OK1XOE 5NN 15")
        // Only his call followed by the exchange.
        #expect(Self.text(FunctionKeyRouter.send([1, 4], context: context)) == "15 OK1XOE")
        context.partialCall = "XOE"
        #expect(Self.text(FunctionKeyRouter.send([4, 2], context: context)) == "XOE TU")
    }

    @Test func cqRepeatStopsAfterItsMaximum() {
        var loop = CqRepeatLoop()
        let inputs = CqRepeatLoop.Inputs(enabled: true, callBlank: true, keyable: true, isSending: false,
                                         repeatSeconds: 30, maxMinutes: 1)
        #expect(loop.next(inputs) == .sendF1)
        #expect(loop.next(inputs) == .wait(milliseconds: 250))
        #expect(loop.next(inputs) == .wait(milliseconds: 30_000))
        #expect(loop.next(inputs) == .sendF1)
        #expect(loop.next(inputs) == .wait(milliseconds: 250))
        #expect(loop.next(inputs) == .wait(milliseconds: 30_000))
        #expect(loop.next(inputs) == .stop(.maxDuration))
        loop.resetDuration()
        loop.restart()
        #expect(loop.next(inputs) == .sendF1)
    }
}
