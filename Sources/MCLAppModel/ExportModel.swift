import Foundation
import MCLCore
import Observation

/// Cabrillo and ADIF export of `ImportExportModel` (Kotlin `AppState.exportAdif` / `exportCabrillo`, `KA:4007-4106`).
///
/// The formatting is the core's (`AdifWriter`, `CabrilloExporter`); the model only gathers the input as Kotlin
/// does and runs the work off the main thread: the log is read on the database handle's queue, the recount and the
/// file write on `BlockingQueue`.
///
/// Kotlin differences (technique):
/// - a failed ADIF write (Kotlin: uncaught → crash) and a failed log read show the error in the status line;
/// - Cabrillo warnings go to the shared `MessagesModel` (the Info window's buffer); the status line
///   shows their count (the Kotlin text).
extension ImportExportModel {

    /// Kotlin `appVersion()`: the bundle version, otherwise „vývojová verze".
    public var versionText: String {
        appVersion ?? language.tr("vývojová verze")
    }

    /// Kotlin `cabrilloFileName()`.
    public var cabrilloFileName: String {
        ExportNames.cabrilloFileName(stationCall: config.config.station.call, definition: contest.definition)
    }

    /// Kotlin `exportAdif(path)`: the active contest's QSOs (`logbook.findAll()`), the station in the header, the
    /// contest's Cabrillo name as `CONTEST_ID`; UTF-8.
    ///
    /// With `range` (Export → ADIF by date) only the QSOs of those UTC days are written; none in it = no file and a
    /// status line saying so.
    ///
    /// `station` (N1MM „Export ADIF by multi-user station name"): only that station's QSOs (`""` = all).
    ///
    /// `allContests` (N1MM „ADIF by date from ALL contests"): every contest of the database and free logging, without
    /// `CONTEST_ID` (the QSOs belong to different contests).
    ///
    /// The file carries N1MM's own fields (`PFX`, `APP_N1MM_EXCHANGE1`, `_POINTS`, `_ISRUNQSO`, and `_MULT1`–`3` of
    /// the open contest's replay).
    public func exportAdif(to file: URL, range: AdifDateRange? = nil, allContests: Bool = false,
                           station networkStation: String = "") async {
        let contestId: String? = allContests ? nil : contest.definition?.cabrillo?.contestName
        let station: Station = config.config.station.toStation()
        let session: ContestSession? = allContests ? nil : contest.runtime.freshSession()
        let fieldsSession: ContestSession? = allContests ? nil : contest.runtime.freshSession()
        let definition: ContestDefinition? = allContests ? nil : contest.definition
        do {
            var qsos: [Qso] = allContests ? try await readAllContests() : try await readLog()
            qsos = AdifRangeModel.byStation(qsos, networkStation)
            if let range {
                qsos = range.filter(qsos)
                if qsos.isEmpty {
                    status.show("Export ADIF: v zadaném období nejsou žádná QSO")
                    return
                }
            }
            let exported: [Qso] = qsos
            try await BlockingQueue.run {
                var writer = AdifWriter(contestId: contestId)
                writer.n1mmFields = true
                if let session {
                    writer.multipliers = Self.newMultipliers(session, exported)
                }
                writer.extraFields = AdifExtraFields.compute(definition, session: fieldsSession, qsos: exported)
                try writer.writeToFile(exported, station: station, to: file)
            }
            if range != nil {
                status.show("Exportováno do %s (%s QSO)", .string(file.path), .int(exported.count))
                return
            }
            status.show("Exportováno do %s", .string(file.path))
        } catch {
            status.showVerbatim(ErrorText.message(error))
        }
    }

    /// Kotlin `exportCabrillo(path)`: Cabrillo 3.0 of the active contest with CLAIMED-SCORE recounted from zero over
    /// the whole log (`contest.freshScore(qsos)`), the contest's setup and QTCs; US-ASCII.
    @discardableResult
    public func exportCabrillo(to file: URL) async -> Bool {
        guard let definition = contest.definition, let replaySession = contest.runtime.freshSession(),
              let fieldsSession = contest.runtime.freshSession() else {
            status.show("Cabrillo: není aktivní závod")
            return false
        }
        let request = CabrilloRequest(
            definition: definition, station: config.config.station, setup: contest.activeSetup,
            qtcs: contest.qtcs, createdBy: "MacContestLogger " + versionText)
        let qsos: [Qso]
        do {
            qsos = try await readLog()
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return false
        }
        let built: Result<CabrilloExporter.Result, CabrilloFailure> = (try? await BlockingQueue.run {
            Self.buildCabrillo(request, qsos: qsos, replaySession: replaySession, fieldsSession: fieldsSession)
        }) ?? .failure(CabrilloFailure(message: language.tr("zrušeno")))
        let result: CabrilloExporter.Result
        switch built {
        case .failure(let failure):
            status.showVerbatim("Cabrillo: " + failure.message)
            return false
        case .success(let value):
            result = value
        }
        let text: String = result.text
        do {
            try await BlockingQueue.run {
                try Self.writeAscii(text, to: file)
            }
        } catch {
            status.show("Cabrillo: zápis selhal (%s)", .string(ErrorText.message(error)))
            return false
        }
        messages.add(result.warnings.map { "Cabrillo: " + $0 }, at: now())
        let summary: String = "Cabrillo: " + String(result.qsoCount) + " QSO → " + file.lastPathComponent
        if result.warnings.isEmpty {
            status.showVerbatim(summary)
        } else {
            status.showJoined([.verbatim(summary), ContestMessage("%s upozornění (viz Info okno)",
                                                                   .int(result.warnings.count))],
                              separator: " · ")
        }
        return true
    }

    // MARK: - work off the main thread

    /// Every contest's live QSOs of the database (and free logging), by time.
    func readAllContests() async throws -> [Qso] {
        await contest.settleActivations()
        return try await database.handle.run { access in
            try access.service.findAllIncludingDeleted().filter { !$0.deleted }
        }
    }

    /// The multipliers each QSO counted as new in a replay of the log (by `Qso.uuid`, binding order) — N1MM's
    /// `APP_N1MM_MULT1`–`3`.
    nonisolated static func newMultipliers(_ session: ContestSession, _ qsos: [Qso]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        _ = ContestReplay.replay(session, qsos) { qso, result in
            let keys: [String] = result.multipliers.compactMap { mult in
                guard mult.countsAsMultiplier && mult.isNew, let key = mult.key, !key.isEmpty else { return nil }
                return key
            }
            if !keys.isEmpty && !qso.uuid.isEmpty {
                out[qso.uuid] = keys
            }
        }
        return out
    }

    /// What the Cabrillo export reads on the main thread (Kotlin reads it synchronously).
    struct CabrilloRequest: Sendable {
        let definition: ContestDefinition
        let station: StationConfig
        let setup: ContestSetup?
        let qtcs: [QtcRecord]
        let createdBy: String
    }

    /// Kotlin `runCatching { … }.getOrElse { statusMessage = "Cabrillo: ${it.message}" }`.
    struct CabrilloFailure: Error, Sendable, CustomStringConvertible {
        let message: String

        var description: String {
            message
        }
    }

    /// The Kotlin builder chain: category, sent exchange, operators, soapbox, the recounted score, QTCs, created-by.
    nonisolated static func buildCabrillo(_ request: CabrilloRequest, qsos: [Qso], replaySession: ContestSession,
                                          fieldsSession: ContestSession)
        -> Result<CabrilloExporter.Result, CabrilloFailure> {
        do {
            let claimed: Int64 = try ContestReplay.replay(replaySession, qsos).session.score().total
            var input = CabrilloExporter.Input(definition: request.definition, station: request.station,
                                               qsos: qsos) { call in
                try fieldsSession.activeReceivedFields(call: call)
            }
            input.category = linked(request.setup?.category)
            input.sentExchange = linked(request.setup?.sentExchange)
            input.operators = request.setup?.operators ?? ""
            input.soapbox = request.setup?.soapbox ?? ""
            input.claimedScore = claimed
            input.qtcs = request.qtcs
            input.createdBy = request.createdBy
            return .success(try CabrilloExporter.export(input))
        } catch let error as CabrilloExportError {
            switch error {
            case .illegalArgument(let message):
                return .failure(CabrilloFailure(message: message))
            }
        } catch {
            return .failure(CabrilloFailure(message: ErrorText.message(error)))
        }
    }

    /// Kotlin `HashMap` → the exporter's map (the exporter only looks keys up, the order does not matter).
    private nonisolated static func linked(_ map: [String: String]?) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        for key in (map ?? [:]).keys.sorted() {
            out.put(key, map?[key])
        }
        return out
    }

    /// `Files.writeString(path, text, US_ASCII)`; the exporter's text is pure ASCII already.
    nonisolated static func writeAscii(_ text: String, to file: URL) throws {
        guard let data = text.data(using: .ascii, allowLossyConversion: false) else {
            // Java `UnmappableCharacterException.getMessage()` of `Files.writeString(…, US_ASCII)`.
            throw CabrilloFailure(message: "Input length = 1")
        }
        try data.write(to: file)
    }
}
