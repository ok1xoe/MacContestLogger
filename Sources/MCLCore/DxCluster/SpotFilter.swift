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
/// - **Spotter origin:** with continents, "own country", spotter prefixes and/or call areas set, only spots from
///   spotters matching any of them stay (the spotter's DXCC from its call, `-#`/`-n` suffixes stripped; a prefix
///   matches the start of the spotter's call; a call area is the digit of a spotter in my own DXCC); nothing set = no
///   filter; a spotter that cannot be resolved passes only by its prefix while the filter is on.
/// - **Call history / worked:** only spots of calls in the call history, or of calls already in the log (the
///   `SpotFilterContext` answers; without one these options do nothing).
/// - **Beacons:** NCDXF/IARU beacon spots hidden (`NcdxfBeacons`).
/// - **Busted spots:** the calls `BustedSpots` found (a similar call reported more often near the same frequency)
///   are hidden; the context carries them.
/// - **Preferred spotters** are not a filter: their spots are highlighted (`isPreferred`); `isDefault` ignores them.
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
            case .vhf: [.m6, .m2, .m125]
            case .uhf: [.cm70, .cm33, .cm23]
            case .microwave: [.cm13, .cm9, .cm6, .cm3, .cm125, .mm6, .mm4, .mm25, .mm2, .mm1]
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
    /// Spotter call prefixes that pass (upper case, N1MM "Filter by Prefix").
    public var spotterPrefixes: [String] = []
    /// Call-area digits ("0"…"9") of spotters in my own DXCC that pass.
    public var spotterCallAreas: Set<String> = []
    /// N1MM "Show only spots in call history".
    public var onlyCallHistory: Bool = false
    /// Only spots of stations already in the log.
    public var onlyWorked: Bool = false
    /// Hide the NCDXF/IARU beacon spots.
    public var hideBeacons: Bool = false
    /// N1MM "Remove Busted Spots" and its "Two Character Errors".
    public var removeBusted: Bool = false
    public var bustedTwoChars: Bool = false
    /// N1MM preferred spotters (at most `preferredLimit`, upper case): highlighted, never filtered.
    public var preferredSpotters: [String] = [] {
        didSet {
            let normalized: [String] = Self.normalizedCalls(preferredSpotters, limit: Self.preferredLimit)
            if normalized != preferredSpotters { preferredSpotters = normalized }
        }
    }

    /// N1MM allows three preferred spotters.
    public static let preferredLimit = 3
    /// The call-area digits.
    public static let callAreas: [String] = (0...9).map(String.init)

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
        !spotterContinents.isEmpty || spotterOwnCountry || !spotterPrefixes.isEmpty || !spotterCallAreas.isEmpty
    }

    /// Calls or prefixes from a text (comma, semicolon or white space separated): trimmed, upper case, only letters,
    /// digits and `/`, unique in order, at most `limit`.
    public static func normalizedCalls(_ items: [String], limit: Int? = nil) -> [String] {
        var out: [String] = []
        for item in items {
            for token in item.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace }) {
                let upper: String = String(token).uppercased()
                guard upper.unicodeScalars.allSatisfy({ ($0.isASCII && CharacterSet.alphanumerics.contains($0))
                    || $0 == "/" }), !out.contains(upper) else { continue }
                out.append(upper)
            }
        }
        if let limit, out.count > limit { out = Array(out.prefix(limit)) }
        return out
    }

    /// The prefix list as edited (a text).
    public var spotterPrefixText: String {
        get { spotterPrefixes.joined(separator: " ") }
        set { spotterPrefixes = Self.normalizedCalls([newValue]) }
    }

    public mutating func setCallArea(_ digit: String, on: Bool) {
        guard Self.callAreas.contains(digit) else { return }
        if on { spotterCallAreas.insert(digit) } else { spotterCallAreas.remove(digit) }
    }

    /// The spotter is a preferred one: its call without the `-n`, `-#` or `/n` suffix equals a preferred call.
    public func isPreferred(_ spotter: String) -> Bool {
        guard !preferredSpotters.isEmpty else { return false }
        return preferredSpotters.contains(Self.preferredBase(spotter))
    }

    /// `WZ7I-2`, `WZ7I-#`, `WZ7I/3` → `WZ7I`.
    static func preferredBase(_ spotter: String) -> String {
        var call: String = JavaText.trim(spotter).uppercased()
        if let dash = call.firstIndex(of: "-") { call = String(call[..<dash]) }
        if let slash = call.lastIndex(of: "/") {
            let tail = call[call.index(after: slash)...]
            if tail.count <= 1 { call = String(call[..<slash]) }
        }
        return call
    }

    /// The call-area digit of a call: the digit of a one-digit portable suffix (`W1AW/4` → 4), else the last digit
    /// of the prefix (`OK1ABC` → 1).
    static func callArea(_ call: String) -> String? {
        let parts: [Substring] = call.split(separator: "/")
        if parts.count > 1, let tail = parts.last, tail.count == 1, tail.allSatisfy(\.isNumber) {
            return String(tail)
        }
        let main: Substring = parts.max(by: { $0.count < $1.count }) ?? Substring(call)
        guard let firstDigit = main.firstIndex(where: \.isNumber) else { return nil }
        let run = main[firstDigit...].prefix(while: \.isNumber)
        return run.last.map { String($0) }
    }

    public mutating func setContinent(_ code: String, on: Bool) {
        guard Self.continents.contains(code) else { return }
        if on { spotterContinents.insert(code) } else { spotterContinents.remove(code) }
    }

    /// Everything on, "Contest" off — the "Obnovit výchozí" state.
    public static let `default` = SpotFilter()

    /// `true` when the filter lets everything through (no work to do per spot).
    public var isDefault: Bool {
        var plain: SpotFilter = self
        plain.preferredSpotters = []
        return plain == .default
    }

    /// The filter needs a `SpotFilterContext` (call history, the log or the busted calls).
    public var needsContext: Bool {
        onlyCallHistory || onlyWorked || removeBusted
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

    /// "Obnovit výchozí": everything shown, Contest off; the preferred spotters stay (they are no filter).
    public mutating func reset() {
        let preferred: [String] = preferredSpotters
        self = .default
        preferredSpotters = preferred
    }

    // MARK: - filtering

    /// Whether the spot stays visible.
    /// - Parameters:
    ///   - analyzer: the spot analysis (mode inference and the active contest); `nil` = no inference possible
    ///   - context: the call history, the log and the busted calls (`.none`: those options do nothing)
    public func allows(_ spot: DxSpot, analyzer: SpotAnalyzer?, context: SpotFilterContext = .none) -> Bool {
        if spot.selfSpotted || isDefault { return true }
        if hideBeacons && NcdxfBeacons.isBeacon(spot.dxCall) { return false }
        if removeBusted && context.busted.contains(spot.dxCall.uppercased()) { return false }
        if onlyCallHistory, let inHistory = context.inCallHistory, !inHistory(spot.dxCall) { return false }
        if onlyWorked, let worked = context.worked, !worked(spot.dxCall) { return false }
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
        if spotterFilterOn && !spotterPasses(spot, analyzer: analyzer) {
            return false
        }
        return true
    }

    /// The origin part: a prefix, a continent, my country or a call area of my country.
    func spotterPasses(_ spot: DxSpot, analyzer: SpotAnalyzer?) -> Bool {
        let base: String = SpotAnalyzer.baseCall(spot.spotter)
        if spotterPrefixes.contains(where: { base.hasPrefix($0) }) { return true }
        guard let analyzer, let origin = analyzer.spotterOrigin(spot) else { return false }
        if spotterContinents.contains(origin.continent ?? "") { return true }
        guard origin.isMyCountry else { return false }
        if spotterOwnCountry { return true }
        return Self.callArea(base).map { spotterCallAreas.contains($0) } ?? false
    }

    public func apply(_ spots: [DxSpot], analyzer: SpotAnalyzer?, context: SpotFilterContext = .none) -> [DxSpot] {
        isDefault ? spots : spots.filter { allows($0, analyzer: analyzer, context: context) }
    }

    /// Console lines (one per entry) with the filtered spot lines removed. A line that is not a spot (a command
    /// reply, WWV, an announcement, the prompt) is always kept; a spot line is a real-time `DX de …` line or a
    /// `SH/DX` row, optionally behind the `[tag] ` of a parallel connection.
    public func applyToConsole(_ lines: [String], analyzer: SpotAnalyzer?,
                               context: SpotFilterContext = .none) -> [String] {
        guard !isDefault else { return lines }
        return lines.filter { line in
            guard let spot = Self.spot(inLine: line) else { return true }
            return allows(spot, analyzer: analyzer, context: context)
        }
    }

    /// The spot a console line carries, or `nil` for any other text. The traffic log's own `HH:mm:ss` time in front
    /// of the line and the `[tag] ` of a parallel connection are skipped.
    public static func spot(inLine line: String) -> DxSpot? {
        var text: Substring = line[...]
        let head: [Character] = Array(text.prefix(9))
        if head.count == 9, head[2] == ":", head[5] == ":", head[8] == " ",
           [0, 1, 3, 4, 6, 7].allSatisfy({ head[$0].isASCII && head[$0].isNumber }) {
            text = text.dropFirst(9).drop(while: { $0 == " " })
        }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            text = text[text.index(after: close)...].drop(while: { $0 == " " })
        }
        return DxSpotParser.parse(String(text))
    }
}

/// What some spot filter options ask the app: the call history, the log and the busted calls of the moment.
public struct SpotFilterContext {
    /// The call is in the call history (`nil`: unknown, "only call history" does nothing).
    public var inCallHistory: ((String) -> Bool)?
    /// The call is in the log (`nil`: unknown).
    public var worked: ((String) -> Bool)?
    /// Upper-case calls `BustedSpots` hides.
    public var busted: Set<String>

    public init(inCallHistory: ((String) -> Bool)? = nil, worked: ((String) -> Bool)? = nil,
                busted: Set<String> = []) {
        self.inCallHistory = inCallHistory
        self.worked = worked
        self.busted = busted
    }

    public static var none: SpotFilterContext { SpotFilterContext() }
}

/// The NCDXF/IARU International Beacon Project stations (14100, 18110, 21150, 24930, 28200 kHz).
public enum NcdxfBeacons {

    public static let calls: Set<String> = [
        "4U1UN", "VE8AT", "W6WX", "KH6RS", "ZL6B", "VK6RBP", "JA2IGY", "RR9O", "VR2B",
        "4S7B", "ZS6DN", "5Z4B", "4X6TU", "OH2B", "CS3B", "LU4AA", "OA4B", "YV5B",
    ]

    /// The beacon frequencies (Hz).
    public static let frequenciesHz: [Int] = [14_100_000, 18_110_000, 21_150_000, 24_930_000, 28_200_000]

    /// The call (with or without `/B`) is one of the beacons.
    public static func isBeacon(_ call: String) -> Bool {
        var upper: String = JavaText.trim(call).uppercased()
        if upper.hasSuffix("/B") { upper.removeLast(2) }
        return calls.contains(upper)
    }
}
