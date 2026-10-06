import Foundation

/// DXCC countries as a multiplier — the key is **`entityCode`** (not `adifDxcc`),
/// derived from the callsign via `DxccLookup`. Enumeration = all entities (for the
/// "missing" view).
///
/// Port of Java `multiplier/sets/DxccMultiplierSet.java`. `isExpected`
/// does not normalise the key (`"0503"` is not `"503"`), `normalize` from an exchange field
/// is not supported.
public final class DxccMultiplierSet: MultiplierSet {

    public let id: String?
    private let resolver: any DxccLookup
    private let order: [String]
    private let byKey: [String: MultiplierValue]

    public init(id: String?, resolver: any DxccLookup) {
        self.id = id
        self.resolver = resolver
        var order: [String] = []
        var byKey: [String: MultiplierValue] = [:]
        for entity in resolver.entities() {
            let key = String(entity.entityCode)
            let value = MultiplierValue(key: key, label: entity.name, attributes: [
                "countryCode": entity.countryCode ?? "",
                "prefix": entity.primaryPrefix ?? "",
                "continent": entity.primaryContinent ?? "",
            ])
            // Java LinkedHashMap: a duplicate entityCode overwrites at the original position
            if byKey.updateValue(value, forKey: key) == nil {
                order.append(key)
            }
        }
        self.order = order
        self.byKey = byKey
    }

    public var enumerable: Bool { true }

    public var values: [MultiplierValue] { order.compactMap { byKey[$0] } }

    public func isExpected(_ key: String?) -> Bool {
        guard let key else { return false }
        return byKey[key] != nil
    }

    /// The country is derived from the callsign, never from an exchange field.
    public func normalize(_ rawValue: String?) -> Resolution {
        .unsupported
    }

    public func deriveFromCallsign(_ callsign: String?) -> Resolution {
        resolution(callsign, resolver.resolve(callsign))
    }

    /// As of the QSO date (Club Log data; the other resolvers ignore the date and answer as above).
    public func deriveFromCallsign(_ callsign: String?, at date: Date?) -> Resolution {
        resolution(callsign, resolver.resolve(callsign, at: date))
    }

    private func resolution(_ callsign: String?, _ resolved: DxccEntity?) -> Resolution {
        if let entity = resolved {
            return .valid(String(entity.entityCode))
        }
        // Java "…" + callsign: null prints as "null"
        return .invalid("neznámá DXCC entita: " + (callsign ?? "null"))
    }
}
