import Dispatch
import os
import Testing
@testable import MCLCore

/// Port of `cat/RigPollerTest` + callback order and counts measured by the `RP.*` probe (maintainer-only probe).
///
/// No fixed time limits: the test waits for an event from the callback (`AsyncStream`) or for the loop to finish
/// (`waitUntilFinished`); `timeLimit` is only a guard against hangs, not a speed measure.
@Suite(.ioSafetyNet) struct RigPollerTests {

    /// Scripted rig: `read()` returns/throws the next script item, after exhaustion repeats the last state.
    final class ScriptedRig: RigController {
        enum Step: Sendable {
            case state(RigState)
            case fail(String)
        }

        private let steps: OSAllocatedUnfairLock<[Step]>
        private let readCount = OSAllocatedUnfairLock(initialState: 0)
        /// Optional barrier: the first `read()` waits until the test opens it (`openGate`).
        private let gate: DispatchSemaphore?
        private let gateUsed = OSAllocatedUnfairLock(initialState: false)

        init(_ steps: [Step], gated: Bool = false) {
            self.steps = OSAllocatedUnfairLock(initialState: steps)
            self.gate = gated ? DispatchSemaphore(value: 0) : nil
        }

        func openGate() {
            gate?.signal()
        }

        var reads: Int { readCount.withLock { $0 } }

        func read() throws -> RigState {
            if let gate, !gateUsed.withLock({ used in
                defer { used = true }
                return used
            }) {
                gate.wait()
            }
            readCount.withLock { $0 += 1 }
            let step: Step = steps.withLock { list in
                list.count > 1 ? list.removeFirst() : list[0]
            }
            switch step {
            case .state(let state): return state
            case .fail(let message): throw CatException("\(message)")
            }
        }

        func setFrequencyHz(_ freqHz: Int64) throws {}
        func setMode(_ mode: Mode?, freqHz: Int64) throws {}
        func setPtt(_ on: Bool) throws {}
        func sendMorse(_ text: String) throws {}
        func stopMorse() throws {}
        func setCwSpeed(_ wpm: Int) throws {}
        func isConnected() -> Bool { true }
        func close() {}
    }

    /// Callback events in the order they arrived (shared between poller and test).
    final class Events: Sendable {
        private let list = OSAllocatedUnfairLock<[String]>(initialState: [])
        let stream: AsyncStream<String>
        private let continuation: AsyncStream<String>.Continuation

        init() {
            (stream, continuation) = AsyncStream.makeStream(of: String.self)
        }

        func add(_ event: String) {
            list.withLock { $0.append(event) }
            continuation.yield(event)
        }

        var all: [String] { list.withLock { $0 } }
    }

    private static let usb = RigState(freqHz: 14_074_000, mode: .ssb, rawMode: "USB", passband: 2400)

    @Test func pollerDeliversStateToCallback() async {
        let events = Events()
        let last = OSAllocatedUnfairLock<RigState?>(initialState: nil)
        let poller = RigPoller(rig: ScriptedRig([.state(Self.usb)]), intervalMs: 10, onState: { state in
            last.withLock { $0 = state }
            events.add("state")
        }, onError: { _ in })
        poller.start()

        var iterator = events.stream.makeAsyncIterator()
        #expect(await iterator.next() == "state", "the callback did not arrive")
        #expect(last.withLock { $0 }?.freqHz == 14_074_000)
        poller.stop()
        await poller.waitUntilFinished()
    }

    @Test func pollerReportsErrorAndStops() async {
        let events = Events()
        let rig = ScriptedRig([.fail("simulovaná chyba spojení")])
        let poller = RigPoller(rig: rig, intervalMs: 10, onState: { _ in events.add("state") },
                               onError: { error in events.add("error \((error as? CatException)?.message ?? "?")") })
        poller.start()
        await poller.waitUntilFinished()
        #expect(events.all == ["error simulovaná chyba spojení"], "error callback did not arrive")
        #expect(rig.reads == 1)
        #expect(!poller.isRunning)
        poller.stop()
    }

    // MARK: - Order and counts (`RP.*`)

    /// `RP.ok-ok-fail`: two states in order, then a single error; `onError` still sees `isRunning == true`,
    /// then the loop ends (`reads=3`, `running=false`). A second `start()` while running starts nothing.
    @Test func statesThenErrorInOrder() async {
        let events = Events()
        let rig = ScriptedRig([
            .state(RigState(freqHz: 1, mode: .cw, rawMode: "CW", passband: 0)),
            .state(RigState(freqHz: 2, mode: .ssb, rawMode: "USB", passband: 0)),
            .fail("spadlo"),
        ], gated: true)
        let holder = PollerHolder()
        let poller = RigPoller(rig: rig, intervalMs: 1, onState: { state in events.add("state \(state.freqHz)") },
                               onError: { error in
                                   let message = (error as? CatException)?.message ?? "?"
                                   events.add("error \(message) running=\(holder.poller?.isRunning ?? false)")
                               })
        holder.poller = poller
        poller.start()
        // The first `read()` stands at the barrier, so the loop cannot end before the second `start()` runs
        // (otherwise under load the second `start()` after the loop finished would start a new one and `reads` would be 4).
        poller.start()
        rig.openGate()
        await poller.waitUntilFinished()
        #expect(events.all == ["state 1", "state 2", "error spadlo running=true"])
        #expect(rig.reads == 3)
        #expect(!poller.isRunning)
    }

    /// `RP.onState-throws`: an exception from the state callback goes to `onError` and the loop ends (Java catches
    /// `RuntimeException` around `read()` and `onState.accept`).
    @Test func throwingStateCallbackStopsPolling() async {
        struct CallbackFailure: Error {}
        let events = Events()
        let rig = ScriptedRig([
            .state(RigState(freqHz: 1, mode: .cw, rawMode: "CW", passband: 0)),
            .state(RigState(freqHz: 2, mode: .cw, rawMode: "CW", passband: 0)),
        ])
        let poller = RigPoller(rig: rig, intervalMs: 1, onState: { state in
            events.add("state \(state.freqHz)")
            throw CallbackFailure()
        }, onError: { error in events.add("error \(error is CallbackFailure)") })
        poller.start()
        await poller.waitUntilFinished()
        #expect(events.all == ["state 1", "error true"])
        #expect(rig.reads == 1)
        #expect(!poller.isRunning)
    }

    /// `stop()` interrupts the wait between reads (Java `interrupt` → `InterruptedException` in `sleep`):
    /// with an hour-long interval the loop would not finish without cancellation.
    @Test func stopCancelsWaitBetweenReads() async {
        let events = Events()
        let rig = ScriptedRig([.state(Self.usb)])
        let poller = RigPoller(rig: rig, intervalMs: 3_600_000, onState: { _ in events.add("state") },
                               onError: { _ in events.add("error") })
        poller.start()
        var iterator = events.stream.makeAsyncIterator()
        #expect(await iterator.next() == "state")
        #expect(poller.isRunning)
        poller.stop()
        #expect(!poller.isRunning)
        await poller.waitUntilFinished()
        #expect(events.all == ["state"])
        #expect(rig.reads == 1)
    }

    /// `RP.negative-interval*`: negative interval — Java `Thread.sleep(-1)` throws an uncaught
    /// `IllegalArgumentException`, the thread ends after the first state without `onError`, `isRunning` stays `true`,
    /// so another `start()` starts nothing; only `stop()` clears the flag.
    @Test func negativeIntervalEndsSilentlyAndStaysRunning() async {
        let events = Events()
        let rig = ScriptedRig([
            .state(RigState(freqHz: 1, mode: .cw, rawMode: "CW", passband: 0)),
            .state(RigState(freqHz: 2, mode: .cw, rawMode: "CW", passband: 0)),
        ])
        let poller = RigPoller(rig: rig, intervalMs: -1, onState: { state in events.add("state \(state.freqHz)") },
                               onError: { _ in events.add("error") })
        poller.start()
        await poller.waitUntilFinished()
        #expect(events.all == ["state 1"])
        #expect(rig.reads == 1)
        #expect(poller.isRunning)
        poller.start()
        await poller.waitUntilFinished()
        #expect(events.all == ["state 1"])
        #expect(rig.reads == 1)
        #expect(poller.isRunning)
        poller.stop()
        #expect(!poller.isRunning)
    }

    /// After an error the poller can be started again (Java: `running == false` → `start()` creates a new thread).
    @Test func restartAfterError() async {
        let events = Events()
        let rig = ScriptedRig([.fail("první"), .fail("druhá")])
        let poller = RigPoller(rig: rig, intervalMs: 1, onState: { _ in events.add("state") },
                               onError: { error in events.add((error as? CatException)?.message ?? "?") })
        poller.start()
        await poller.waitUntilFinished()
        poller.start()
        await poller.waitUntilFinished()
        #expect(events.all == ["první", "druhá"])
        #expect(rig.reads == 2)
    }

    /// Poller bound in the callback (because of `isRunning` inside `onError`).
    final class PollerHolder: Sendable {
        private let lock = OSAllocatedUnfairLock<RigPoller?>(initialState: nil)

        var poller: RigPoller? {
            get { lock.withLock { $0 } }
            set { lock.withLock { $0 = newValue } }
        }
    }
}
