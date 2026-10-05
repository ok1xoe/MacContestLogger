import Foundation

/// A single value of a multiplier set (CQ zone "14", DXCC entity, state…).
///
/// Port of Java `multiplier/MultiplierValue.java` (record).
///
/// `key` and `label` are optional because Java does not validate them and really does
/// send `null` into them: a `ValueDef` without `key` gives a value with key `null` in the registry
/// (and label `null`, since the label falls back to the key), a DXCC entity without a name gives
/// label `null` (measured by the `ProbeSets` probe). Empty text is a different value.
///
/// Consumers read attributes only by key (`prefix`, `continent`, `calls`),
/// nobody iterates them — so a dictionary suffices. A Java map may also carry a `null`
/// value (`attributes: { c: ~ }` in YAML); `get` returns `null` on it just
/// like on a missing key, so the conversion to a dictionary (the registry's job) omits it.
public struct MultiplierValue: Equatable, Sendable {

    /// Canonical key (unique within the set).
    public let key: String?
    /// Human-readable description.
    public let label: String?
    /// Additional attributes (continent, countryCode…), may be empty.
    public let attributes: [String: String]

    public init(key: String?, label: String?, attributes: [String: String] = [:]) {
        self.key = key
        self.label = label
        self.attributes = attributes
    }
}
