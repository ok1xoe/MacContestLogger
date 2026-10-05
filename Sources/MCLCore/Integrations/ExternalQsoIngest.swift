import Foundation

/// What the ingest of an external QSO reads from the application state (`AppState`, v1.1.1: `qsos`, `contest`,
/// `runMode`, `logbook.nextSerial()`, `config.station.call`). A snapshot taken on the main actor, so the decision
/// itself is a pure function — the listener threads never touch the log.
public struct IngestSnapshot: Sendable {
    /// The log rows of the active contest (`AppState.qsos`) — the dedup runs over them.
    public var qsos: [Qso]
    /// `contest.isActive`.
    public var isContestActive: Bool
    /// `contest.exchangeFields(call)`; empty outside a contest. May throw as the Kotlin call does.
    public var exchangeFields: @Sendable (String) throws(ExpressionError) -> [ContestDefinition.ExchangeField]
    /// `logbook.nextSerial()` (1 + the QSOs logged in the active contest) — not the reserved serial.
    public var nextSerial: Int
    /// `AppState.runMode`.
    public var runMode: RunMode
    /// `config.station.call` — the own-echo test of N1MM.
    public var ownCall: String

    public init(qsos: [Qso], isContestActive: Bool,
                exchangeFields: @escaping @Sendable (String) throws(ExpressionError) -> [ContestDefinition.ExchangeField],
                nextSerial: Int, runMode: RunMode, ownCall: String) {
        self.qsos = qsos
        self.isContestActive = isContestActive
        self.exchangeFields = exchangeFields
        self.nextSerial = nextSerial
        self.runMode = runMode
        self.ownCall = ownCall
    }
}

/// A QSO ready to be logged: hand `qso` to the logging pipeline as an imported QSO (no Club Log, plugin,
/// broadcast, WSJT-X), then count it into the contest session with `call`/`bandAdif`/`modeName`/`receivedRaw`
/// (`contest.log`) and show `status(counted:)`; when `contest.log` throws show `ExternalQsoIngest.failureStatus`.
public struct IngestedQso: Sendable {
    /// The QSO as `log(qso)` receives it: `imported`, run mode, serial sent, flat exchange (ADIF: serial received).
    public let qso: Qso
    public let call: String
    /// ADIF band of the QSO, `""` without one.
    public let bandAdif: String
    /// Mode name for the contest session (`(qso.mode ?: default).name`) — not necessarily `qso.mode`.
    public let modeName: String
    public let receivedRaw: JavaLinkedMap<String>
    /// `"N1MM"` or the ADIF source label.
    public let source: String

    /// The status once the QSO is logged: imported, or not counted (the contest does not have the mode).
    public func status(counted: Bool) -> EntryStatus {
        if source == ExternalQsoIngest.n1mmSource {
            return counted
                ? .tr("N1MM: importováno QSO %s", .string(call))
                : .tr("N1MM: QSO %s v módu %s — závod ho nemá, do skóre se nepočítá", .string(call), .string(modeName))
        }
        return counted
            ? .tr("%s: importováno QSO %s", .string(source), .string(call))
            : .tr("%s: QSO %s v módu %s — závod ho nemá, do skóre se nepočítá", .string(source), .string(call),
                  .string(modeName))
    }
}

public enum IngestOutcome: Sendable {
    /// Nothing happens and nothing is shown (not a contact, own echo, duplicate).
    case drop
    /// Only a status line.
    case status(EntryStatus)
    /// Log the QSO.
    case log(IngestedQso)
}

/// The shared path of the externally received QSOs — N1MM `contactinfo` over UDP, and a logged ADIF record from
/// WSJT-X or a bare ADIF datagram (`AppState.onN1mmContact` / `importAdifRecord`, v1.1.1) — as one pure function.
///
/// The differences stay as in Kotlin: N1MM drops its own echo and defaults the mode name to SSB, ADIF has no echo
/// test, defaults to FT8 and takes the serial received from the `nr` field. The dedup (120 s) runs over the
/// snapshot of the log.
public enum ExternalQsoIngest {

    public static let n1mmSource = "N1MM"
    /// Window of `WsjtxDedup` (seconds).
    public static let dedupWindowSeconds: Int64 = 120

    public static func n1mm(_ xml: String, snapshot: IngestSnapshot) -> IngestOutcome {
        guard let parsed = N1mmContactParser.parse(xml) else { return .drop }
        if isOwnEcho(app: parsed.app, stationName: parsed.stationName, ownCall: snapshot.ownCall) { return .drop }
        var qso: Qso = parsed.qso
        fillBand(&qso)
        if WsjtxDedup.isDuplicate(snapshot.qsos, qso, windowSeconds: dedupWindowSeconds) { return .drop }
        if !snapshot.isContestActive {
            return .status(.tr("N1MM: přijato QSO %s, ale není aktivní závod — neuloženo", .string(qso.call)))
        }
        let modeName: String = (qso.mode ?? .ssb).rawValue
        do {
            let fields = try snapshot.exchangeFields(qso.call)
            let received: JavaLinkedMap<String> = WsjtxExchangeMapper.toReceivedRaw(fields, dictionary(parsed.fields))
            qso.runMode = snapshot.runMode
            qso.serialSent = snapshot.nextSerial
            qso.exchangeRcvd = flatExchange(fields, received) ?? ""
            qso.imported = true
            return .log(IngestedQso(qso: qso, call: qso.call, bandAdif: qso.band?.adif ?? "", modeName: modeName,
                                    receivedRaw: received, source: n1mmSource))
        } catch {
            return .status(failureStatus(source: n1mmSource, message: error.ingestMessage))
        }
    }

    public static func adif(_ record: String, source: String, snapshot: IngestSnapshot) -> IngestOutcome {
        do {
            guard let imported = try WsjtxImportMapper.map(record) else {
                return .status(.tr("%s: přijatý ADIF bez volačky, ignoruji", .string(source)))
            }
            var qso: Qso = imported.qso
            fillBand(&qso)
            if WsjtxDedup.isDuplicate(snapshot.qsos, qso, windowSeconds: dedupWindowSeconds) { return .drop }
            if !snapshot.isContestActive {
                return .status(.tr("%s: přijato QSO %s, ale není aktivní závod — neuloženo", .string(source),
                                   .string(qso.call)))
            }
            let modeName: String = (qso.mode ?? .ft8).rawValue
            let fields = try snapshot.exchangeFields(qso.call)
            let received: JavaLinkedMap<String> = WsjtxExchangeMapper.toReceivedRaw(fields, imported.adifFields)
            qso.runMode = snapshot.runMode
            qso.serialSent = snapshot.nextSerial
            qso.serialRcvd = received["nr"].flatMap { KotlinNumber.toIntOrNull(KotlinText.trim($0)) }.map { Int($0) }
            qso.exchangeRcvd = flatExchange(fields, received) ?? ""
            qso.imported = true
            return .log(IngestedQso(qso: qso, call: qso.call, bandAdif: qso.band?.adif ?? "", modeName: modeName,
                                    receivedRaw: received, source: source))
        } catch {
            return .status(failureStatus(source: source, message: error.ingestMessage))
        }
    }

    /// `"<source>: import selhal (<message>)"` — Kotlin `"$sourceLabel: import selhal (${it.message})"`, not translated.
    public static func failureStatus(source: String, message: String?) -> EntryStatus {
        .verbatim(source + ": import selhal (" + (message ?? "null") + ")")
    }

    /// `app == "MacContestLogger" || stationName == config.station.call` (exact, case-sensitive).
    static func isOwnEcho(app: String?, stationName: String?, ownCall: String) -> Bool {
        if let app, JavaText.equals(app, BroadcastXml.app) { return true }
        guard let stationName else { return false }
        return JavaText.equals(stationName, ownCall)
    }

    /// `Band.fromFrequencyHz(qso.freqHz).ifPresent { qso.band = it }` when the QSO has no band.
    private static func fillBand(_ qso: inout Qso) {
        if qso.band == nil, let band = Band.from(frequencyHz: qso.freqHz) {
            qso.band = band
        }
    }

    /// The received exchange as the entry window stores it: the values of the active fields in the definition order,
    /// separated by a space (`AppState.flatExchange`).
    static func flatExchange(_ fields: [ContestDefinition.ExchangeField], _ received: JavaLinkedMap<String>) -> String? {
        var parts: [String] = []
        for field in fields {
            guard let value = received[field.id] else { continue }
            let trimmed: String = KotlinText.trim(value)
            if !KotlinText.isBlank(trimmed) {
                parts.append(trimmed)
            }
        }
        let joined: String = parts.joined(separator: " ")
        return KotlinText.isBlank(joined) ? nil : joined
    }

    private static func dictionary(_ map: JavaLinkedMap<String>) -> [String: String] {
        var out: [String: String] = [:]
        for entry in map.entries {
            if let key = entry.key, let value = entry.value {
                out[key] = value
            }
        }
        return out
    }
}

private extension Error {
    /// Message of the errors the ingest can see: an `ExpressionError` carries its Java message.
    var ingestMessage: String {
        (self as? ExpressionError)?.message ?? JavaThrowables.message(self)
    }
}
