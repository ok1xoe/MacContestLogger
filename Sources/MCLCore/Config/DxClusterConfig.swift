import Foundation

/// DX cluster settings (telnet spotting network) stored in `config.json`.
/// Holds the list of favorite clusters (`DxClusterFavorite`) and a shared set of
/// preset command buttons (`DxClusterCommand`). Mirrors `DxClusterConfig.java`.
///
/// Note: not to be confused with `ClusterConfig` — that is the MQTT "cluster sync" (network multi-op
/// logbook). This is the classic DX cluster over telnet.
public struct DxClusterConfig: Codable, Equatable, Sendable {

    /// How many command buttons the window shows (pads/trims the stored list).
    public static let commandCount = 10

    public var favorites: [DxClusterFavorite] = []
    /// Always non-empty — an empty or missing list is replaced with `defaultCommands()`.
    public var commands: [DxClusterCommand] = DxClusterConfig.defaultCommands() {
        didSet {
            let normalized = DxClusterConfig.normalizedCommands(commands)
            if normalized != commands { commands = normalized }
        }
    }
    /// Name of the last selected favorite (preselected when the window opens).
    public var lastFavorite: String = ""
    public var spotBufferMinutes: Int = 90 {
        didSet {
            let normalized = DxClusterConfig.normalizedSpotBufferMinutes(spotBufferMinutes)
            if normalized != spotBufferMinutes { spotBufferMinutes = normalized }
        }
    }
    /// A click on a spot with "UP 5" / "QSX 14025" in the comment turns on split to that frequency.
    public var autoSplit: Bool = true
    /// Tint the bandplan segments in the bandmap (CW / digi / phone).
    public var showBandPlan: Bool = true
    /// Skimmer / RBN spots: 0 = hide, 1 = all, n = confirmed by at least n skimmers.
    public var minSkimmers: Int = 1 {
        didSet {
            let normalized = max(0, minSkimmers)
            if normalized != minSkimmers { minSkimmers = normalized }
        }
    }
    public var wheelStepHz: Int = 100 {
        didSet {
            let normalized = DxClusterConfig.normalizedWheelStepHz(wheelStepHz)
            if normalized != wheelStepHz { wheelStepHz = normalized }
        }
    }
    /// Tuning-wheel step with Shift held (Hz).
    public var wheelStepShiftHz: Int = 1000 {
        didSet {
            let normalized = DxClusterConfig.normalizedWheelStepShiftHz(wheelStepShiftHz)
            if normalized != wheelStepShiftHz { wheelStepShiftHz = normalized }
        }
    }
    /// Detune threshold for creating a self-spot (Hz).
    public var selfSpotThresholdHz: Int = 2500 {
        didSet {
            let normalized = DxClusterConfig.normalizedSelfSpotThresholdHz(selfSpotThresholdHz)
            if normalized != selfSpotThresholdHz { selfSpotThresholdHz = normalized }
        }
    }
    /// Old blacklist format (strings only) — kept for migration to
    /// `callBlacklist`/`spotterBlacklist`. Emptied after migration.
    public var blacklistedCalls: [String] = []
    public var blacklistedSpotters: [String] = []
    /// Application-side blacklist — entries with the time added and a note.
    public var callBlacklist: [BlacklistEntry] = []
    public var spotterBlacklist: [BlacklistEntry] = []

    enum CodingKeys: String, CodingKey {
        case favorites, commands, lastFavorite, spotBufferMinutes, autoSplit, showBandPlan
        case minSkimmers, wheelStepHz, wheelStepShiftHz, selfSpotThresholdHz
        case blacklistedCalls, blacklistedSpotters, callBlacklist, spotterBlacklist
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DxClusterConfig()
        favorites = c.value(.favorites, default: d.favorites)
        commands = DxClusterConfig.normalizedCommands(c.value(.commands, default: d.commands))
        lastFavorite = c.value(.lastFavorite, default: d.lastFavorite)
        spotBufferMinutes = DxClusterConfig.normalizedSpotBufferMinutes(
            c.value(.spotBufferMinutes, default: d.spotBufferMinutes))
        autoSplit = c.value(.autoSplit, default: d.autoSplit)
        showBandPlan = c.value(.showBandPlan, default: d.showBandPlan)
        minSkimmers = max(0, c.value(.minSkimmers, default: d.minSkimmers))
        wheelStepHz = DxClusterConfig.normalizedWheelStepHz(c.value(.wheelStepHz, default: d.wheelStepHz))
        wheelStepShiftHz = DxClusterConfig.normalizedWheelStepShiftHz(
            c.value(.wheelStepShiftHz, default: d.wheelStepShiftHz))
        selfSpotThresholdHz = DxClusterConfig.normalizedSelfSpotThresholdHz(
            c.value(.selfSpotThresholdHz, default: d.selfSpotThresholdHz))
        blacklistedCalls = c.value(.blacklistedCalls, default: d.blacklistedCalls)
        blacklistedSpotters = c.value(.blacklistedSpotters, default: d.blacklistedSpotters)
        callBlacklist = c.value(.callBlacklist, default: d.callBlacklist)
        spotterBlacklist = c.value(.spotterBlacklist, default: d.spotterBlacklist)
    }

    /// Default set of `commandCount` commands (common DXSpider commands).
    public static func defaultCommands() -> [DxClusterCommand] {
        [
            DxClusterCommand(label: "SH/DX", command: "SH/DX"),
            DxClusterCommand(label: "SH/DX 25", command: "SH/DX 25"),
            DxClusterCommand(label: "SH/DX 20m", command: "SH/DX ON 20M"),
            DxClusterCommand(label: "SH/DX 40m", command: "SH/DX ON 40M"),
            DxClusterCommand(label: "WWV", command: "SH/WWV"),
            DxClusterCommand(label: "WCY", command: "SH/WCY"),
            DxClusterCommand(label: "Uživatelé", command: "SH/USERS"),
            DxClusterCommand(label: "Cluster", command: "SH/CLUSTER"),
            DxClusterCommand(label: "Moje info", command: "SH/STATION"),
            DxClusterCommand(label: "Nápověda", command: "HELP"),
        ]
    }

    private static func normalizedCommands(_ list: [DxClusterCommand]) -> [DxClusterCommand] {
        list.isEmpty ? defaultCommands() : list
    }

    private static func normalizedSpotBufferMinutes(_ value: Int) -> Int {
        value <= 0 ? 90 : value
    }

    private static func normalizedWheelStepHz(_ value: Int) -> Int {
        value <= 0 ? 100 : value
    }

    private static func normalizedWheelStepShiftHz(_ value: Int) -> Int {
        value <= 0 ? 1000 : value
    }

    private static func normalizedSelfSpotThresholdHz(_ value: Int) -> Int {
        value <= 0 ? 2500 : value
    }
}
