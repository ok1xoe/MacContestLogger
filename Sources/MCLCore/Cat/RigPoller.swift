import Foundation
import os

/// Periodically reads the rig state from `RigController` and passes it to the callback (Java `cat/RigPoller`).
///
/// Like Java, the poller has **its own thread** `rig-poller`, on which it calls the blocking `read()` and callbacks
/// (the caller wraps them in `@MainActor`, like Kotlin in `Dispatchers.Main`). Not a task in Swift's shared
/// thread pool: a blocking read would hold one of the few pool threads (three on CI)
/// and under load the loop would never get a turn.
///
/// Behaviour as in Java:
/// - loop `read()` → `onState` → wait `intervalMs` (period = interval + read time);
/// - the **first error** from `read()` **or from `onState`** (Java catches `RuntimeException` around both) →
///   `onError` (still with `isRunning == true`), then `isRunning = false` and the loop ends — no reconnect;
/// - `stop()` clears the flag and interrupts **this** loop (Java thread `interrupt`): the currently running `read()`
///   finishes and its state may still reach `onState`, then the loop ends at the wait — even if in the meantime
///   `start()` launched a new loop (the interrupt belongs to the thread, not the poller);
/// - `start()` while running does nothing; after an error or `stop()` it starts a new loop;
/// - negative interval: Java `Thread.sleep` throws `IllegalArgumentException`, which the loop does not catch —
///   the thread ends after the first read without `onError` and `isRunning` stays `true`. Reproduced.
public final class RigPoller: Sendable {

    /// One started loop (Java thread): interrupt flag, waiting and loop end.
    private final class Loop: @unchecked Sendable {
        private let condition = NSCondition()
        private var interrupted = false
        private var finished = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func interrupt() {
            condition.lock()
            interrupted = true
            condition.broadcast()
            condition.unlock()
        }

        /// Java `Thread.sleep`: `false` when the loop is interrupted (even before the wait begins).
        func sleep(milliseconds: Int64) -> Bool {
            // A huge interval (> ~317 years) is clamped — Java would sleep practically forever too.
            let seconds: Double = min(Double(milliseconds) / 1000, 1e10)
            let deadline = Date(timeIntervalSinceNow: seconds)
            condition.lock()
            defer { condition.unlock() }
            while !interrupted {
                if !condition.wait(until: deadline) {
                    return !interrupted
                }
            }
            return false
        }

        func finish() {
            condition.lock()
            finished = true
            let pending = waiters
            waiters = []
            condition.unlock()
            for waiter in pending {
                waiter.resume()
            }
        }

        func waitUntilFinished() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                condition.lock()
                if finished {
                    condition.unlock()
                    continuation.resume()
                    return
                }
                waiters.append(continuation)
                condition.unlock()
            }
        }
    }

    private struct State {
        var running = false
        var loop: Loop?
        /// Last started loop (even after `stop()`), so tests can wait for it.
        var lastLoop: Loop?
    }

    private let rig: any RigController
    private let intervalMs: Int64
    private let onState: @Sendable (RigState) throws -> Void
    private let onError: @Sendable (any Error) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(rig: any RigController, intervalMs: Int64, onState: @escaping @Sendable (RigState) throws -> Void,
                onError: @escaping @Sendable (any Error) -> Void) {
        self.rig = rig
        self.intervalMs = intervalMs
        self.onState = onState
        self.onError = onError
    }

    public func start() {
        let started: Loop? = state.withLock { s in
            if s.running {
                return nil
            }
            s.running = true
            let loop = Loop()
            s.loop = loop
            s.lastLoop = loop
            return loop
        }
        guard let loop = started else {
            return
        }
        let thread = Thread { [self] in
            self.run(loop)
            loop.finish()
        }
        thread.name = "rig-poller"
        thread.start()
    }

    public func stop() {
        let loop: Loop? = state.withLock { s in
            s.running = false
            let current = s.loop
            s.loop = nil
            return current
        }
        loop?.interrupt()
    }

    public var isRunning: Bool {
        state.withLock { $0.running }
    }

    /// Waits until the last started loop ends (tests; Java has no equivalent).
    func waitUntilFinished() async {
        let loop = state.withLock { $0.lastLoop }
        await loop?.waitUntilFinished()
    }

    private func run(_ loop: Loop) {
        while isRunning {
            do {
                let current = try rig.read()
                try onState(current)
            } catch {
                onError(error)
                state.withLock { $0.running = false } // on connection error we end polling
                return
            }
            guard intervalMs >= 0 else {
                return
            }
            if !loop.sleep(milliseconds: intervalMs) {
                return // interrupted via stop() — Java InterruptedException
            }
        }
    }
}
