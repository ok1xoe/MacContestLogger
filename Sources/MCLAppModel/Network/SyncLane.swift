import Foundation
import MCLCore
import os

/// The one serial lane of the cluster sync: every blocking transport call — the connect, the publishes of
/// QSOs, statuses, messages and spots, the serial request, the goodbye and the close — runs here, in the order it was
/// asked for, on a thread of its own: never on the main thread and never in Swift's cooperative pool. Kotlin runs
/// them on `Dispatchers.IO` or on the UI thread; a broker that does not answer must not stop the keying, the entry
/// window or the quit.
///
/// Shared spots (a skimmer feed is hundreds per minute) are capped: when `spotCap` of them wait in the queue (the
/// broker does not answer) the newest are dropped instead of growing the queue.
final class SyncLane: Sendable {

    /// The most shared spots that wait in the queue.
    static let spotCap = 200

    private let lane = SerialLane(name: "cz.ok1xoe.maccontestlogger.cluster-sync")
    private let waitingSpots = OSAllocatedUnfairLock(initialState: 0)

    /// Queues `job` after everything submitted before it.
    func submit(_ job: @escaping @Sendable () -> Void) {
        lane.submit(job)
    }

    /// Queues a shared spot; `false` = the queue is full and the spot was dropped.
    @discardableResult
    func submitSpot(_ job: @escaping @Sendable () -> Void) -> Bool {
        let accepted: Bool = waitingSpots.withLock { count in
            guard count < Self.spotCap else { return false }
            count += 1
            return true
        }
        guard accepted else { return false }
        lane.submit { [waitingSpots] in
            waitingSpots.withLock { $0 -= 1 }
            job()
        }
        return true
    }

    /// Spots waiting in the queue (tests).
    var spotsWaiting: Int {
        waitingSpots.withLock { $0 }
    }

    /// Waits (without blocking a thread) until everything submitted before has run.
    func settle() async {
        await lane.settle()
    }
}

/// Fires once from any thread; `wait` returns after the first `fire` (or at once when it already happened). Used to
/// end a wait on whichever comes first: the lane finishing its work or the time bound.
final class OneShot: @unchecked Sendable {
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
        await withCheckedContinuation { (next: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                next.resume()
                return
            }
            continuation = next
            lock.unlock()
        }
    }
}

/// The latest own status waiting to be published, so a burst of changes becomes one publish (the state loop and the
/// transmit announcements offer a status; only the newest goes out).
final class StatusSlot: Sendable {
    private struct State {
        var latest: StationStatusWire?
        var queued = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Stores `status` as the latest; `true` = no publish is queued yet and the caller queues one.
    func offer(_ status: StationStatusWire) -> Bool {
        state.withLock { current in
            current.latest = status
            if current.queued {
                return false
            }
            current.queued = true
            return true
        }
    }

    /// The newest status; the next `offer` queues a new publish.
    func take() -> StationStatusWire? {
        state.withLock { current in
            current.queued = false
            let latest: StationStatusWire? = current.latest
            current.latest = nil
            return latest
        }
    }
}
