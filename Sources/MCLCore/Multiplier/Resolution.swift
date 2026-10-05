import Foundation

/// Result of normalising or deriving a multiplier key.
///
/// Port of Java `multiplier/Resolution.java`. Deliberately a **struct with three
/// optional fields**, not an enum with payloads: the Java record has `status`, `key`
/// and `reason`, and consumers compare it as a whole and read `key` even on an
/// invalid result (they get `null`).
///
/// - `valid` — the key is well-formed (whether it is "expected" is decided by
///   `MultiplierSet.isExpected`),
/// - `invalid` — the value cannot be normalised to a key, `reason` says why,
/// - `unsupported` — the operation makes no sense for this set (deriving from a callsign
///   for a set filled from an exchange field).
public struct Resolution: Equatable, Sendable {

    public enum Status: Sendable, Equatable {
        case valid
        case invalid
        case unsupported
    }

    public let status: Status
    public let key: String?
    public let reason: String?

    public init(status: Status, key: String?, reason: String?) {
        self.status = status
        self.key = key
        self.reason = reason
    }

    /// Valid key (`reason == nil`).
    public static func valid(_ key: String?) -> Resolution {
        Resolution(status: .valid, key: key, reason: nil)
    }

    /// Invalid value with a reason (`key == nil`).
    public static func invalid(_ reason: String?) -> Resolution {
        Resolution(status: .invalid, key: nil, reason: reason)
    }

    /// Unsupported operation (`key == nil`, `reason == nil`).
    public static let unsupported = Resolution(status: .unsupported, key: nil, reason: nil)

    public var isValid: Bool { status == .valid }
}
