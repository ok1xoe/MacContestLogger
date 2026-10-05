import Foundation

/// Building the QSO(s) to log from the entry form. Port of the assembly part of `logQso`
/// (`ui/EntryPanel.kt:468-567`); the side effects (logbook, contest session, status, wipe) belong to the
/// caller. Kotlin `null` of a `Qso` text field is `""` here (the `Qso` convention).
///
/// The paper-log time (post-contest entry) is only the `at` parameter — its dialog is in the app layer.
public enum QsoAssembly {

    /// Result of the operating-rules check before a contest QSO is written.
    public enum OperatingGate: Equatable, Sendable {
        case proceed
        /// Write it, status `"Pozor: <violation>"`.
        case warn(String)
        /// Do not write it, status `NEZAPSÁNO — <violation> (Ctrl+Alt+Enter zapíše i tak)`.
        case block(String)
    }

    /// One contest QSO. `fields` = the active received fields for the callsign
    /// (`contest.exchangeFields(call)`), `rstFieldIds` = their report fields (`EntryForm.rstFieldIds`),
    /// `sentFlat` = `SentExchange.flat` for this copy, `note` = the comment (`comment ?: pendingNote`).
    ///
    /// - `exchangeRcvd`: non-blank (Kotlin `isNotBlank`) values of `fields` in field order, **not trimmed**,
    ///   joined with a space; the report stays inside (the replay splits it by position).
    /// - `rstSent`: the form's sent report, blank → empty, otherwise as is.
    /// - `rstRcvd`: the first report field, Kotlin-trimmed, blank → empty.
    /// - `serialRcvd`: `contestExchange["nr"]`, Kotlin `trim().toIntOrNull()` — read even when `nr`
    ///   is not an active field.
    public static func contest(form: EntryForm, fields: [ContestDefinition.ExchangeField], rstFieldIds: [String?],
                               serial: Int, runMode: RunMode, sentFlat: String?, note: String?, at: Date?) -> Qso {
        var qso = base(form, runMode: runMode)
        var received: [String] = []
        for field in fields {
            guard let value = form.contestExchange[field.id], !KotlinText.isBlank(value) else { continue }
            received.append(value)
        }
        qso.exchangeRcvd = received.joined(separator: " ")
        qso.rstSent = blankToEmpty(form.rstSent)
        if let first = rstFieldIds.first, let report = form.contestExchange[first] {
            qso.rstRcvd = blankToEmpty(KotlinText.trim(report))
        }
        qso.serialSent = serial
        qso.serialRcvd = form.contestExchange["nr"].flatMap(intOrNil)
        qso.exchangeSent = sentFlat ?? ""
        qso.comment = note ?? ""
        qso.timestampUtc = at
        return qso
    }

    /// The QSO copies of one contest entry: with a county line in a contest that uses the rover QTH,
    /// one copy per county (N1MM COUNTYLINE), otherwise one copy with `roverQthForDupe`. All copies carry
    /// the same serial number (the one that was sent); `sentFlat` is asked for every copy's QTH.
    public static func contestQsos(form: EntryForm, fields: [ContestDefinition.ExchangeField],
                                   rstFieldIds: [String?], serial: Int, runMode: RunMode, countyLine: [String],
                                   usesRoverQth: Bool, roverQth: String, note: String?, at: Date?,
                                   sentFlat: (String?) -> String?) -> [(qth: String?, qso: Qso)] {
        let qths = loggingQths(countyLine: countyLine, usesRoverQth: usesRoverQth, roverQth: roverQth)
        return qths.map { qth in
            let qso = contest(form: form, fields: fields, rstFieldIds: rstFieldIds, serial: serial, runMode: runMode,
                              sentFlat: sentFlat(qth), note: note, at: at)
            return (qth: qth, qso: qso)
        }
    }

    /// My QTH for each copy (`EntryPanel.kt:512-516`): the county line when non-empty and the contest
    /// uses the rover QTH, otherwise `[roverQthForDupe]`.
    public static func loggingQths(countyLine: [String], usesRoverQth: Bool, roverQth: String) -> [String?] {
        if !countyLine.isEmpty && usesRoverQth {
            return countyLine
        }
        return [roverQthForDupe(roverQth: roverQth, usesRoverQth: usesRoverQth)]
    }

    /// `AppState.roverQthForDupe` (`AppState.kt:3822-3823`): the Kotlin-trimmed rover QTH, blank → `nil`,
    /// only when the contest uses the rover QTH.
    public static func roverQthForDupe(roverQth: String, usesRoverQth: Bool) -> String? {
        let trimmed = KotlinText.trim(roverQth)
        guard usesRoverQth, !KotlinText.isBlank(trimmed) else {
            return nil
        }
        return trimmed
    }

    /// A QSO outside a contest (`EntryPanel.kt:551-563`): reports and the generic exchange as is
    /// (blank → empty), `serialRcvd` = Kotlin `exch.trim().toIntOrNull()`.
    public static func free(form: EntryForm, serial: Int, runMode: RunMode, note: String?, at: Date?) -> Qso {
        var qso = base(form, runMode: runMode)
        qso.rstSent = blankToEmpty(form.rstSent)
        qso.rstRcvd = blankToEmpty(form.rstRcvd)
        qso.exchangeRcvd = blankToEmpty(form.exch)
        qso.serialSent = serial
        qso.serialRcvd = intOrNil(form.exch)
        qso.comment = note ?? ""
        qso.timestampUtc = at
        return qso
    }

    /// The operating-rules check of a contest entry (`EntryPanel.kt:495-506` with `operatingViolation`,
    /// `AppState.kt:2722-2733`): skipped for a forced write and in post-contest entry; with enforcement
    /// `OFF` the violation is not even computed; otherwise `BLOCK` blocks and anything else warns.
    ///
    /// `violation` = `OperatingGuard.check(stats of this station, band-change rules of the category,
    /// band, now, operatingStationType(…), newMultiplier)`. Off the network the station type is `NONE`
    /// (no MULT rule), but the definition's band-change rules still apply unless enforcement is `OFF`.
    public static func operatingGate(force: Bool, postContest: Bool, enforcement: OperatingGuard.Enforcement,
                                     violation: () -> String?) -> OperatingGate {
        if force || postContest || enforcement == .off {
            return .proceed
        }
        guard let found = violation() else {
            return .proceed
        }
        return enforcement == .block ? .block(found) : .warn(found)
    }

    /// The station type for `OperatingGuard.check`: the configured one only when the station is in a
    /// network (`stationNet != null || config.cluster.isEnabled`), otherwise `NONE`.
    public static func operatingStationType(networked: Bool,
                                            configured: OperatingGuard.StationType) -> OperatingGuard.StationType {
        networked ? configured : .none
    }

    // MARK: - helpers

    private static func base(_ form: EntryForm, runMode: RunMode) -> Qso {
        var qso = Qso()
        qso.call = form.call
        qso.freqHz = Int(form.freqHz)
        qso.mode = form.mode
        qso.runMode = runMode
        return qso
    }

    /// Kotlin `ifBlank { null }` mapped onto the `Qso` empty-string convention.
    private static func blankToEmpty(_ text: String) -> String {
        KotlinText.isBlank(text) ? "" : text
    }

    /// Kotlin `trim().toIntOrNull()`.
    private static func intOrNil(_ text: String) -> Int? {
        KotlinNumber.toIntOrNull(KotlinText.trim(text)).map { Int($0) }
    }
}
