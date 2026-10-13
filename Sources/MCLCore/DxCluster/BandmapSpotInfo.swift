import Foundation

/// What the band map shows next to a spot and in its tooltip beyond v1.1.1's label (N1MM Logger+ Bandmap window):
/// the skimmer mark (`#`, `!` for one's own skimmer), the gray-line mark `¤`, the QSX (split) frequency, `NEW` for a
/// fresh spot, and the tooltip text. Pure functions; the band map model supplies the time, the coordinates and the
/// buffer's counts.
public enum BandmapSpotInfo {

    /// N1MM: "NEW" marks a spot less than three minutes old.
    public static let newSeconds: Double = 180
    /// A station whose sunrise or sunset is at most this far from now (either side) is on the gray line.
    public static let grayLineSeconds: Int32 = 1_800
    /// The gray-line mark (N1MM `¤`).
    public static let grayLineMark: String = "\u{a4}"

    /// `#` for a skimmer / RBN spot, `!` when the skimmer is one's own (the spotter's call without its `-#`/`-n`
    /// suffix equals `myCall`), `nil` for a spot from a human or a self-spot.
    public static func skimmerMark(_ spot: DxSpot, myCall: String) -> String? {
        guard SkimmerSpot.isSkimmer(spot) else { return nil }
        let mine: String = baseCall(myCall)
        if !mine.isEmpty && baseCall(spot.spotter) == mine {
            return "!"
        }
        return "#"
    }

    /// A call without a trailing `-…` suffix (`OK1XOE-#` → `OK1XOE`, `DL8LAS-2` → `DL8LAS`), upper case.
    static func baseCall(_ call: String) -> String {
        let trimmed: String = JavaText.trim(call).uppercased()
        guard let dash = trimmed.lastIndex(of: "-") else { return trimmed }
        return String(trimmed[..<dash])
    }

    /// The spot is younger than `newSeconds` (an unknown time is never new).
    public static func isNew(spottedAt: Date?, now: Date) -> Bool {
        guard let spottedAt else { return false }
        let age: TimeInterval = now.timeIntervalSince(spottedAt)
        return age >= 0 && age < newSeconds
    }

    /// The whole minutes since the spot arrived (0 for a future time).
    public static func ageMinutes(spottedAt: Date, now: Date) -> Int {
        Swift.max(0, Int(now.timeIntervalSince(spottedAt) / 60))
    }

    /// The transmit frequency of the spot's split comment (`UP 5`, `QSX 14025`; a bare `UP` is 5 kHz in phone,
    /// 1 kHz otherwise — the same rule as the automatic split), `nil` without one.
    public static func qsxHz(_ spot: DxSpot) -> Int? {
        let mode: String = SpotModeParser.fromComment(spot.comment) ?? ""
        let phone: Bool = mode == "SSB"
        return SplitFromComment.parse(spot.comment, spotFreqHz: spot.freqHz, defaultUpHz: phone ? 5_000 : 1_000)
    }

    /// N1MM shows the QSX frequency in three digits on HF (`14027.5` → `027`); above 30 MHz the whole kHz.
    public static func qsxText(_ txHz: Int) -> String {
        let kHz: Int = txHz / 1000
        if txHz < 30_000_000 {
            let digits = String(kHz % 1000)
            return String(repeating: "0", count: 3 - digits.count) + digits
        }
        return String(kHz)
    }

    /// The station's sunrise or sunset (of today and of the neighbouring days, so midnight UTC does not matter) is at
    /// most `grayLineSeconds` from `now`. `nil` coordinates, polar day or night: `false`.
    public static func onGrayLine(lat: Double, lon: Double, now: Date) -> Bool {
        let seconds: Double = now.timeIntervalSince1970
        let epochDay = Int64((seconds / 86_400).rounded(.down))
        for offset: Int64 in [-1, 0, 1] {
            guard let times = SolarTimes.forLocation(lat, lon, epochDay: epochDay + offset) else { continue }
            let dayStart = Double(epochDay + offset) * 86_400
            for event in [times.sunrise, times.sunset] {
                let at: Double = dayStart + Double(event)
                if abs(at - seconds) <= Double(grayLineSeconds) {
                    return true
                }
            }
        }
        return false
    }

    /// The label as drawn: v1.1.1's `labelText` (call, azimuth, skimmer count) with the skimmer mark and `¤` right
    /// after the call, then `QSX 027` and `NEW`.
    public static func label(call: String, azimuth: Int?, skimmers: Int, skimmerMark: String?, grayLine: Bool,
                             qsxHz: Int?, isNew: Bool) -> String {
        var head: String = call
        if let skimmerMark {
            head += skimmerMark
        }
        if grayLine {
            head += grayLineMark
        }
        var out: String = BandmapLayout.labelText(call: head, azimuth: azimuth, skimmers: skimmers)
        if let qsxHz {
            out += " QSX " + qsxText(qsxHz)
        }
        if isNew {
            out += " NEW"
        }
        return out
    }

    /// What the tooltip needs beyond the spot itself.
    public struct TooltipFacts: Equatable, Sendable {
        public var spottedAt: Date?
        public var now: Date
        public var count: Int
        public var skimmers: Int
        public var azimuth: Int?
        public var grayLine: Bool
        public var qsxHz: Int?

        public init(spottedAt: Date?, now: Date, count: Int = 1, skimmers: Int = 0, azimuth: Int? = nil,
                    grayLine: Bool = false, qsxHz: Int? = nil) {
            self.spottedAt = spottedAt
            self.now = now
            self.count = count
            self.skimmers = skimmers
            self.azimuth = azimuth
            self.grayLine = grayLine
            self.qsxHz = qsxHz
        }
    }

    /// N1MM's spot tooltip: the call and the exact frequency the spotter sent, the spotter, the minutes since the
    /// spot, the comment, the QSX frequency, how many times it was spotted and by how many skimmers, the azimuth, the
    /// gray line and „Self Spotted".
    public static func tooltip(_ spot: DxSpot, facts: TooltipFacts, translator: Translator = .source) -> String {
        let kHz: String = JavaFormat.format("%.1f", .double(Double(spot.freqHz) / 1000.0))
        var lines: [String] = [spot.dxCall + "   " + kHz + " kHz"]
        if !KotlinText.isBlank(spot.spotter) {
            lines.append("Spotter: " + spot.spotter)
        }
        if let spottedAt = facts.spottedAt {
            lines.append(translator.translate("Před %d min", [.int(ageMinutes(spottedAt: spottedAt, now: facts.now))]))
        }
        if !KotlinText.isBlank(spot.comment) {
            lines.append(translator.translate("Komentář: %s", [.string(spot.comment)]))
        }
        if let qsx = facts.qsxHz {
            lines.append("QSX " + JavaFormat.format("%.1f", .double(Double(qsx) / 1000.0)) + " kHz")
        }
        if facts.count > 1 {
            lines.append(translator.translate("Spotováno %dx", [.int(facts.count)]))
        }
        if facts.skimmers > 0 {
            lines.append(translator.translate("Skimmerů: %d", [.int(facts.skimmers)]))
        }
        if let azimuth = facts.azimuth {
            lines.append(translator.translate("Azimut: %d°", [.int(azimuth)]))
        }
        if facts.grayLine {
            lines.append(grayLineMark + " " + translator.translate("u stanice vychází nebo zapadá slunce"))
        }
        if spot.selfSpotted {
            lines.append(translator.translate("Vlastní spot"))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - call-frame and search

    /// N1MM call-frame: the spot nearest to `freqHz` within `toleranceHz` (inclusive; the first on a tie), `nil` for a
    /// frequency ≤ 0.
    public static func callFrameSpot(_ spots: [DxSpot], freqHz: Int64, toleranceHz: Int) -> DxSpot? {
        guard freqHz > 0 else { return nil }
        var best: DxSpot?
        var bestDistance = Int64.max
        for spot in spots {
            let distance: Int64 = abs(Int64(spot.freqHz) - freqHz)
            if distance <= Int64(toleranceHz) && distance < bestDistance {
                best = spot
                bestDistance = distance
            }
        }
        return best
    }

    /// N1MM „Find a Callsign": the lowest spot above `fromHz` whose call contains `query` (case-insensitive),
    /// wrapping around to the lowest match. Searching again from the found frequency finds the next instance. `nil` =
    /// no match or a blank query.
    public static func find(_ query: String, in spots: [DxSpot], fromHz: Int64) -> DxSpot? {
        let wanted: String = JavaText.trim(query).uppercased()
        guard !wanted.isEmpty else { return nil }
        let matching: [DxSpot] = spots.enumerated().filter { $0.element.dxCall.uppercased().contains(wanted) }
            .sorted { left, right in
                left.element.freqHz != right.element.freqHz
                    ? left.element.freqHz < right.element.freqHz : left.offset < right.offset
            }
            .map(\.element)
        return matching.first { Int64($0.freqHz) > fromHz } ?? matching.first
    }
}

extension SpotAnalyzer {

    /// N1MM „Always use packet spot mode": the mode of a spot from its comment, the digital frequencies or the band
    /// plan (no fallback to the contest's mode); `nil` when none tells.
    public func packetSpotMode(_ spot: DxSpot) -> Mode? {
        let name: String
        if let mode = SpotModeParser.fromComment(spot.comment) {
            name = mode
        } else if let mode = digiFrequencies.modeAt(spot.freqHz) {
            name = mode
        } else {
            let region = BandPlan.IaruRegion.forContinent(dxcc?.resolve(spot.dxCall)?.primaryContinent)
            guard let category = bandPlan.modeAt(Int64(spot.freqHz), region) else { return nil }
            name = Self.categoryToMode(category)
        }
        return Mode(rawValue: name.uppercased())
    }
}
