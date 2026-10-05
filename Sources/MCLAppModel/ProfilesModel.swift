import Foundation
import MCLCore
import Observation

/// Configuration profiles (Kotlin `ProfilesWindow`, `PW:1-67`, and `AS:2502-2527`; N1MM/DXLog profiles): save the
/// current configuration under a name, load one into it, delete one. Files in `<data>/profiles/` (`ConfigProfiles`).
///
/// Loading merges the profile like Jackson (`ProfileMerge`) and is **atomic**: a profile Jackson would reject
/// halfway, or a failed write, leaves the configuration unchanged (Kotlin keeps the half-merged live object and
/// swallows the write failure); the effects run through `SettingsModel.applyConfigChanges`. The
/// listing, reading and writing run off the main thread; the list is read again after every action and when the
/// window opens.
@Observable @MainActor
public final class ProfilesModel {

    /// The saved profiles (Kotlin `profiles.list()`, Java order).
    public private(set) var names: [String] = []

    @ObservationIgnored private let profiles: ConfigProfiles<AppConfig>
    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let settings: SettingsModel
    @ObservationIgnored private var listGeneration: Int = 0
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var nextTaskId: Int = 0

    init(dir: URL, config: ConfigModel, status: StatusModel, settings: SettingsModel) {
        profiles = ConfigProfiles<AppConfig>(dir: dir)
        self.config = config
        self.status = status
        self.settings = settings
    }

    /// Reads the list off the main thread (a slower older listing never replaces a newer one).
    public func refresh() async {
        listGeneration += 1
        let generation: Int = listGeneration
        let profiles: ConfigProfiles<AppConfig> = self.profiles
        let listed: [String]? = try? await BlockingQueue.run {
            profiles.list()
        }
        guard let listed, generation == listGeneration else { return }
        names = listed
    }

    /// „Uložit aktuální" (Kotlin `if (name.isNotBlank()) state.saveProfile(name)`): the current configuration under
    /// the trimmed name; status `tr("Profil „%s“ uložen")`, or `"Profil: " + message`.
    public func save(name: String) async {
        guard !KotlinStrings.isBlank(name) else { return }
        let trimmed: String = KotlinStrings.trim(name)
        let snapshot: AppConfig = config.config
        let profiles: ConfigProfiles<AppConfig> = self.profiles
        do {
            try await BlockingQueue.run {
                try profiles.save(trimmed, snapshot)
            }
            status.show("Profil „%s“ uložen", .string(trimmed))
        } catch {
            status.showVerbatim("Profil: " + ErrorText.message(error))
        }
        await refresh()
    }

    /// Kotlin `loadProfile(name)` (`AS:2509-2522`) through the executor of the Settings commit
    /// (`ConfigEffectPlan.profileLoad`): the profile merged into a **copy** of the configuration (`ProfileMerge`),
    /// the copy written, then made live, the inner effects of `saveConfig` (DX cluster call, parallel clusters,
    /// footswitch — other subsystems' ports — and `master.scp` + call history), the mode settings, the key
    /// bindings (read live), the radio mode, Alt+F11 (`syncRunModeFromConfig`), the contest data reloaded,
    /// `configRevision` and the text. The language is **not** switched (Kotlin does not call `I18n.use`); the look
    /// follows the configuration. ESM and the network restarts are not part of it (Kotlin).
    ///
    /// Atomic (unlike Kotlin, which merges into the live object and swallows a failed write): a failure to read,
    /// merge or write shows `"Profil: " + message` and changes nothing.
    public func load(_ name: String) async {
        let id: Int = nextTaskId
        nextTaskId += 1
        let task = Task { [weak self] in
            await self?.performLoad(name)
            self?.tasks[id] = nil
        }
        tasks[id] = task
        await task.value
    }

    /// A profile load is in flight (its config write not yet adopted).
    var isLoading: Bool {
        !tasks.isEmpty
    }

    /// Waits for the profile loads in flight (tests, shutdown).
    func settle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }

    private func performLoad(_ name: String) async {
        let profiles: ConfigProfiles<AppConfig> = self.profiles
        let read: (data: Data, replacesAntennas: Bool)
        do {
            read = try await BlockingQueue.run {
                let data: Data = try profiles.profileData(name)
                return (data, ProfilesModel.hasAntennasKey(data))
            }
        } catch {
            status.showVerbatim(SettingsTexts.profileFailurePrefix + ErrorText.message(error))
            await refresh()
            return
        }
        // Merged on the main thread over the configuration as it is now: no edit made meanwhile is lost.
        let base: AppConfig = config.config
        let merged: AppConfig
        do {
            merged = try ProfileMerge.merge(current: base, profileData: read.data)
        } catch {
            // Never the partial state (`ProfileMergeError.partial`): the load is atomic.
            status.showVerbatim(SettingsTexts.profileFailurePrefix + IoTexts.template(error.javaMessage))
            await refresh()
            return
        }
        let data: Data = read.data
        let application = ConfigApplication(config: merged, base: base) { live in
            try? ProfileMerge.merge(current: live, profileData: data)
        }
        let plan: [ConfigEffect] = ConfigEffectPlan.profileLoad(name: name, replacesAntennas: read.replacesAntennas)
        await settings.applyConfigChanges(plan, application)
        await refresh()
    }

    /// The profile file has the top-level key `antennas` (Java's `ConfigProfiles` then replaces the `AntennaEntry`
    /// instances, `List` is not mergeable). A file that is not a JSON object has none (the merge rejects it anyway).
    nonisolated static func hasAntennasKey(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let fields = object as? [String: Any] else {
            return false
        }
        return fields["antennas"] != nil
    }

    /// Kotlin `deleteProfile(name)`: no confirmation, no text; a failure is silent (`runCatching`).
    public func delete(_ name: String) async {
        let profiles: ConfigProfiles<AppConfig> = self.profiles
        _ = try? await BlockingQueue.run {
            try profiles.delete(name)
        }
        await refresh()
    }
}
