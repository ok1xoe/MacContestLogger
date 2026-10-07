import Foundation

/// The spot filter of the DX cluster (modelled on N1MM+'s Telnet window: the "Bands/Modes" and "Filters" tabs).
///
/// The filter is applied when spots are *read* (the DX Cluster window's spot lines, band map, Available Mults, spot
/// navigation); the spot buffer is never changed, so a changed filter applies to the existing spots and unhiding
/// brings them back at once. Command replies and other console text, the plugin `spot-received` events and the
/// spots shared over the network are not filtered (every station applies its own filter).
///
/// - **Bands/Modes:** a spot is hidden when its band is switched off, or when its mode category (CW / PHONE /
///   DIGI, the inference the band map uses: comment, digi calibration frequency, band plan) is switched off. A spot
///   without a band is never hidden by the band switches; a spot whose mode cannot be determined is shown unless all
///   three modes are switched off.
/// - **Contest** / **non-workable:** with an active contest, a spot must be on a band of the contest definition
///   (when it lists bands) and in a mode category the definition allows (when it lists modes). `contestOnly` (the
///   Bands/Modes tab) and `hideNonWorkable` (the Filters tab) use the same rule of the contest definition — the
///   definitions have no other "cannot be worked" rule. Dupes stay. Without a contest both have no effect.
/// - **Spotter origin:** with continents and/or "own country" checked, only spots from spotters located there
///   (the spotter's DXCC from its call, `-#`/`-n` suffixes stripped) stay; nothing checked = no filter; a spotter
///   that cannot be resolved is hidden while the filter is on.
/// - Own spots (Mark, Store, self-spots) are never hidden.
public struct SpotFilter: Equatable, Sendable {

    /// A named group of bands (the group buttons).
    public enum Group: String, CaseIterable, Sendable {
        case hf = "HF"
        case vhf = "VHF"
        case uhf = "UHF"
        case microwave = "Mw"

        /// The bands of MCL's `Band` that belong to the group.
        public var bands: [Band] {
            switch self {
            case .hf: [.m160, .m80, .m60, .m40, .m30, .m20, .m17, .m15, .m12, .m10]
            case .vhf: [.m6, .m2]
            case .uhf: [.cm70, .cm23]
            case .microwave: [.cm13, .cm9, .cm6, .cm3]
            }
        }
    }

    /// The mode categories of the filter, in display order (`SpotModeCategory` values).
    public static let modes: [String] = [SpotModeCategory.cw, SpotModeCategory.phone, SpotModeCategory.digi]

    public var hiddenBands: Set<Band> = []
    public var hiddenModes: Set<String> = []
    public var contestOnly: Bool = false
    /// Spotter continents that pass (`Self.continents` codes); empty (with `spotterOwnCountry` off) = no filter.
    public var spotterContinents: Set<String> = []
    /// Spotters located in my own DXCC entity pass.
    public var spotterOwnCountry: Bool = false
    /// Hide the spots the active contest does not allow working (band / mode).
    public var hideNonWorkable: Bool = false

    /// The continent codes of the spotter-origin checkboxes.
    public static let continents: [String] = ["EU", "NA", "SA", "AS", "AF", "OC"]

    public init(hiddenBands: Set<Band> = [], hiddenModes: Set<String> = [], contestOnly: Bool = false,
                spotterContinents: Set<String> = [], spotterOwnCountry: Bool = false,
                hideNonWorkable: Bool = false) {
        self.hiddenBands = hiddenBands
        self.hiddenModes = hiddenModes.intersection(Self.modes)
        self.contestOnly = contestOnly
        self.spotterContinents = spotterContinents.intersection(Self.continents)
        self.spotterOwnCountry = spotterOwnCountry
        self.hideNonWorkable = hideNonWorkable
    }

    /// The origin filter is on.
    public var spotterFilterOn: Bool {
        !spotterContinents.isEmpty || spotterOwnCountry
    }

    public mutating func setContinent(_ code: String, on: Bool) {
        guard Self.continents.contains(code) else { return }
        if on { spotterContinents.insert(code) } else { spotterContinents.remove(code) }
    }

    /// Everything on, "Contest" off — the "Obnovit výchozí" state.
    public static let `default` = SpotFilter()

    /// `true` when the filter lets everything through (no work to do per spot).
    public var isDefault: Bool {
        self == .default
    }

    // MARK: - editing

    public func isBandOn(_ band: Band) -> Bool {
        !hiddenBands.contains(band)
    }

    public mutating func setBand(_ band: Band, on: Bool) {
        if on { hiddenBands.remove(band) } else { hiddenBands.insert(band) }
    }

    /// `true` when every band of the group is on.
    public func isGroupOn(_ group: Group) -> Bool {
        group.bands.allSatisfy(isBandOn)
    }

    /// The group button: when the whole group is on, switch it off; otherwise switch it all on.
    public mutating func toggleGroup(_ group: Group) {
        let target: Bool = !isGroupOn(group)
        for band in group.bands {
            setBand(band, on: target)
        }
    }

    public func isModeOn(_ mode: String) -> Bool {
        !hiddenModes.contains(mode)
    }

    public mutating func setMode(_ mode: String, on: Bool) {
        guard Self.modes.contains(mode) else { return }
        if on { hiddenModes.remove(mode) } else { hiddenModes.insert(mode) }
    }

    /// The "All Modes" button: every mode on.
    public mutating func allModes() {
        hiddenModes = []
    }

    /// "Obnovit výchozí": all bands and modes on, Contest off.
    public mutating func reset() {
        self = .default
    }

    // MARK: - filtering

    /// Whether the spot stays visible.
    /// - Parameters:
    ///   - analyzer: the spot analysis (mode inference and the active contest); `nil` = no inference possible
    public func allows(_ spot: DxSpot, analyzer: SpotAnalyzer?) -> Bool {
        if spot.selfSpotted || isDefault { return true }
        let band: Band? = spot.band
        if let band, hiddenBands.contains(band) { return false }
        if !hiddenModes.isEmpty {
            if let category = analyzer?.spotModeCategory(spot) {
                if hiddenModes.contains(category) { return false }
            } else if hiddenModes.count >= Self.modes.count {
                return false
            }
        }
        if (contestOnly || hideNonWorkable), let analyzer, !analyzer.isWorkable(spot) { return false }
        if spotterFilterOn {
            guard let analyzer, let spotter = analyzer.spotterOrigin(spot) else { return false }
            let passes: Bool = spotterContinents.contains(spotter.continent ?? "")
                || (spotterOwnCountry && spotter.isMyCountry)
            if !passes { return false }
        }
        return true
    }

    public func apply(_ spots: [DxSpot], analyzer: SpotAnalyzer?) -> [DxSpot] {
        isDefault ? spots : spots.filter { allows($0, analyzer: analyzer) }
    }

    /// Console lines (one per entry) with the filtered spot lines removed. A line that is not a spot (a command
    /// reply, WWV, an announcement, the prompt) is always kept; a spot line is a real-time `DX de …` line or a
    /// `SH/DX` row, optionally behind the `[tag] ` of a parallel connection.
    public func applyToConsole(_ lines: [String], analyzer: SpotAnalyzer?) -> [String] {
        guard !isDefault else { return lines }
        return lines.filter { line in
            guard let spot = Self.spot(inLine: line) else { return true }
            return allows(spot, analyzer: analyzer)
        }
    }

    /// The spot a console line carries, or `nil` for any other text.
    public static func spot(inLine line: String) -> DxSpot? {
        var text: Substring = line[...]
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = text[text.index(after: close)...].drop(while: { $0 == " " })
        }
        return DxSpotParser.parse(String(text))
    }
}
