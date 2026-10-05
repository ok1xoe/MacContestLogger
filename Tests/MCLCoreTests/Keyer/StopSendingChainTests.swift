import Testing
@testable import MCLCore

/// `StopSendingChain` against `AppState.stopSending` (`AS:1757-1765`).
@Suite struct StopSendingChainTests {

    final class Calls {
        var names: [String] = []
    }

    static func run(tuning: Bool = false, cqRepeat: Bool = false, voice: Bool = false, digital: Bool = false,
                    cw: Bool = false) -> (StopSendingChain.Result, [String]) {
        let calls = Calls()
        let result = StopSendingChain.run(
            tuning: tuning, cqRepeat: cqRepeat,
            voice: { calls.names.append("voice"); return voice },
            digital: { calls.names.append("digital"); return digital },
            cw: { calls.names.append("cw"); return cw })
        return (result, calls.names)
    }

    @Test func tuningStopsFirstAndLeavesTheRepeatAlone() {
        let (result, calls) = Self.run(tuning: true, cqRepeat: true, voice: true)
        #expect(result == StopSendingChain.Result(stopped: true, stopTuning: true, clearCqRepeat: false))
        #expect(calls.isEmpty)
    }

    /// Short-circuit: when the voice keyer stopped something, the CW `abort` is never called.
    @Test func voiceStoppingSkipsDigitalAndCw() {
        let (result, calls) = Self.run(voice: true, cw: true)
        #expect(result.stopped)
        #expect(result.clearCqRepeat)
        #expect(calls == ["voice"])
    }

    @Test func orderIsVoiceDigitalCw() {
        #expect(Self.run(digital: true).1 == ["voice", "digital"])
        #expect(Self.run(cw: true).1 == ["voice", "digital", "cw"])
    }

    /// The CQ repeat alone: it is switched off and Esc counts as handled.
    @Test func repeatingCountsAsStopped() {
        let (result, calls) = Self.run(cqRepeat: true)
        #expect(result == StopSendingChain.Result(stopped: true, stopTuning: false, clearCqRepeat: true))
        #expect(calls == ["voice", "digital", "cw"])
        #expect(!Self.run().0.stopped)
        #expect(Self.run().0.clearCqRepeat)
    }
}
