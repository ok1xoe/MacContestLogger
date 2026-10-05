import Foundation

/// The NETON and NETOFF commands of the call field (`AppState.networkOn`/`networkOff`, `AS:1259-1280`).
public enum NetworkCommands {

    public static let notConfiguredKey = "Síť není nastavená — vyplň Nastavení → Cluster"
    public static let alreadyRunningKey = "Síťová synchronizace už běží"
    public static let offKey = "Síťová synchronizace vypnuta — loguji lokálně"

    /// What NETON does.
    public enum OnOutcome: Sendable, Equatable {
        /// The broker host or the station ID is blank: only this status.
        case notConfigured(EntryStatus)
        /// The synchronisation already runs: only this status.
        case alreadyRunning(EntryStatus)
        /// Set `cluster.enabled = true`, save the configuration (a failure is ignored) and start the cluster.
        case start
    }

    /// `networkOn`: blank host or ID (Kotlin `isBlank`) → not configured; a running coordinator → already running.
    public static func on(config: ClusterConfig, running: Bool) -> OnOutcome {
        if KotlinText.isBlank(config.brokerHost) || KotlinText.isBlank(config.stationId) {
            return .notConfigured(.tr(notConfiguredKey))
        }
        if running {
            return .alreadyRunning(.tr(alreadyRunningKey))
        }
        return .start
    }

    /// `networkOff`: stop the cluster, set `cluster.enabled = false`, save the configuration (a failure is ignored),
    /// then show this status.
    public static let off: EntryStatus = .tr(offKey)
}
