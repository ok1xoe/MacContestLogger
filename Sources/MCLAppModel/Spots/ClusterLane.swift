import Foundation
import MCLCore
import os

/// One DX cluster connection with its serial lane: `connect`, `login`, `logout`, `send`, `disconnect`
/// and the `myCall` updates of the session run there in the order they were asked for, never on the main thread or
/// in Swift's cooperative pool. A call that throws (the traffic log's Java error) is reported through `onError`
/// like the session's own unexpected errors.
final class ClusterLane: Sendable {
    let session: any ClusterSessionPort
    private let lane: SerialLane
    private let onError: @Sendable (any Error) -> Void
    private let pending = OSAllocatedUnfairLock(initialState: false)

    init(session: any ClusterSessionPort, name: String, onError: @escaping @Sendable (any Error) -> Void) {
        self.session = session
        self.lane = SerialLane(name: name)
        self.onError = onError
    }

    /// Runs `body` with the session on the lane.
    func run(_ body: @escaping @Sendable (any ClusterSessionPort) throws -> Void) {
        let session: any ClusterSessionPort = self.session
        let onError: @Sendable (any Error) -> Void = self.onError
        lane.submit {
            do {
                try body(session)
            } catch {
                onError(error)
            }
        }
    }

    /// A `connect` is queued and has not reached the session yet (the session is not „connecting" until then).
    var connectPending: Bool {
        pending.withLock { $0 }
    }

    /// Queues `connect`; until it runs `connectPending` is `true` (Kotlin sets `connecting` synchronously).
    func connect(_ fav: DxClusterFavorite, autoLogin: Bool) {
        pending.withLock { $0 = true }
        let pending: OSAllocatedUnfairLock<Bool> = self.pending
        run { session in
            defer { pending.withLock { $0 = false } }
            try session.connect(fav, autoLogin: autoLogin)
        }
    }

    /// Waits until the work queued before has run.
    func settle() async {
        await lane.settle()
    }

    /// Waits for the lane, then for the session's own threads (a connect, its auto-login, sending).
    func idle() async {
        await lane.settle()
        await session.idle()
    }
}
