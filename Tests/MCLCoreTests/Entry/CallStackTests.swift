@testable import MCLCore
import Testing

/// The call stack (N1MM single-operator and partner call stacking): pushing, the three orders, dupes, the cap, the
/// band, and the `{LOGTHENPOP}` split of a message; the router's `{LOGTHENPOP}` and ESM's Next Call key.
@Suite struct CallStackTests {

    private static func neutral(_ call: String) -> CallStack.Evaluation { .neutral }

    @Test func pushNormalisesAndRefusesBlankDupesAndRepeats() {
        var stack = CallStack()
        let first = stack.push(" dl1abc ", band: "20m")
        let again = stack.push("DL1ABC", band: "20m")
        let blank = stack.push("  ", band: "20m")
        let dupe = stack.push("K1ZZ", band: "20m", evaluation: .init(dupe: true, newMults: 0))
        #expect(first == .added && again == .alreadyStacked && blank == .blank && dupe == .dupe)
        #expect(stack.entries.map(\.call) == ["DL1ABC"])
    }

    @Test func theCapDropsTheOldest() {
        var stack = CallStack()
        for index in 0..<(CallStack.cap + 2) {
            stack.push("K\(index)AA", band: "20m")
        }
        #expect(stack.entries.count == CallStack.cap)
        #expect(stack.entries.first?.call == "K2AA")
    }

    @Test func ordersFifoLifoAndMultsFirst() {
        var stack = CallStack()
        for call in ["DL1A", "JA1A", "W1A", "VK2A"] {
            stack.push(call, band: "20m")
        }
        let mults: (String) -> CallStack.Evaluation = { call in
            switch call {
            case "JA1A": .init(dupe: false, newMults: 1)
            case "VK2A": .init(dupe: false, newMults: 2)
            default: .neutral
            }
        }
        #expect(stack.ordered(.fifo, evaluate: mults).map(\.call) == ["DL1A", "JA1A", "W1A", "VK2A"])
        #expect(stack.ordered(.lifo, evaluate: mults).map(\.call) == ["VK2A", "W1A", "JA1A", "DL1A"])
        #expect(stack.ordered(.multsFirst, evaluate: mults).map(\.call) == ["VK2A", "JA1A", "DL1A", "W1A"])
        let best = stack.pop(.multsFirst, evaluate: mults)
        let last = stack.pop(.lifo, evaluate: mults)
        #expect(best == "VK2A" && last == "W1A")
        #expect(stack.entries.map(\.call) == ["DL1A", "JA1A"])
    }

    /// A call worked since it was stacked (now a dupe) is skipped and dropped when the next call is taken.
    @Test func popSkipsCallsThatBecameDupes() {
        var stack = CallStack()
        stack.push("DL1A", band: "20m")
        stack.push("K1ZZ", band: "20m")
        let worked: (String) -> CallStack.Evaluation = { $0 == "DL1A" ? .init(dupe: true, newMults: 0) : .neutral }
        #expect(stack.peek(.fifo, evaluate: worked) == "K1ZZ")
        let popped = stack.pop(.fifo, evaluate: worked)
        #expect(popped == "K1ZZ")
        #expect(stack.isEmpty)
        let none = stack.pop(.fifo, evaluate: Self.neutral)
        #expect(none == nil)
    }

    @Test func removeTopRemoveClearAndPrune() {
        var stack = CallStack()
        stack.push("DL1A", band: "20m")
        stack.push("K1ZZ", band: "40m")
        stack.push("OK1A", band: "")
        let top = stack.removeTop(.fifo, evaluate: Self.neutral)
        #expect(top == "DL1A")
        let pruned = stack.prune(band: "20m")
        #expect(pruned)
        #expect(stack.entries.map(\.call) == ["OK1A"], "an unknown band is never pruned")
        let unknown = stack.prune(band: "")
        #expect(!unknown)
        let removed = stack.remove("ok1a")
        let again = stack.remove("OK1A")
        #expect(removed && !again)
        stack.push("W1AW", band: "20m")
        stack.clear()
        #expect(stack.isEmpty)
    }

    @Test func orderFromConfiguration() {
        #expect(CallStack.Order.from("LIFO") == .lifo)
        #expect(CallStack.Order.from("FIFO") == .fifo)
        #expect(CallStack.Order.from("garbage") == .multsFirst)
    }

    // MARK: - macros

    @Test func splitAtTheFirstLogThenPop() throws {
        let split = try #require(CallStackMacro.split("! {logthenpop} TU {F5}{F2} {LOGTHENNEXT}"))
        #expect(split.prefix == "! ")
        #expect(split.suffix == " TU {F5}{F2} {LOGTHENNEXT}")
        #expect(!split.next)
        let next = try #require(CallStackMacro.split("{LOGTHENNEXT}TU"))
        #expect(next.prefix.isEmpty && next.suffix == "TU" && next.next)
        #expect(CallStackMacro.split("TU {LOG}") == nil)
        #expect(CallStackMacro.hasLogThenPop("x {LogThenPop}"))
        #expect(!CallStackMacro.hasLogThenPop("{LOGTHENNEXT}"))
    }

    @Test func functionKeysReferencedByAText() {
        #expect(CallStackMacro.functionKeys(in: " TU {F5}{f2} {F12} {F13} {F} {X1}") == [4, 1, 11])
    }

    @Test func voiceMacrosAreItemsOfTheMessage() {
        #expect(CallStackMacro.voiceMacros("{logthenpop}, tu.wav ,{F5},{CLRSTACK}") == ["{LOGTHENPOP}", "{CLRSTACK}"])
    }

    @Test func builderTurnsStackMacrosIntoActions() {
        let ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 1, rst: "599",
                                           exchange: "15", cutNumbers: false, leadingZeros: false, now: nil)
        let message = CwMessageBuilder.build("{SOCALLSTACK}{STACKANOTHER} {CLRSTACK}", ctx)
        #expect(message.actions == [.soCallStack, .stackAnother, .clearStack])
        #expect(message.unknownMacros.isEmpty)
    }

    // MARK: - the router

    private static func context(run: Bool = true, call: String = "DL1ABC", exchangeSent: Bool = true,
                                valid: Bool = true, next: String? = "K1ZZ", mode: Mode = .cw) -> FunctionKeyContext {
        var keys: [FunctionKeyMessage] = (0..<12).map { FunctionKeyMessage(label: "F\($0 + 1)", text: "") }
        keys[1] = FunctionKeyMessage(label: "Exch", text: "5NN #")
        keys[2] = FunctionKeyMessage(label: "TU", text: "TU ! *")
        keys[4] = FunctionKeyMessage(label: "His", text: "!")
        keys[11] = FunctionKeyMessage(label: "Next", text: "! {LOGTHENPOP} TU {F5} {F2}")
        let set = FunctionKeySet(run: keys, sp: keys)
        let base = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 7, rst: "",
                                            exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        let progress: EsmProgress = exchangeSent ? EsmProgress.empty.afterSent([1], call) : .empty
        return FunctionKeyContext(mode: mode, digitalReady: true, postContest: false, run: run, call: call,
                                  rstSent: "599", freqHz: 14_025_000, progress: progress, stationCall: "OK1XOE",
                                  voice: set, cw: set, digital: set, cwBase: base, exchangeValid: valid,
                                  stackNext: next, serialAfterLog: 8)
    }

    @Test func logThenPopSendsToBothStationsAndLogs() {
        let out = FunctionKeyRouter.send([11], context: Self.context())
        guard case .cw(let message, let index) = out.transmission else {
            Issue.record("no CW transmission")
            return
        }
        #expect(index == 11)
        #expect(message.plainText() == "DL1ABC TU K1ZZ 5NN 8")
        #expect(message.actions == [.logThenPop])
        #expect(out.stackNextCall == "K1ZZ")
        #expect(out.stackProgress == EsmProgress.empty.afterSent([4, 1], "K1ZZ"))
    }

    @Test func logThenPopWithAnEmptyStackLogsAndThanks() {
        let out = FunctionKeyRouter.send([11], context: Self.context(next: nil))
        guard case .cw(let message, _) = out.transmission else {
            Issue.record("no CW transmission")
            return
        }
        #expect(message.plainText() == "DL1ABC TU DL1ABC OK1XOE")
        #expect(message.actions == [.logThenPop])
        #expect(out.stackNextCall == nil)
    }

    @Test func logThenPopIsDigitalPlainText() {
        let out = FunctionKeyRouter.send([11], context: Self.context(mode: .rtty))
        #expect(out.transmission == .digital(text: "DL1ABC TU K1ZZ 5NN 8", index: 11))
    }

    @Test func logThenPopRefusesOutsideRunAndBeforeTheExchange() {
        for context in [Self.context(run: false), Self.context(exchangeSent: false), Self.context(valid: false),
                        Self.context(call: " ")] {
            let out = FunctionKeyRouter.send([11], context: context)
            #expect(out.transmission == nil)
            #expect(out.status != nil)
            #expect(out.progress == nil && out.lastSentKeys == nil)
            #expect(out.actions.isEmpty)
        }
    }

    // MARK: - ESM

    @Test func esmSendsTheNextCallKeyInsteadOfTu() {
        let options = EsmEngine.Options(spCallOnce: false, workDupes: false)
        let progress: EsmProgress = EsmProgress.empty.afterSent([4, 1], "DL1ABC")
        let input = EsmFlow.Input(progress: progress, run: true, call: "DL1ABC", dupe: false, exchangeValid: true,
                                  options: options, nextCallKey: 11)
        let out: EsmFlow.Outcome = EsmFlow.enter(input)
        #expect(out.keys == [11])
        #expect(!out.log)
        var plain = input
        plain.nextCallKey = nil
        #expect(EsmFlow.enter(plain).keys == [EsmEngine.f3])
        #expect(EsmFlow.enter(plain).log)
        // A corrected call is sent again before the Next Call key.
        let corrected = EsmFlow.Input(progress: progress, run: true, call: "DL1ABD", dupe: false, exchangeValid: true,
                                      options: options, nextCallKey: 11)
        #expect(EsmFlow.enter(corrected).keys == [EsmEngine.f5, 11])
        // Not in S&P, and not before the end of the QSO.
        var sp = input
        sp.run = false
        #expect(EsmFlow.enter(sp).keys == [])
        let early = EsmFlow.Input(progress: .empty, run: true, call: "DL1ABC", dupe: false, exchangeValid: true,
                                  options: options, nextCallKey: 11)
        #expect(EsmFlow.enter(early).keys == [EsmEngine.f5, EsmEngine.f2])
    }
}
