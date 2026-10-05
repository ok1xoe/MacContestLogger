/// Structural and referential validation of a contest definition. It does not verify the existence of
/// multiplier sets in the registry (that is done by `DefinitionEditing.check`);
/// here the internal consistency of the definition is checked.
///
/// Port of Java `contest/def/ContestValidator.java`. **The order of findings and their
/// texts are a contract** — the definition editor shows them in order and `DefinitionUpdater`
/// reports the first of them. The order is given by the order of checks (id sets are only queried).
public enum ContestValidator {

    public static func validate(_ def: ContestDefinition?) -> ValidationReport {
        var r = ValidationReport()
        guard let def else {
            r.error("definice je null")
            return r
        }
        if def.schemaVersion <= 0 {
            r.error("schemaVersion musí být kladné")
        }
        if isBlank(def.id) {
            r.error("chybí id závodu")
        }
        if def.metadata == nil || isBlank(def.metadata?.name) {
            r.warning("chybí metadata.name")
        }
        if let sessions = def.period?.sessions {
            // Java builds the text from `start` and `Integer minutes` (null → "").
            let text = (sessions.start ?? "") + "/" + (sessions.minutes.map { String($0) } ?? "")
            if Tour.parse(text) == nil {
                r.error("period.sessions: start musí být hhmm (UTC) a minutes aspoň \(Tour.minDuration)")
            }
        }
        if isEmpty(def.bands) {
            r.error("chybí bands")
        }
        if isEmpty(def.modes) {
            r.error("chybí modes")
        }

        let stationClassIds = stationClassIds(def)
        let sentIds = fieldIds(def.exchange?.sent)
        let recvIds = fieldIds(def.exchange?.received)

        validateExchange(def, &r, stationClassIds)
        validateScoring(def, &r)
        validateMultipliers(def, &r, recvIds, stationClassIds)
        validateCabrillo(def, &r, sentIds, recvIds)
        validateStationClasses(def, &r)
        return r
    }

    private static func validateExchange(_ def: ContestDefinition, _ r: inout ValidationReport,
                                         _ stationClassIds: Set<String>) {
        guard let exchange = def.exchange else {
            r.error("chybí exchange")
            return
        }
        if isEmpty(exchange.received) {
            r.error("exchange.received nesmí být prázdné")
        }
        for f in exchange.sent ?? [] {
            checkField(f, &r, stationClassIds, "sent")
        }
        for f in exchange.received ?? [] {
            checkField(f, &r, stationClassIds, "received")
        }
    }

    private static func checkField(_ field: ContestDefinition.ExchangeField?, _ r: inout ValidationReport,
                                   _ stationClassIds: Set<String>, _ role: String) {
        guard let f = field, let id = f.id, !JavaText.isBlank(id) else {
            r.error("exchange.\(role) obsahuje pole bez id")
            return
        }
        if f.type == nil {
            r.error("pole '\(id)' nemá type")
        }
        if let regex = f.validation?.regex {
            // A syntax error has text identical to Java `getMessage()`; constructs
            // that the adapter does not convert are reported in Czech (a deliberate divergence from Java v1.1.1).
            do {
                _ = try JavaRegex(regex)
            } catch {
                r.error("pole '\(id)' má neplatný regex: \(error.message)")
            }
        }
        if let workedClass = f.appliesWhen?.workedClass, !stationClassIds.contains(workedClass) {
            r.error("pole '\(id)' odkazuje na nedefinovanou stationClass '\(workedClass)'")
        }
    }

    private static func validateScoring(_ def: ContestDefinition, _ r: inout ValidationReport) {
        guard let scoring = def.scoring else {
            r.error("chybí scoring")
            return
        }
        if let qsoPoints = scoring.qsoPoints {
            if qsoPoints.mode == nil {
                r.error("scoring.qsoPoints.mode musí být FIRST_MATCH nebo SUM")
            }
        } else {
            r.error("chybí scoring.qsoPoints")
        }
        if isBlank(scoring.total) {
            r.error("chybí scoring.total (formule)")
        }
    }

    private static func validateMultipliers(_ def: ContestDefinition, _ r: inout ValidationReport,
                                            _ recvIds: Set<String>, _ stationClassIds: Set<String>) {
        var ids = Set<String>()
        for binding in def.multipliers ?? [] {
            guard let m = binding, let id = m.id, !JavaText.isBlank(id) else {
                r.error("multiplier bez id")
                continue
            }
            // Java `HashSet.add` == false: reported on the second and further occurrences,
            // before their own errors.
            if !ids.insert(id).inserted {
                r.error("duplicitní multiplier id '\(id)'")
            }
            if isBlank(m.set) {
                r.error("multiplier '\(id)' nemá set")
            }
            if m.scope == nil {
                r.error("multiplier '\(id)' nemá scope")
            }
            if let from = m.from, !JavaText.isBlank(from) {
                if !JavaChar.equalsIgnoreCase("callsign", from) && !recvIds.contains(from) {
                    r.error("multiplier '\(id)' from='\(from)' není 'callsign' ani id přijatého exchange pole")
                }
            } else {
                r.error("multiplier '\(id)' nemá from")
            }
            if let workedClass = m.appliesWhen?.workedClass, !stationClassIds.contains(workedClass) {
                r.error("multiplier '\(id)' odkazuje na nedefinovanou stationClass '\(workedClass)'")
            }
        }
    }

    private static func validateCabrillo(_ def: ContestDefinition, _ r: inout ValidationReport,
                                         _ sentIds: Set<String>, _ recvIds: Set<String>) {
        guard let cabrillo = def.cabrillo else {
            r.warning("chybí cabrillo (export nebude možný)")
            return
        }
        // `nil` element: Java `HashSet.contains(null)` is false and string concatenation prints „null".
        for id in cabrillo.sentOrder ?? [] where !(id.map(sentIds.contains) ?? false) {
            r.error("cabrillo.sentOrder odkazuje na neexistující sent pole '\(id ?? "null")'")
        }
        for id in cabrillo.receivedOrder ?? [] where !(id.map(recvIds.contains) ?? false) {
            r.error("cabrillo.receivedOrder odkazuje na neexistující received pole '\(id ?? "null")'")
        }
    }

    private static func validateStationClasses(_ def: ContestDefinition, _ r: inout ValidationReport) {
        for sc in def.stationClasses ?? [] where isBlank(sc?.id) {
            r.error("stationClass bez id")
        }
    }

    /// Station class ids; `nil` is not added, `""` is (baseline 7.4).
    private static func stationClassIds(_ def: ContestDefinition) -> Set<String> {
        Set((def.stationClasses ?? []).compactMap { $0?.id })
    }

    /// Exchange field ids; `nil` is not added, `""` is (baseline 7.4).
    private static func fieldIds(_ fields: [ContestDefinition.ExchangeField?]?) -> Set<String> {
        Set((fields ?? []).compactMap { $0?.id })
    }

    private static func isEmpty<T>(_ list: [T]?) -> Bool {
        list?.isEmpty ?? true
    }

    /// Java `s == null || s.isBlank()`.
    private static func isBlank(_ text: String?) -> Bool {
        guard let text else { return true }
        return JavaText.isBlank(text)
    }
}
