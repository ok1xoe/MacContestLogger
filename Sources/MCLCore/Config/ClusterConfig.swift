import Foundation

/// Settings of the station's connection to the cluster (network multi-op logbook over MQTT). Stored
/// in `config.json`. When `enabled == false`, the station runs purely locally. Mirrors
/// `ClusterConfig.java`.
///
/// Note: the Java original carries fields of types `Interlock.Scope` (package `cluster/`) and
/// `OperatingGuard.StationType`/`Enforcement` (package `contest/engine/`) — so here it
/// refers to `Interlock`/`OperatingGuard` from `Sources/MCLCore/Cluster/` and
/// `Sources/MCLCore/Contest/Engine/`, not to its own nested copies: a type belongs where the
/// Java package puts it, even though for now only
/// its data shape (`Scope`/`StationType`/`Enforcement`) exists, not the real behaviour
/// (`Interlock.lockedBy`, `OperatingGuard.check`) — that will come with the port of those
/// packages. The same principle as moving `CutStyle` to `Sources/MCLCore/Keyer/`.
public struct ClusterConfig: Codable, Equatable, Sendable {

    public var enabled: Bool = false
    public var brokerHost: String = ""
    public var port: Int = 1883
    public var username: String = ""
    public var password: String = ""
    /// Stable station identifier = MQTT Client ID + QSO origin (e.g. `OP1`).
    public var stationId: String = ""
    /// TLS (ssl://, typically port 8883) for an untrusted LAN.
    public var tls: Bool = false
    /// Share spots from the DX cluster with other stations (N1MM Multi-User telnet).
    public var shareSpots: Bool = true
    public var interlock: Interlock.Scope = .none
    public var stationType: OperatingGuard.StationType = .none
    public var ruleEnforcement: OperatingGuard.Enforcement = .warn
    /// Serial numbers from the authority (serial number server) instead of local counting.
    public var serialServer: Bool = false
    /// N1MM Multi-two Run1/Run2: the number of a RUN station (1 or 2, 0 = none); the other stations see `RUN1` /
    /// `RUN2` as its type. Swift-only key.
    public var runNumber: Int = 0
    /// The columns of the Network Status station table in order (`NetworkStationColumn` names); empty = the default.
    /// Swift-only key.
    public var statusColumns: [String] = []

    enum CodingKeys: String, CodingKey {
        case enabled, brokerHost, port, username, password, stationId, tls, shareSpots
        case interlock, stationType, ruleEnforcement, serialServer
        case runNumber, statusColumns
    }

    /// The station type the other stations see: `RUN1` / `RUN2` for a numbered RUN station (N1MM Multi-two).
    public var announcedStationType: String {
        switch stationType {
        case .none: return ""
        case .run: return runNumber == 1 || runNumber == 2 ? "RUN" + String(runNumber) : "RUN"
        case .mult: return "MULT"
        }
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClusterConfig()
        enabled = c.value(.enabled, default: d.enabled)
        brokerHost = c.value(.brokerHost, default: d.brokerHost)
        port = c.value(.port, default: d.port)
        username = c.value(.username, default: d.username)
        password = c.value(.password, default: d.password)
        stationId = c.value(.stationId, default: d.stationId)
        tls = c.value(.tls, default: d.tls)
        shareSpots = c.value(.shareSpots, default: d.shareSpots)
        interlock = c.value(.interlock, default: d.interlock)
        stationType = c.value(.stationType, default: d.stationType)
        ruleEnforcement = c.value(.ruleEnforcement, default: d.ruleEnforcement)
        serialServer = c.value(.serialServer, default: d.serialServer)
        runNumber = c.value(.runNumber, default: d.runNumber)
        statusColumns = c.value(.statusColumns, default: d.statusColumns)
    }
}
