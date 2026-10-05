import Foundation
import MCLCore
import os

/// A serial lane for the blocking work of one integration service (UDP bind and send, HTTP, plugin processes), on a
/// thread of its own — never on the main thread or in Swift's cooperative pool. Jobs queued after `markClosed` (the
/// quit) are skipped; the one running finishes.
final class ServiceLane: Sendable {
    private let lane: SerialLane
    private let closed = OSAllocatedUnfairLock(initialState: false)

    init(name: String) {
        lane = SerialLane(name: name)
    }

    var isClosed: Bool {
        closed.withLock { $0 }
    }

    /// Runs `body` on the lane (skipped once closed).
    func submit(_ body: @escaping @Sendable () -> Void) {
        let closed = self.closed
        lane.submit {
            if closed.withLock({ $0 }) { return }
            body()
        }
    }

    /// `body` on the lane, then `then` with its result on the main actor (neither once the job was skipped).
    func submit<T: Sendable>(_ body: @escaping @Sendable () -> T, then: @escaping @MainActor @Sendable (T) -> Void) {
        let closed = self.closed
        lane.submit {
            if closed.withLock({ $0 }) { return }
            let result: T = body()
            MainHop.post {
                then(result)
            }
        }
    }

    /// Waits (without blocking a thread) until everything queued before has run.
    func settle() async {
        await lane.settle()
    }

    /// Skips the queued and later jobs without waiting.
    func markClosed() {
        closed.withLock { $0 = true }
    }

    /// Skips the queued jobs and waits for the running one.
    func close() async {
        markClosed()
        await lane.settle()
    }
}

/// The lane of the UDP services (broadcast sends, WSJT-X sends and replies, the listeners' bind).
typealias IntegrationLane = ServiceLane
/// The lanes of the HTTP services (Club Log and the scoreboard each have their own).
typealias HttpLane = ServiceLane
/// The lane of the plugin processes.
typealias PluginLane = ServiceLane

/// Lets the work already posted to the main queue run (the lanes' results hop there).
@MainActor
func drainMainQueue() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

/// A one-shot gate: `wait` returns once `fire` was called (before or after), however often it is called.
final class WaitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func fire() {
        lock.lock()
        fired = true
        let waiting: CheckedContinuation<Void, Never>? = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}

extension ServiceLane {
    /// Waits until what is queued has run, but at most `boundMs` of `clock` (a blocked job — DNS in a bind or a send —
    /// must not hold the quit before the database closes; the job is then left behind).
    @MainActor
    func settle(boundMs: Int, clock: any RescoreClock) async {
        let gate = WaitGate()
        let timer: any RescoreTimer = clock.schedule(afterMilliseconds: boundMs) {
            gate.fire()
        }
        Task { [self] in
            await settle()
            gate.fire()
        }
        await gate.wait()
        timer.cancel()
    }
}
