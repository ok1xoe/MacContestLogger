import Foundation

/// Conversion of the received exchange of an imported QSO to the form in which the entry window stores it:
/// values of the contest's active fields in definition order, separated by a space (with the report in place
/// of the RST field). Score recalculation and the Cabrillo export read this form. Port of
/// `io/ImportedExchange.java` (Java v1.1.1).
///
/// Importers split the exchange in their own way: `CabrilloReader` puts the first token after the callsign into
/// `rstRcvd` and the rest into `exchangeRcvd`, `AdifReader` fills only `rstRcvd` and `serialRcvd`.
/// The tokens are therefore joined back together and assigned to fields in the order `cabrillo.receivedOrder` —
/// the way the sender wrote them.
///
/// Java `null` in `rstRcvd`/`exchangeRcvd` is `""` here; Java treats both
/// via `isBlank()` the same way, so the difference does not matter.
public enum ImportedExchange {

    /// - Parameters:
    ///   - def: definition of the active contest
    ///   - active: received fields valid for the QSO's callsign
    ///   - q: imported QSO
    /// - Returns: the exchange in entry-window form, or `nil` when nothing is left
    public static func toFlat(_ def: ContestDefinition, _ active: [ContestDefinition.ExchangeField],
                              _ q: Qso) -> String? {
        var tokens: [String] = []
        let hasReport = !JavaText.isBlank(q.rstRcvd)
        if hasReport {
            tokens.append(JavaText.trim(q.rstRcvd))
        }
        if !JavaText.isBlank(q.exchangeRcvd) {
            tokens.append(contentsOf: splitOnJavaSpace(JavaText.trim(q.exchangeRcvd)))
        }

        // `LinkedHashMap<String, ExchangeField>`: a later field with the same id overwrites the earlier one
        // at its position; a `null` key is valid. Ids compared by UTF-16 (`JavaLinkedMap`).
        var byId = JavaLinkedMap<ContestDefinition.ExchangeField>()
        for field in active {
            byId.put(field.id, field)
        }
        // `receivedOrder.stream().filter(byId::containsKey)` — a repeated id stays repeated.
        var order: [String?] = []
        for id in def.cabrillo?.receivedOrder ?? [] where byId.containsKey(id) {
            order.append(id)
        }
        for id in byId.keys where !order.contains(where: { JavaStringKey($0) == JavaStringKey(id) }) {
            order.append(id)
        }

        var values = JavaLinkedMap<String>()
        var next = 0
        for id in order {
            let type = byId[id]?.type
            // Without a report in the file (ADIF without RST) do not steal the first exchange token as the report.
            let isReport = type == .RST || type == .RS
            if isReport && !hasReport {
                continue
            }
            if next < tokens.count {
                values.put(id, tokens[next])
                next += 1
            } else if type == .SERIAL, let serial = q.serialRcvd {
                values.put(id, String(serial))
            }
        }
        var flat: [String] = []
        for field in active {
            if let value = values[field.id], !JavaText.isBlank(value) {
                flat.append(value.uppercased())
            }
        }
        return flat.isEmpty ? nil : flat.joined(separator: " ")
    }

    /// Java `text.split("\\s+")` over an already **trimmed** text: `trim()` drops all characters
    /// ≤ U+0020, hence the whole Java `\s` (`[ \t\n\u{0B}\f\r]`), so an empty token arises
    /// only from empty text (`[""]`) — e.g. from the exchange `"\u{0001}"`, which `isBlank()` does not
    /// consider empty. NBSP is not Java `\s` and does not split a token.
    static func splitOnJavaSpace(_ trimmed: String) -> [String] {
        var out: [String] = []
        var current: [UInt8] = []
        var inSpace = false
        for byte in trimmed.utf8 {
            if byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) {
                inSpace = true
            } else {
                if inSpace {
                    out.append(String(decoding: current, as: UTF8.self))
                    current.removeAll(keepingCapacity: true)
                    inSpace = false
                }
                current.append(byte)
            }
        }
        out.append(String(decoding: current, as: UTF8.self))
        return out
    }
}
