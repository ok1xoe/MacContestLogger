import Foundation

/// IARU band plan: maps a frequency to a traffic category (CW/DIGI/PHONE) according to
/// region. Used to estimate a spot's mode when it does not come clearly from the DX cluster.
///
/// Segments can be supplied externally in `contest-data/bandplan.yaml` (`fromDir`);
/// without the file the built-in `defaultPlan()` is used. Segment boundaries are
/// **inclusive**; on an overlap at a boundary the order (CW, DIGI, PHONE) decides —
/// a boundary frequency belongs to the **earlier** segment.
///
/// Port of Java `bandplan/BandPlan.java`. An essential property that the port
/// **copies and does not fix**: Java **swallows** errors here. `BandPlan.java:201`
/// catches a bare `Exception` and silently falls back to `defaultPlan()`, **without logging**.
/// Broken YAML, a nonsensical structure and a missing file therefore look the same
/// from outside — as "the user supplied no band plan". Our YAML reader, on the contrary,
/// **throws** the error (correctly, see `YamlParser`), so `fromDir`
/// must catch it and do what Java does today.
public struct BandPlan: Sendable {

    /// Traffic category according to the band plan. The order of cases is as in Java
    /// (CW, PHONE, DIGI) — nothing depends on it, but it differs from the order in which
    /// segments are inserted into the plan (CW, DIGI, PHONE).
    public enum ModeCategory: String, Sendable, Hashable, CaseIterable {
        case cw = "CW"
        case phone = "PHONE"
        case digi = "DIGI"
    }

    /// IARU region derived from the DX station's continent.
    public enum IaruRegion: String, Sendable, Hashable, CaseIterable {
        case r1 = "R1"
        case r2 = "R2"
        case r3 = "R3"

        /// Region by continent (EU/AF→R1, NA/SA→R2, AS/OC→R3, otherwise including `nil`→R1).
        ///
        /// The trim is Java `trim()` (`JavaText`), not Swift
        /// `.whitespacesAndNewlines`: Java does **not** drop the non-breaking
        /// space U+00A0, so `forContinent("\u{00A0}NA")` is R1, not R2
        /// (measured on Java 21).
        public static func forContinent(_ continent: String?) -> IaruRegion {
            guard let continent else {
                return .r1
            }
            switch JavaText.trim(continent).uppercased() {
            case "NA", "SA": return .r2
            case "AS", "OC": return .r3
            default: return .r1 // EU, AF, AN, unknown
            }
        }
    }

    /// Band section with a single traffic category; boundaries are inclusive.
    public struct Segment: Sendable, Hashable {
        public let category: ModeCategory
        public let lowHz: Int64
        public let highHz: Int64

        public init(category: ModeCategory, lowHz: Int64, highHz: Int64) {
            self.category = category
            self.lowHz = lowHz
            self.highHz = highHz
        }
    }

    private let byRegion: [IaruRegion: [Segment]]

    private init(byRegion: [IaruRegion: [Segment]]) {
        self.byRegion = byRegion
    }

    /// Traffic category at the given frequency in the given region, or `nil` when
    /// the frequency falls into no segment.
    ///
    /// **Region `nil` behaves differently here than in `segmentsIn`.** Java has
    /// `byRegion` as an `EnumMap`, whose `get(null)` does not throw, only returns `null`,
    /// so it falls through to the R1 segments — `modeAt(7_005_000, nil)` is CW, whereas
    /// `segmentsIn(…, nil)` is an empty list (both measured on Java 21).
    /// That asymmetry exists in the original, so it exists here too.
    public func modeAt(_ freqHz: Int64, _ region: IaruRegion?) -> ModeCategory? {
        // The second `??` is in Java too and is **unreachable**: both plan constructors
        // always fill R1 and `init` is private. Kept for fidelity.
        guard let segments = region.flatMap({ byRegion[$0] }) ?? byRegion[.r1] else {
            return nil
        }
        for segment in segments where freqHz >= segment.lowHz && freqHz <= segment.highHz {
            return segment.category
        }
        return nil
    }

    /// Band plan sections in the frequency window `[lowHz, highHz]`, sorted and clipped
    /// to the window. Used to draw the band plan in the bandmap, so it must say the same
    /// as `modeAt`: an overlap of two sections (the file has them — R2 on 80 m has digi inside
    /// cw) is cut by the same rule — the earlier segment wins, the later one is
    /// shortened by the overlap and if nothing remains of it, it drops out. A later segment
    /// that **encloses** an earlier one splits into two pieces (measured).
    ///
    /// Returns an empty list when the window falls into no section or the
    /// arguments are out of range (reversed window, `region == nil`).
    public func segmentsIn(_ lowHz: Int64, _ highHz: Int64, _ region: IaruRegion?) -> [Segment] {
        guard let region, highHz >= lowHz else {
            return []
        }
        guard let segments = byRegion[region] ?? byRegion[.r1] else {
            return [] // also unreachable in Java, see `modeAt`
        }
        var out: [Segment] = []
        for segment in segments {
            let lo = max(segment.lowHz, lowHz)
            let hi = min(segment.highHz, highHz)
            // Subtract what the earlier segment already took (by splitting into what remains of the section).
            var free: [(lo: Int64, hi: Int64)] = [(lo, hi)]
            for taken in out {
                var next: [(lo: Int64, hi: Int64)] = []
                for piece in free {
                    if piece.hi < taken.lowHz || piece.lo > taken.highHz {
                        next.append(piece)
                        continue
                    }
                    // Both branches are guaranteed that `-1`/`+1` does not wrap around:
                    // `piece.lo < taken.lowHz` excludes `Int64.min`, the second
                    // condition `Int64.max`.
                    if piece.lo < taken.lowHz {
                        next.append((piece.lo, taken.lowHz - 1))
                    }
                    if piece.hi > taken.highHz {
                        next.append((taken.highHz + 1, piece.hi))
                    }
                }
                free = next
            }
            for piece in free where piece.lo <= piece.hi {
                out.append(Segment(category: segment.category, lowHz: piece.lo, highHz: piece.hi))
            }
        }
        // Java `out.sort(comparing lowHz)` is **stable** (`List.sort` is
        // merge sort), Swift `sorted(by:)` does not guarantee stability. Identical
        // `lowHz` cannot result after subtraction, but relying on that would be a
        // silent divergence, so we sort with the original index as the tie-breaker.
        return out.enumerated()
            .sorted { left, right in
                left.element.lowHz == right.element.lowHz
                    ? left.offset < right.offset
                    : left.element.lowHz < right.element.lowHz
            }
            .map(\.element)
    }

    /// Built-in band plan (IARU R1 segments, shared also for R2/R3 until YAML
    /// supplies others).
    public static func defaultPlan() -> BandPlan {
        var r1: [Segment] = []
        addBand(&r1, 1_810, 1_838, 1_838, 1_840, 1_840, 2_000)       // 160m
        addBand(&r1, 3_500, 3_600, 3_580, 3_600, 3_600, 3_800)       // 80m
        addBand(&r1, 7_000, 7_040, 7_040, 7_050, 7_050, 7_200)       // 40m
        addBand(&r1, 14_000, 14_070, 14_070, 14_099, 14_101, 14_350) // 20m
        addBand(&r1, 21_000, 21_070, 21_070, 21_150, 21_151, 21_450) // 15m
        addBand(&r1, 28_000, 28_070, 28_070, 28_190, 28_300, 29_700) // 10m
        var map: [IaruRegion: [Segment]] = [:]
        for region in IaruRegion.allCases {
            map[region] = r1
        }
        return BandPlan(byRegion: map)
    }

    /// Adds three segments (CW/DIGI/PHONE) in kHz for one band.
    private static func addBand(_ out: inout [Segment],
                                _ cwLo: Int, _ cwHi: Int,
                                _ digiLo: Int, _ digiHi: Int,
                                _ phoneLo: Int, _ phoneHi: Int) {
        out.append(Segment(category: .cw, lowHz: khz(Double(cwLo)), highHz: khz(Double(cwHi))))
        out.append(Segment(category: .digi, lowHz: khz(Double(digiLo)), highHz: khz(Double(digiHi))))
        out.append(Segment(category: .phone, lowHz: khz(Double(phoneLo)), highHz: khz(Double(phoneHi))))
    }

    /// Java `Math.round(khz * 1000.0)`.
    static func khz(_ khz: Double) -> Int64 {
        javaRound(khz * 1000.0)
    }

    /// Equivalent of Java `Math.round(double)`.
    ///
    /// Swift `rounded()` cannot be used here: it rounds **away from zero** (`-0.5` → −1,
    /// Java 0) and the conversion `Int64(Double)` of `NaN` or out of range **crashes**, whereas
    /// Java turns `NaN` into 0 and clamps overflow to the extreme `long` (measured on
    /// Java 21: `Math.round(Double.NaN)` = 0, `Math.round(Infinity)` =
    /// `Long.MAX_VALUE`). Both are reachable from the band plan — the range
    /// `"NaN-7040"` gives a segment from 0 Hz and `"Infinity-7040"` a segment
    /// from `Long.MAX_VALUE` (measured).
    static func javaRound(_ value: Double) -> Int64 {
        if value.isNaN {
            return 0
        }
        let floored = value.rounded(.down)
        // The difference is exact for finite numbers; for ±∞ it gives NaN, so it
        // is not added and it is clamped only at the extreme `long`.
        let rounded = (value - floored) >= 0.5 ? floored + 1 : floored
        if rounded >= 9_223_372_036_854_775_808.0 {
            return Int64.max
        }
        if rounded <= -9_223_372_036_854_775_808.0 {
            return Int64.min
        }
        return Int64(rounded)
    }

    /// Loads the band plan from `<contestDataDir>/bandplan.yaml`. When the file or
    /// directory is missing (or invalid), returns `defaultPlan()` — **silently**,
    /// exactly like Java.
    public static func fromDir(_ contestDataDir: URL?) -> BandPlan {
        guard let contestDataDir else {
            return defaultPlan()
        }
        let file = contestDataDir.appendingPathComponent(fileName)
        guard isRegularFile(file) else {
            return defaultPlan()
        }
        do {
            let document = try YamlParser.parse(try Utf8Text.readFile(file))
            guard let dto = try PlanDto.decode(document), let regions = dto.regions,
                  !regions.isEmpty else {
                return defaultPlan()
            }
            var map: [IaruRegion: [Segment]] = [:]
            for (key, rows) in regions {
                guard let region = IaruRegion(rawValue: JavaText.trim(key).uppercased()) else {
                    continue // skip an unknown region
                }
                var segs: [Segment] = []
                for maybeRow in rows ?? [] {
                    // a `null` row gives `NullPointerException` in Java on `row.cw`,
                    // i.e. a crash of the whole load (measured).
                    guard let row = maybeRow else {
                        throw BandPlanFormatError(message: "řádek regionu je null")
                    }
                    addRange(&segs, .cw, row.cw)
                    addRange(&segs, .digi, row.digi)
                    addRange(&segs, .phone, row.phone)
                }
                if !segs.isEmpty {
                    map[region] = segs
                }
            }
            if map.isEmpty {
                return defaultPlan()
            }
            // Fill missing regions from R1 (or the default), so that `modeAt` never
            // returns empty because of a missing region.
            let fallback = map[.r1] ?? defaultPlan().byRegion[.r1] ?? []
            for region in IaruRegion.allCases where map[region] == nil {
                map[region] = fallback
            }
            return BandPlan(byRegion: map)
        } catch {
            return defaultPlan()
        }
    }

    /// File name; the same constant is in `BandPlanFile` (twice in Java too).
    private static let fileName = "bandplan.yaml"

    /// Java `Files.isRegularFile(path)`.
    static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// Adds a segment from the string `"low-high"` in kHz; ignores empty/invalid.
    private static func addRange(_ out: inout [Segment], _ category: ModeCategory, _ range: String?) {
        guard let pair = BandPlanFile.parseRange(range) else {
            return
        }
        out.append(Segment(category: category, lowHz: khz(pair.from), highHz: khz(pair.to)))
    }
}

// MARK: - Document binding (what Jackson does in Java)

/// Error that Jackson would throw in Java when binding a document to
/// `PlanDto`/`BandRow`, or a `NullPointerException` on a `null` row. Both
/// end in the same `catch (Exception)` in Java, so one type is enough.
struct BandPlanFormatError: Error {
    let message: String
}

extension BandPlan {

    /// Row `{band, cw, digi, phone}`. Unknown keys are ignored (Java has
    /// `FAIL_ON_UNKNOWN_PROPERTIES` off), keys are **case-sensitive**
    /// — `CW:` is an unknown key, so no segment arises (measured).
    struct BandRow {
        var band: String?
        var cw: String?
        var digi: String?
        var phone: String?
    }

    /// `regions: { R1: [ {band, cw, digi, phone}, … ] }`.
    ///
    /// The order of regions is the order in the document (Java has `LinkedHashMap`); a duplicate
    /// key is already handled by `YamlMapping` just like Jackson — the last value wins
    /// (measured: two `R1` give only the second).
    struct PlanDto {
        /// `nil` = the `regions` key is missing or `null`.
        var regions: [(key: String, rows: [BandRow?]?)]?

        /// Binding the document to the DTO with the same **strictness** as Jackson.
        /// Measured on Java 21: a scalar or sequence where a map or
        /// list is expected fails the **whole** file load — a single `cw: [1]` on the last
        /// row discards all the earlier valid segments too. A number and `true` on the
        /// other hand convert to `String` (`cw: 7000` is the text "7000").
        ///
        /// - Returns: `nil` when the document itself is `null` (Java `dto == null`).
        static func decode(_ document: YamlValue) throws -> PlanDto? {
            if document.isNull {
                return nil
            }
            guard let root = document.mapping else {
                throw BandPlanFormatError(message: "korenem dokumentu není mapa")
            }
            guard let value = root["regions"], !value.isNull else {
                return PlanDto(regions: nil)
            }
            guard let regionsMap = value.mapping else {
                throw BandPlanFormatError(message: "`regions` není mapa")
            }
            var regions: [(key: String, rows: [BandRow?]?)] = []
            for (key, regionValue) in regionsMap {
                if regionValue.isNull {
                    regions.append((key, nil))
                    continue
                }
                guard let items = regionValue.sequence else {
                    throw BandPlanFormatError(message: "region `\(key)` není seznam")
                }
                var rows: [BandRow?] = []
                for item in items {
                    if item.isNull {
                        rows.append(nil)
                        continue
                    }
                    guard let row = item.mapping else {
                        throw BandPlanFormatError(message: "řádek regionu `\(key)` není mapa")
                    }
                    rows.append(BandRow(
                        band: try text(row["band"]),
                        cw: try text(row["cw"]),
                        digi: try text(row["digi"]),
                        phone: try text(row["phone"])))
                }
                regions.append((key, rows))
            }
            return PlanDto(regions: regions)
        }

        /// Value of a text field: missing and `null` are `nil`, a scalar is taken
        /// **as originally written** (Jackson puts into a `String` field literally what is
        /// in the file), a sequence and a map throw — just like Jackson.
        private static func text(_ value: YamlValue?) throws -> String? {
            guard let value, !value.isNull else {
                return nil
            }
            guard let raw = value.rawText else {
                throw BandPlanFormatError(message: "textové pole má strukturovanou hodnotu")
            }
            return raw
        }
    }
}
