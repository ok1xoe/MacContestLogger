import Foundation
import MCLCore

/// The effects of a saved configuration that belong to other subsystems, as injected main-actor
/// closures in the pattern of `AppModel.ShutdownServices`. Each is a no-op until the app wires it;
/// `SettingsModel.applyConfigChanges` calls them at their place in the Kotlin order (`ConfigEffectPlan`), so the
/// order never changes when a port is wired. The ports are synchronous: Kotlin runs the whole commit in one EDT turn.
public struct SettingsServices {
    /// Every effect as it runs, in order (tests record the plan as executed; production: nothing).
    public var trace: @MainActor (ConfigEffect) -> Void = { _ in }

    /// `AntennaSelector` index → `nil` after the antenna table was written.
    public var resetAntennaIndex: @MainActor () -> Void = {}
    /// `dxCluster.myCall` and the parallel clusters' `myCall` = the station call.
    public var dxMyCall: @MainActor () -> Void = {}
    /// `syncParallelClusters()`.
    public var parallelClusters: @MainActor () -> Void = {}
    /// `reloadFootswitch()`.
    public var footswitch: @MainActor () -> Void = {}
    /// `updateCwSpeed(config.cwKeyer.speed)` — the entry window has no CW speed state before the keyer.
    public var cwSpeed: @MainActor () -> Void = {}
    /// `syncRadioModeFromConfig()` — SO2V/SO2R and the OTRSP port.
    public var radioMode: @MainActor () -> Void = {}
    /// `applyModeSettings()` — `HamlibModes.configure`.
    public var modeSettings: @MainActor () -> Void = {}
    /// `checkClock()` — NTP.
    public var checkClock: @MainActor () -> Void = {}
    /// `dxCluster.setBufferMinutes`.
    public var spotBuffer: @MainActor () -> Void = {}
    /// `dxCluster.spots.setMinSkimmers`.
    public var minSkimmers: @MainActor () -> Void = {}
    /// `applyDxClusterBlacklist()`.
    public var blacklist: @MainActor () -> Void = {}
    /// `reloadHamQth()`.
    public var hamQth: @MainActor () -> Void = {}
    /// `stopCluster()` + `startClusterIfEnabled()` (may overwrite the status with the connection state).
    public var restartCluster: @MainActor () -> Void = {}
    /// `stopBroadcast()` + `startBroadcastIfEnabled()`.
    public var restartBroadcast: @MainActor () -> Void = {}
    /// `stopWsjtx()` + `startWsjtxIfEnabled()`.
    public var restartWsjtx: @MainActor () -> Void = {}
    /// `stopN1mm()` + `startN1mmIfEnabled()`.
    public var restartN1mm: @MainActor () -> Void = {}
    /// `stopAdifUdp()` + `startAdifUdpIfEnabled()`.
    public var restartAdifUdp: @MainActor () -> Void = {}
    /// `state.cat.connected` (no CAT before it).
    public var catConnected: @MainActor () -> Bool = { false }
    /// `cat.disconnect(tr("překonfigurováno"))` when the argument is `true`, then `cat.connect(config.rig)`.
    public var reconnectCat: @MainActor (_ disconnectFirst: Bool) -> Void = { _ in }
    /// `reportScoreNow()` after „Odeslat teď".
    public var reportScoreNow: @MainActor () -> Void = {}

    public init() {}
}
