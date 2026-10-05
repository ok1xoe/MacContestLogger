import Testing
@testable import MCLCore

/// `CqRepeatLoop` against the effect `EP:757-768` (a simulated runner over manual time) and (modified):
/// the loop stops on the TX lockout and in post-contest entry instead of pressing F1.
@Suite struct CqRepeatLoopTests {

    /// A runner over manual time: records F1 presses at their time and lets the test script `isSending`.
    struct Runner {
        var loop = CqRepeatLoop()
        var inputs = CqRepeatLoop.Inputs(enabled: true, callBlank: true, keyable: true, isSending: false,
                                         repeatSeconds: 2.5)
        var now: Int64 = 0
        var sends: [Int64] = []
        var waits: [Int64] = []
        var stopped: CqRepeatLoop.StopReason?

        /// Runs steps until `until` ms or an idle/stop; `sending(now)` gives `isSending` at each step.
        mutating func run(until: Int64, sending: (Int64) -> Bool = { _ in false }) {
            while now < until {
                inputs.isSending = sending(now)
                switch loop.next(inputs) {
                case .idle:
                    return
                case .stop(let reason):
                    stopped = reason
                    return
                case .sendF1:
                    sends.append(now)
                case .wait(let ms):
                    waits.append(ms)
                    now += ms
                }
            }
        }
    }

    @Test func sendsF1ThenGapThenPauseRepeatedly() {
        var runner = Runner()
        runner.run(until: 6_000)
        #expect(runner.sends == [0, 2_750, 5_500])
        #expect(Array(runner.waits.prefix(4)) == [250, 2_500, 250, 2_500])
    }

    /// While a message is being sent the loop polls every 100 ms — before F1 and after the 250 ms gap.
    @Test func waitsForTheRunningMessageBeforeAndAfter() {
        var runner = Runner()
        // A message runs 0–300 ms (e.g. TU); F1's own CQ announces itself within the gap and runs to 1 000 ms.
        runner.run(until: 4_000) { now in now < 300 || (now >= 500 && now < 1_000) }
        #expect(runner.sends.first == 300)
        #expect(Array(runner.waits.prefix(3)) == [100, 100, 100])
        // After the 250 ms gap (at 550) it polls until 1 000 → 650, 750, 850, 950, 1 050 — then the pause.
        let expected: Int64 = 1_050 + 2_500
        #expect(runner.sends.dropFirst().first == expected)
    }

    @Test func gateIsCqRepeatBlankCallAndKeyableMode() {
        #expect(CqRepeatLoop.shouldRun(enabled: true, callBlank: true, keyable: true))
        #expect(!CqRepeatLoop.shouldRun(enabled: false, callBlank: true, keyable: true))
        #expect(!CqRepeatLoop.shouldRun(enabled: true, callBlank: false, keyable: true))
        #expect(!CqRepeatLoop.shouldRun(enabled: true, callBlank: true, keyable: false))
        #expect(CqRepeatLoop.isKeyable(mode: .cw, digitalReady: false))
        #expect(CqRepeatLoop.isKeyable(mode: .fm, digitalReady: false))
        #expect(!CqRepeatLoop.isKeyable(mode: .rtty, digitalReady: false))
        #expect(CqRepeatLoop.isKeyable(mode: .rtty, digitalReady: true))
    }

    /// Typing a call cancels the loop (even in the middle of the pause); clearing it starts again from the top, so F1
    /// goes out at once.
    @Test func typingACallCancelsAndClearingRestarts() {
        var runner = Runner()
        runner.run(until: 1_000)
        #expect(runner.sends == [0])
        runner.inputs.callBlank = false
        runner.loop.restart()
        #expect(runner.loop.next(runner.inputs) == .idle)
        runner.inputs.callBlank = true
        runner.loop.restart()
        #expect(runner.loop.next(runner.inputs) == .sendF1)
    }

    /// A non-keyable mode stops the loop (`cqRepeat` off) — Kotlin only pauses and would call CQ by
    /// itself once the mode becomes keyable again.
    @Test func nonKeyableModeStopsTheLoop() {
        var runner = Runner()
        runner.run(until: 1_000)
        #expect(runner.sends == [0])
        runner.inputs.keyable = false
        runner.loop.restart()
        runner.run(until: 10_000)
        #expect(runner.stopped == .notKeyable)
        // The runner switched `cqRepeat` off: a keyable mode later sends nothing.
        runner.inputs.enabled = false
        runner.inputs.keyable = true
        runner.loop.restart()
        runner.stopped = nil
        runner.run(until: 20_000)
        #expect(runner.sends == [0])
        #expect(runner.stopped == nil)
    }

    /// A typed call wins over the mode: the loop only pauses until the call is cleared.
    @Test func typedCallPausesEvenInANonKeyableMode() {
        var loop = CqRepeatLoop()
        let inputs = CqRepeatLoop.Inputs(enabled: true, callBlank: false, keyable: false, isSending: false,
                                         repeatSeconds: 1)
        #expect(loop.next(inputs) == .idle)
    }

    /// A failed F1 send stops the loop — no automatic retry after the pause.
    @Test func failedSendStopsTheLoop() {
        var loop = CqRepeatLoop()
        let inputs = CqRepeatLoop.Inputs(enabled: true, callBlank: true, keyable: true, isSending: false,
                                         repeatSeconds: 1)
        #expect(loop.next(inputs) == .sendF1)
        #expect(loop.sendFailed() == .stop(.sendFailed))
        #expect(loop.phase == .waitBeforeSend)
    }

    /// The TX lockout stops the loop instead of pressing F1 again (Kotlin keeps repeating the
    /// `TX LOCKOUT` status).
    @Test func txLockoutStopsTheLoop() {
        var runner = Runner()
        runner.run(until: 1_000)
        #expect(runner.sends == [0])
        runner.inputs.txLocked = true
        runner.run(until: 10_000)
        #expect(runner.sends == [0])
        #expect(runner.stopped == .txLockout)
    }

    /// Post-contest entry stops the loop (Kotlin keeps showing the post-contest status).
    @Test func postContestStopsTheLoop() {
        var runner = Runner()
        runner.inputs.postContest = true
        runner.run(until: 10_000)
        #expect(runner.sends.isEmpty)
        #expect(runner.stopped == .postContest)
    }

    /// A message still running when the lockout comes is waited for first; the stop comes instead of the next F1.
    @Test func lockoutIsCheckedWhenF1WouldGoOut() {
        var loop = CqRepeatLoop()
        let inputs = CqRepeatLoop.Inputs(enabled: true, callBlank: true, keyable: true, isSending: true,
                                         txLocked: true, repeatSeconds: 1)
        #expect(loop.next(inputs) == .wait(milliseconds: 100))
    }

    @Test func pauseIsTruncatedMillisecondsLikeTheJvm() throws {
        let rows = RigKeyingProbeTable.area("repeat")
        #expect(rows.count == 9)
        for row in rows {
            let seconds = row.input == "NaN" ? Double.nan : try #require(Double(row.input))
            #expect(String(CqRepeatLoop.pauseMillis(seconds)) == row.result, "\(row.input)")
        }
    }
}
