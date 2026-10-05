import Foundation

/// WPX prefixes — an open set (cannot be enumerated). The key is derived from the callsign
/// by the `PrefixExtractor.wpx` algorithm; any prefix is "known".
///
/// Port of Java `multiplier/sets/WpxMultiplierSet.java`. `normalize` does not check the
/// shape of the prefix, only `trim()` + uppercase.
public final class WpxMultiplierSet: MultiplierSet {

    public let id: String?

    public init(id: String?) {
        self.id = id
    }

    public var enumerable: Bool { false }

    public var values: [MultiplierValue] { [] }

    /// Open set — everything is "known", even `nil`.
    public func isExpected(_ key: String?) -> Bool { true }

    public func normalize(_ rawValue: String?) -> Resolution {
        guard let rawValue, !JavaText.isBlank(rawValue) else {
            return .invalid("prázdný prefix")
        }
        return .valid(JavaText.trim(rawValue).uppercased())
    }

    public func deriveFromCallsign(_ callsign: String?) -> Resolution {
        guard let callsign, !JavaText.isBlank(callsign) else {
            return .invalid("prázdná volačka")
        }
        return .valid(PrefixExtractor.wpx(callsign))
    }
}
