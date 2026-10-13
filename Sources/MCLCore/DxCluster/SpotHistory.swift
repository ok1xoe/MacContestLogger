import Foundation
import os

/// Every spot the DX cluster connections received (N1MM „Show Telnet history" of a station and „My call spot
/// history"), kept longer than the traffic log and independent of the spot buffer's timeout: the newest `capacity`
/// spots with the time they arrived and the connection they came from. Thread-safe (filled by the reader threads).
public final class SpotHistory: Sendable {

    /// One received spot.
    public struct Entry: Equatable, Sendable {
        public let spot: DxSpot
        public let at: Date
        /// The parallel connection's tag (its favourite name), `""` for the main connection.
        public let source: String

        public init(spot: DxSpot, at: Date, source: String) {
            self.spot = spot
            self.at = at
            self.source = source
        }
    }

    public static let defaultCapacity = 20_000

    private let capacity: Int
    private let state = OSAllocatedUnfairLock(initialState: [Entry]())

    public init(capacity: Int = SpotHistory.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    public func add(_ spot: DxSpot, at: Date, source: String) {
        let cap: Int = capacity
        state.withLock { entries in
            entries.append(Entry(spot: spot, at: at, source: source))
            if entries.count > cap {
                entries.removeFirst(entries.count - cap)
            }
        }
    }

    /// The spots of `call` (trimmed, ignoring case), oldest first.
    public func entries(of call: String) -> [Entry] {
        let wanted: String = KotlinText.trim(call).uppercased()
        guard !wanted.isEmpty else { return [] }
        return state.withLock { entries in entries.filter { $0.spot.dxCall.uppercased() == wanted } }
    }

    public var count: Int {
        state.withLock { $0.count }
    }

    public func clear() {
        state.withLock { $0.removeAll() }
    }
}
