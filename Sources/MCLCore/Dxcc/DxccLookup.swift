import Foundation

/// Interface for resolving a callsign to a DXCC entity. Implementations: `DxccResolver`
/// (from `dxcc.json`) and later `CtyDxccResolver` (from `cty.dat` -- more precise,
/// with exceptions for specific callsigns and per-prefix zones/continent).
///
/// Port of the Java `dxcc/DxccLookup.java`. The contract nowhere specifies the behaviour for
/// empty input -- each implementation handles it itself, but all agree on
/// "nothing", never an exception. That is why `callsign` is optional: the Java `null` callsign
/// is part of the behaviour (returns nothing), not an error.
///
/// **`Sendable`:** Java builds a new session in the background and shares the resolver with the live
/// session on the main thread (the Java resolvers keep caches in a `ConcurrentHashMap`). Hence
/// every implementation must be safe for concurrent `resolve` -- the memoization cache
/// belongs behind a lock (`DxccResolver`, `CtyDxccResolver`).
public protocol DxccLookup: Sendable {

    /// Resolves a callsign to a DXCC entity, or returns `nil` when it is not known.
    func resolve(_ callsign: String?) -> DxccEntity?

    /// All entities (for enumerating a multiplier set).
    func entities() -> [DxccEntity]

    /// Resolves a callsign as of a QSO date (`nil` = now). Only a source with date-ranged records (Club Log's
    /// `cty.xml`) uses the date; the default ignores it and answers `resolve(_:)`.
    func resolve(_ callsign: String?, at date: Date?) -> DxccEntity?
}

extension DxccLookup {

    public func resolve(_ callsign: String?, at date: Date?) -> DxccEntity? {
        resolve(callsign)
    }
}
