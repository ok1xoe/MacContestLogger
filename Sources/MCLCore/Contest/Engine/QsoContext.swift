import os

/// A QSO enriched by resolvers — input for the evaluators (points, multipliers, dupe). The evaluators
/// read only from here → pure, testable logic. Port of Java `engine/QsoContext.java`
/// (`record`, 11 components); an immutable value, passed freely between threads (the only internal
/// state is a lazily built map of expression variables behind a lock, see `expressionVariables`).
///
/// - `received`: received exchange fields by id in definition order. A Java `LinkedHashMap`,
///   hence `JavaLinkedMap` (keys by UTF-16, `nil` id and `nil` value are possible).
/// - `ownQth`: where I transmit from (rover / county line, N1MM ROVERQTH) — from another county
///   the same station can be worked again.
/// - `bonusStation`: the other station is on the list of bonus stations (N1MM BONUS, QSO party).
///
/// The shortened Java constructors (without `ownGrid`, `ownItuZone`, `ownQth`, `bonusStation`)
/// are replaced by default parameter values: missing = `nil` / `false`.
public struct QsoContext: Sendable {
    public let call: String?
    public let band: String?
    public let mode: String?
    public let received: JavaLinkedMap<ExchangeValue>?
    public let workedEntity: DxccEntity?
    public let ownEntity: DxccEntity?
    public let workedClass: String?
    public let ownGrid: String?
    public let ownItuZone: String?
    public let ownQth: String?
    public let bonusStation: Bool

    /// Map of expression variables, built only on the first read (`expressionVariables`).
    private let variablesCache = VariablesCache()

    public init(call: String?, band: String?, mode: String?, received: JavaLinkedMap<ExchangeValue>?,
                workedEntity: DxccEntity?, ownEntity: DxccEntity?, workedClass: String?,
                ownGrid: String? = nil, ownItuZone: String? = nil, ownQth: String? = nil,
                bonusStation: Bool = false) {
        self.call = call
        self.band = band
        self.mode = mode
        self.received = received
        self.workedEntity = workedEntity
        self.ownEntity = ownEntity
        self.workedClass = workedClass
        self.ownGrid = ownGrid
        self.ownItuZone = ownItuZone
        self.ownQth = ownQth
        self.bonusStation = bonusStation
    }

    /// Expression variables (`QsoVariables.of(self)`) built **once per QSO**.
    ///
    /// Java builds the map anew for every expression (`when.expr`, `value.expr`, bonuses). The result is
    /// however a function of the immutable context (a Java `record`, `ExchangeValue` is also a `record`)
    /// and `Expression` only reads the map (`vars.get`), so one shared map gives the same.
    /// A copy of the context shares the same map — all components are `let`.
    var expressionVariables: JavaLinkedMap<ExpressionValue> {
        if let cached = variablesCache.storage.withLock({ $0 }) {
            return cached
        }
        // Built outside the lock; concurrent building gives the same map and either one is stored.
        let built = QsoVariables.of(self)
        variablesCache.storage.withLock { $0 = built }
        return built
    }

    /// Both entities known and have the same `entityCode`.
    public var ownDxcc: Bool {
        guard let workedEntity, let ownEntity else { return false }
        return workedEntity.entityCode == ownEntity.entityCode
    }

    public var workedContinent: String? { workedEntity?.primaryContinent }

    public var ownContinent: String? { ownEntity?.primaryContinent }

    /// Java `w != null && w.equals(own)` — by UTF-16, not by Swift `==`.
    public var sameContinent: Bool {
        guard let worked = workedContinent else { return false }
        return JavaText.equals(worked, ownContinent)
    }

    /// Both known and different (by UTF-16).
    public var otherContinent: Bool {
        guard let worked = workedContinent, let own = ownContinent else { return false }
        return !JavaText.equals(worked, own)
    }

    /// Canonical value of a received field or `nil`.
    ///
    /// A `nil` id over an empty map: Java fails only over the immutable `Map.of()` (the probe context of
    /// `StationClassifier`), not over a `LinkedHashMap`; here always "field missing"
    /// (a recorded leniency).
    public func fieldCanonical(_ id: String?) -> String? {
        received?[id]?.canonical
    }

    /// Raw value of a received field (for normalization in the multiplier set).
    public func fieldRaw(_ id: String?) -> String? {
        received?[id]?.raw
    }

    /// The field is received and valid.
    public func fieldPresent(_ id: String?) -> Bool {
        received?[id]?.valid ?? false
    }
}

/// Box of lazily built variables; a class so that copies of the context share it.
private final class VariablesCache: Sendable {
    let storage = OSAllocatedUnfairLock<JavaLinkedMap<ExpressionValue>?>(initialState: nil)
}
