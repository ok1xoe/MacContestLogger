import Foundation
import MCLCore
import Observation

/// The contest and database dialogs of the slice (Kotlin `showNewContestDialog`, `showContestBrowser`,
/// `showNewDatabaseDialog`, `showOpenDatabaseDialog`; the start-up offer is `ContestModel.showStartupDialog`).
///
/// They are separate windows with the Kotlin ids. Dialogs are never reopened at start (Kotlin keeps
/// these flags out of `openWindows`). What a window lists is read **once per opening, off the main thread** —
/// Kotlin re-ran the SQL / directory listing on every composition.
@Observable @MainActor
public final class DialogsModel {

    /// Window ids (the same as Kotlin's `rememberPersistentWindowState` ids; the new-contest window keeps no
    /// geometry).
    public enum Window: String, CaseIterable, Sendable {
        case startup
        case newContest = "new-contest"
        case contests
        case databaseNew = "db-new"
        case databaseOpen = "db-open"
        /// The operator at the key (Kotlin `OperatorDialog`, Ctrl+O / OPON).
        case operatorLogin = "operator"

        /// Kotlin default size.
        public var defaultSize: CGSize {
            switch self {
            case .startup: return CGSize(width: 460, height: 330)
            case .newContest: return CGSize(width: 760, height: 900)
            case .contests: return CGSize(width: 620, height: 520)
            case .databaseNew: return CGSize(width: 420, height: 200)
            case .databaseOpen: return CGSize(width: 420, height: 360)
            case .operatorLogin: return CGSize(width: 400, height: 230)
            }
        }

        /// The new-contest window is a Kotlin `DialogWindow` whose geometry is not saved.
        public var savesGeometry: Bool {
            self != .newContest
        }
    }

    /// The open „Nový závod" window's state (`nil` = closed).
    public private(set) var newContest: NewContestModel?
    public private(set) var showContestBrowser: Bool = false
    public private(set) var showNewDatabase: Bool = false
    public private(set) var showOpenDatabase: Bool = false

    /// The Continue button's label (Kotlin `lastContestLabel()`); `nil` = no button.
    public private(set) var startupLabel: String?
    /// Rows of the contest browser; `nil` while they are read.
    public private(set) var browserRows: [ContestBrowserRow]?
    /// Database names of the open-database window; `nil` while they are read.
    public private(set) var databaseNames: [String]?
    /// The name typed into the new-database window.
    public var newDatabaseName: String = ""

    // MARK: entry dialogs

    /// A text prompt (Kotlin `TextPrompt`, `AS:1028`): title, hint, initial text and what OK does. The texts are
    /// messages translated when shown.
    public struct TextPrompt: Identifiable {
        public let id: Int
        public let title: ContestMessage
        public let hint: ContestMessage
        public let initial: String
        let submit: @MainActor (String) -> Void
    }

    /// A question with OK / Zrušit (`WipeLogConfirmDialog.kt`, the EXIT dialog of `App.kt:276-286`).
    public enum Confirmation: Equatable, Sendable {
        /// WIPELOG / CLEARLOG.
        case wipeLog
        /// Ctrl+D.
        case deleteLast
        /// BYE / EXIT / QUIT.
        case exit
    }

    /// The open text prompt (Kotlin `textPrompt`).
    public private(set) var textPrompt: TextPrompt?
    /// The open confirmation.
    public private(set) var confirmation: Confirmation?
    /// The operator window (Kotlin `showOperatorDialog`, window id `operator`).
    public private(set) var showOperator: Bool = false
    /// Raised when the app should quit (EXITNOW, or EXIT confirmed); the app layer quits through `AppQuit.request`.
    public private(set) var quitRequest: Int = 0
    /// What the wipe and delete confirmations do (wired by the app model).
    @ObservationIgnored var onWipeLog: (@MainActor () -> Void)?
    @ObservationIgnored var onDeleteLast: (@MainActor () -> Void)?
    @ObservationIgnored private var promptCounter: Int = 0

    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let database: DatabaseModel
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var work: Task<Void, Never>?

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let operating: OperatingModel
    /// Kotlin `state.clusterConnected` (set by the app: `ClusterSyncModel.connected`).
    @ObservationIgnored var clusterConnected: @MainActor () -> Bool = { false }

    init(contest: ContestModel, database: DatabaseModel, config: ConfigModel, status: StatusModel,
         logbook: LogbookModel, operating: OperatingModel, now: @escaping @Sendable () -> Date) {
        self.contest = contest
        self.database = database
        self.config = config
        self.status = status
        self.logbook = logbook
        self.operating = operating
        self.now = now
    }

    // MARK: - open and close

    public func isOpen(_ window: Window) -> Bool {
        switch window {
        case .startup: return contest.showStartupDialog
        case .newContest: return newContest != nil
        case .contests: return showContestBrowser
        case .databaseNew: return showNewDatabase
        case .databaseOpen: return showOpenDatabase
        case .operatorLogin: return showOperator
        }
    }

    /// The dialogs that should be shown; the main window opens and closes their windows to match.
    public var openDialogs: Set<Window> {
        Set(Window.allCases.filter { isOpen($0) })
    }

    /// Opens or closes a dialog (menu action, a button, the window's close button). Opening resets the window's
    /// state, as Kotlin's `remember` inside a window that is shown again.
    public func setOpen(_ window: Window, _ open: Bool) {
        switch window {
        case .startup:
            contest.showStartupDialog = open
        case .newContest:
            if !open {
                newContest = nil
            } else if newContest == nil {
                newContest = NewContestModel(contests: contest.runtime.available, config: config, now: now)
            }
        case .contests:
            if open && !showContestBrowser {
                browserRows = nil
            }
            showContestBrowser = open
        case .databaseNew:
            if open && !showNewDatabase {
                newDatabaseName = ""
            }
            showNewDatabase = open
        case .databaseOpen:
            if open && !showOpenDatabase {
                databaseNames = nil
            }
            showOpenDatabase = open
        case .operatorLogin:
            showOperator = open
        }
    }

    // MARK: - reading (once per opening, off the main thread)

    /// The start-up window's Continue label (re-read when the window opens or the database changes).
    public func loadStartup() async {
        startupLabel = await contest.lastContestLabel()
    }

    /// The contest browser's rows.
    public func loadBrowser() async {
        browserRows = await contest.browserRows()
    }

    /// The database names (Kotlin `databaseCatalog.list()`; a failure — a Kotlin crash — shows the error and an
    /// empty list).
    public func loadDatabases() async {
        do {
            databaseNames = try await database.list()
        } catch {
            databaseNames = []
            status.showVerbatim(ErrorText.message(error))
        }
    }

    // MARK: - actions of the windows

    /// Start-up „Pokračovat: …".
    public func continueLastContest() {
        setOpen(.startup, false)
        run { await $0.contest.continueLastContest() }
    }

    /// Start-up „Nový závod…".
    public func startupNewContest() {
        setOpen(.startup, false)
        setOpen(.newContest, true)
    }

    /// Start-up „Otevřít existující…".
    public func startupOpenContest() {
        setOpen(.startup, false)
        setOpen(.contests, true)
    }

    /// New contest „OK": the setup is remembered for the definition (prefill next time), the window closes and the
    /// contest is created and started (Kotlin order).
    public func confirmNewContest() {
        guard let model = newContest else { return }
        let setup: ContestSetup = model.setup()
        guard let id = model.selectedId else {
            setOpen(.newContest, false)
            return
        }
        config.config.contestSetups[id] = setup
        config.save(failureKey: "Uložení setupu selhalo (%s)")
        setOpen(.newContest, false)
        run { await $0.contest.createAndStart(definitionId: id, setup: setup) }
    }

    /// A row of the contest browser.
    public func openContest(_ contestId: String) {
        setOpen(.contests, false)
        run { await $0.contest.open(contestId: contestId) }
    }

    /// New database „Založit".
    public func createDatabase() {
        let name: String = newDatabaseName
        setOpen(.databaseNew, false)
        run { await $0.database.create(name) }
    }

    /// A row of the open-database window.
    public func openDatabase(_ name: String) {
        setOpen(.databaseOpen, false)
        run { await $0.database.open(name) }
    }

    /// The first-run dialog chose a directory.
    public func chooseDatabasesDir(_ dir: URL) {
        run { await $0.database.setDatabasesDir(dir) }
    }

    // MARK: - entry dialogs

    /// Opens a text prompt (a newer one replaces an open one, as Kotlin's single `textPrompt`).
    public func prompt(title: ContestMessage, hint: ContestMessage, initial: String,
                       submit: @escaping @MainActor (String) -> Void) {
        promptCounter += 1
        textPrompt = TextPrompt(id: promptCounter, title: title, hint: hint, initial: initial, submit: submit)
    }

    /// OK of the text prompt: the prompt closes, then its action runs with the text.
    public func submitPrompt(_ text: String) {
        guard let open = textPrompt else { return }
        textPrompt = nil
        open.submit(text)
    }

    public func cancelPrompt() {
        textPrompt = nil
    }

    /// Opens a confirmation.
    public func ask(_ question: Confirmation) {
        confirmation = question
    }

    public func cancelConfirmation() {
        confirmation = nil
    }

    /// The confirm button: the dialog closes, then the action runs (`WipeLogConfirmDialog.kt`).
    public func confirm() {
        guard let question = confirmation else { return }
        let emptyLog: Bool = logbook.rows.isEmpty
        if question == .deleteLast && emptyLog {
            // The Kotlin button is disabled on an empty log.
            return
        }
        confirmation = nil
        switch question {
        case .wipeLog:
            onWipeLog?()
        case .deleteLast:
            onDeleteLast?()
        case .exit:
            quitRequest += 1
        }
    }

    /// EXITNOW / QUITNOW: quit without asking.
    public func quitNow() {
        quitRequest += 1
    }

    /// The title of the open confirmation, read when shown (Kotlin reads the log in the composition).
    public var confirmationTitle: ContestMessage? {
        switch confirmation {
        case nil:
            return nil
        case .wipeLog?:
            return ContestMessage("Vymazat celý deník (%s QSO)?", .int(logbook.rows.count))
        case .deleteLast?:
            guard let last = logbook.rows.last else { return ContestMessage("Deník je prázdný") }
            return ContestMessage("Smazat poslední QSO %s?", .string(last.call))
        case .exit?:
            return ContestMessage("Ukončit MacContestLogger?")
        }
    }

    /// The text of the open confirmation. WIPELOG adds the cluster note while `clusterConnected` (Kotlin
    /// `state.clusterConnected`: the one-time snapshot of the connection), read when the dialog is shown.
    public var confirmationText: EntryStatus? {
        switch confirmation {
        case nil:
            return nil
        case .wipeLog?:
            let base: EntryStatus = .tr("Smažou se všechna spojení aktuálního deníku a skóre se vynuluje. Akci nelze vzít zpět.")
            return base.appending(NetTexts.wipeNote(connected: clusterConnected()))
        case .deleteLast?:
            return .tr("Spojení se odstraní z deníku a skóre se přepočítá.")
        case .exit?:
            return .tr("Deník je uložený průběžně, nic se neztratí.")
        }
    }

    /// The confirm button's label: Kotlin writes "Vymazat" / "Smazat" outside `tr`, "Ukončit" through it.
    public var confirmationButton: ContestMessage? {
        switch confirmation {
        case nil: return nil
        case .wipeLog?: return .verbatim("Vymazat")
        case .deleteLast?: return .verbatim("Smazat")
        case .exit?: return ContestMessage("Ukončit")
        }
    }

    /// Whether the confirm button is enabled (Ctrl+D on an empty log: disabled).
    public var confirmationEnabled: Bool {
        confirmation != .deleteLast || !logbook.rows.isEmpty
    }

    /// Opens the operator window (OPON without a call, Ctrl+O).
    public func openOperator() {
        showOperator = true
    }

    public func closeOperator() {
        showOperator = false
    }

    /// „Přihlásit" of the operator window: `setOperator(call, persist)`.
    public func confirmOperator(call: String, persist: Bool) {
        showOperator = false
        operating.setOperator(call, persist: persist)
    }

    /// Waits for the actions started here (tests).
    func settle() async {
        while let task = work {
            await task.value
            if task == work {
                return
            }
        }
    }

    /// The actions run one after another (Kotlin runs them synchronously on the UI thread).
    private func run(_ body: @escaping @MainActor (DialogsModel) async -> Void) {
        let previous: Task<Void, Never>? = work
        work = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await body(self)
        }
    }
}

/// The two lines of a contest-browser row (Kotlin `ContestBrowser.kt`; program output, not translated).
public enum ContestBrowserText {

    /// `"${name}  (${year})"` — a missing name is Kotlin's `null`.
    public static func title(_ row: ContestBrowserRow) -> String {
        (row.name ?? "null") + "  (" + row.year + ")"
    }

    /// `"${dateRange} · ${qsoCount} QSO · ${bands} · ${category} · ${power}"`.
    public static func detail(_ row: ContestBrowserRow) -> String {
        let parts: [String] = [row.dateRange, String(row.qsoCount) + " QSO", row.bands, row.category, row.power]
        return parts.joined(separator: " · ")
    }
}
