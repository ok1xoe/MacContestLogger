import Foundation

/// Reading/writing `bandplan.yaml` as a **flat list of segments** for editing
/// in the UI. One segment = region + mode (CW/DIGI/PHONE) + range in kHz. It is written
/// back in the format `BandPlan` reads (one row per segment with only the given
/// mode filled) — that is why `contest-data/bandplan.yaml` has `band: ""` on **every**
/// row: the writer fills that field with empty text and never otherwise
/// (verified on all 54 rows of the file and on the output of Java `write`).
///
/// Port of Java `bandplan/BandPlanFile.java`. Errors are **swallowed** just like
/// in `BandPlan` (`BandPlanFile.java:54` catches a bare `Exception`, no log) —
/// with one trap that the original has and the port copies: `catch` returns the
/// **partially filled** list, not an empty one. When the file passes binding and falls apart
/// only in the loop (a `null` row), the segments read **before** it are returned
/// (measured on Java 21). `BandPlan.fromDir`, on the contrary, always falls back to the whole
/// default plan, it knows no partial result.
public enum BandPlanFile {

    /// Editable row: region (R1/R2/R3), mode (CW/DIGI/PHONE), range in kHz.
    ///
    /// In Java it is a `record` whose `equals` compares `double` bitwise
    /// (`Double.equals`): `NaN` equals `NaN` and `0.0` does **not** equal `-0.0`.
    /// Swift synthesis does the opposite, and `NaN` can appear in ranges
    /// (`fmt(Double.nan)` writes "NaN" and reading returns it), so `==` and hash
    /// are done after Java's model.
    public struct Segment: Sendable, Hashable {
        public let region: String
        public let mode: String
        public let fromKhz: Double
        public let toKhz: Double

        public init(region: String, mode: String, fromKhz: Double, toKhz: Double) {
            self.region = region
            self.mode = mode
            self.fromKhz = fromKhz
            self.toKhz = toKhz
        }

        public static func == (lhs: Segment, rhs: Segment) -> Bool {
            lhs.region == rhs.region
                && lhs.mode == rhs.mode
                && lhs.fromKhz.bitPattern == rhs.fromKhz.bitPattern
                && lhs.toKhz.bitPattern == rhs.toKhz.bitPattern
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(region)
            hasher.combine(mode)
            hasher.combine(fromKhz.bitPattern)
            hasher.combine(toKhz.bitPattern)
        }
    }

    private static let fileName = "bandplan.yaml"

    /// Reads segments from `<contestDataDir>/bandplan.yaml`. A missing directory,
    /// missing file and broken content all give an **empty list, without an error**.
    public static func read(_ contestDataDir: URL?) -> [Segment] {
        var out: [Segment] = []
        guard let contestDataDir else {
            return out
        }
        let file = contestDataDir.appendingPathComponent(fileName)
        guard BandPlan.isRegularFile(file) else {
            return out
        }
        do {
            let document = try YamlParser.parse(try Utf8Text.readFile(file))
            guard let dto = try BandPlan.PlanDto.decode(document), let regions = dto.regions else {
                return out
            }
            for (key, rows) in regions {
                // The region is **not filtered** by `IaruRegion`: `read` keeps
                // even "R4" (unlike `BandPlan.fromDir`, which drops it) —
                // measured on Java 21.
                let region = JavaText.trim(key).uppercased()
                guard let rows else {
                    continue
                }
                for maybeRow in rows {
                    guard let row = maybeRow else {
                        // Java NPE on `row.cw` — `catch` returns the partially filled `out`.
                        throw BandPlanFormatError(message: "řádek regionu je null")
                    }
                    addSeg(&out, region, "CW", row.cw)
                    addSeg(&out, region, "DIGI", row.digi)
                    addSeg(&out, region, "PHONE", row.phone)
                }
            }
        } catch {
            return out
        }
        return out
    }

    private static func addSeg(_ out: inout [Segment], _ region: String, _ mode: String,
                               _ range: String?) {
        if let pair = parseRange(range) {
            out.append(Segment(region: region, mode: mode, fromKhz: pair.from, toKhz: pair.to))
        }
    }

    /// Range `"low-high"` in kHz, or `nil` when it cannot be read.
    ///
    /// The semantics are Java's down to the detail and both are reachable from a user
    /// file (all measured on Java 21):
    /// - emptiness is tested by Java `isBlank()` (`JavaText`), not Swift
    ///   `.isEmpty` — `"   "` is empty, `"\u{00A0}"` is **not**;
    /// - it splits by Java `String.split("-")`, which **drops trailing empty
    ///   pieces**, so `"7000-"` has one piece (→ `nil`), `"-"` zero pieces (→ `nil`)
    ///   and `"-7000-7040"` three (→ `nil`). A negative frequency therefore **cannot**
    ///   be read from a file;
    /// - numbers are parsed by Java `Double.parseDouble` (`JavaDouble.parseDouble`),
    ///   not Swift `Double(String)`: Java accepts `"1e3"`, `"+7000"`, `"Infinity"`,
    ///   `"NaN"` and a suffix such as `"7000d"`, but **not** `"0x10"` (hex without `p`) or `"inf"`
    ///   — Swift `Double` accepts both and would produce a segment where
    ///   Java has none.
    static func parseRange(_ range: String?) -> (from: Double, to: Double)? {
        guard let range, !JavaText.isBlank(range) else {
            return nil
        }
        let parts = splitOnDash(range)
        guard parts.count == 2 else {
            return nil
        }
        guard let from = JavaDouble.parseDouble(JavaText.trim(parts[0])),
              let to = JavaDouble.parseDouble(JavaText.trim(parts[1])) else {
            return nil
        }
        return (from, to)
    }

    /// Java `String.split("-")` (limit 0): splits on the **scalar** U+002D
    /// and drops trailing empty pieces. When the text contains no hyphen at all,
    /// Java returns the whole text as a single piece (even if empty), so
    /// `"".split("-")` has length 1 — hence that special first branch.
    ///
    /// It splits by scalars, not graphemes: Swift `split(separator: "-")` would
    /// treat a hyphen with a combining mark (`"-\u{0301}"`) as one grapheme
    /// and not split it, Java does.
    static func splitOnDash(_ text: String) -> [String] {
        guard text.unicodeScalars.contains("-") else {
            return [text]
        }
        var parts: [String] = [""]
        for scalar in text.unicodeScalars {
            if scalar == "-" {
                parts.append("")
            } else {
                parts[parts.count - 1].unicodeScalars.append(scalar)
            }
        }
        while let last = parts.last, last.isEmpty {
            parts.removeLast()
        }
        return parts
    }

    /// Does the segment `[fromKhz, toKhz]` in the given region overlap another segment
    /// in the list? Ignores the index `selfIndex` (the row being edited). The mode is not considered —
    /// two segments must not overlap in frequency, otherwise the mode in the overlap would be
    /// ambiguous.
    ///
    /// Boundaries are compared **strictly**, so a touch (`7040–7050` next to
    /// `7000–7040`) is not an overlap. The region is compared by Java
    /// `equalsIgnoreCase(String)`, which returns `false` on `nil` — `region == nil`
    /// therefore does not crash and says "does not overlap" (measured).
    public static func overlaps(_ segments: [Segment], _ region: String?,
                                _ fromKhz: Double, _ toKhz: Double, _ selfIndex: Int) -> Bool {
        for index in segments.indices where index != selfIndex {
            let segment = segments[index]
            if JavaChar.equalsIgnoreCase(segment.region, region),
               fromKhz < segment.toKhz, toKhz > segment.fromKhz {
                return true
            }
        }
        return false
    }

    /// Writes segments to `bandplan.yaml` (grouped by region, one row
    /// per segment). The directory is created, an existing file is overwritten.
    ///
    /// The order of regions is the order of **first occurrence** in the input (Java has
    /// `LinkedHashMap` + `computeIfAbsent`), the order of rows within a region is preserved.
    public static func write(_ contestDataDir: URL, _ segments: [Segment]) throws {
        var order: [String] = []
        var rowsByRegion: [String: [YamlValue]] = [:]
        for segment in segments {
            var row = YamlMapping()
            row.set("band", .string(""))
            // When the mode is "BAND", the second `put` **overwrites** the `band` key and the row
            // comes out as `band: "7000-7040"` (measured) — `YamlMapping.set`
            // leaves the position to an existing key, so it comes out the same.
            row.set(segment.mode.lowercased(), .string(fmt(segment.fromKhz) + "-" + fmt(segment.toKhz)))
            let key = segment.region.uppercased()
            if rowsByRegion[key] == nil {
                order.append(key)
            }
            rowsByRegion[key, default: []].append(.mapping(row))
        }
        var regions = YamlMapping()
        for key in order {
            regions.set(key, .sequence(rowsByRegion[key] ?? []))
        }
        var root = YamlMapping()
        root.set("regions", .mapping(regions))
        try FileManager.default.createDirectory(at: contestDataDir, withIntermediateDirectories: true)
        try YamlWriter.write(.mapping(root))
            .write(to: contestDataDir.appendingPathComponent(fileName),
                   atomically: false, encoding: .utf8)
    }

    /// Java `fmt`: an integer without `.0`, otherwise Java `Double.toString`.
    ///
    /// Into Jackson goes **not a `double` but the finished text** — that is why frequencies
    /// in `bandplan.yaml` are quoted. Two measured curiosities that
    /// follow: `(long)` overflow is **clamped**, so `1e20` is written as
    /// `9223372036854775807`, and `NaN` escapes equality with `floor`, so it
    /// goes through the second branch and is written literally "NaN".
    private static func fmt(_ khz: Double) -> String {
        khz == khz.rounded(.down) ? String(JavaMath.d2l(khz)) : JavaDouble.toString(khz)
    }
}
