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
    /// Draw the US licence class sub-band edges on the band map scale (Swift-only key; off by default).
    public var showUsLicenseLines: Bool = false
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
    /// N1MM call-frame: a single click on a band map spot and tuning near a spot put the call into the call-frame
    /// above the call field (the space bar takes it); a double click fills the call field. Off = a click fills the
    /// call field at once (v1.1.1).
    public var callFrame: Bool = true
    /// N1MM tuning tolerance per mode (Hz, 0…20 000): how close to a spot the tuned frequency must be for its call
    /// to show in the call-frame.
    public var tuningToleranceCwHz: Int = DxClusterConfig.defaultTuningToleranceHz {
        didSet {
            let normalized = DxClusterConfig.normalizedTolerance(tuningToleranceCwHz)
            if normalized != tuningToleranceCwHz { tuningToleranceCwHz = normalized }
        }
    }
    public var tuningToleranceSsbHz: Int = DxClusterConfig.defaultTuningToleranceHz {
        didSet {
            let normalized = DxClusterConfig.normalizedTolerance(tuningToleranceSsbHz)
            if normalized != tuningToleranceSsbHz { tuningToleranceSsbHz = normalized }
        }
    }
    public var tuningToleranceDigiHz: Int = DxClusterConfig.defaultTuningToleranceHz {
        didSet {
            let normalized = DxClusterConfig.normalizedTolerance(tuningToleranceDigiHz)
            if normalized != tuningToleranceDigiHz { tuningToleranceDigiHz = normalized }
        }
    }
    /// N1MM "Always use packet spot mode": tuning to a spot also sets the mode of the spot (its comment, the digital
    /// frequencies, the band plan).
    public var spotModeOnTune: Bool = false
    /// The band map's programmable buttons (N1MM: up to 36, rows of four); see `BandmapButtonCommand`.
    public var bandmapButtons: [DxClusterCommand] = [] {
        didSet {
            if bandmapButtons.count > DxClusterConfig.bandmapButtonLimit {
                bandmapButtons = Array(bandmapButtons.prefix(DxClusterConfig.bandmapButtonLimit))
            }
        }
    }
    /// The filter widths of the band map's Wide/Narrow button (Hz, hamlib passband; N1MM "Transceiver Filter
    /// Codes").
    public var filterCwWideHz: Int = 500 { didSet { clampWidth(\.filterCwWideHz) } }
    public var filterCwNarrowHz: Int = 250 { didSet { clampWidth(\.filterCwNarrowHz) } }
    public var filterSsbWideHz: Int = 2_400 { didSet { clampWidth(\.filterSsbWideHz) } }
    public var filterSsbNarrowHz: Int = 1_800 { didSet { clampWidth(\.filterSsbNarrowHz) } }
    public var filterDigiWideHz: Int = 500 { didSet { clampWidth(\.filterDigiWideHz) } }
    public var filterDigiNarrowHz: Int = 250 { didSet { clampWidth(\.filterDigiNarrowHz) } }
    /// Old blacklist format (strings only) — kept for migration to
    /// `callBlacklist`/`spotterBlacklist`. Emptied after migration.
    public var blacklistedCalls: [String] = []
    public var blacklistedSpotters: [String] = []
    /// Application-side blacklist — entries with the time added and a note.
    public var callBlacklist: [BlacklistEntry] = []
    public var spotterBlacklist: [BlacklistEntry] = []
    /// Bands/Modes spot filter (Swift-only keys; v1.1.1 ignores them). Stored as the switched-off items so a
    /// configuration without the keys means "everything on, Contest off" and new bands default to visible.
    public var spotFilterHiddenBands: [String] = []
    public var spotFilterHiddenModes: [String] = []
    public var spotFilterContest: Bool = false
    /// "Filters" part: spotter continents / own country that pass (none = no filter), hide non-workable spots.
    public var spotFilterSpotterContinents: [String] = []
    public var spotFilterSpotterOwnCountry: Bool = false
    public var spotFilterHideNonWorkable: Bool = false
    /// Spotter prefixes and call areas of the origin filter, call history / worked, beacons, busted spots and the
    /// preferred spotters (see `SpotFilter`).
    public var spotFilterSpotterPrefixes: [String] = []
    public var spotFilterSpotterCallAreas: [String] = []
    public var spotFilterOnlyCallHistory: Bool = false
    public var spotFilterOnlyWorked: Bool = false
    public var spotFilterHideBeacons: Bool = false
    public var spotFilterRemoveBusted: Bool = false
    public var spotFilterBustedTwoChars: Bool = false
    public var spotFilterPreferredSpotters: [String] = []
    /// The blacklists apply (N1MM's enable checkbox); off keeps the lists but the buffer drops nothing.
    public var blacklistEnabled: Bool = true
    /// Band map: the lowest frequency at the bottom (N1MM „Show Lowest Freq at Bottom"; Swift-only key).
    public var bandmapLowestAtBottom: Bool = false
    /// Band map: the mouse wheel neither tunes nor zooms (N1MM „Disable Mouse Wheel"; Swift-only key).
    public var bandmapWheelDisabled: Bool = false
    /// The node software for the commands MCL builds (`ClusterSoftware` raw value; `auto` = from the greeting).
    public var clusterSoftware: String = ClusterSoftware.auto.rawValue
    /// N1MM „automatically log on to the selected cluster whenever the Telnet window is open".
    public var autoLogon: Bool = false
    /// N1MM „Show Telnet Buttons".
    public var showButtons: Bool = true
    /// N1MM „Comment For All Spots": the comment of every spot MCL makes, with `SpotComment` macros.
    public var spotComment: String = ""
    /// N1MM Config → „Spot all S&P QSOs": every S&P QSO not yet in the band map is spotted to the cluster (opt-in).
    public var spotAllSpQsos: Bool = false
    /// N1MM Special Calls: spots of these calls get a heart in the band map and the Available window.
    public var specialCalls: [String] = []
    /// The active contest's bonus stations (BONUS) count as special calls.
    public var specialCallsIncludeBonus: Bool = true
    /// The Available window's visible columns in their order (`AvailableColumn` ids; empty = the default order).
    public var availColumns: [String] = []
    /// The Available window's column widths (hundredths of a share, by column id; missing = the default).
    public var availColumnWidths: [String: Int] = [:]
    /// N1MM „Summary Panel Band Selection": the bands of the Available window's summary (ADIF; empty = the contest's).
    public var availSummaryBands: [String] = []
    /// N1MM „Show Summary Panel".
    public var availShowSummary: Bool = true
    /// How many spots the band map's SH/DX asks for.
    public var showDxCount: Int = ClusterCommandFormat.defaultShowDxCount {
        didSet {
            let normalized = ClusterCommandFormat.clampedCount(showDxCount)
            if normalized != showDxCount { showDxCount = normalized }
        }
    }
    /// N1MM „Save Spots": the spot buffer is saved at quit and restored at start (within its timeout).
    public var saveSpots: Bool = false
    /// N1MM „Randomize incoming spot frequencies": tuning to a spot lands a little off it.
    public var randomizeSpotFrequencies: Bool = false

    /// The filter as a value (see `SpotFilter`); setting it rewrites the three keys.
    public var spotFilter: SpotFilter {
        get {
            var filter = SpotFilter(hiddenBands: Set(spotFilterHiddenBands.compactMap { Band.from(adif: $0) }),
                                    hiddenModes: Set(spotFilterHiddenModes), contestOnly: spotFilterContest,
                                    spotterContinents: Set(spotFilterSpotterContinents),
                                    spotterOwnCountry: spotFilterSpotterOwnCountry,
                                    hideNonWorkable: spotFilterHideNonWorkable)
            filter.spotterPrefixes = SpotFilter.normalizedCalls(spotFilterSpotterPrefixes)
            filter.spotterCallAreas = Set(spotFilterSpotterCallAreas).intersection(SpotFilter.callAreas)
            filter.onlyCallHistory = spotFilterOnlyCallHistory
            filter.onlyWorked = spotFilterOnlyWorked
            filter.hideBeacons = spotFilterHideBeacons
            filter.removeBusted = spotFilterRemoveBusted
            filter.bustedTwoChars = spotFilterBustedTwoChars
            filter.preferredSpotters = spotFilterPreferredSpotters
            return filter
        }
        set {
            spotFilterHiddenBands = Band.allCases.filter { newValue.hiddenBands.contains($0) }.map(\.adif)
            spotFilterHiddenModes = SpotFilter.modes.filter { newValue.hiddenModes.contains($0) }
            spotFilterContest = newValue.contestOnly
            spotFilterSpotterContinents = SpotFilter.continents.filter { newValue.spotterContinents.contains($0) }
            spotFilterSpotterOwnCountry = newValue.spotterOwnCountry
            spotFilterHideNonWorkable = newValue.hideNonWorkable
            spotFilterSpotterPrefixes = newValue.spotterPrefixes
            spotFilterSpotterCallAreas = SpotFilter.callAreas.filter { newValue.spotterCallAreas.contains($0) }
            spotFilterOnlyCallHistory = newValue.onlyCallHistory
            spotFilterOnlyWorked = newValue.onlyWorked
            spotFilterHideBeacons = newValue.hideBeacons
            spotFilterRemoveBusted = newValue.removeBusted
            spotFilterBustedTwoChars = newValue.bustedTwoChars
            spotFilterPreferredSpotters = newValue.preferredSpotters
        }
    }

    enum CodingKeys: String, CodingKey {
        case favorites, commands, lastFavorite, spotBufferMinutes, autoSplit, showBandPlan
        case minSkimmers, wheelStepHz, wheelStepShiftHz, selfSpotThresholdHz
        case blacklistedCalls, blacklistedSpotters, callBlacklist, spotterBlacklist
        case spotFilterHiddenBands, spotFilterHiddenModes, spotFilterContest
        case spotFilterSpotterContinents, spotFilterSpotterOwnCountry, spotFilterHideNonWorkable
        case callFrame, tuningToleranceCwHz, tuningToleranceSsbHz, tuningToleranceDigiHz, spotModeOnTune
        case showUsLicenseLines
        case bandmapLowestAtBottom, bandmapWheelDisabled
        case bandmapButtons, filterCwWideHz, filterCwNarrowHz, filterSsbWideHz, filterSsbNarrowHz, filterDigiWideHz
        case filterDigiNarrowHz
        case clusterSoftware, autoLogon, showButtons, showDxCount
        case saveSpots, randomizeSpotFrequencies
        case spotFilterSpotterPrefixes, spotFilterSpotterCallAreas, spotFilterOnlyCallHistory, spotFilterOnlyWorked
        case spotFilterHideBeacons, spotFilterRemoveBusted, spotFilterBustedTwoChars, spotFilterPreferredSpotters
        case blacklistEnabled
        case spotComment, spotAllSpQsos, specialCalls, specialCallsIncludeBonus
        case availColumns, availColumnWidths, availSummaryBands, availShowSummary
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
        showUsLicenseLines = c.value(.showUsLicenseLines, default: d.showUsLicenseLines)
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
        spotFilterHiddenBands = c.value(.spotFilterHiddenBands, default: d.spotFilterHiddenBands)
        spotFilterHiddenModes = c.value(.spotFilterHiddenModes, default: d.spotFilterHiddenModes)
        spotFilterContest = c.value(.spotFilterContest, default: d.spotFilterContest)
        spotFilterSpotterContinents = c.value(.spotFilterSpotterContinents, default: d.spotFilterSpotterContinents)
        spotFilterSpotterOwnCountry = c.value(.spotFilterSpotterOwnCountry, default: d.spotFilterSpotterOwnCountry)
        spotFilterHideNonWorkable = c.value(.spotFilterHideNonWorkable, default: d.spotFilterHideNonWorkable)
        bandmapLowestAtBottom = c.value(.bandmapLowestAtBottom, default: d.bandmapLowestAtBottom)
        bandmapWheelDisabled = c.value(.bandmapWheelDisabled, default: d.bandmapWheelDisabled)
        callFrame = c.value(.callFrame, default: d.callFrame)
        tuningToleranceCwHz = DxClusterConfig.normalizedTolerance(
            c.value(.tuningToleranceCwHz, default: d.tuningToleranceCwHz))
        tuningToleranceSsbHz = DxClusterConfig.normalizedTolerance(
            c.value(.tuningToleranceSsbHz, default: d.tuningToleranceSsbHz))
        tuningToleranceDigiHz = DxClusterConfig.normalizedTolerance(
            c.value(.tuningToleranceDigiHz, default: d.tuningToleranceDigiHz))
        spotModeOnTune = c.value(.spotModeOnTune, default: d.spotModeOnTune)
        bandmapButtons = Array(c.value(.bandmapButtons, default: d.bandmapButtons).prefix(Self.bandmapButtonLimit))
        filterCwWideHz = Self.clampedWidth(c.value(.filterCwWideHz, default: d.filterCwWideHz))
        filterCwNarrowHz = Self.clampedWidth(c.value(.filterCwNarrowHz, default: d.filterCwNarrowHz))
        filterSsbWideHz = Self.clampedWidth(c.value(.filterSsbWideHz, default: d.filterSsbWideHz))
        filterSsbNarrowHz = Self.clampedWidth(c.value(.filterSsbNarrowHz, default: d.filterSsbNarrowHz))
        filterDigiWideHz = Self.clampedWidth(c.value(.filterDigiWideHz, default: d.filterDigiWideHz))
        filterDigiNarrowHz = Self.clampedWidth(c.value(.filterDigiNarrowHz, default: d.filterDigiNarrowHz))
        clusterSoftware = c.value(.clusterSoftware, default: d.clusterSoftware)
        autoLogon = c.value(.autoLogon, default: d.autoLogon)
        showButtons = c.value(.showButtons, default: d.showButtons)
        showDxCount = ClusterCommandFormat.clampedCount(c.value(.showDxCount, default: d.showDxCount))
        saveSpots = c.value(.saveSpots, default: d.saveSpots)
        randomizeSpotFrequencies = c.value(.randomizeSpotFrequencies, default: d.randomizeSpotFrequencies)
        spotFilterSpotterPrefixes = c.value(.spotFilterSpotterPrefixes, default: d.spotFilterSpotterPrefixes)
        spotFilterSpotterCallAreas = c.value(.spotFilterSpotterCallAreas, default: d.spotFilterSpotterCallAreas)
        spotFilterOnlyCallHistory = c.value(.spotFilterOnlyCallHistory, default: d.spotFilterOnlyCallHistory)
        spotFilterOnlyWorked = c.value(.spotFilterOnlyWorked, default: d.spotFilterOnlyWorked)
        spotFilterHideBeacons = c.value(.spotFilterHideBeacons, default: d.spotFilterHideBeacons)
        spotFilterRemoveBusted = c.value(.spotFilterRemoveBusted, default: d.spotFilterRemoveBusted)
        spotFilterBustedTwoChars = c.value(.spotFilterBustedTwoChars, default: d.spotFilterBustedTwoChars)
        spotFilterPreferredSpotters = c.value(.spotFilterPreferredSpotters, default: d.spotFilterPreferredSpotters)
        blacklistEnabled = c.value(.blacklistEnabled, default: d.blacklistEnabled)
        spotComment = c.value(.spotComment, default: d.spotComment)
        spotAllSpQsos = c.value(.spotAllSpQsos, default: d.spotAllSpQsos)
        specialCalls = c.value(.specialCalls, default: d.specialCalls)
        specialCallsIncludeBonus = c.value(.specialCallsIncludeBonus, default: d.specialCallsIncludeBonus)
        availColumns = c.value(.availColumns, default: d.availColumns)
        availColumnWidths = c.value(.availColumnWidths, default: d.availColumnWidths)
        availSummaryBands = c.value(.availSummaryBands, default: d.availSummaryBands)
        availShowSummary = c.value(.availShowSummary, default: d.availShowSummary)
    }

    /// N1MM's band map has at most 36 programmable buttons.
    public static let bandmapButtonLimit = 36
    /// The passband a rigctld `M` command accepts (`PluginCatPolicy`).
    public static let filterWidthRange: ClosedRange<Int> = 0...20_000

    /// The wide and narrow filter of `mode` (CW, phone, digital).
    public func filterWidths(_ mode: Mode) -> (wide: Int, narrow: Int) {
        switch mode {
        case .cw: return (filterCwWideHz, filterCwNarrowHz)
        case .ssb, .am, .fm: return (filterSsbWideHz, filterSsbNarrowHz)
        default: return (filterDigiWideHz, filterDigiNarrowHz)
        }
    }

    private mutating func clampWidth(_ field: WritableKeyPath<DxClusterConfig, Int>) {
        let value: Int = self[keyPath: field]
        let clamped: Int = Self.clampedWidth(value)
        if clamped != value { self[keyPath: field] = clamped }
    }

    static func clampedWidth(_ value: Int) -> Int {
        Swift.min(Swift.max(value, filterWidthRange.lowerBound), filterWidthRange.upperBound)
    }

    /// N1MM's default tuning tolerance (Hz).
    public static let defaultTuningToleranceHz = 300
    /// N1MM's limits of the tuning tolerance (Hz).
    public static let tuningToleranceRange: ClosedRange<Int> = 0...20_000

    /// The tuning tolerance of `mode`: CW, phone (SSB/AM/FM) or digital (RTTY and the rest).
    public func tuningToleranceHz(_ mode: Mode) -> Int {
        switch mode {
        case .cw: return tuningToleranceCwHz
        case .ssb, .am, .fm: return tuningToleranceSsbHz
        default: return tuningToleranceDigiHz
        }
    }

    static func normalizedTolerance(_ value: Int) -> Int {
        Swift.min(Swift.max(value, tuningToleranceRange.lowerBound), tuningToleranceRange.upperBound)
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
