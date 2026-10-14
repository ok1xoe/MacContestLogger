import Foundation

/// Open sets keyed on the worked callsign itself (Swift-only algorithms, N1MM `MultSqlString = CallSign` /
/// `LASTLETTER`): `callsign` = the base call (`OK1ABC/P` = `OK1ABC`, every station is a multiplier — e.g. each OK/OL
/// station per band in OK DX RTTY), `lastLetter` = the last character of the base call (`OK1WC` memorial: A–Z, 0–9).
public final class CallsignMultiplierSet: MultiplierSet {

    public enum Kind: Sendable {
        case callsign, lastLetter
    }

    public let id: String?
    let kind: Kind

    public init(id: String?, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public var enumerable: Bool { false }

    public var values: [MultiplierValue] { [] }

    public func isExpected(_ key: String?) -> Bool { true }

    public func normalize(_ rawValue: String?) -> Resolution {
        guard let rawValue, !JavaText.isBlank(rawValue) else {
            return .invalid("prázdná volačka")
        }
        return key(of: rawValue)
    }

    public func deriveFromCallsign(_ callsign: String?) -> Resolution {
        guard let callsign, !JavaText.isBlank(callsign) else {
            return .invalid("prázdná volačka")
        }
        return key(of: callsign)
    }

    private func key(of call: String) -> Resolution {
        let base: String = ContestSession.baseCall(call)
        switch kind {
        case .callsign:
            return base.isEmpty ? .invalid("prázdná volačka") : .valid(base)
        case .lastLetter:
            guard let last = base.last else { return .invalid("prázdná volačka") }
            return .valid(String(last))
        }
    }
}
