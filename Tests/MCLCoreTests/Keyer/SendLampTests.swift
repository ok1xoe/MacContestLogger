import Testing
@testable import MCLCore

/// `SendLamp` against `cwSendingKey`/`cwToken`/`digitalSending` of `AppState` (`AS:1580-1618`, `AS:1714-1755`).
@Suite struct SendLampTests {

    @Test func cwSendLightsTheKeyAndOnlyTheCurrentTokenPutsItOut() {
        var lamp = SendLamp()
        let first = lamp.begin(key: 0)
        #expect(lamp.key == 0)
        #expect(!first.wasSending)
        // F2 interrupts F1: the keyer is aborted first, the old estimate must not put out the new lamp.
        let second = lamp.begin(key: 1)
        #expect(second.wasSending)
        #expect(second.token == first.token + 1)
        let result6 = lamp.finish(first.token)
        #expect(!result6)
        #expect(lamp.key == 1)
        let result7 = lamp.finish(second.token)
        #expect(result7)
        #expect(lamp.key == nil)
    }

    /// An ESM pair (F5+F2) lights the last index; free text is `-1`.
    @Test func freeTextIsMinusOne() {
        var lamp = SendLamp()
        _ = lamp.begin(key: -1)
        #expect(lamp.key == -1)
    }

    @Test func abortCwReportsWhetherSomethingWasLitAndInvalidatesTheToken() {
        var lamp = SendLamp()
        let result8 = lamp.abortCw()
        #expect(!result8) // nothing lit — still bumps the token (Kotlin `abortCw` with an open keyer)
        #expect(lamp.token == 1)
        let send = lamp.begin(key: 3)
        let result9 = lamp.abortCw()
        #expect(result9)
        #expect(lamp.key == nil)
        let result10 = lamp.finish(send.token)
        #expect(!result10)
    }

    @Test func digitalSendAndAbort() {
        var lamp = SendLamp()
        let result11 = lamp.abortDigital()
        #expect(!result11)
        #expect(lamp.token == 0)
        let token = lamp.beginDigital(key: 2)
        #expect(lamp.digitalSending)
        #expect(lamp.key == 2)
        let result12 = lamp.abortDigital()
        #expect(result12)
        #expect(!lamp.digitalSending)
        #expect(lamp.key == nil)
        #expect(lamp.token == token + 1)
    }

    @Test func digitalFinishAndFailure() {
        var lamp = SendLamp()
        let old = lamp.beginDigital(key: 0)
        let current = lamp.beginDigital(key: 1)
        lamp.finishDigital(old) // a superseded watch touches nothing
        #expect(lamp.key == 1)
        #expect(lamp.digitalSending)
        lamp.failDigital(old) // a superseded failure: lamp stays, `digitalSending` goes (Kotlin)
        #expect(lamp.key == 1)
        #expect(!lamp.digitalSending)
        let again = lamp.beginDigital(key: 4)
        #expect(again == current + 1)
        lamp.finishDigital(again)
        #expect(lamp.key == nil)
        #expect(!lamp.digitalSending)
    }

    @Test func estimateIsCwTiming() {
        let message = CwMessage(parts: [.text("PARIS")])
        #expect(SendLamp.estimateMillis(message, wpm: 12) == 4_300)
    }
}
