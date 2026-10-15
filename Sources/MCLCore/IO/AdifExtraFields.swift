import Foundation

/// The contest definition's `adif` map applied to the logged QSOs: ADIF field name → a received field's value or a
/// fixed `=text` (N1MM DXSATELLIT writes `PROP_MODE` SAT and `SAT_NAME`).
public enum AdifExtraFields {

    public struct Field: Equatable, Sendable {
        public let name: String
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// The fields of every QSO (by `uuid`); QSOs without a value for any of them are left out.
    public static func compute(_ definition: ContestDefinition?, session: ContestSession?,
                               qsos: [Qso]) -> [String: [Field]] {
        guard let map = definition?.adif, !map.keys.isEmpty else { return [:] }
        var out: [String: [Field]] = [:]
        for qso in qsos where !qso.uuid.isEmpty {
            let received: JavaLinkedMap<String> = (try? session?.receivedFromFlat(
                call: qso.call, exchangeRcvdFlat: qso.exchangeRcvd, serialRcvd: qso.serialRcvd)) ?? JavaLinkedMap()
            var fields: [Field] = []
            for name in map.keys {
                guard let source = map[name].map({ JavaText.trim($0) }), !source.isEmpty else { continue }
                let value: String
                if source.hasPrefix("=") {
                    value = String(source.dropFirst())
                } else {
                    value = JavaText.trim(received[source] ?? "")
                }
                if !value.isEmpty {
                    fields.append(Field(name: name.uppercased(), value: value))
                }
            }
            if !fields.isEmpty {
                out[qso.uuid] = fields
            }
        }
        return out
    }
}
