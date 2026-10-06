import Foundation
import MCLCore
import Observation

/// The Settings window (Kotlin `ConfigurerWindow`, `CW:55-140`, and `AppState.openConfigurer`/`closeConfigurer`/
/// `applyPendingSettingsTab`, `AS:1810-1823, 2697-2714`): which tabs it shows, the selected tab and the draft of the
/// configuration the tabs edit. OK commits the draft (`SettingsModel+Commit`), Cancel, Esc and the close button drop
/// it.
///
/// - The tab specs are built from the current menu (`MenuModel.tree`) at **every** opening (Kotlin
///   `remember(menuConfig)`: after „Načíst menu znovu" the new ones apply).
/// - The draft is made once per opened window, off the main thread (the band plan and the digi
///   frequencies are read from the old `contestDataDir` on the blocking queue); the window shows only the sidebar
///   until it is there. Closing the window before the read finished drops the late draft.
/// - Opening while the window is open keeps the draft (Kotlin's draft lives as long as the window), selects the
///   first enabled tab again and then the pending deep link.
@Observable @MainActor
public final class SettingsModel {

    /// The SwiftUI window id of the Settings window.
    public static let windowId = "settings"

    /// The window is open (Kotlin `configurerOpen`).
    public private(set) var isOpen: Bool = false
    /// The visible tabs (`HIDDEN` left out, `DISABLE` shown grey).
    public private(set) var specs: [ConfigurerTabSpec] = []
    /// The selected tab (Kotlin `configurerTab`).
    public private(set) var selected: ConfigurerTab = .hardware
    /// The edited configuration; `nil` while it is being read.
    public var draft: ConfigurerDraft?
    /// The draft as it was read from the committed configuration (opening, or the last Apply); `draft` differs
    /// from it exactly when there is something to apply.
    public private(set) var savedDraft: ConfigurerDraft?
    /// The draft has edits not yet committed (enables „Použít").
    public var hasChanges: Bool {
        guard let draft else { return false }
        return draft != savedDraft
    }
    /// A commit is running (OK, „Uložit a připojit" and „Odeslat teď" are disabled).
    public internal(set) var isSaving: Bool = false

    /// The ports of the effects owned by other subsystems.
    @ObservationIgnored public var services: SettingsServices

    @ObservationIgnored let config: ConfigModel
    @ObservationIgnored let language: LanguageModel
    @ObservationIgnored let status: StatusModel
    @ObservationIgnored let menu: MenuModel
    @ObservationIgnored let windows: WindowsModel
    @ObservationIgnored let contest: ContestModel
    @ObservationIgnored let callData: CallDataModel
    @ObservationIgnored let operating: OperatingModel
    @ObservationIgnored let dataDir: URL
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var draftGeneration: Int = 0
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored var commitTask: Task<Bool, Never>?
    /// `cancel()` came while a commit was writing: the window closes when the commit ends.
    @ObservationIgnored var closeWhenSaved: Bool = false

    struct Dependencies {
        let config: ConfigModel
        let language: LanguageModel
        let status: StatusModel
        let menu: MenuModel
        let windows: WindowsModel
        let contest: ContestModel
        let callData: CallDataModel
        let operating: OperatingModel
        let dataDir: URL
        let now: @Sendable () -> Date
        let services: SettingsServices
    }

    init(_ dependencies: Dependencies) {
        config = dependencies.config
        language = dependencies.language
        status = dependencies.status
        menu = dependencies.menu
        windows = dependencies.windows
        contest = dependencies.contest
        callData = dependencies.callData
        operating = dependencies.operating
        dataDir = dependencies.dataDir
        now = dependencies.now
        services = dependencies.services
    }

    /// `AppPaths.defaultContestDataDir()` of this data directory, as text.
    var defaultContestDataDir: String {
        dataDir.appendingPathComponent("contest-data").path
    }

    /// The menu action `settings.open` (`openConfigurer(tabSpecs)`), with the deep link of MSGS/WKEY/NETCONFIG/
    /// FUNCTION_KEYS_SETUP (`applyPendingSettingsTab`): the specs from the current menu, the first enabled tab, then
    /// the tab `tabKey` when it is visible — a disabled one too (Kotlin `firstOrNull { it.tab.key == key }`).
    /// The window is asked to the front; a closed one gets a new draft.
    public func open(tabKey: String? = nil) {
        var menuConfig = MenuConfig()
        menuConfig.menu = menu.tree
        specs = ConfigurerTabSpecs.build(menu: menuConfig)
        selected = ConfigurerTabSpecs.firstEnabled(specs)
        // A reopen during a write wants the window (the close asked before is void).
        closeWhenSaved = false
        if !isOpen {
            isOpen = true
            startDraft()
        }
        if let tabKey {
            applyDeepLink(tabKey)
        }
        windows.requestWindow(Self.windowId)
    }

    /// `applyPendingSettingsTab()`: selects the visible tab with the key (disabled too); nothing when the window is
    /// closed or the key is not shown.
    public func applyDeepLink(_ key: String) {
        guard isOpen, let tab = ConfigurerTabSpecs.deepLink(specs, key: key) else { return }
        selected = tab
    }

    /// A click in the sidebar: only an enabled tab can be chosen (a disabled one is grey and not selectable).
    public func select(_ tab: ConfigurerTab) {
        guard specs.contains(where: { $0.tab == tab && $0.state == .enable }) else { return }
        selected = tab
    }

    /// Cancel, Esc (on release) and the close button (`closeConfigurer`): the draft is dropped, nothing changes.
    ///
    /// While a commit is writing, nothing is dropped: the close is only noted and happens when the commit ends
    /// (OK followed by ⌘Q must not lose the settings).
    public func cancel() {
        guard isOpen else { return }
        if isSaving {
            closeWhenSaved = true
            return
        }
        closeWhenSaved = false
        isOpen = false
        draft = nil
        savedDraft = nil
        draftGeneration += 1
        draftTask = nil
    }

    /// Waits for the draft read and a commit in flight (tests, shutdown).
    func settle() async {
        await draftTask?.value
        _ = await commitTask?.value
    }

    /// Kotlin `remember { ConfigurerDraft(state.config) }`: the configuration as it is now, the band data read off
    /// the main thread from the old `contestDataDir` (Kotlin reads them on the EDT). A blank directory means the
    /// default one (`ContestEnvironment.dataRoot`), as for the contest data and `reloadBandData` — Kotlin's
    /// `Path.of(contestDataDir ?: default)` would read `""` relative to the process directory and then overwrite the
    /// default tables with empty ones (a fixed divergence).
    private func startDraft() {
        draftGeneration += 1
        let generation: Int = draftGeneration
        draft = nil
        savedDraft = nil
        let snapshot: AppConfig = config.config
        let defaultDir: String = defaultContestDataDir
        let dir: URL = ContestEnvironment.dataRoot(configured: snapshot.contestDataDir, fallback: defaultDir)
        draftTask = Task { [weak self] in
            let tables: ([BandPlanFile.Segment], DigiFreqFile.Table)? = try? await BlockingQueue.run {
                (BandPlanFile.read(dir), DigiFreqFile.read(dir))
            }
            guard let self, let tables, generation == self.draftGeneration, self.isOpen else { return }
            let fresh = ConfigurerDraft(config: snapshot, bandSegments: tables.0, digi: tables.1,
                                        defaultContestDataDir: defaultDir)
            self.draft = fresh
            self.savedDraft = fresh
        }
    }

    /// After Apply: the draft is read again from the committed configuration (and the band data from the new
    /// directory) so further edits start from the saved state. Edits made while it was read are kept; they only
    /// stay marked as unsaved.
    func rereadDraft(committed: ConfigurerDraft) async {
        let snapshot: AppConfig = config.config
        let defaultDir: String = defaultContestDataDir
        let dir: URL = ContestEnvironment.dataRoot(configured: snapshot.contestDataDir, fallback: defaultDir)
        let tables: ([BandPlanFile.Segment], DigiFreqFile.Table)? = try? await BlockingQueue.run {
            (BandPlanFile.read(dir), DigiFreqFile.read(dir))
        }
        guard isOpen, let tables else { return }
        let fresh = ConfigurerDraft(config: snapshot, bandSegments: tables.0, digi: tables.1,
                                    defaultContestDataDir: defaultDir)
        if draft == committed {
            draft = fresh
        }
        savedDraft = fresh
    }
}
