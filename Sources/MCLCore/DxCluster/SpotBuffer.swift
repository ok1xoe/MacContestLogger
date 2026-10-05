import Foundation
import os

/// Time-limited buffer of DX spots (Java `dxcluster.SpotBuffer`). Key = callsign of the spotted station
/// (uppercased); a re-spot of the same station updates the spot and the time. `snapshot()` returns only spots younger than
/// `maxAge`. Thread-safe (filled by the network thread, read by the UI).
///
/// Java behaviour the ordering rests on:
/// - storage is a `LinkedHashMap` without access-order: **a re-spot keeps the original position** (`put` on an
///   existing key), `remove` + a new `add` goes to the end; `snapshot()` is in insertion order and the tie in
///   `SpotNavigator.next` and in `nearestWithin` rests on it (first wins);
/// - `alive`: with a fixed end `until > now`, otherwise `at > now − maxAge` (strictly — a spot exactly `maxAge`
///   old is dead), `maxAge = max(1, minutes)`;
/// - skimmer merge: the previous entry must be alive, have non-empty skimmers and `|Δf| ≤ 1000 Hz`, otherwise
///   it is counted anew; the clock is called **twice** in `add` for a skimmer spot, but only when the previous
///   entry has non-empty skimmers (the second call is behind short-circuit evaluation of the condition);
/// - keys and the blacklist are compared by UTF-16 units (`JavaStringKey`) after Java uppercasing
///   (port convention `uppercased()`);
/// - listeners are called **outside the lock, synchronously on the caller's thread**.
///
/// Time is a `Date` from the supplied clock (Java `Supplier<Instant>`): seconds in a `Double`, not the nanoseconds
/// of `Instant` (a deliberate divergence from Java v1.1.1). The clock is called **under the lock** (non-reentrant
/// `OSAllocatedUnfairLock`, Java `synchronized` is reentrant) — it must not reach back into the buffer.
public final class SpotBuffer: Sendable {

    /// A skimmer spot of the same station within this distance counts as a confirmation.
    static let skimmerMergeHz: Int64 = 1000

    /// Listener identity for `removeListener` (a Java `Runnable` is removed by identity).
    public struct ListenerID: Hashable, Sendable {
        fileprivate let raw: UInt64
    }

    /// A spot together with the time it arrived — the Info window shows its age in minutes.
    public struct Spotted: Equatable, Sendable {
        public let spot: DxSpot
        public let spottedAt: Date

        public init(spot: DxSpot, spottedAt: Date) {
            self.spot = spot
            self.spottedAt = spottedAt
        }

        /// Age of the spot in whole minutes at time `now` — Java `Duration.between(spottedAt, now).toMinutes()`:
        /// seconds rounded toward −∞ (whole `Duration` seconds), then division by 60 truncating toward zero.
        public func ageMinutes(_ now: Date) -> Int64 {
            let micros = Int64(((now.timeIntervalSince1970 - spottedAt.timeIntervalSince1970) * 1_000_000).rounded())
            let seconds: Int64 = JavaMath.floorDiv(micros, 1_000_000)
            return seconds / 60
        }
    }

    /// - `until`: fixed end of validity (beacons, N1MM `BEACONS`), `nil` = ordinary `maxAge` aging
    /// - `skimmers`: skimmers that report the station (empty = a spot from a human)
    private struct Entry {
        let spot: DxSpot
        let at: Date
        let until: Date?
        let skimmers: Set<JavaStringKey>

        func alive(_ now: Date, _ maxAgeSeconds: Double) -> Bool {
            if let until {
                return until > now
            }
            return at.timeIntervalSince1970 > now.timeIntervalSince1970 - maxAgeSeconds
        }
    }

    private struct State {
        var keys: [JavaStringKey] = []
        var entries: [JavaStringKey: Entry] = [:]
        var maxAgeSeconds: Double
        var blacklistedCalls: Set<JavaStringKey> = []
        var blacklistedSpotters: Set<JavaStringKey> = []
        /// How many different skimmers must confirm a spot (0 = hide skimmer spots, 1 = all).
        var minSkimmers: Int = 1
        var listeners: [(id: UInt64, run: @Sendable () -> Void)] = []
        var nextListenerID: UInt64 = 0

        func isBlacklisted(_ spot: DxSpot) -> Bool {
            blacklistedCalls.contains(JavaStringKey(spot.dxCall.uppercased()))
                || blacklistedSpotters.contains(JavaStringKey(spot.spotter.uppercased()))
        }

        /// Java `LinkedHashMap.put`: an existing key stays at its position.
        mutating func put(_ key: JavaStringKey, _ entry: Entry) {
            if entries.updateValue(entry, forKey: key) == nil {
                keys.append(key)
            }
        }

        mutating func removeKeys(where shouldRemove: (Entry) -> Bool) {
            keys.removeAll { key in
                guard let entry = entries[key], shouldRemove(entry) else { return false }
                entries[key] = nil
                return true
            }
        }
    }

    private let clock: @Sendable () -> Date
    private let state: OSAllocatedUnfairLock<State>

    /// - Parameters:
    ///   - maxAgeMinutes: age after which a spot disappears (at least 1 minute)
    ///   - clock: time source (Java `Supplier<Instant>`)
    public init(maxAgeMinutes: Int, clock: @escaping @Sendable () -> Date) {
        self.clock = clock
        self.state = OSAllocatedUnfairLock(initialState: State(maxAgeSeconds: Self.seconds(minutes: maxAgeMinutes)))
    }

    private static func seconds(minutes: Int) -> Double {
        Double(max(1, minutes)) * 60
    }

    public func setMaxAgeMinutes(_ minutes: Int) {
        state.withLock { $0.maxAgeSeconds = Self.seconds(minutes: minutes) }
        notifyListeners()
    }

    public func add(_ spot: DxSpot) {
        let added: Bool = state.withLock { s in
            if s.isBlacklisted(spot) {
                return false
            }
            let key = JavaStringKey(spot.dxCall.uppercased())
            var skimmers: Set<JavaStringKey> = []
            if SkimmerSpot.isSkimmer(spot) {
                if let prev = s.entries[key], !prev.skimmers.isEmpty, prev.alive(clock(), s.maxAgeSeconds),
                   JavaMath.abs(Int64(prev.spot.freqHz) &- Int64(spot.freqHz)) <= Self.skimmerMergeHz {
                    skimmers = prev.skimmers
                }
                skimmers.insert(JavaStringKey(JavaText.trim(spot.spotter).uppercased()))
            }
            s.put(key, Entry(spot: spot, at: clock(), until: nil, skimmers: skimmers))
            return true
        }
        if added {
            notifyListeners()
        }
    }

    /// Skimmer spot filter: 0 = hide, 1 = all, n = only those confirmed by at least n skimmers.
    public func setMinSkimmers(_ n: Int) {
        state.withLock { $0.minSkimmers = max(0, n) }
        notifyListeners()
    }

    /// How many skimmers report the station (0 = a spot from a human or no spot); ignores age.
    public func skimmerCount(_ dxCall: String?) -> Int {
        guard let dxCall else { return 0 }
        let key = JavaStringKey(JavaText.trim(dxCall).uppercased())
        return state.withLock { $0.entries[key]?.skimmers.count ?? 0 }
    }

    /// Adds a spot with its own validity period (beacons from `BEACONS` last tens of hours).
    public func addUntil(_ spot: DxSpot, until: Date?) {
        let added: Bool = state.withLock { s in
            if s.isBlacklisted(spot) {
                return false
            }
            s.put(JavaStringKey(spot.dxCall.uppercased()), Entry(spot: spot, at: clock(), until: until, skimmers: []))
            return true
        }
        if added {
            notifyListeners()
        }
    }

    /// Removes the spot of the given callsign from the buffer (listeners are called even if it was not there).
    public func remove(_ dxCall: String?) {
        guard let dxCall else { return }
        let key = JavaStringKey(dxCall.uppercased())
        state.withLock { s in
            if s.entries.removeValue(forKey: key) != nil {
                s.keys.removeAll { $0 == key }
            }
        }
        notifyListeners()
    }

    /// Empties the buffer.
    public func clear() {
        state.withLock { s in
            s.keys.removeAll()
            s.entries.removeAll()
        }
        notifyListeners()
    }

    /// Sets the blacklist (callsigns + spotters, compared after uppercasing) and cleans the already stored spots.
    public func setBlacklist(calls: [String]?, spotters: [String]?) {
        let c: Set<JavaStringKey> = Set((calls ?? []).map { JavaStringKey($0.uppercased()) })
        let p: Set<JavaStringKey> = Set((spotters ?? []).map { JavaStringKey($0.uppercased()) })
        state.withLock { s in
            s.blacklistedCalls = c
            s.blacklistedSpotters = p
            let current = s
            s.removeKeys { current.isBlacklisted($0.spot) }
        }
        notifyListeners()
    }

    /// The nearest non-expired spot within tolerance `toleranceHz` of `freqHz`, or `nil`; on a tie the
    /// first in `snapshot()` order wins. The distance is a Java `long` (`Math.abs` wraps around).
    public func nearestWithin(_ freqHz: Int, toleranceHz: Int) -> DxSpot? {
        var best: DxSpot?
        var bestDistance = Int64.max
        let tolerance = Int64(toleranceHz)
        for spot in snapshot() {
            let distance = JavaMath.abs(Int64(spot.freqHz) &- Int64(freqHz))
            if distance <= tolerance && distance < bestDistance {
                best = spot
                bestDistance = distance
            }
        }
        return best
    }

    /// A non-expired spot of the given callsign (Java `trim()` + uppercasing); an expired one is not returned.
    public func find(_ dxCall: String?) -> Spotted? {
        guard let dxCall, !JavaText.isBlank(dxCall) else { return nil }
        let key = JavaStringKey(JavaText.trim(dxCall).uppercased())
        return state.withLock { s in
            guard let entry = s.entries[key], entry.alive(clock(), s.maxAgeSeconds) else { return nil }
            return Spotted(spot: entry.spot, spottedAt: entry.at)
        }
    }

    /// Non-expired spots (a copy) in insertion order, after the skimmer filter.
    public func snapshot() -> [DxSpot] {
        state.withLock { s in
            let now = clock()
            let min = s.minSkimmers
            var out: [DxSpot] = []
            for key in s.keys {
                guard let entry = s.entries[key], entry.alive(now, s.maxAgeSeconds) else { continue }
                if entry.skimmers.isEmpty || (min > 0 && entry.skimmers.count >= min) {
                    out.append(entry.spot)
                }
            }
            return out
        }
    }

    /// Manually notifies listeners (e.g. after grids are looked up) without a content change.
    public func touch() {
        notifyListeners()
    }

    /// Adds a listener (called after every change on the caller's thread). The same listener added
    /// twice is called twice, as in Java.
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

    private func notifyListeners() {
        // Java `CopyOnWriteArrayList`: listeners by snapshot, called outside the lock.
        let listeners = state.withLock { $0.listeners }
        for listener in listeners {
            listener.run()
        }
    }
}
