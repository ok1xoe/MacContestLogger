import Foundation

/// One step of applying a changed configuration (the Settings commit, `CD:554-614`, or a profile load,
/// `AS:2509-2522`), in the order Kotlin v1.1.1 runs it (`CD:` = `ui/configurer/ConfigurerDraft.kt`, `AS:` =
/// `ui/AppState.kt`). The plan only names the steps; the app layer runs them (the ones another subsystem owns go to
/// its injected port in the same order).
public enum ConfigEffect: Equatable, Sendable {

    /// The status shown when the write of `config.json` fails.
    public enum FailureStatus: Equatable, Sendable {
        /// The Settings commit: `tr(SettingsTexts.saveFailed, message)` (`CD:566`), the window stays open.
        case settingsSaveFailed
        /// The profile load: `SettingsTexts.profileFailurePrefix + message`, not translated (Kotlin's text for a
        /// failed profile read, `AS:2511`; Kotlin itself swallows a failed write there, `AS:2514`).
        case profileFailed
    }

    /// What a failed write of `config.json` does to the rest of the plan.
    public enum SaveFailure: Equatable, Sendable {
        /// Show `status` and run **no further effect**: the live configuration, the language and every live state
        /// stay unchanged (the atomic commit of and the atomic profile load).
        case abortPlan(status: FailureStatus)
    }

    /// The effects `AppState.saveConfig()` runs after the store write (`AS:3726-3736`), in its order. They run only
    /// when the write succeeded (an exception from `configStore.save` leaves the function). In Kotlin an exception
    /// from one of these too would reach `runCatching` at `CD:564` and report "save failed" although the file was
    /// written; the Swift effects do not throw, so that path does not exist.
    public enum SaveInner: Equatable, Sendable {
        /// `dxCluster.myCall = station.call` and the same for every parallel cluster (`AS:3730-3731`).
        case dxMyCall
        /// `syncParallelClusters()` — the favourites may have changed (`AS:3732`).
        case parallelClusters
        /// `reloadFootswitch()` (`AS:3733`).
        case footswitch
        /// `reloadScp()` + `reloadCallHistory()` (`AS:3735-3736`).
        case callData
    }

    /// Writes the configuration (`configStore.save`): the **applied draft** (commit) or the **merged copy** (profile
    /// load) while the live configuration is still the old one. Always the first effect of a plan.
    case saveConfig(onFailure: SaveFailure)
    /// The written value becomes the live configuration (Kotlin: `draft.applyTo(config)` / `profiles.loadInto`,
    /// both before the write).
    case applyConfig
    /// Commit only: `I18n.use(config.language)` — always, even with an unchanged language (`CD:513`).
    case switchLanguage
    /// The antenna table was written (a deliberate divergence from Java v1.1.1: `AntennaSelector` works by position instead of
    /// instance identity): the current antenna index becomes `nil`, the shown antenna value stays.
    case resetAntennaIndex
    case saveInner(SaveInner)
    /// `statusMessage = tr("Nastavení uloženo")` (`CD:569`).
    case statusSaved
    /// `updateCwSpeed(config.cwKeyer.speed)` (`CD:570`).
    case cwSpeed
    /// `syncEsmFromConfig()` (`CD:571`).
    case esm
    /// `syncRunModeFromConfig()` (`CD:572`).
    case runMode
    /// `syncRadioModeFromConfig()` (`CD:573`).
    case radioMode
    /// `applyModeSettings()` (`CD:574`).
    case modeSettings
    /// `checkClock()` (`CD:575`).
    case checkClock
    /// `reloadKeyBindings()` (`CD:576`).
    case keyBindings
    /// `configRevision++` (`CD:577`).
    case configRevision
    /// `dxCluster.setBufferMinutes(spotBufferMinutes)` (`CD:578`).
    case spotBuffer
    /// `dxCluster.spots.setMinSkimmers(minSkimmers)` (`CD:579`).
    case minSkimmers
    /// `applyDxClusterBlacklist()` (`CD:580`).
    case blacklist
    /// `reloadHamQth()` (`CD:581`).
    case hamQth
    /// `stopCluster()` + `startClusterIfEnabled()` (may overwrite the status with the connection state).
    case restartCluster
    /// `stopBroadcast()` + `startBroadcastIfEnabled()`.
    case restartBroadcast
    /// `stopWsjtx()` + `startWsjtxIfEnabled()`.
    case restartWsjtx
    /// `stopN1mm()` + `startN1mmIfEnabled()`.
    case restartN1mm
    /// `stopAdifUdp()` + `startAdifUdpIfEnabled()`.
    case restartAdifUdp
    /// `reloadContestData()` (`AS:3707-3709`).
    case reloadContestData
    /// `requestRescore()` (`CD:604`).
    case rescore
    /// `draft.writeBandData()`; a failure only sets `SettingsTexts.bandDataSaveFailed` (overwriting "saved") and the
    /// plan goes on (`CD:606-607`).
    case writeBandData
    /// `reloadBandData()` (`AS:3717-3724`).
    case reloadBandData
    /// `cat.disconnect(tr("překonfigurováno"))` when `disconnectFirst`, then `cat.connect(config.rig)` (`CD:609-612`).
    case reconnectCat(disconnectFirst: Bool)
    /// `statusMessage = tr(SettingsTexts.profileLoaded, name)` (`AS:2521`).
    case profileLoaded(name: String)
}

/// The eight "what changed" predicates of the commit (`CD:554-561`), computed over the **old** configuration
/// before the draft is applied.
public struct ConfigChanges: Equatable, Sendable {
    public var cluster: Bool
    public var broadcast: Bool
    public var wsjtx: Bool
    public var n1mm: Bool
    public var adifUdp: Bool
    public var contestDir: Bool
    public var rig: Bool
    public var scoringStation: Bool

    public init(
        cluster: Bool = false, broadcast: Bool = false, wsjtx: Bool = false, n1mm: Bool = false,
        adifUdp: Bool = false, contestDir: Bool = false, rig: Bool = false, scoringStation: Bool = false
    ) {
        self.cluster = cluster
        self.broadcast = broadcast
        self.wsjtx = wsjtx
        self.n1mm = n1mm
        self.adifUdp = adifUdp
        self.contestDir = contestDir
        self.rig = rig
        self.scoringStation = scoringStation
    }

    /// Nothing changed.
    public static let none = ConfigChanges()
}

/// The ordered effects of the Settings commit and of a profile load.
///
/// **Order difference from Kotlin (the commit is atomic).** Kotlin applies the draft to the live
/// configuration and switches the language (`draft.applyTo(state.config)`, `CD:563`, inside it `I18n.use`, `CD:513`,
/// and the new antenna instances, `CD:518`) **before** `saveConfig()`; a failed write therefore leaves the memory
/// changed. Swift writes first and checks: `.saveConfig(onFailure: .abortPlan(…))` is the first effect, and only after
/// it succeeds come `.applyConfig`, `.switchLanguage` and `.resetAntennaIndex` (the three parts of `applyTo` that
/// touch live state, in Kotlin's order), then the inner effects of `saveConfig` and the rest exactly as `CD:569-612`.
/// On a failed write nothing changes and no effect runs. After a success the observable result equals Kotlin's.
/// The profile load is atomic the same way (Kotlin merges into the live configuration and
/// swallows a failed write).
public enum ConfigEffectPlan {

    /// The inner effects of `AppState.saveConfig()` (`AS:3730-3736`), in order.
    public static let saveInnerEffects: [ConfigEffect] = [
        .saveInner(.dxMyCall), .saveInner(.parallelClusters), .saveInner(.footswitch), .saveInner(.callData),
    ]

    /// `commitConfigurer(state, draft, reconnectRig)` (`CD:554-614`).
    ///
    /// - Parameters:
    ///   - changes: the predicates over the old configuration (`CD:554-561`).
    ///   - reconnectRig: "Uložit a připojit" (save and connect).
    ///   - catConnected: `state.cat.connected`, sampled when the plan is built. Kotlin reads it at the end of the commit
    ///     in the same EDT turn; the executor must therefore run the plan without suspending between effects, or
    ///     re-read the connection state when it runs `.reconnectCat`.
    public static func commit(_ changes: ConfigChanges, reconnectRig: Bool, catConnected: Bool) -> [ConfigEffect] {
        var plan: [ConfigEffect] = [.saveConfig(onFailure: .abortPlan(status: .settingsSaveFailed))]
        plan += [.applyConfig, .switchLanguage, .resetAntennaIndex]
        plan += saveInnerEffects
        plan += [.statusSaved, .cwSpeed, .esm, .runMode, .radioMode, .modeSettings, .checkClock, .keyBindings]
        plan += [.configRevision, .spotBuffer, .minSkimmers, .blacklist, .hamQth]
        plan += restarts(changes)
        if changes.contestDir { plan.append(.reloadContestData) }
        if changes.scoringStation { plan.append(.rescore) }
        plan += [.writeBandData, .reloadBandData]
        if reconnectRig || (changes.rig && catConnected) {
            plan.append(.reconnectCat(disconnectFirst: catConnected))
        }
        return plan
    }

    /// `loadProfile(name)` after a successful `profiles.loadInto` (`AS:2509-2521`), made atomic: the profile is
    /// merged into a **copy** of the configuration outside the plan; the plan writes the copy first and only then
    /// makes it live. Kotlin merges into the live configuration and swallows a failed write (`runCatching`).
    ///
    /// - Parameter replacesAntennas: the profile file has the `antennas` key. Java's `ConfigProfiles` merges with
    ///   `List` not mergeable, so such a file replaces the `AntennaEntry` instances (identity lost →
    ///   `.resetAntennaIndex` right after the copy becomes live); a profile saved by the app always has the key.
    ///   Kotlin does **not** switch the language, start ESM or restart the clusters here.
    public static func profileLoad(name: String, replacesAntennas: Bool) -> [ConfigEffect] {
        var plan: [ConfigEffect] = [.saveConfig(onFailure: .abortPlan(status: .profileFailed)), .applyConfig]
        if replacesAntennas { plan.append(.resetAntennaIndex) }
        plan += saveInnerEffects
        plan += [.modeSettings, .keyBindings, .radioMode, .runMode, .reloadContestData, .configRevision]
        plan.append(.profileLoaded(name: name))
        return plan
    }

    /// The conditional restarts in Kotlin order (`CD:582-601`).
    private static func restarts(_ changes: ConfigChanges) -> [ConfigEffect] {
        var out: [ConfigEffect] = []
        if changes.cluster { out.append(.restartCluster) }
        if changes.broadcast { out.append(.restartBroadcast) }
        if changes.wsjtx { out.append(.restartWsjtx) }
        if changes.n1mm { out.append(.restartN1mm) }
        if changes.adifUdp { out.append(.restartAdifUdp) }
        return out
    }
}
