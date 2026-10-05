import Foundation
import os

/// Live traffic log of communication with the DX cluster (Java `dxcluster.DxClusterTrafficLog`). A ring buffer
/// of the last `maxLines` lines; thread-safe — written by the client's reader thread and the UI (sent
/// commands). Modelled on `CatTrafficLog`, but the instance belongs to a specific connection (not a singleton).
///
/// Line: `HH:mm:ss` (Java `LocalTime.now()` = **local** time of the system zone, seconds truncated) + two
/// spaces + `» `/`· `/nothing + text. Listeners are called outside the lock, synchronously on the writer's thread.
///
/// Negative capacity: after inserting, Java empties the queue and `removeFirst` then throws
/// `NoSuchElementException` — here `JavaNoSuchElementError` (the buffer stays empty, listeners are not
/// called), hence `tx`/`rx`/`info` throw.
public final class DxClusterTrafficLog: Sendable {

    /// Listener identity for `removeListener`.
    public struct ListenerID: Hashable, Sendable {
        fileprivate let raw: UInt64
    }

    private struct State {
        var lines: [String] = []
        var listeners: [(id: UInt64, run: @Sendable () -> Void)] = []
        var nextListenerID: UInt64 = 0
    }

    let maxLines: Int
    private let clock: @Sendable () -> Date
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// - Parameters:
    ///   - maxLines: buffer capacity (Java default constructor: 1,000)
    ///   - clock: time source (tests); the zone is always the current system zone
    public init(maxLines: Int = 1000, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.maxLines = maxLines
        self.clock = clock
    }

    /// Command sent to the cluster.
    public func tx(_ msg: String) throws {
        try record("\u{00BB} " + msg)
    }

    /// Line received from the cluster (without framing — raw text).
    public func rx(_ msg: String) throws {
        try record(msg)
    }

    /// Informational/status message (connection, errors).
    public func info(_ msg: String) throws {
        try record("\u{00B7} " + msg)
    }

    /// Current snapshot of the buffer (a copy).
    public func snapshot() -> [String] {
        state.withLock { $0.lines }
    }

    public func clear() {
        state.withLock { $0.lines.removeAll() }
    }

    @discardableResult
    public func addListener(_ listener: @escaping @Sendable () -> Void) -> ListenerID {
        state.withLock { s in
            let id = s.nextListenerID
            s.nextListenerID += 1
            s.listeners.append((id, listener))
            return ListenerID(raw: id)
        }
    }

    public func removeListener(_ id: ListenerID) {
        state.withLock { s in
            if let index = s.listeners.firstIndex(where: { $0.id == id.raw }) {
                s.listeners.remove(at: index)
            }
        }
    }

    private func record(_ body: String) throws {
        // `LocalTime.format("HH:mm:ss")` = the first eight characters of `HH:mm:ss.SSS` from `CatTrafficLog`.
        let stamp = String(CatTrafficLog.timestamp(clock(), timeZone: TimeZone.current).prefix(8))
        let line = stamp + "  " + body
        try state.withLock { s in
            s.lines.append(line)
            while s.lines.count > maxLines {
                guard !s.lines.isEmpty else { throw JavaNoSuchElementError() }
                s.lines.removeFirst()
            }
        }
        let listeners = state.withLock { $0.listeners }
        for listener in listeners {
            listener.run()
        }
    }
}
