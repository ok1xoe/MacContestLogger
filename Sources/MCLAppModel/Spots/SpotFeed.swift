import Foundation
import MCLCore
import Observation
import os

/// The one subscription of the app to the spot buffer: Kotlin adds a `SpotBuffer` listener in five
/// places (the bandmap, the available multipliers, the multiplier grids, the map and the callbook prefetch), each
/// copying the buffer on the network thread. Here a single listener (its `ListenerID` kept and removed on `stop`)
/// coalesces the buffer's changes into one pending hop to the main actor — however many spots arrive meanwhile —
/// where `revision` rises and the observers run; the windows read `snapshot()` when they redraw. A 15 s tick
/// (Kotlin's bandmap `delay(15_000)`) raises `revision` too, so aged spots disappear without a new one arriving.
@Observable @MainActor
public final class SpotFeed {

    /// Kotlin's bandmap refresh period.
    public static let tickMilliseconds = 15_000

    /// Observer identity for `removeObserver`.
    public struct ObserverID: Hashable, Sendable {
        fileprivate let raw: Int
    }

    /// Rises after every batch of buffer changes and every tick.
    public private(set) var revision: Int = 0

    @ObservationIgnored public let buffer: SpotBuffer
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private let pending = OSAllocatedUnfairLock(initialState: false)
    @ObservationIgnored private var listener: SpotBuffer.ListenerID?
    @ObservationIgnored private var observers: [(id: Int, run: @MainActor () -> Void)] = []
    @ObservationIgnored private var nextObserver = 0
    @ObservationIgnored private var tickTimer: (any RescoreTimer)?

    init(buffer: SpotBuffer, clock: any RescoreClock) {
        self.buffer = buffer
        self.clock = clock
    }

    /// How many observers are registered (tests check the windows unsubscribe).
    var observerCount: Int {
        observers.count
    }

    /// The live spots (a copy, insertion order, after the skimmer filter).
    public func snapshot() -> [DxSpot] {
        buffer.snapshot()
    }

    /// The Bands/Modes filter now (set by the app from the configuration; default: everything passes).
    @ObservationIgnored public var spotFilter: @MainActor () -> SpotFilter = { .default }
    /// The analysis the filter infers modes and the contest from (set by the app).
    @ObservationIgnored public var filterAnalyzer: @MainActor () -> SpotAnalyzer? = { nil }

    /// The live spots after the Bands/Modes filter — what the band map, the Available Mults and the spot
    /// navigation show. The buffer itself is untouched, so a changed filter applies to the existing spots.
    public func filteredSnapshot() -> [DxSpot] {
        let all: [DxSpot] = buffer.snapshot()
        let filter: SpotFilter = spotFilter()
        guard !filter.isDefault else { return all }
        return filter.apply(all, analyzer: filterAnalyzer())
    }

    /// The filter (or the contest it depends on) changed: redraw the observers like after a new spot.
    public func filterChanged() {
        changed()
    }

    /// `body` runs on the main actor after every batch of buffer changes (not on the tick).
    @discardableResult
    public func addObserver(_ body: @escaping @MainActor () -> Void) -> ObserverID {
        let id: Int = nextObserver
        nextObserver += 1
        observers.append((id, body))
        return ObserverID(raw: id)
    }

    public func removeObserver(_ id: ObserverID) {
        observers.removeAll { $0.id == id.raw }
    }

    /// Subscribes to the buffer and starts the tick.
    func start() {
        guard listener == nil else { return }
        let pending: OSAllocatedUnfairLock<Bool> = self.pending
        listener = buffer.addListener { [weak self] in
            let first: Bool = pending.withLock { waiting in
                if waiting { return false }
                waiting = true
                return true
            }
            guard first else { return }
            MainHop.post {
                pending.withLock { $0 = false }
                self?.changed()
            }
        }
        scheduleTick()
    }

    /// Unsubscribes and stops the tick (the quit).
    func stop() {
        if let listener {
            buffer.removeListener(listener)
        }
        listener = nil
        tickTimer?.cancel()
        tickTimer = nil
        observers.removeAll()
    }

    private func changed() {
        revision += 1
        for observer in observers {
            observer.run()
        }
    }

    private func scheduleTick() {
        tickTimer = clock.schedule(afterMilliseconds: Self.tickMilliseconds) { [weak self] in
            guard let self, self.listener != nil else { return }
            self.revision += 1
            self.scheduleTick()
        }
    }
}
