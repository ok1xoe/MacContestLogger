import Foundation
import MCLCore
import Observation

/// Import, merge, the exports and printing of the log (Kotlin `AppState`, `AS:4007-4180`).
///
/// The formatting, detection and preparation are the core's (`LogImporter`, `ExportJobs`, `LogExports`,
/// `PrintLayout`, `AdifWriter`, `CabrilloExporter`); this model gathers the input as Kotlin does — a snapshot of the
/// main-thread state (definition, a fresh session for the exchange fields, setup, station) — and runs the work off
/// the main thread: files on `BlockingQueue`, the log on the database handle's serial queue. An import or a merge is
/// one job of `LogbookModel.importBatch` (the QSOs are inserted and the log re-read in it), followed by the full
/// refresh of the log state and the recount request.
///
/// Kotlin crashes that are not reproduced (the uncaught exception becomes a status text, nothing is inserted or
/// written — the precedent of the ADIF write failure):
/// - A reader exception on import → `tr("Nelze přečíst soubor: %s")` like an unreadable file;
/// - an error of the station-class expression while converting the exchange on import (`AS:4164-4168`) or in the
///   EDI export (`AS:4068`), and of the recount for the summary of the other exports (`AS:4045`) → the error's
///   message (Java `getMessage()`), verbatim.
///
/// On the merge path Kotlin catches everything that happens while reading the source (`AS:4118-4135`), including the
/// exchange conversion: `tr("Sloučení: nelze přečíst %s (%s)")` with the Java message.
@Observable @MainActor
public final class ImportExportModel {

    /// What the print dialog prints (Kotlin `printLog`: the title and `LogExports.text(title, logbook.findAll())`).
    public struct PrintJob: Equatable, Sendable {
        public let title: String
        public let text: String

        public init(title: String, text: String) {
            self.title = title
            self.text = text
        }
    }

    /// How the print dialog ended (Kotlin `LogPrinter.print` → `true` / `false` / an exception).
    public enum PrintOutcome: Equatable, Sendable {
        case sent
        case cancelled
        /// The exception's message (`nil` = Java `null`).
        case failed(String?)
    }

    /// A request for the app layer that a model produced asynchronously (the print job is read off the main thread
    /// after the menu action returned); the app takes it with `MenuActions.takeModelRequest`.
    public private(set) var pendingRequest: MenuActions.Request?

    @ObservationIgnored let contest: ContestModel
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let database: DatabaseModel
    @ObservationIgnored let logbook: LogbookModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let language: LanguageModel
    @ObservationIgnored let messages: MessagesModel
    @ObservationIgnored let appVersion: String?
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var running: Task<Void, Never>?

    init(contest: ContestModel, config: ConfigModel, database: DatabaseModel, logbook: LogbookModel,
         status: StatusModel, language: LanguageModel, messages: MessagesModel, appVersion: String?,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.contest = contest
        self.config = config
        self.database = database
        self.logbook = logbook
        self.status = status
        self.language = language
        self.messages = messages
        self.appVersion = appVersion
        self.now = now
    }

    // MARK: - running

    /// Waits for the work started through `start` (tests, quit, a database switch).
    func settle() async {
        while let task = running {
            await task.value
            if task == running {
                return
            }
        }
    }

    /// Starts an import, merge, export or print preparation without waiting (a panel's completion); the jobs run one
    /// after another.
    public func start(_ body: @escaping @MainActor (ImportExportModel) async -> Void) {
        let previous: Task<Void, Never>? = running
        running = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await body(self)
        }
    }

    /// The pending request, cleared.
    func takePendingRequest() -> MenuActions.Request? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    /// The active contest's QSOs (Kotlin `logbook.findAll()`) on the handle's queue.
    func readLog() async throws -> [Qso] {
        try await database.handle.run { access in
            try access.service.findAll()
        }
    }

    /// `contest.definition()?.metadata()?.name() ?: tr("Deník")`.
    private var logName: String {
        contest.definition?.metadata?.name ?? language.tr(IoTexts.defaultLogName)
    }

    // MARK: - import (`AS:4154-4180`)

    /// Kotlin `importQsos(path)`: the file is read (`Files.readString`) and parsed off the main thread — a failure of
    /// either is `tr("Nelze přečíst soubor: %s", fileName)` with nothing inserted; then, in one job of the
    /// logbook, the exchange is converted with the active definition (fields of a fresh session), countries are
    /// filled, every QSO is logged into the log's active contest and the log is re-read; the recount is requested and
    /// the status is `tr("Importováno %s QSO (%s) z %s")` with the number of QSOs read. Import works outside a
    /// contest too.
    public func importQsos(from file: URL) async {
        let fileName: String = file.lastPathComponent
        let parsed: (format: LogImporter.Format, qsos: [Qso])
        do {
            parsed = try await BlockingQueue.run {
                let content: String = try LogImporter.readText(file)
                let format: LogImporter.Format = LogImporter.importFormat(fileName: fileName, content: content)
                return (format, try LogImporter.read(format, content: content))
            }
        } catch {
            status.show(IoTexts.unreadable(file: fileName))
            return
        }
        await contest.settleActivations()
        let source = ExchangeSource(contest)
        let active: String = logbook.activeContestId
        let qsos: [Qso] = parsed.qsos
        let outcome: LogbookModel.BatchOutcome<Void> = await logbook.importBatch(contestId: active) { _ in
            let prepared: [Qso] = try LogImporter.prepareImport(qsos, definition: source.definition,
                                                                fields: source.fields, dxcc: source.dxcc)
            return LogbookModel.BatchPlan(qsos: prepared, value: ())
        }
        switch outcome {
        case .refused(let error):
            if error is LogbookModel.ContestChanged {
                status.show(Self.contestChanged(file: fileName))
            } else {
                status.showVerbatim(ErrorText.message(error))
            }
        case .stored(_, _, let error):
            contest.requestRescore()
            if let error {
                status.showVerbatim(ErrorText.message(error))
            } else {
                status.show(IoTexts.imported(count: qsos.count, format: parsed.format, file: fileName))
            }
        }
    }

    /// Swift only: the log's active contest changed while the import or merge of `file` waited behind other log
    /// work; nothing was inserted (Kotlin runs it synchronously).
    static func contestChanged(file: String) -> ContestMessage {
        ContestMessage("Závod se mezitím změnil — z %s se nic nevložilo", .string(file))
    }

    // MARK: - merge (`AS:4115-4152`)

    /// The source of a merge could not be read: the Kotlin `runCatching` around the read.
    private struct SourceUnreadable: Error {
        let error: any Error
    }

    /// Where the merged QSOs come from.
    private enum MergeSource: Sendable {
        /// Read before the job (a file, or a foreign database from its temporary copy).
        case read([Qso])
        /// The database open now: read through its own handle inside the job (no second connection).
        case openDatabase
    }

    /// Kotlin `mergeLog(path)` (N1MM Merge logs): a MacContestLogger database (`.sqlite`/`.db`), ADIF or Cabrillo.
    ///
    /// - A database is read from a temporary copy (the source is never modified) and gives the QSOs of the
    ///   log's active contest when it has any, otherwise all; the database open now is read through its own handle.
    /// - ADIF/Cabrillo by the merge rule (extension or `<eor>`, not `<call`), the exchange converted with the active
    ///   definition.
    /// - Any failure while reading the source: `tr("Sloučení: nelze přečíst %s (%s)", fileName, message)`.
    ///
    /// Then one job of the logbook: the log is read (`existing`, inside the job), `LogMerger` picks the new QSOs,
    /// each gets `id = nil`, the active contest, `isImported = true` and missing countries, and is logged; status
    /// `tr("Sloučeno z %s: přidáno %s QSO, přeskočeno %s duplicit")`, the recount is requested.
    public func merge(from file: URL) async {
        let fileName: String = file.lastPathComponent
        await contest.settleActivations()
        let active: String? = logbook.activeContestId.isEmpty ? nil : logbook.activeContestId
        let source = ExchangeSource(contest)
        let openUrl: URL = database.handle.url
        let read: MergeSource
        do {
            read = try await BlockingQueue.run {
                try Self.readMergeSource(file, fileName: fileName, active: active, openUrl: openUrl, source: source)
            }
        } catch {
            status.show(IoTexts.mergeUnreadable(file: fileName, message: JavaThrowables.describe(error).message))
            return
        }
        let dxcc: (any DxccLookup)? = source.dxcc
        let outcome: LogbookModel.BatchOutcome<Int> = await logbook.importBatch(contestId: active ?? "") { access in
            let incoming: [Qso]
            switch read {
            case .read(let qsos):
                incoming = qsos
            case .openDatabase:
                do {
                    incoming = LogImporter.databaseSource(try access.repository.findAll(), activeContestId: active)
                } catch {
                    throw SourceUnreadable(error: error)
                }
            }
            let existing: [Qso] = try access.service.findAll()
            let merged = LogImporter.prepareMerge(existing: existing, incoming: incoming, activeContestId: active,
                                                  dxcc: dxcc)
            return LogbookModel.BatchPlan(qsos: merged.toAdd, value: merged.duplicates)
        }
        switch outcome {
        case .refused(let error):
            if error is LogbookModel.ContestChanged {
                status.show(Self.contestChanged(file: fileName))
            } else if let unreadable = error as? SourceUnreadable {
                let message: String? = JavaThrowables.describe(unreadable.error).message
                status.show(IoTexts.mergeUnreadable(file: fileName, message: message))
            } else {
                status.showVerbatim(ErrorText.message(error))
            }
        case .stored(let inserted, let duplicates, let error):
            contest.requestRescore()
            if let error {
                status.showVerbatim(ErrorText.message(error))
            } else {
                status.show(IoTexts.merged(file: fileName, added: inserted, skipped: duplicates))
            }
        }
    }

    private nonisolated static func readMergeSource(_ file: URL, fileName: String, active: String?, openUrl: URL,
                                                    source: ExchangeSource) throws -> MergeSource {
        if LogImporter.isDatabase(fileName: fileName) {
            if FileIdentity.same(file, openUrl) {
                return .openDatabase
            }
            return .read(try LogImporter.readDatabase(at: file, activeContestId: active))
        }
        let content: String = try LogImporter.readText(file)
        let format: LogImporter.Format = LogImporter.mergeFormat(fileName: fileName, content: content)
        let qsos: [Qso] = try LogImporter.read(format, content: content)
        return .read(try LogImporter.applyExchange(qsos, definition: source.definition, fields: source.fields))
    }

    // MARK: - EDI (`AS:4055-4074`)

    /// Kotlin `exportEdi(dir)`: one REG1TEST file per band into `directory` (ISO-8859-1; a band whose text has a
    /// character outside Latin-1 is left out silently, like a file that cannot be written). Checks in Kotlin order:
    /// no active contest (also checked by the menu before the directory panel), the 6-character locator, an
    /// empty log. The exchange fields come from a fresh session of the active contest. Status
    /// `tr("EDI: zapsáno %s do %s")`.
    public func exportEdi(to directory: URL) async {
        guard let definition = contest.definition else {
            status.show(IoTexts.ediNoContest)
            return
        }
        let station: StationConfig = config.config.station
        let setup: ContestSetup? = contest.activeSetup
        let source = ExchangeSource(contest)
        let qsos: [Qso]
        do {
            qsos = try await readLog()
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return
        }
        let written: Result<[String], ContestMessage>
        do {
            written = try await BlockingQueue.run {
                let built = try ExportJobs.edi(definition: definition, station: station, setup: setup, qsos: qsos,
                                               fields: source.fields)
                return built.map { files in ExportJobs.write(files, to: directory) }
            }
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return
        }
        switch written {
        case .failure(let message):
            status.show(message)
        case .success(let names):
            status.show(IoTexts.ediWritten(names: names, dir: directory.path))
        }
    }

    // MARK: - CSV, text, summary (`AS:4038-4052`)

    /// Kotlin `exportOther(dir)`: `<base>.csv`, `<base>.txt` and `<base>-summary.txt` (UTF-8) into `directory`; the
    /// summary carries the score recounted from zero in an active contest. All three texts are built before the
    /// first file is written; a file that cannot be written is left out silently. Status (no `tr`)
    /// `"Export: <names> do <dir>"`.
    public func exportOther(to directory: URL) async {
        let name: String = logName
        let call: String = config.config.station.call
        let replay: ContestSession? = contest.isActive ? contest.runtime.freshSession() : nil
        let qsos: [Qso]
        do {
            qsos = try await readLog()
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return
        }
        let written: [String]
        do {
            written = try await BlockingQueue.run {
                let score: ScoreState? = try replay.map { session in
                    try ContestReplay.replay(session, qsos).session.score()
                }
                let files: [ExportFile] = try ExportJobs.other(contestName: name, call: call, score: score, qsos: qsos)
                return ExportJobs.write(files, to: directory)
            }
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return
        }
        status.show(IoTexts.otherWritten(names: written, dir: directory.path))
    }

    // MARK: - printing (`AS:4025-4035`)

    /// Kotlin `printLog()` up to the dialog: the title `"<contest name or Deník> — <call>"` and the text listing of
    /// the active contest's log, read and built off the main thread (the log snapshot is dropped once the text is
    /// built). `nil` = the log could not be read (the error is shown).
    public func printJob() async -> PrintJob? {
        let title: String = PrintLayout.title(definitionName: logName, call: config.config.station.call)
        do {
            let qsos: [Qso] = try await readLog()
            let text: String = try await BlockingQueue.run {
                LogExports.text(title, qsos)
            }
            return PrintJob(title: title, text: text)
        } catch {
            status.showVerbatim(ErrorText.message(error))
            return nil
        }
    }

    /// The menu's print action: prepares the job and hands it to the app layer as `pendingRequest` (`.print`).
    public func startPrint() {
        start { model in
            if let job = await model.printJob() {
                model.pendingRequest = .print(job)
            }
        }
    }

    /// The end of the print dialog: `tr("Deník odeslán na tiskárnu")`, `tr("Tisk zrušen")` or
    /// `"Tisk selhal: <message>"` (no `tr`).
    public func printFinished(_ outcome: PrintOutcome) {
        switch outcome {
        case .sent:
            status.show(IoTexts.printSent)
        case .cancelled:
            status.show(IoTexts.printCancelled)
        case .failed(let message):
            status.show(IoTexts.printFailed(message: message))
        }
    }
}

/// The main-thread snapshot the exchange conversion and the EDI export read off the main thread: the active
/// definition, a fresh session of it for the received exchange fields (Kotlin `contest.exchangeFields(call)`;
/// a stateless query, so a fresh session answers like the live one) and the DXCC lookup.
struct ExchangeSource: Sendable {
    let definition: ContestDefinition?
    let session: ContestSession?
    let dxcc: (any DxccLookup)?

    @MainActor init(_ contest: ContestModel) {
        definition = contest.definition
        session = contest.definition == nil ? nil : contest.runtime.freshSession()
        dxcc = contest.runtime.dxccLookup
    }

    /// The received fields of a call (empty without a session); an expression error propagates.
    func fields(_ call: String) throws -> [ContestDefinition.ExchangeField] {
        try session?.activeReceivedFields(call: call) ?? []
    }
}

/// Whether two paths name the same file (device and inode after resolving links), so a merge from the database
/// open now reads through its own handle.
enum FileIdentity {
    static func same(_ a: URL, _ b: URL) -> Bool {
        guard let left = identity(a), let right = identity(b) else { return false }
        return left == right
    }

    private struct Key: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private static func identity(_ url: URL) -> Key? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Key(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino))
    }
}
