import Foundation
import MCLCore
import Observation

/// The data tools of the Database and Contest menus (Kotlin `AppState`): the DXCC refill of the log with its
/// confirmation (`AS:1162-1186`, `WL:59-80`), "Update call history from log" (`AS:206-235`) and the update of the
/// contest definitions from the internet (`AS:3682-3704`).
///
/// File and network work runs off the main thread; the log is changed only through `LogbookModel` (one job on the
/// handle's serial queue). The definition updates run one after another: a second request while one runs is queued
/// behind it (Kotlin would start a second download beside the first).
@Observable @MainActor
public final class DataToolsModel {

    /// Where the definitions come from: `DefinitionUpdater.defaultBase` in the app, a local server in tests.
    public struct DefinitionSource: Sendable {
        public var fetcher: any DataFetcher
        public var base: URL

        public init(fetcher: any DataFetcher = URLSessionDataFetcher(), base: URL = DefinitionUpdater.defaultBase) {
            self.fetcher = fetcher
            self.base = base
        }
    }

    /// The texts of the refill confirmation (Kotlin `RefillDxccConfirmDialog`).
    public struct RefillConfirmation: Equatable, Sendable {
        public let title: String
        public let text: String
        public let confirm: String
        public let cancel: String
    }

    @ObservationIgnored let contest: ContestModel
    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored let callData: CallDataModel
    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let language: LanguageModel
    @ObservationIgnored let messages: MessagesModel
    @ObservationIgnored let dataDir: URL
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let definitionSource: DefinitionSource
    /// The download of Club Log's `cty.xml`; `nil` = no network (tests, `MCL_INERT_NETWORK`).
    @ObservationIgnored let clubLogFetcher: (any DataFetcher)?
    @ObservationIgnored var clubLogChain: Task<Void, Never>?
    @ObservationIgnored var observedCtyEnabled: Bool?
    /// The Club Log DXCC line of Settings → Score Reporting (`nil` until the cache state is read).
    public internal(set) var clubLogCtyStatus: ContestMessage?
    /// The result of the last Club Log DXCC update in this session (Settings → Score Reporting).
    public internal(set) var clubLogCtyResult: ContestMessage?
    /// A Club Log DXCC update is running (the Settings button is off meanwhile).
    public internal(set) var clubLogCtyRunning: Bool = false
    @ObservationIgnored private var definitionChain: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTaskId: Int = 0

    struct Dependencies {
        let contest: ContestModel
        let logbook: LogbookModel
        let callData: CallDataModel
        let config: ConfigModel
        let status: StatusModel
        let language: LanguageModel
        let messages: MessagesModel
        let dataDir: URL
        let now: @Sendable () -> Date
        let definitionSource: DefinitionSource
        var clubLogFetcher: (any DataFetcher)? = nil
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        logbook = dependencies.logbook
        callData = dependencies.callData
        config = dependencies.config
        status = dependencies.status
        language = dependencies.language
        messages = dependencies.messages
        dataDir = dependencies.dataDir
        now = dependencies.now
        definitionSource = dependencies.definitionSource
        clubLogFetcher = dependencies.clubLogFetcher
    }

    // MARK: - DXCC refill

    /// The confirmation before the refill (`WL:59-80`): `count` = the QSOs of the log when it is opened
    /// (`MenuActions.Request.confirmRefillDxcc(count:)`); the text is Kotlin's five `tr` pieces joined unchanged.
    public func refillConfirmation(count: Int) -> RefillConfirmation {
        let pieces: [String] = [
            language.tr("Země (číslo DXCC, název, kontinent) se u všech spojení odvodí znovu z volačky "),
            language.tr("podle dnešního country file a přepíše to, co je uložené teď.\n\n"),
            language.tr("Hodí se, když jsou uložená čísla špatně. Pozor: přepíše i údaje z importovaného "),
            language.tr("deníku, které mohly být určené přesněji než odhadem z prefixu. Spojení, jejichž "),
            language.tr("volačku country file nezná, zůstanou beze změny."),
        ]
        return RefillConfirmation(title: language.tr("Přepočítat DXCC u %s QSO?", .int(count)),
                                  text: pieces.joined(), confirm: language.tr("Přepočítat"),
                                  cancel: language.tr("Zrušit"))
    }

    /// Kotlin `refillDxcc()` (`AS:1162-1186`), after the confirmation: the country of every QSO of the active
    /// contest derived again from today's DXCC data and written locally (`LogbookModel.refillDxcc`).
    ///
    /// - Returns: the number of corrected QSOs (Kotlin's return value).
    @discardableResult
    public func refillDxcc() async -> Int {
        guard let dxcc = contest.runtime.dxccLookup else {
            status.show("Přepočet DXCC: chybí data o zemích (~/dxcc-json)")
            return 0
        }
        guard let outcome = await logbook.refillDxcc(dxcc) else { return 0 }
        if let error = outcome.error {
            // Kotlin lets a failed write escape (a crash); the message goes to the status line.
            status.showVerbatim(ErrorText.message(error))
            return outcome.changed
        }
        if outcome.changed == 0 {
            status.show("Přepočet DXCC: vše sedí (%s QSO)", .int(outcome.total))
        } else {
            status.show("Přepočet DXCC: opraveno %s z %s QSO", .int(outcome.changed), .int(outcome.total))
        }
        return outcome.changed
    }

    // MARK: - call history from the log

    /// Kotlin `updateCallHistoryFromLog()` (`AS:206-235`, N1MM "Update Call History from log"): the received
    /// exchange of the log's QSOs merged into the call history and saved — the configured file (trimmed), or
    /// `<data>/CALLHISTORY.txt`, whose path is then written into the configuration (Kotlin `configStore.save`, not
    /// `saveConfig`: nothing is reloaded).
    ///
    /// The values are computed off the main thread over a snapshot of the rows and a **fresh** session of the active
    /// contest: `CallHistoryUpdater` reads only the definition and the station class (DXCC of the worked call and of
    /// the own call), never the logged state, so the fresh session gives the live one's result. (It takes the own
    /// call of now; the live session took it at the activation or the last recount.)
    public func updateCallHistoryFromLog() {
        guard let session = contest.runtime.freshSession() else {
            status.show("Call history se aktualizuje z deníku závodu — otevři závod")
            return
        }
        let rows: [Qso] = logbook.rows
        let history: CallHistory = callData.callHistory
        let configured: String = KotlinStrings.trim(config.config.callHistoryFile)
        let target: (url: URL, persist: Bool) = ContestDataPaths.callHistoryTarget(
            configured: config.config.callHistoryFile, dataDir: dataDir)
        // Kotlin `Path.of(configured)`: a relative path stays relative (saved against the working directory).
        let path: String = target.persist ? target.url.path : configured
        track { [weak self] in
            let outcome: CallHistoryOutcome = await Self.computeAndSave(session: session, rows: rows,
                                                                        history: history, path: path)
            self?.finishCallHistory(outcome, path: path, persist: target.persist)
        }
    }

    private enum CallHistoryOutcome: Sendable {
        case expression(String)
        case empty
        case saved(merged: CallHistory, calls: Int)
        case failed(String)
    }

    nonisolated private static func computeAndSave(session: ContestSession, rows: [Qso], history: CallHistory,
                                                   path: String) async -> CallHistoryOutcome {
        let computed: CallHistoryOutcome? = try? await BlockingQueue.run { () -> CallHistoryOutcome in
            let updates: JavaLinkedMap<JavaLinkedMap<String>>
            do {
                updates = try CallHistoryUpdater.updates(session, rows, history)
            } catch {
                return .expression(ErrorText.message(error))
            }
            if updates.isEmpty {
                return .empty
            }
            let merged: CallHistory = history.withUpdates(updates)
            do throws(CallHistorySaveError) {
                try merged.save(path)
            } catch {
                return .failed(error.message)
            }
            return .saved(merged: merged, calls: updates.count)
        }
        return computed ?? .failed("null")
    }

    private func finishCallHistory(_ outcome: CallHistoryOutcome, path: String, persist: Bool) {
        switch outcome {
        case .expression(let message):
            // Kotlin crashes on a station-class expression error; the message goes to the status line.
            status.showVerbatim(message)
        case .empty:
            status.show("Deník nemá žádnou výměnu k uložení do call history")
        case .failed(let message):
            status.show("Uložení call history selhalo: %s", .string(message))
        case .saved(let merged, let calls):
            callData.adoptCallHistory(merged, path: path)
            if persist {
                config.config.callHistoryFile = path
                config.saveSilently()
            }
            status.show("Call history: %s volaček z deníku, celkem %s → %s", .int(calls), .int(merged.size),
                        .string(path))
        }
    }

    // MARK: - definition updates

    /// Kotlin `updateContestDefinitions()` (`AS:3682-3704`): downloads the published contest data into the contest
    /// data root (`DefinitionUpdater`, locally edited files kept), then reloads the contest data and lists the
    /// changed files in the messages (`"Definice <path>: <STATUS>"` + `" — <detail>"`, without `tr`).
    public func updateDefinitions() {
        status.show("Stahuji definice závodů…")
        let previous: Task<Void, Never>? = definitionChain
        let task = Task { [weak self] in
            await previous?.value
            await self?.runDefinitionUpdate()
        }
        definitionChain = task
        track {
            await task.value
        }
    }

    private func runDefinitionUpdate() async {
        let root: URL = ContestDataPaths.root(contestDataDir: config.config.contestDataDir,
                                              default: dataDir.appendingPathComponent("contest-data"))
        let result: Result<DefinitionUpdater.Report, DefinitionUpdaterError> =
            await Self.downloadAndApply(definitionSource, root: root)
        switch result {
        case .failure(let error):
            status.showVerbatim("Aktualizace definic selhala: " + error.message)
        case .success(let report):
            await contest.reloadContestData()
            status.show("Definice závodů: %s", .string(report.summary()))
            messages.add(Self.messageLines(report), at: now())
        }
    }

    /// `DefinitionUpdater.update` in its phases: the network phases are awaited, the file phases (manifest, checks,
    /// writes) run on `BlockingQueue` — never on the shared pool. Java's error order is kept: index, manifest, paths.
    nonisolated static func downloadAndApply(_ source: DefinitionSource,
                                             root: URL) async -> Result<DefinitionUpdater.Report, DefinitionUpdaterError> {
        let updater = DefinitionUpdater(fetcher: source.fetcher)
        do {
            let index: DefinitionUpdater.Index = try await updater.fetchIndex(source.base)
            let manifest: JavaProperties = try await BlockingQueue.run {
                try DefinitionUpdater.loadManifest(dataDir: root)
            }
            let downloaded: DefinitionUpdater.Downloaded = try await updater.download(index)
            return .success(try await BlockingQueue.run {
                try DefinitionUpdater.apply(downloaded, manifest: manifest, dataDir: root)
            })
        } catch let error as DefinitionUpdaterError {
            return .failure(error)
        } catch {
            return .failure(DefinitionUpdaterError(message: ErrorText.message(error)))
        }
    }

    /// The messages of a report: every file that is not `UNCHANGED`, in the report's order.
    nonisolated static func messageLines(_ report: DefinitionUpdater.Report) -> [String] {
        report.files.filter { $0.status != .unchanged }.map { file in
            let head: String = "Definice " + file.path + ": " + file.status.description
            return KotlinStrings.isBlank(file.detail) ? head : head + " — " + file.detail
        }
    }

    // MARK: - tasks

    func track(_ body: @escaping @MainActor () async -> Void) {
        let id: Int = nextTaskId
        nextTaskId += 1
        tasks[id] = Task { [weak self] in
            await body()
            self?.tasks[id] = nil
        }
    }

    /// Waits for the call history saves and definition updates in flight (tests; `AppModel.shutdown` awaits it before the database closes).
    func settle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }
}
