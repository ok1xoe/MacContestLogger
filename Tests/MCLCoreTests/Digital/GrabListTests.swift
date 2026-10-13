@testable import MCLCore
import Testing

/// N1MM's Grab window and Insert key, and `{LOGTHENGRAB}` in the router.
@Suite struct GrabListTests {

    @Test func offerKeepsPlacesAndTheCap() {
        var list = GrabList()
        let first: Bool = list.offer("dl1abc")
        let again: Bool = list.offer("DL1ABC")
        #expect(first && !again)
        for index in 0..<11 {
            list.offer("K\(index)ZZ")
        }
        #expect(list.calls.count == GrabList.cap)
        #expect(list.calls.first == "K1ZZ")
        #expect(list.shown(.lifo).first == "K10ZZ")
        #expect(list.shown(.fifo).first == "K1ZZ")
    }

    @Test func grabSelectAndDelete() {
        var list = GrabList()
        for call in ["DL1ABC", "K1ZZ", "W1AW"] {
            list.offer(call)
        }
        #expect(list.highlighted(.lifo) == "W1AW")
        list.select("DL1ABC")
        #expect(list.highlighted(.lifo) == "DL1ABC")
        let grabbed = list.grab(.lifo)
        #expect(grabbed == "DL1ABC")
        #expect(list.selected == nil)
        list.removeTop(.fifo)
        #expect(list.calls == ["W1AW"])
        list.removeSelected(.lifo)
        #expect(list.calls.isEmpty)
        let none = list.grab(.lifo)
        #expect(none == nil)
        list.offer("OK1ABC")
        list.clear()
        #expect(list.calls.isEmpty)
    }

    @Test func insertKeyTable() {
        let callExchange: [Int] = [EsmEngine.f5, EsmEngine.f2]
        // ESM off: a dupe sends nothing.
        #expect(InsertKey.keys(run: true, esm: false, dupe: false, workDupes: false, exchangeValid: false) == callExchange)
        #expect(InsertKey.keys(run: false, esm: false, dupe: true, workDupes: true, exchangeValid: false).isEmpty)
        // ESM on, Run.
        #expect(InsertKey.keys(run: true, esm: true, dupe: true, workDupes: false, exchangeValid: false) == [EsmEngine.f6])
        #expect(InsertKey.keys(run: true, esm: true, dupe: true, workDupes: true, exchangeValid: false) == callExchange)
        // ESM on, S&P: F4 until the exchange is entered, then F5+F2.
        #expect(InsertKey.keys(run: false, esm: true, dupe: false, workDupes: false, exchangeValid: false) == [EsmEngine.f4])
        #expect(InsertKey.keys(run: false, esm: true, dupe: false, workDupes: false, exchangeValid: true) == callExchange)
    }

    @Test func logThenGrabTakesTheGrabWindowsCall() throws {
        let split = try #require(CallStackMacro.split("! {LOGTHENGRAB} TU {F5}"))
        #expect(split.grab && split.next)
        var keys: [FunctionKeyMessage] = (0..<12).map { FunctionKeyMessage(label: "F\($0 + 1)", text: "") }
        keys[4] = FunctionKeyMessage(label: "His", text: "!")
        keys[8] = FunctionKeyMessage(label: "Now", text: "! {LOGTHENGRAB} TU {F5}")
        let set = FunctionKeySet(run: keys, sp: keys)
        let base = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 7, rst: "",
                                            exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        let context = FunctionKeyContext(mode: .rtty, digitalReady: true, postContest: false, run: true,
                                         call: "DL1ABC", rstSent: "599", freqHz: 14_080_000,
                                         progress: EsmProgress.empty.afterSent([1], "DL1ABC"),
                                         stationCall: "OK1XOE", voice: set, cw: set, digital: set, cwBase: base,
                                         exchangeValid: true, stackNext: "W1AW", grabNext: "K1ZZ")
        let out = FunctionKeyRouter.send([8], context: context)
        #expect(out.transmission == .digital(text: "DL1ABC TU K1ZZ", index: 8))
        #expect(out.nextFromGrab)
        #expect(out.stackNextCall == "K1ZZ")
    }

    @Test func grabMacrosAreActions() {
        let ctx = CwMessageBuilder.Context(myCall: "OK1XOE", hisCall: "", lastLogged: "", serial: 1, rst: "599",
                                           exchange: "", cutNumbers: false, leadingZeros: false, now: nil)
        let message = CwMessageBuilder.build("{GRAB}{DELALL}{DELTOP}{DELSEL}{SCQ}", ctx)
        #expect(message.actions == [.grab, .grabDeleteAll, .grabDeleteTop, .grabDeleteSelected, .resumeCq])
    }
}
