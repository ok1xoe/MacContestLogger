import Foundation

/// Values for updating call history from the log (N1MM "Update Call History from log", DXLog
/// "Update prefill database from log"), Java `callhistory/CallHistoryUpdater` v1.1.1: from each
/// QSO the received exchange fields (without report and serial number); a newer QSO overwrites an older one.
public enum CallHistoryUpdater {

    /// Callsign (trimmed `trim`, upper-cased `toUpperCase()`) → (column → value), columns per
    /// `CallHistory.columnFor`. Without deleted, X-QSO and QSO with an empty callsign; QSOs stably by
    /// time, those without time first (`nullsFirst`).
    ///
    /// Throws the station class expression error like Java (`activeReceivedFields`). A field without type or without
    /// `id` Java cannot handle (NPE from `Set.of(…).contains(null)`, resp. `columnFor`); here it is skipped.
    public static func updates(_ session: ContestSession, _ qsos: [Qso],
                               _ callHistory: CallHistory) throws(ExpressionError) -> JavaLinkedMap<JavaLinkedMap<String>> {
        var out = JavaLinkedMap<JavaLinkedMap<String>>()
        let kept: [(index: Int, qso: Qso)] = qsos.enumerated()
            .filter { !$0.element.deleted && !$0.element.xqso && !JavaText.isBlank($0.element.call) }
            .map { (index: $0.offset, qso: $0.element) }
        let ordered = kept.sorted { left, right in
            switch (left.qso.timestampUtc, right.qso.timestampUtc) {
            case let (l?, r?) where l != r:
                return l < r
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            default:
                return left.index < right.index
            }
        }
        for (_, qso) in ordered {
            let raw: JavaLinkedMap<String> = try session.receivedFromFlat(
                call: qso.call, exchangeRcvdFlat: qso.exchangeRcvd, serialRcvd: qso.serialRcvd)
            for field in try session.activeReceivedFields(call: qso.call) {
                guard let type = field.type, !CallHistory.isSkipped(type),
                      let column = callHistory.columnFor(field),
                      let value = raw[field.id], !JavaText.isBlank(value) else { continue }
                let key: String = JavaText.toUpperCase(JavaText.trim(qso.call))
                var record: JavaLinkedMap<String> = out[key] ?? JavaLinkedMap()
                record.put(column, value)
                out.put(key, record)
            }
        }
        return out
    }
}
