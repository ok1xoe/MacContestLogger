import Foundation
import MCLCore
import Observation

/// The DX cluster blacklist (Kotlin `AS:473-500, 1029-1073`): the callsigns and spotters whose spots the buffer
/// drops, with the time added and a note, edited in the Blacklist window, from the bandmap and the available
/// multipliers (Alt+D / Alt+Shift+D), and in Settings.
///
/// A change writes `config.json` (Kotlin `runCatching { saveConfig() }` — a failure is swallowed) and
/// applies the blacklist to the buffer, nothing else. Kotlin's `saveConfig` would also re-plan the parallel
/// clusters, reopen the footswitch and reload SCP and the call history; those side effects are not run.
@Observable @MainActor
public final class BlacklistModel {

    /// Rises after every change of the lists (the window re-reads `entries`).
    public private(set) var revision: Int = 0

    @ObservationIgnored private let config: ConfigModel
    @ObservationIgnored private let spots: SpotBuffer
    @ObservationIgnored private let now: @Sendable () -> Date

    init(config: ConfigModel, spots: SpotBuffer, now: @escaping @Sendable () -> Date) {
        self.config = config
        self.spots = spots
        self.now = now
    }

    /// Kotlin `blacklistEntries(isCall)`: a copy of the callsign (`true`) or spotter (`false`) list.
    public func entries(isCall: Bool) -> [BlacklistEntry] {
        isCall ? config.config.dxCluster.callBlacklist : config.config.dxCluster.spotterBlacklist
    }

    /// Kotlin `applyDxClusterBlacklist()`: the skimmer threshold and both lists into the buffer.
    public func apply() {
        let dx: DxClusterConfig = config.config.dxCluster
        spots.setMinSkimmers(dx.minSkimmers)
        spots.setBlacklist(calls: BlacklistService.values(dx.callBlacklist),
                           spotters: BlacklistService.values(dx.spotterBlacklist))
    }

    /// Kotlin `migrateLegacyBlacklist()` (start-up): the old string lists merged into the entries and emptied, then
    /// saved (only the file).
    public func migrateLegacy() {
        var dx: DxClusterConfig = config.config.dxCluster
        if dx.blacklistedCalls.isEmpty && dx.blacklistedSpotters.isEmpty {
            return
        }
        let stamp: String = nowUtc()
        dx.callBlacklist = BlacklistService.migrate(dx.blacklistedCalls, dx.callBlacklist, nowUtc: stamp)
        dx.spotterBlacklist = BlacklistService.migrate(dx.blacklistedSpotters, dx.spotterBlacklist, nowUtc: stamp)
        dx.blacklistedCalls = []
        dx.blacklistedSpotters = []
        config.config.dxCluster = dx
        config.saveSilently()
        revision += 1
    }

    /// Kotlin `blacklistCall(call)`.
    public func blacklistCall(_ call: String) {
        add(isCall: true, value: call, note: "")
    }

    /// Kotlin `blacklistSpotter(spotter)`.
    public func blacklistSpotter(_ spotter: String) {
        add(isCall: false, value: spotter, note: "")
    }

    /// Kotlin `blacklistAdd(isCall, value, note)` (time = `Instant.now().toString()`).
    public func add(isCall: Bool, value: String, note: String) {
        let stamp: String = nowUtc()
        edit(isCall) { BlacklistService.add(&$0, value, note: note, nowUtc: stamp) }
    }

    /// Kotlin `blacklistRemove`.
    public func remove(isCall: Bool, value: String) {
        edit(isCall) { BlacklistService.remove(&$0, value) }
    }

    /// Kotlin `blacklistUpdateValue`.
    public func updateValue(isCall: Bool, oldValue: String, newValue: String) {
        edit(isCall) { BlacklistService.updateValue(&$0, oldValue, newValue) }
    }

    /// Kotlin `blacklistSetNote`.
    public func setNote(isCall: Bool, value: String, note: String) {
        edit(isCall) { BlacklistService.setNote(&$0, value, note) }
    }

    /// Kotlin `persistBlacklist(changed)` around one list operation.
    private func edit(_ isCall: Bool, _ operation: (inout [BlacklistEntry]) -> Bool) {
        var list: [BlacklistEntry] = entries(isCall: isCall)
        let changed: Bool = operation(&list)
        // Kotlin edits the live list in place, so even an unchanged result (`remove` of a blank value that dropped
        // blank entries) stays in memory; only a change is saved.
        if isCall {
            config.config.dxCluster.callBlacklist = list
        } else {
            config.config.dxCluster.spotterBlacklist = list
        }
        guard changed else { return }
        config.saveSilently()
        apply()
        revision += 1
    }

    private func nowUtc() -> String {
        JavaInstant(date: now()).toString()
    }
}
