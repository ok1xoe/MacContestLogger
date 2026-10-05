import Testing
@testable import MCLCore

/// The ESM flow of the entry window (`EP:168-176, 672-684, 816-861, 873-884, 968-989`).
@Suite struct EsmFlowTests {

    private static let options = EsmEngine.Options(spCallOnce: false, workDupes: false)

    /// `phone || cw || digi` and `esmActive` over every mode.
    @Test func activeOnlyInTransmittingModesOutsidePostContest() {
        for mode in Mode.allCases {
            let phone: Bool = mode == .ssb || mode == .am || mode == .fm
            for ready in [false, true] {
                let transmit: Bool = phone || mode == .cw || (mode.isDigital && ready)
                #expect(EsmFlow.canTransmit(mode: mode, digitalReady: ready) == transmit, "\(mode) \(ready)")
                #expect(EsmFlow.isActive(esmEnabled: true, mode: mode, digitalReady: ready, postContest: false) == transmit)
                #expect(!EsmFlow.isActive(esmEnabled: true, mode: mode, digitalReady: ready, postContest: true))
                #expect(!EsmFlow.isActive(esmEnabled: false, mode: mode, digitalReady: ready, postContest: false))
            }
        }
    }

    @Test func exchangeValid() {
        #expect(EsmFlow.exchangeValid(contestActive: true, contestReady: true, call: ""))
        #expect(!EsmFlow.exchangeValid(contestActive: true, contestReady: false, call: "W1AW"))
        #expect(EsmFlow.exchangeValid(contestActive: false, contestReady: false, call: "W1AW"))
        #expect(!EsmFlow.exchangeValid(contestActive: false, contestReady: true, call: "\u{00A0}"))
    }

    private static func input(run: Bool, call: String, dupe: Bool = false, valid: Bool = false,
                              progress: EsmProgress = .empty) -> EsmFlow.Input {
        EsmFlow.Input(progress: progress, run: run, call: call, dupe: dupe, exchangeValid: valid, options: options)
    }

    /// `esmEnter` (`EP:817-835`): the engine step, or the S&P dupe refusal.
    @Test func enterFollowsTheEngine() {
        let cq = EsmFlow.enter(Self.input(run: true, call: ""))
        #expect(cq == EsmFlow.Outcome(status: nil, keys: [EsmEngine.f1], log: false, focus: .call))
        let exchange = EsmFlow.enter(Self.input(run: true, call: "W1AW"))
        #expect(exchange.keys == [EsmEngine.f5, EsmEngine.f2])
        #expect(exchange.focus == .exchange)
        let sent = EsmProgress.empty.afterSent([EsmEngine.f5, EsmEngine.f2], "W1AW")
        let tu = EsmFlow.enter(Self.input(run: true, call: "W1AW", valid: true, progress: sent))
        #expect(tu.keys == [EsmEngine.f3])
        #expect(tu.log)
        let corrected = EsmFlow.enter(Self.input(run: true, call: "W1AX", valid: true, progress: sent))
        #expect(corrected.keys == [EsmEngine.f5, EsmEngine.f3])
        let dupe = EsmFlow.enter(Self.input(run: false, call: "W1AW", dupe: true))
        #expect(dupe == EsmFlow.Outcome(status: .tr("DUPE — v S&P ESM nic nevysílá"), keys: [], log: false,
                                        focus: .none))
        // S&P with a valid exchange already sent: log without keys.
        let quiet = EsmFlow.enter(Self.input(run: false, call: "W1AW", valid: true,
                                             progress: EsmProgress.empty.afterSent([EsmEngine.f2], "W1AW")))
        #expect(quiet.keys.isEmpty)
        #expect(quiet.log)
        #expect(quiet.status == nil)
    }

    @Test func nextStepOnlyWhenActive() {
        #expect(EsmFlow.nextStep(Self.input(run: true, call: ""), active: false) == nil)
        #expect(EsmFlow.nextStep(Self.input(run: true, call: ""), active: true)?.keys == [EsmEngine.f1])
    }

    /// Space in the call field (`EP:856-861`).
    @Test func jumpToExchange() {
        let start = EsmProgress.empty
        #expect(EsmFlow.jumpToExchange(start, esmEnabled: true, mode: .ssb, run: true, call: "W1AW").exchangeSent)
        #expect(EsmFlow.jumpToExchange(start, esmEnabled: true, mode: .fm, run: true, call: "W1AW").exchangeSent)
        #expect(!EsmFlow.jumpToExchange(start, esmEnabled: true, mode: .cw, run: true, call: "W1AW").exchangeSent)
        #expect(!EsmFlow.jumpToExchange(start, esmEnabled: true, mode: .ssb, run: false, call: "W1AW").exchangeSent)
        #expect(!EsmFlow.jumpToExchange(start, esmEnabled: false, mode: .ssb, run: true, call: "W1AW").exchangeSent)
        #expect(!EsmFlow.jumpToExchange(start, esmEnabled: true, mode: .ssb, run: true, call: " ").exchangeSent)
    }

    /// `LaunchedEffect(call.isBlank())` (`EP:176`): only the transition filled → blank resets.
    @Test func clearedCallResetsProgress() {
        let sent = EsmProgress.empty.afterSent([EsmEngine.f5, EsmEngine.f2], "W1AW")
        #expect(EsmFlow.afterCallChange(sent, previousCall: "W1AW", call: "") == .empty)
        #expect(EsmFlow.afterCallChange(sent, previousCall: "W", call: "\u{00A0}") == .empty)
        #expect(EsmFlow.afterCallChange(sent, previousCall: "W1AW", call: "W1A") == sent)
        // Blank → blank and blank → filled: the effect key does not change / is false — nothing resets.
        #expect(EsmFlow.afterCallChange(sent, previousCall: "", call: " ") == sent)
        #expect(EsmFlow.afterCallChange(sent, previousCall: " ", call: "W") == sent)
    }

    /// `=` (`EP:983-989`).
    @Test func equalsRepeatsTheLastKeys() {
        #expect(EsmFlow.repeatLast(esmActive: false, lastSentKeys: [1], pressed: true) == .notEsm)
        #expect(EsmFlow.repeatLast(esmActive: true, lastSentKeys: [4, 1], pressed: true) == .send([4, 1]))
        #expect(EsmFlow.repeatLast(esmActive: true, lastSentKeys: [4, 1], pressed: false) == .consume)
        #expect(EsmFlow.repeatLast(esmActive: true, lastSentKeys: [], pressed: true) == .consume)
    }

    /// `runShortcut` send-and-log rows (`EP:875-884`).
    @Test func shortcutKeys() {
        let table: [(ShortcutAction, Bool, Bool, Bool, [Int]?)] = [
            (.sendCallExchange, true, false, false, [EsmEngine.f5, EsmEngine.f2]),
            (.sendCallExchange, false, false, true, nil),
            (.tuAndLog, true, true, true, [EsmEngine.f3]),
            (.tuAndLog, true, false, false, nil),
            (.tuAndLog, false, false, true, nil),
            (.logWithoutSending, true, false, true, [EsmEngine.f3]),
            (.logWithoutSending, true, true, true, nil),
            (.logWithoutSending, true, false, false, nil),
            (.wipe, true, false, true, nil),
        ]
        for (action, transmit, esm, valid, keys) in table {
            #expect(EsmFlow.shortcutKeys(action, canTransmit: transmit, esmActive: esm, exchangeValid: valid) == keys,
                    "\(action) \(transmit) \(esm) \(valid)")
        }
    }

    /// Enter on release (`EP:968-980`).
    @Test func enterRoute() {
        #expect(EsmFlow.enterRoute(scpPick: 2, isCommand: true, ctrlEnter: true, esmActive: true) == .takeSuggestion(2))
        #expect(EsmFlow.enterRoute(scpPick: -1, isCommand: true, ctrlEnter: true, esmActive: true)
                == .command(ctrlEnter: true))
        #expect(EsmFlow.enterRoute(scpPick: -1, isCommand: false, ctrlEnter: true, esmActive: true) == .esm)
        #expect(EsmFlow.enterRoute(scpPick: -1, isCommand: false, ctrlEnter: false, esmActive: false) == .log)
    }
}
