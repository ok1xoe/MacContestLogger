import Foundation

/// Multiplier set at runtime. It has two faces: **enumeration** (closed sets —
/// for the all/missing views) and **resolving** (from the exchange field `normalize`, or
/// from the callsign `deriveFromCallsign`).
///
/// Port of Java `multiplier/MultiplierSet.java`. Implementations:
/// `FixedMultiplierSet`, `DxccMultiplierSet`, `WpxMultiplierSet`.
///
/// Beware of `isExpected`: the javadoc claims "always true for non-enumerable", but
/// `FixedMultiplierSet` with empty values (`grid_fields`, `rda_oblasts`)
/// claims `enumerable == true` and returns `false` for everything. The consumer
/// works around it with the condition `enumerable && !values.isEmpty` — the behaviour is copied.
///
/// **`Sendable`:** the sets are held by the registry, which a live session shares with background replay.
/// All implementations are immutable after construction.
public protocol MultiplierSet: Sendable {

    /// Set id from the definition; `nil` when the definition has none (Java lets it through).
    var id: String? { get }

    /// Can all values be enumerated? (`false` for open sets, e.g. WPX.)
    var enumerable: Bool { get }

    /// All expected values in definition order (empty for open sets).
    var values: [MultiplierValue] { get }

    /// Is the key in the expected enumeration?
    func isExpected(_ key: String?) -> Bool

    /// Normalisation of a value entered in an exchange field to the canonical key.
    func normalize(_ rawValue: String?) -> Resolution

    /// Deriving the key from a callsign (DXCC, WPX); otherwise `unsupported`.
    func deriveFromCallsign(_ callsign: String?) -> Resolution
}
