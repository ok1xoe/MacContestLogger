/// Editing the band plan at a frequency from the band map (N1MM+ "Display and Adjustment of Band Plans in Background
/// of Bandmap Frequency Scale": a right click on the scale sets the lower or upper edge of a CW, digital or phone
/// sub-band there, or removes it). The rows are the `bandplan.yaml` ones Settings → Band plan edits
/// (`BandPlanFile.Segment`); the caller writes them back and reloads the band data like the Settings commit.
///
/// Pure logic. Only the station's region is touched; the edited segment never overlaps another one afterwards
/// (neighbours are shortened or dropped, a touch is allowed — the same rule as `BandPlanFile.overlaps`).
public enum BandPlanEdit {

    /// What to do at the frequency.
    public enum Action: Equatable, Sendable {
        /// The lower edge of the band's `mode` segment (`CW`, `DIGI`, `PHONE`) moves to the frequency.
        case setLow(mode: String)
        /// The upper edge of the band's `mode` segment moves to the frequency.
        case setHigh(mode: String)
        /// The segment under the frequency is removed.
        case remove
    }

    /// Why an edit was not made.
    public enum Refusal: Equatable, Sendable {
        /// The frequency is outside the amateur bands.
        case outsideBand
        /// The band has no segment of that mode (or none under the frequency for `remove`).
        case noSegment
        /// The new edge would leave the segment empty (the lower edge at or above the upper one).
        case empty
    }

    public enum Outcome: Equatable, Sendable {
        case edited([BandPlanFile.Segment])
        case refused(Refusal)
    }

    /// The rows an edit starts from: the file's rows, the built-in plan's (as region R1) when the file has none, and
    /// the R1 rows copied to `region` when the region has no rows of its own — `BandPlan.fromDir` fills a missing
    /// region from R1, so the copy keeps what the band map showed while the region gets its own rows.
    public static func seeded(_ file: [BandPlanFile.Segment], region: String) -> [BandPlanFile.Segment] {
        var rows: [BandPlanFile.Segment] = file
        if rows.isEmpty {
            for row in BandPlan.defaultRows {
                for (mode, range) in [("CW", row.cw), ("DIGI", row.digi), ("PHONE", row.phone)] {
                    rows.append(BandPlanFile.Segment(region: "R1", mode: mode, fromKhz: Double(range.0),
                                                     toKhz: Double(range.1)))
                }
            }
        }
        if !rows.contains(where: { sameRegion($0.region, region) }) {
            let r1: [BandPlanFile.Segment] = rows.filter { sameRegion($0.region, "R1") }
            rows += r1.map { BandPlanFile.Segment(region: region, mode: $0.mode, fromKhz: $0.fromKhz, toKhz: $0.toKhz) }
        }
        return rows
    }

    /// Applies `action` at `khz` to the rows of `region` within `band`.
    public static func apply(_ action: Action, atKhz khz: Double, band: Band?, region: String,
                             segments: [BandPlanFile.Segment]) -> Outcome {
        guard let band else { return .refused(.outsideBand) }
        let bandLow: Double = Double(band.lowHz) / 1000.0
        let bandHigh: Double = Double(band.highHz) / 1000.0
        guard khz >= bandLow, khz <= bandHigh else { return .refused(.outsideBand) }
        let inBand: [Int] = segments.indices.filter { index in
            let segment: BandPlanFile.Segment = segments[index]
            return sameRegion(segment.region, region) && segment.fromKhz <= bandHigh && segment.toKhz >= bandLow
        }
        switch action {
        case .remove:
            let hit: Set<Int> = Set(inBand.filter { segments[$0].fromKhz <= khz && khz <= segments[$0].toKhz })
            guard !hit.isEmpty else { return .refused(.noSegment) }
            return .edited(segments.indices.filter { !hit.contains($0) }.map { segments[$0] })
        case .setLow(let mode), .setHigh(let mode):
            let candidates: [Int] = inBand.filter { segments[$0].mode.uppercased() == mode.uppercased() }
            guard let target = nearest(candidates, segments, khz) else { return .refused(.noSegment) }
            let old: BandPlanFile.Segment = segments[target]
            let edited: BandPlanFile.Segment
            if case .setLow = action {
                edited = BandPlanFile.Segment(region: old.region, mode: old.mode, fromKhz: khz, toKhz: old.toKhz)
            } else {
                edited = BandPlanFile.Segment(region: old.region, mode: old.mode, fromKhz: old.fromKhz, toKhz: khz)
            }
            guard edited.fromKhz < edited.toKhz else { return .refused(.empty) }
            return .edited(resolve(segments, edited: target, with: edited, region: region))
        }
    }

    /// The candidate containing `khz`, otherwise the one with the nearest edge (the first on a tie).
    private static func nearest(_ candidates: [Int], _ segments: [BandPlanFile.Segment], _ khz: Double) -> Int? {
        if let inside = candidates.first(where: { segments[$0].fromKhz <= khz && khz <= segments[$0].toKhz }) {
            return inside
        }
        func distance(_ index: Int) -> Double {
            Swift.min(abs(segments[index].fromKhz - khz), abs(segments[index].toKhz - khz))
        }
        var best: Int?
        for index in candidates where best == nil || distance(index) < distance(best!) {
            best = index
        }
        return best
    }

    /// The edited row in place; the other rows of the region that now overlap it are shortened (the part on their
    /// own side kept) or dropped when covered.
    private static func resolve(_ segments: [BandPlanFile.Segment], edited index: Int, with edited: BandPlanFile.Segment,
                                region: String) -> [BandPlanFile.Segment] {
        var out: [BandPlanFile.Segment] = []
        for (position, segment) in segments.enumerated() {
            if position == index {
                out.append(edited)
                continue
            }
            guard sameRegion(segment.region, region), segment.fromKhz < edited.toKhz,
                  segment.toKhz > edited.fromKhz else {
                out.append(segment)
                continue
            }
            if segment.fromKhz >= edited.fromKhz && segment.toKhz <= edited.toKhz {
                continue
            }
            let below: Double = edited.fromKhz - segment.fromKhz
            let above: Double = segment.toKhz - edited.toKhz
            if below >= above {
                out.append(BandPlanFile.Segment(region: segment.region, mode: segment.mode, fromKhz: segment.fromKhz,
                                                toKhz: edited.fromKhz))
            } else {
                out.append(BandPlanFile.Segment(region: segment.region, mode: segment.mode, fromKhz: edited.toKhz,
                                                toKhz: segment.toKhz))
            }
        }
        return out
    }

    private static func sameRegion(_ left: String, _ right: String) -> Bool {
        left.uppercased() == right.uppercased()
    }
}

/// The US amateur licence class sub-band edges (47 CFR §97.301 (b)–(d)) drawn as red lines on the band map scale —
/// N1MM+ draws its own (older) list. For US operators; off by default.
public enum UsLicenseLines {

    /// The edges in kHz: CW 3525, 7025, 14025, 21025 and the phone edges of the Extra, Advanced and General classes.
    public static let edgesKhz: [Int] = [
        3_525, 3_600, 3_700, 3_800,
        7_025, 7_125, 7_175,
        14_025, 14_150, 14_175, 14_225,
        21_025, 21_200, 21_225, 21_275,
    ]

    /// The edges inside `lo…hi` (Hz, inclusive), ascending.
    public static func edges(lo loHz: Int64, hi hiHz: Int64) -> [Int64] {
        edgesKhz.map { Int64($0) * 1000 }.filter { $0 >= loHz && $0 <= hiHz }
    }
}
