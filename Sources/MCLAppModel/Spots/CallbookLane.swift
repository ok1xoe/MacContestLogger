import Foundation
import MCLCore
import os

/// The serial lane of the callbook work (Kotlin `Dispatchers.IO`): the HamQTH and QRZ.com lookups (blocking HTTP),
/// the spot prefetch and the lazy load of the offline grid data run there one after another, never on the main
/// thread or in Swift's cooperative pool. After `close` (the quit) queued jobs are skipped.
final class CallbookLane: Sendable {
    private let lane = SerialLane(name: "callbook")
    private let closed = OSAllocatedUnfairLock(initialState: false)

    /// Runs `body` on the lane (skipped once closed).
    func submit(_ body: @escaping @Sendable () -> Void) {
        let closed = self.closed
        lane.submit {
            if closed.withLock({ $0 }) { return }
            body()
        }
    }

    /// `body` on the lane, then `then` with its result on the main actor (neither once closed).
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

    /// Waits until the work queued before has run.
    func settle() async {
        await lane.settle()
    }

    /// Skips the queued and later jobs without waiting.
    func markClosed() {
        closed.withLock { $0 = true }
    }

    /// Skips the queued jobs and waits for the running one (the quit).
    func close() async {
        closed.withLock { $0 = true }
        await lane.settle()
    }
}

/// The merged callbook records by call key (Kotlin `hamQthCache`, a `ConcurrentHashMap`): written on the callbook
/// lane, read by the spot analysis on any thread. `EMPTY` = asked, nothing found. `clear` starts a new generation, so
/// a lookup that was in flight then does not write its stale result.
final class CallbookCache: Sendable {
    private struct State {
        var records: [String: HamQthRecord] = [:]
        var generation = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var generation: Int {
        state.withLock { $0.generation }
    }

    func record(_ key: String) -> HamQthRecord? {
        state.withLock { $0.records[key] }
    }

    func contains(_ key: String) -> Bool {
        state.withLock { $0.records[key] != nil }
    }

    /// Stores `record` unless the cache was cleared after `generation` was read.
    func store(_ key: String, _ record: HamQthRecord, generation: Int) {
        state.withLock { s in
            if s.generation == generation {
                s.records[key] = record
            }
        }
    }

    func clear() {
        state.withLock { s in
            s.records.removeAll()
            s.generation += 1
        }
    }
}

/// The offline grid data (Kotlin `by lazy` `gridDatabase` and `gridFieldMap`), loaded once on the callbook lane.
public struct GridData: Sendable {
    public let database: GridDatabase
    public let fieldMap: GridFieldMap
}

/// Loads `GridData` once (on the lane) and keeps it for later lane jobs.
final class GridDataLoader: Sendable {
    private let loaded = OSAllocatedUnfairLock<GridData?>(initialState: nil)

    var current: GridData? {
        loaded.withLock { $0 }
    }

    /// The data, read from `root` the first time (blocks; on the lane only).
    func load(root: URL, dxcc: (any DxccLookup)?) -> GridData {
        if let data = current {
            return data
        }
        let data = GridData(database: GridDatabase.fromDir(root), fieldMap: GridFieldMap.fromDir(root, dxcc))
        loaded.withLock { $0 = data }
        return data
    }
}
