import Foundation

/// Definition-driven duplicate check (`dupe.scope`). Key = callsign + scope
/// (band / mode / `*`) + my county (rover/county line: from another county it is not a dupe)
/// + session number if TOUR is on (each session is worked anew).
///
/// Port of Java `contest.engine.ContestDupeChecker`. Java has a mutable class with a `HashSet`;
/// here it is a `struct` with value semantics (a copy is independent), because the session travels
/// between threads. Keys are compared **by UTF-16 units** like `HashSet<String>`, not by
/// Swift's canonical `==` (`Å` U+00C5 and `A` + U+030A are different callsigns for Java).
///
/// The key is a glued text `callsign|scopeKey|county|session` without escape characters, so
/// as in Java values with `|` can collide (e.g. band `a|b` + mode `c` and band `a`
/// + mode `b|c` in `PER_BAND_MODE`) — measured, copied.
public struct ContestDupeChecker: Sendable {

    /// Key by UTF-16 units (matches `String.equals`/`hashCode` in Java).
    private struct Key: Hashable, Sendable {
        let units: [UInt16]
    }

    private let scope: ContestDefinition.Scope
    private var worked: Set<Key> = []
    /// `dupe.none`: nothing is a dupe.
    private let none: Bool
    /// `dupe.reworkMinutes`: the last time of each key (epoch seconds) and the minutes after which it is no dupe.
    private let reworkSeconds: Int64?
    private var lastWorked: [Key: Int64] = [:]
    /// `dupe.byField`: a received field that is part of the key.
    private let byField: String?

    /// TOUR session (`nil` = the whole contest is one session). Java `setTour`; it does not delete keys already written.
    public var tour: Tour?

    /// Java constructor: a missing `dupe` and a missing `dupe.scope` both give `PER_BAND`.
    public init(definition: ContestDefinition) {
        self.init(scope: definition.dupe?.scope, none: definition.dupe?.none ?? false,
                  reworkMinutes: definition.dupe?.reworkMinutes, byField: definition.dupe?.byField)
    }

    public init(scope: ContestDefinition.Scope?, none: Bool = false, reworkMinutes: Int? = nil,
                byField: String? = nil) {
        self.scope = scope ?? .PER_BAND
        self.none = none
        self.reworkSeconds = reworkMinutes.flatMap { $0 > 0 ? Int64($0) * 60 : nil }
        self.byField = byField.flatMap { JavaText.isBlank($0) ? nil : $0 }
    }

    /// Java `isDupe(ctx, at)`; `atEpochSecond == nil` = `Instant` `null` (the session is not counted
    /// and the key has an empty session part even when TOUR is on).
    public func isDupe(_ context: QsoContext, atEpochSecond: Int64?) -> Bool {
        if none { return false }
        let key = key(context, atEpochSecond)
        if let reworkSeconds {
            guard let last = lastWorked[key] else { return false }
            guard let at = atEpochSecond else { return true }
            return at - last < reworkSeconds
        }
        return worked.contains(key)
    }

    /// `dupe.reworkMinutes`: minutes until the station may be worked again at `atEpochSecond` (`nil` = it may).
    public func minutesUntilRework(_ context: QsoContext, atEpochSecond: Int64) -> Int64? {
        guard !none, let reworkSeconds, let last = lastWorked[key(context, atEpochSecond)] else { return nil }
        let left: Int64 = reworkSeconds - (atEpochSecond - last)
        return left > 0 ? (left + 59) / 60 : nil
    }

    /// The instant as `Date` (floor of seconds, see `Tour.session(at:)`).
    public func isDupe(_ context: QsoContext, at date: Date) -> Bool {
        isDupe(context, atEpochSecond: Self.epochSecond(date))
    }

    /// Java `isDupe(ctx)` = `Instant.now()`.
    public func isDupe(_ context: QsoContext) -> Bool {
        isDupe(context, at: Date())
    }

    public mutating func add(_ context: QsoContext, atEpochSecond: Int64?) {
        let key = key(context, atEpochSecond)
        // dupe.reworkMinutes counts from the last QSO that counted (a dupe logged anyway does not restart it).
        if reworkSeconds != nil, let atEpochSecond, !isDupe(context, atEpochSecond: atEpochSecond) {
            lastWorked[key] = atEpochSecond
        }
        worked.insert(key)
    }

    public mutating func add(_ context: QsoContext, at date: Date) {
        add(context, atEpochSecond: Self.epochSecond(date))
    }

    public mutating func add(_ context: QsoContext) {
        add(context, at: Date())
    }

    public mutating func reset() {
        worked.removeAll()
        lastWorked.removeAll()
    }

    private static func epochSecond(_ date: Date) -> Int64 {
        JavaMath.d2l(date.timeIntervalSince1970.rounded(.down))
    }

    /// `call.trim().toUpperCase()` (`null` → `""`) + `|` + `scopeKey` + `|` + `ownQth`
    /// (`null` → `""`, without trim and without changing case) + `|` + session number (or `""`).
    private func key(_ context: QsoContext, _ epochSecond: Int64?) -> Key {
        let call = context.call.map { JavaText.trim($0).uppercased() } ?? ""
        let qth = context.ownQth ?? ""
        var session = ""
        if let tour, let epochSecond {
            session = String(tour.session(epochSecond: epochSecond))
        }
        var units = Array(call.utf16)
        units.append(0x7C)
        units.append(contentsOf: ScopeKey.make(scope, context).utf16)
        units.append(0x7C)
        units.append(contentsOf: qth.utf16)
        units.append(0x7C)
        units.append(contentsOf: session.utf16)
        if let byField {
            // dupe.byField: a station in another county / grid is a new one.
            units.append(0x7C)
            units.append(contentsOf: (context.fieldCanonical(byField) ?? "").utf16)
        }
        return Key(units: units)
    }
}

/// Java `MultiplierEvaluator.scopeKey(scope, ctx)`: `ONCE` → `*`, `PER_BAND` → band,
/// `PER_MODE` → mode, `PER_BAND_MODE` → `band|mode`; a missing band/mode is written as `null`
/// (`String.valueOf`, or string concatenation). Shared by the dupe check and multiplier evaluation.
enum ScopeKey {
    static func make(_ scope: ContestDefinition.Scope?, _ context: QsoContext) -> String {
        guard let scope else { return "*" }
        switch scope {
        case .ONCE: return "*"
        case .PER_BAND: return context.band ?? "null"
        case .PER_MODE: return context.mode ?? "null"
        case .PER_BAND_MODE: return (context.band ?? "null") + "|" + (context.mode ?? "null")
        }
    }
}
