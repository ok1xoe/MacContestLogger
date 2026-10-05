import Foundation

/// Mapping between the domain `Qso` (station) and the wire schema of cluster sync (`QsoWire`/`QsoState`/
/// `QsoCommand`/`DeleteCommand`) — Java `cluster.WireMapper`. Band and mode go as the names of Java enums
/// (`M20`, `CW`); unknown values are tolerated when reading (the band stays derived from the frequency, the mode empty).
///
/// Text: the Swift `Qso` holds `""` where Java has `null` (a deliberate divergence from Java v1.1.1). On the wire therefore
/// empty text goes as `null` (a Java QSO from the UI has unfilled fields `null` — Kotlin `ifBlank { null }`) and `null`
/// from the wire is read as `""`. A Java station that would send an explicit `""` differs from this only in
/// what it stores in its logbook (`''` instead of `NULL`).
///
/// Time: the model's `Date` ↔ the wire's `JavaInstant` at microsecond level (`JavaInstant(date:)`); nanoseconds from the wire
/// are rounded to the precision of `Date` in `Qso`.
public enum WireMapper {

    static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    public static func toWire(_ q: Qso) -> QsoWire {
        QsoWire(
            timestampUtc: q.timestampUtc.map(JavaInstant.init(date:)),
            call: nonEmpty(q.call),
            freqHz: q.freqHz,
            band: q.band?.javaName,
            mode: q.mode?.rawValue,
            rstSent: nonEmpty(q.rstSent),
            rstRcvd: nonEmpty(q.rstRcvd),
            exchangeSent: nonEmpty(q.exchangeSent),
            exchangeRcvd: nonEmpty(q.exchangeRcvd),
            serialSent: q.serialSent.map { Int32(truncatingIfNeeded: $0) },
            serialRcvd: q.serialRcvd.map { Int32(truncatingIfNeeded: $0) },
            operator: nonEmpty(q.operator),
            comment: nonEmpty(q.comment),
            dxccEntity: q.dxccEntity.map { Int32(truncatingIfNeeded: $0) },
            dxccName: nonEmpty(q.dxccName),
            continent: nonEmpty(q.continent),
            xqso: q.xqso ? true : nil)
    }

    /// `Qso` (read model) from a canonical network state. Without a payload (`qso == nil`) only the synchronisation fields.
    public static func toQso(_ s: QsoState) -> Qso {
        var q = Qso()
        if let w = s.qso {
            q.timestampUtc = w.timestampUtc?.date
            q.call = w.call ?? ""
            q.freqHz = w.freqHz // derives the band from the frequency
            if let name = w.band, let band = Band(javaName: name) {
                q.band = band
            }
            if let name = w.mode, let mode = Mode(rawValue: name) {
                q.mode = mode
            }
            q.rstSent = w.rstSent ?? ""
            q.rstRcvd = w.rstRcvd ?? ""
            q.exchangeSent = w.exchangeSent ?? ""
            q.exchangeRcvd = w.exchangeRcvd ?? ""
            q.serialSent = w.serialSent.map(Int.init)
            q.serialRcvd = w.serialRcvd.map(Int.init)
            q.operator = w.operator ?? ""
            q.comment = w.comment ?? ""
            q.dxccEntity = w.dxccEntity.map(Int.init)
            q.dxccName = w.dxccName ?? ""
            q.continent = w.continent ?? ""
            q.xqso = w.xqso == true
        }
        q.uuid = s.uuid ?? ""
        q.stationId = s.stationId ?? ""
        q.version = s.version
        q.updatedAtUtc = s.updatedAtUtc?.date
        q.deleted = s.deleted
        return q
    }

    /// Instant of the client command: `updatedAtUtc`, otherwise `timestampUtc`.
    static func clientTimestamp(_ q: Qso) -> JavaInstant? {
        (q.updatedAtUtc ?? q.timestampUtc).map(JavaInstant.init(date:))
    }

    public static func toInsertCommand(_ stationId: String?, _ q: Qso) -> QsoCommand {
        QsoCommand(stationId: stationId, uuid: nonEmpty(q.uuid), clientTimestampUtc: clientTimestamp(q),
                   qso: toWire(q))
    }

    public static func toDeleteCommand(_ stationId: String?, _ q: Qso) -> DeleteCommand {
        DeleteCommand(stationId: stationId, uuid: nonEmpty(q.uuid), clientTimestampUtc: clientTimestamp(q))
    }
}
