import Foundation
import MCLCore
import Observation

/// The contest definition editor (Kotlin `DefinitionEditorWindow`, `DE:1-244`; N1MM UDC Editor): the YAML files of
/// `contests/`, the text with a live check and preview, a new contest from the template, a duplicate, a QSO party,
/// the county import, saving (with a reload of the contest data) and discarding.
///
/// Kotlin computes the directories and lists in `remember` blocks and reads/writes files on the UI thread; here the
/// listing, reading, writing and the check run off the main thread. The lists follow `config.contestDataDir`, a save,
/// a county import and every contest-data reload (also a definition update while the editor is open — Kotlin keeps
/// its stale list there). The check runs 250 ms after the last change of the text, the contest or the known sets
/// (Kotlin `LaunchedEffect` + `delay(250)`), with a generation: a late result for an older text is dropped.
@Observable @MainActor
public final class DefinitionEditorModel {

    /// The contest data root (Kotlin `state.contestDataRoot()`).
    public private(set) var root: URL
    /// `<root>/contests`, or the root when only it is a directory (`ContestDataPaths.contestsDir`).
    public private(set) var contestsDir: URL
    /// The multiplier sets of `<root>/multipliers` (`DefinitionEditing.knownSets`).
    public private(set) var knownSets: [String] = []
    /// The definition ids of `contestsDir` (`DefinitionEditing.listIds`).
    public private(set) var ids: [String] = []
    /// The definition being edited; `nil` = none.
    public private(set) var currentId: String?
    /// The text as last read or saved (Kotlin `original`; `""` for a new contest).
    public private(set) var original: String = ""
    /// The edited text.
    public var text: String = "" {
        didSet {
            documentGeneration += 1
            scheduleCheck()
        }
    }
    /// The last finished check; `nil` = none yet, or no definition open.
    public private(set) var check: DefinitionEditing.Check?
    /// The editor's own status (Kotlin `status`, shown in the footer before anything else).
    public private(set) var status: StatusText?

    /// Kotlin `dirty = text != original` (`String.equals`: UTF-16 units, not canonical equivalence).
    public var isDirty: Bool {
        !text.utf16.elementsEqual(original.utf16)
    }

    /// The check found errors in an open definition (the footer turns red).
    public var hasCheckErrors: Bool {
        currentId != nil && (check?.hasErrors ?? false)
    }

    /// The footer: the status, else the error warning, else „Neuloženo" when dirty, else nothing.
    public var footerText: String {
        if let status {
            let shown: String = language.text(status)
            if !shown.isEmpty {
                return shown
            }
        }
        if hasCheckErrors {
            return language.tr("Definice má chyby — se chybami se závod nenačte")
        }
        return isDirty ? language.tr("Neuloženo") : ""
    }

    /// „Uložit" (Kotlin `enabled = currentId != null && dirty`).
    public var canSave: Bool {
        currentId != nil && isDirty
    }

    /// „Uložit a přenačíst závody" (`currentId != null`).
    public var canSaveAndReload: Bool {
        currentId != nil
    }

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let defaultRoot: URL
    @ObservationIgnored private let clock: any RescoreClock
    @ObservationIgnored private var checkTimer: (any RescoreTimer)?
    @ObservationIgnored private var checkGeneration: Int = 0
    @ObservationIgnored private var listGeneration: Int = 0
    /// Raised by every change of the document (text, open, new); a slow read of `open` is dropped when it changed.
    @ObservationIgnored private var documentGeneration: Int = 0
    @ObservationIgnored private var observedDataDir: String?
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTaskId: Int = 0

    init(config: ConfigModel, contest: ContestModel, language: LanguageModel, dataDir: URL, clock: any RescoreClock) {
        self.config = config
        self.contest = contest
        self.language = language
        self.clock = clock
        defaultRoot = dataDir.appendingPathComponent("contest-data")
        let root: URL = ContestDataPaths.root(contestDataDir: config.config.contestDataDir, default: defaultRoot)
        self.root = root
        contestsDir = root.appendingPathComponent("contests")
    }

    // MARK: - lists

    /// Reads the directories and lists again off the main thread (window shown, a save, a reload, a changed
    /// `contestDataDir`).
    public func refresh() {
        let root: URL = ContestDataPaths.root(contestDataDir: config.config.contestDataDir, default: defaultRoot)
        listGeneration += 1
        let generation: Int = listGeneration
        track { [weak self] in
            let lists: Lists? = try? await BlockingQueue.run {
                let contestsDir: URL = ContestDataPaths.contestsDir(root: root)
                return Lists(contestsDir: contestsDir,
                             knownSets: DefinitionEditing.knownSets(root.appendingPathComponent("multipliers")),
                             ids: DefinitionEditing.listIds(contestsDir))
            }
            guard let self, let lists, generation == self.listGeneration else { return }
            let setsChanged: Bool = lists.knownSets != self.knownSets
            self.root = root
            self.contestsDir = lists.contestsDir
            self.ids = lists.ids
            self.knownSets = lists.knownSets
            if setsChanged {
                // Kotlin keys the check on `knownSets` too.
                self.scheduleCheck()
            }
        }
    }

    private struct Lists: Sendable {
        let contestsDir: URL
        let knownSets: [String]
        let ids: [String]
    }

    /// Refreshes the lists when `config.contestDataDir` changes (Kotlin `remember(state.configRevision)`), re-armed
    /// after every change.
    func observeDataDir() {
        withObservationTracking {
            _ = config.config.contestDataDir
        } onChange: { [weak self] in
            MainHop.post {
                guard let self else { return }
                let current: String? = self.config.config.contestDataDir
                if current != self.observedDataDir {
                    self.observedDataDir = current
                    self.refresh()
                }
                self.observeDataDir()
            }
        }
        observedDataDir = config.config.contestDataDir
    }

    // MARK: - opening and new definitions

    /// Kotlin `open(id)`: refused while the text is unsaved; the file is read like `Files.readString` (strict UTF-8).
    public func open(_ id: String) async {
        if isDirty {
            showStatus(ContestMessage("Neuložené změny — ulož je, nebo zahoď"))
            return
        }
        let file: URL = contestsDir.appendingPathComponent(id + ".yaml")
        let generation: Int = documentGeneration
        let read: Result<String, JavaIOError> = await Self.read(file)
        // The text was edited (or another definition opened) meanwhile: the newer document wins.
        guard generation == documentGeneration else { return }
        switch read {
        case .success(let content):
            currentId = id
            original = content
            text = content
            status = nil
        case .failure(let error):
            showStatus(ContestMessage("Nelze otevřít %s.yaml: %s", .string(id),
                                      .string(IoTexts.template(error.message))))
        }
    }

    nonisolated private static func read(_ file: URL) async -> Result<String, JavaIOError> {
        do {
            return .success(try await BlockingQueue.run {
                try LogImporter.readText(file)
            })
        } catch let error as JavaIOError {
            return .failure(error)
        } catch {
            return .failure(JavaIOError(ErrorText.message(error)))
        }
    }

    /// „Nový ze šablony…": `DefinitionEditing.template(id, id)` with the trimmed id.
    public func startNew(id: String) {
        let trimmed: String = KotlinStrings.trim(id)
        startNew(trimmed, content: DefinitionEditing.template(trimmed, trimmed))
    }

    /// „Duplikovat…": the current text (unsaved edits included) under the trimmed id; nothing without an open
    /// definition (Kotlin disables the button).
    public func duplicate(id: String) {
        guard currentId != nil else { return }
        let trimmed: String = KotlinStrings.trim(id)
        startNew(trimmed, content: DefinitionEditing.withId(text, trimmed))
    }

    /// „Nová QSO party…": `CountyListImport.qsoPartyTemplate` with `ContestDataPaths.qsoPartyArguments`.
    public func newQsoParty(id: String) {
        let arguments = ContestDataPaths.qsoPartyArguments(id: id)
        startNew(arguments.id, content: CountyListImport.qsoPartyTemplate(arguments.id, arguments.name,
                                                                           arguments.countySet))
    }

    /// Kotlin `startNew(id, content)`: an invalid or existing id is refused; otherwise the new text replaces the
    /// editor's — **unsaved changes are dropped without a question**, as in Kotlin.
    private func startNew(_ id: String, content: String) {
        if !DefinitionEditing.isValidId(id) {
            showStatus(ContestMessage("Id smí mít jen malá písmena, číslice, - a _"))
        } else if ids.contains(where: { $0.utf16.elementsEqual(id.utf16) }) {
            showStatus(ContestMessage("Závod '%s' už existuje", .string(id)))
        } else {
            currentId = id
            original = ""
            text = content
            showStatus(ContestMessage("Nový závod %s — ulož ho", .string(id)))
        }
    }

    // MARK: - county import

    /// „Importovat okresy…": the file read like `Files.readAllLines` (strict UTF-8), `CountyListImport.parse` and
    /// `write` into `<root>/multipliers` as the set `setId` (trimmed, also its name), then the sets refreshed and the
    /// contest data reloaded.
    public func importCounties(file: URL, setId: String) async {
        await tracked { await self.performImportCounties(file: file, setId: setId) }
    }

    private func performImportCounties(file: URL, setId: String) async {
        let id: String = KotlinStrings.trim(setId)
        let multipliers: URL = root.appendingPathComponent("multipliers")
        let written: Result<Int, any Error>
        do {
            written = .success(try await BlockingQueue.run {
                let values = CountyListImport.parse(try GoalFileIO.readLines(file.path))
                return try CountyListImport.write(multipliers, setId: id, name: id, values: values)
            })
        } catch {
            written = .failure(error)
        }
        switch written {
        case .success(let count):
            showStatus(ContestMessage("Sada %s: %s okresů z %s", .string(id), .int(count),
                                      .string(file.lastPathComponent)))
            refresh()
            await contest.reloadContestData()
        case .failure(let error):
            showStatus(ContestMessage("Import okresů: %s", .string(ErrorText.message(error))))
        }
    }

    // MARK: - saving

    /// Kotlin `save(reload)`: `DefinitionEditing.save` (atomic), the list refreshed, with `reload` the contest data
    /// reloaded; status „Uloženo <file>" + „ a definice přenačteny", or „Uložení selhalo: …".
    public func save(reload: Bool) async {
        await tracked { await self.performSave(reload: reload) }
    }

    private func performSave(reload: Bool) async {
        guard let id = currentId else { return }
        let saved: String = text
        let dir: URL = contestsDir
        let result: Result<URL, any Error>
        do {
            result = .success(try await BlockingQueue.run {
                try DefinitionEditing.save(dir, id: id, yaml: saved)
            })
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let file):
            if currentId == id {
                original = saved
            }
            refresh()
            if reload {
                await contest.reloadContestData()
            }
            var parts: [ContestMessage] = [ContestMessage("Uloženo %s", .string(file.lastPathComponent))]
            if reload {
                parts.append(ContestMessage(" a definice přenačteny"))
            }
            status = .joined(parts, separator: "")
        case .failure(let error):
            showStatus(ContestMessage("Uložení selhalo: %s", .string(ErrorText.message(error))))
        }
    }

    /// „Zahodit změny": the text back to the original.
    public func discard() {
        text = original
        showStatus(ContestMessage("Změny zahozeny"))
    }

    /// The editor window closed (Kotlin's state lives in the window's `remember` blocks, `DE:60-64`, and is gone with
    /// it): no definition, no text (unsaved changes are dropped without a question, as in Kotlin), no check, no
    /// status. A pending check and an `open` still reading are dropped (generations). Not called on quit.
    public func reset() {
        currentId = nil
        original = ""
        text = ""
        checkTimer?.cancel()
        checkTimer = nil
        checkGeneration += 1
        documentGeneration += 1
        check = nil
        status = nil
    }

    private func showStatus(_ message: ContestMessage) {
        status = .message(message)
    }

    // MARK: - check

    /// Kotlin `LaunchedEffect(text, currentId, knownSets) { delay(250); check = … }`: the pending check is replaced;
    /// without a definition the check becomes `nil`.
    private func scheduleCheck() {
        checkTimer?.cancel()
        checkGeneration += 1
        let generation: Int = checkGeneration
        checkTimer = clock.schedule(afterMilliseconds: 250) { [weak self] in
            self?.runCheck(generation)
        }
    }

    private func runCheck(_ generation: Int) {
        guard generation == checkGeneration else { return }
        guard let id = currentId else {
            check = nil
            return
        }
        let yaml: String = text
        let sets: [String] = knownSets
        track { [weak self] in
            let result: DefinitionEditing.Check? = try? await BlockingQueue.run {
                DefinitionEditing.check(yaml, fileId: id, knownSets: sets)
            }
            guard let self, let result, generation == self.checkGeneration else { return }
            self.check = result
        }
    }

    // MARK: - tasks

    private func track(_ body: @escaping @MainActor () async -> Void) {
        let id: Int = nextTaskId
        nextTaskId += 1
        tasks[id] = Task { [weak self] in
            await body()
            self?.tasks[id] = nil
        }
    }

    /// Runs a save or import as a tracked task, so that `settle()` (shutdown) waits for it, its reload included.
    private func tracked(_ body: @escaping @MainActor () async -> Void) async {
        let id: Int = nextTaskId
        nextTaskId += 1
        let task = Task { [weak self] in
            await body()
            self?.tasks[id] = nil
        }
        tasks[id] = task
        await task.value
    }

    /// Waits for the listings, checks, saves and imports in flight (tests, shutdown).
    func settle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }
}
