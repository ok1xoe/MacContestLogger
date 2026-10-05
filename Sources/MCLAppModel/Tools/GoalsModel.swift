import Foundation
import MCLCore
import Observation

/// The goal editor and the import of goals from an earlier log (Kotlin `GoalWindows.kt`).
///
/// The editor works on a draft of texts per hour (`GoalEditing.Draft`), so a field can be emptied without a zero being
/// filled in. A save writes the goals to the config and the file (`saveNow`, the failure text of the window); no
/// `saveConfig` side effects. The goals of another database are read off the main thread **read-only**:
/// the file is only opened for the queries of `ContestStore.listSummaries` and `findAll`; nothing is written to it.
@Observable @MainActor
public final class GoalsModel {

    // MARK: - the editor

    /// The hour keys of the active contest; empty without a running contest that has a start date.
    public private(set) var hours: [Int32] = []
    public var draft = GoalEditing.Draft(goalSet: GoalSet.empty(), hours: [])
    public var bulk = GoalEditing.BulkFill(hours: [])
    /// Kotlin `hours.isEmpty()` → the window shows the "needs a running contest" text.
    public var needsContest: Bool {
        hours.isEmpty
    }

    // MARK: - from an earlier log

    /// The databases of the catalog (`databaseCatalog.list()`).
    public private(set) var databases: [String] = []
    public private(set) var selectedDatabase: String = ""
    /// The band filter (`nil` = all).
    public var band: Band?
    public private(set) var contests: [ContestStore.ContestSummary] = []
    /// The error line of the window.
    public private(set) var error: String = ""
    /// The import finished and the window closes itself (Kotlin `onClose()` after a successful import).
    public private(set) var imported = false

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let database: DatabaseModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let info: InfoModel
    /// Where the private copy of a foreign database is made (a seam for the tests; removed again after the read).
    @ObservationIgnored var scratchRoot: URL = FileManager.default.temporaryDirectory
    /// The files that travel with a foreign database into its private copy (as in `LogImporter`, plus the shared memory).
    nonisolated static let sidecarSuffixes: [String] = ["-journal", "-wal", "-shm"]
    /// Set by the quit: nothing writes the config after its final flush.
    @ObservationIgnored var isShuttingDown: () -> Bool = { false }
    /// Generation of the contest list: a late answer for another database is dropped.
    @ObservationIgnored private var listGeneration = 0

    struct Dependencies {
        let contest: ContestModel
        let config: ConfigModel
        let database: DatabaseModel
        let status: StatusModel
        let language: LanguageModel
        let info: InfoModel
    }

    init(_ dependencies: Dependencies) {
        contest = dependencies.contest
        config = dependencies.config
        database = dependencies.database
        status = dependencies.status
        language = dependencies.language
        info = dependencies.info
    }

    private var translator: Translator {
        language.translator
    }

    // MARK: - editor

    /// The editor opened: the hours of the active contest, the draft from the saved goals.
    public func openEditor() {
        let start: JavaInstant? = info.contestStart
        let computed: [Int32] = (try? GoalEditing.hours(contestStart: start, definition: contest.definition)) ?? []
        hours = computed
        let saved: GoalSet = GoalFileWriter.fromConfigMap(config.config.goals)
        draft = GoalEditing.Draft(goalSet: saved, hours: computed)
        bulk = GoalEditing.BulkFill(hours: computed)
    }

    /// The explanation above the editor.
    public var helpText: String {
        GoalEditing.helpText(translate: translator)
    }

    /// The text of a window without a running contest.
    public var noContestText: String {
        GoalEditing.noContestText(translate: translator)
    }

    /// „Vyplnit": the bulk value into the range.
    public func applyBulk() {
        bulk.apply(to: &draft)
    }

    /// „Uložit": the goals into the config and the file; the status says how many hours or why it failed. Returns
    /// whether the editor can close (Kotlin closes it either way).
    @discardableResult
    public func save() async -> Bool {
        if isShuttingDown() { return false }
        let goals: GoalSet = draft.goalSet()
        config.config.goals = GoalFileWriter.toConfigMap(goals)
        do {
            try await config.saveNow(config.config)
            status.showVerbatim(GoalEditing.savedText(hours: goals.entries.count, translate: translator))
        } catch {
            status.showVerbatim(GoalEditing.saveFailedText(ErrorText.message(error), translate: translator))
        }
        info.recompute()
        return true
    }

    // MARK: - from an earlier log

    /// The window opened: the catalog's databases and the active one selected.
    public func openFromLog() async {
        imported = false
        error = ""
        band = nil
        databases = (try? await database.list()) ?? []
        await selectDatabase(database.currentName)
    }

    /// The database picker: the contests of the chosen database, read off the main thread.
    public func selectDatabase(_ name: String) async {
        selectedDatabase = name
        contests = []
        error = ""
        listGeneration += 1
        let mine: Int = listGeneration
        let result: Result<[ContestStore.ContestSummary], any Error> = await read(name) { _, store in
            try store.listSummaries()
        }
        guard mine == listGeneration else { return }
        switch result {
        case .success(let summaries):
            contests = summaries
        case .failure(let failure):
            error = translator.translate("Databázi se nepodařilo otevřít (%s)",
                                         [.string(ErrorText.message(failure))])
        }
    }

    /// A click on a contest: the goal of each hour = the number of QSOs made in it (`GoalsFromLog.derive`).
    public func importFrom(_ summary: ContestStore.ContestSummary) async {
        if isShuttingDown() { return }
        guard let started = summary.startedAt else {
            error = translator.translate("Závod nemá vyplněné datum startu, hodiny nejdou určit.")
            return
        }
        let start: JavaInstant = JavaInstant(date: Date(timeIntervalSince1970: Double(started) / 1000.0))
        let filter: Band? = band
        let contestId: String = summary.contestId
        let name: String = selectedDatabase
        let result: Result<GoalSet, any Error> = await read(name) { repository, _ in
            let qsos: [Qso] = try repository.findAll(contestId: contestId)
            return try GoalsFromLog.derive(qsos, start, filter)
        }
        switch result {
        case .failure(let failure):
            error = translator.translate("Deník se nepodařilo přečíst (%s)", [.string(ErrorText.message(failure))])
        case .success(let goals):
            // The quit may have started during the read: nothing is written after it.
            if isShuttingDown() { return }
            config.config.goals = GoalFileWriter.toConfigMap(goals)
            do {
                try await config.saveNow(config.config)
                status.showVerbatim(GoalEditing.fromLogStatus(contestName: summary.name ?? "", hours: goals.entries.count,
                                                              band: filter, translate: translator))
            } catch {
                status.showVerbatim(GoalEditing.saveFailedText(ErrorText.message(error), translate: translator))
            }
            info.recompute()
            imported = true
        }
    }

    /// The label of the band picker.
    public var bandLabel: String {
        GoalEditing.bandLabel(band, translate: translator)
    }

    /// The explanation of the window.
    public var fromLogHelpText: String {
        GoalEditing.fromLogHelpText(translate: translator)
    }

    /// Runs `body` over the named database: the active one through its own handle, any other through a connection of
    /// its own that is closed again — off the main thread, and nothing in `body` writes.
    private func read<T: Sendable>(_ name: String,
                                   _ body: @escaping @Sendable (LogbookRepository, ContestStore) throws -> T)
        async -> Result<T, any Error> {
        if name == database.currentName {
            let handle: LogbookHandle = database.handle
            do {
                return .success(try await handle.run { access in
                    try body(access.repository, access.contests)
                })
            } catch {
                return .failure(error)
            }
        }
        let dir: URL = database.databasesDir
        let root: URL = scratchRoot
        do {
            let value: T = try await BlockingQueue.run {
                // Data safety (divergence from Kotlin, which opens the file read-write): the foreign file is never
                // opened by the app's repository. A missing file is an error (nothing is created); an existing one
                // is copied byte for byte to a private temporary directory and the copy is read — schema creation
                // and migration of an old file happen on the copy, the original and its directory stay untouched.
                let source: URL = try DatabaseCatalog(databasesDir: dir).pathFor(name)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw LogbookError("Soubor databáze neexistuje: \(source.path)")
                }
                let scratch: URL = root
                    .appendingPathComponent("mcl-goals-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: scratch) }
                let copy: URL = scratch.appendingPathComponent("copy.sqlite")
                try FileManager.default.copyItem(at: source, to: copy)
                // A write-ahead log next to the file holds committed rows that are not in the main file yet; a hot journal
                // is rolled back in the copy (as `LogImporter` does).
                for suffix in Self.sidecarSuffixes {
                    let side = URL(fileURLWithPath: source.path + suffix)
                    if FileManager.default.fileExists(atPath: side.path) {
                        try FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
                    }
                }
                let repository = try LogbookRepository(url: copy)
                defer { repository.close() }
                return try body(repository, try ContestStore(repository))
            }
            return .success(value)
        } catch {
            return .failure(error)
        }
    }
}
