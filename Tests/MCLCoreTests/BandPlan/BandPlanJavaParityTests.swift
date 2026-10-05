import Foundation
import Testing
@testable import MCLCore

/// Behaviour of `bandplan/` that the Java tests **do not cover** — corrupt YAML,
/// an unknown key, a silent fallback, exact bytes of the writer and boundary ranges.
///
/// All expectations are **measured on running Java v1.1.1** (JDK 21.0.2,
/// Jackson 2.22.0 + SnakeYAML 2.5, locale `en`) with a small `Probe.java` against
/// `build/classes/java/main`. They are not designed rules but a capture of
/// the behaviour Java has today — including the part that could be regarded
/// as a defect (silent swallowing of errors, a partial result of `read`).
@Suite struct BandPlanJavaParityTests {

    /// Is the plan indistinguishable from the built-in one? It is compared **segment by segment in
    /// all three regions**, so it does not rely on a single frequency.
    static func isDefault(_ plan: BandPlan) -> Bool {
        let reference = BandPlan.defaultPlan()
        return BandPlan.IaruRegion.allCases.allSatisfy {
            plan.segmentsIn(0, 100_000_000, $0) == reference.segmentsIn(0, 100_000_000, $0)
        }
    }

    private static func seg(_ category: BandPlan.ModeCategory,
                            _ lowHz: Int64, _ highHz: Int64) -> BandPlan.Segment {
        BandPlan.Segment(category: category, lowHz: lowHz, highHz: highHz)
    }

    // MARK: - built-in plan

    /// The whole built-in plan, segment by segment, as printed by `segmentsIn`.
    /// 80 m has only CW and PHONE, because the built-in DIGI 3580–3600 lies **entirely
    /// inside** CW 3500–3600 and the rule "the earlier wins" erases it —
    /// that is how it is in the original (measured), even though it is probably not intended.
    @Test func defaultPlanHasSeventeenVisibleSegments() {
        let segs = BandPlan.defaultPlan().segmentsIn(0, 100_000_000, .r1)
        #expect(segs == [
            Self.seg(.cw, 1_810_000, 1_838_000),
            Self.seg(.digi, 1_838_001, 1_840_000),
            Self.seg(.phone, 1_840_001, 2_000_000),
            Self.seg(.cw, 3_500_000, 3_600_000),
            Self.seg(.phone, 3_600_001, 3_800_000),
            Self.seg(.cw, 7_000_000, 7_040_000),
            Self.seg(.digi, 7_040_001, 7_050_000),
            Self.seg(.phone, 7_050_001, 7_200_000),
            Self.seg(.cw, 14_000_000, 14_070_000),
            Self.seg(.digi, 14_070_001, 14_099_000),
            Self.seg(.phone, 14_101_000, 14_350_000),
            Self.seg(.cw, 21_000_000, 21_070_000),
            Self.seg(.digi, 21_070_001, 21_150_000),
            Self.seg(.phone, 21_151_000, 21_450_000),
            Self.seg(.cw, 28_000_000, 28_070_000),
            Self.seg(.digi, 28_070_001, 28_190_000),
            Self.seg(.phone, 28_300_000, 29_700_000),
        ])
    }

    /// Segment boundaries are **inclusive** and at a junction the earlier wins
    /// (CW before DIGI, DIGI before PHONE).
    /// Frequencies and categories, measured on Java 21.
    static let boundaryCases: [(freqHz: Int64, expected: BandPlan.ModeCategory?)] = [
        (7_000_000, .cw),
        (6_999_999, nil),
        (7_040_000, .cw),
        (7_040_001, .digi),
        (7_050_000, .digi),
        (7_050_001, .phone),
        (7_200_000, .phone),
        (7_200_001, nil),
        (3_580_000, .cw),
        (3_600_000, .cw),
        (3_600_001, .phone),
        (14_099_000, .digi),
        (14_100_000, nil),
        (14_101_000, .phone),
        (21_150_000, .digi),
        (21_150_500, nil),
        (21_151_000, .phone),
        (28_190_000, .digi),
        (28_250_000, nil),
        (Int64.min, nil),
        (Int64.max, nil),
    ]

    @Test(arguments: Self.boundaryCases)
    func modeAtBoundaries(freqHz: Int64, expected: BandPlan.ModeCategory?) {
        #expect(BandPlan.defaultPlan().modeAt(freqHz, .r1) == expected)
    }

    /// `modeAt` on a `nil` region falls back to R1, `segmentsIn` on a `nil` region returns
    /// empty. That asymmetry **is** in Java (`EnumMap.get(null)` does not throw, it only
    /// returns `null`, whereas `segmentsIn` has an explicit test for `null`) and the port
    /// copies it.
    @Test func nilRegionIsAsymmetric() {
        let plan = BandPlan.defaultPlan()
        #expect(plan.modeAt(7_005_000, nil) == .cw)
        #expect(plan.segmentsIn(7_000_000, 7_100_000, nil).isEmpty)
    }

    /// Continent: trimming is Java `trim()`, so a non-breaking space **stays**
    /// and `"\u{00A0}NA"` becomes R1, not R2. A tab, on the other hand, is dropped.
    static let continentCases: [(continent: String, expected: BandPlan.IaruRegion)] = [
        ("AN", .r1),
        ("na", .r2),
        (" na ", .r2),
        ("NA ", .r2),
        ("\tNA\t", .r2),
        ("\u{1C}NA", .r2),
        ("", .r1),
        ("\u{00a0}NA", .r1),
        ("NA\u{00a0}", .r1),
    ]

    @Test(arguments: Self.continentCases)
    func forContinentEdges(continent: String, expected: BandPlan.IaruRegion) {
        #expect(BandPlan.IaruRegion.forContinent(continent) == expected)
    }

    // MARK: - silent fallback: corrupt file and nonsensical structure

    /// **Corrupt YAML gives no error, it gives the built-in plan and an empty list.**
    /// Java catches a bare `Exception` without logging (`BandPlan.java:201`,
    /// `BandPlanFile.java:54`), so the user learns nothing about the broken file.
    /// This is copied deliberately; our YAML reader, however, **throws** the error,
    /// it is just that these two functions swallow it.
    @Test(arguments: [
        // unclosed quote
        "regions:\n  R1:\n  - band: \"x\n    cw: \"7000-7040\"\n",
        // tab in indentation
        "regions:\n\tR1:\n\t- cw: \"7000-7040\"\n",
        // alias without an anchor
        "regions: *chybi\n",
        "regions:\n  R1:\n  - cw: *neni\n",
        // scrambled indentation
        "regions:\n  R1:\n   - cw: \"7000-7040\"\n  X\n",
        // the root is a scalar or a list
        "ahoj\n",
        "- a\n- b\n",
        // `regions` has the wrong shape
        "regions: ahoj\n",
        "regions: []\n",
        // region is not a list
        "regions:\n  R1: ahoj\n",
        // row is not a map
        "regions:\n  R1:\n  - ahoj\n",
        // `null` row (in Java an NPE on `row.cw`)
        "regions:\n  R1:\n  - \n",
        // a structured value in a text field brings down the **whole** file
        "regions:\n  R1:\n  - cw: {a: 1}\n    digi: \"7040-7050\"\n",
        "regions:\n  R1:\n  - cw: [1]\n    digi: \"7040-7050\"\n",
        "regions:\n  R1:\n  - band: {a: 1}\n    cw: \"7000-7040\"\n",
        // only the second row / second region is bad — everything fails anyway
        "regions:\n  R1:\n  - cw: \"7000-7040\"\n  - digi: [1]\n",
        "regions:\n  R1:\n  - cw: \"7000-7040\"\n  R2:\n  - digi: [1]\n",
        // a wrong **shape** of a region or row brings down the file even when
        // a valid region / valid row sits next to it (measured — `continue` would
        // load the valid one here, Java loads nothing)
        "regions:\n  R1: ahoj\n  R2:\n  - cw: \"7000-7040\"\n",
        "regions:\n  R1:\n  - cw: \"7000-7040\"\n  R2: ahoj\n",
        "regions:\n  R1: {a: 1}\n  R2:\n  - cw: \"7000-7040\"\n",
        "regions:\n  R1:\n  - ahoj\n  - cw: \"7000-7040\"\n",
        "regions:\n  R1:\n  - cw: \"7000-7040\"\n  - ahoj\n",
        "regions:\n  R1:\n  - [1, 2]\n  - cw: \"7000-7040\"\n",
        "regions:\n  R1:\n  - 42\n  - cw: \"7000-7040\"\n",
        "regions:\n  R1:\n  - cw: \"7000-7040\"\n  R2:\n  - ahoj\n",
    ])
    func brokenFileSilentlyFallsBack(yaml: String) throws {
        let dir = try BandPlanTestDir.with(yaml)
        defer { BandPlanTestDir.remove(dir) }
        #expect(Self.isDefault(BandPlan.fromDir(dir)), "should be the built-in plan: \(yaml)")
        #expect(BandPlanFile.read(dir).isEmpty, "should be empty: \(yaml)")
    }

    /// An empty document, `null` and a bare `---` give the same as a missing
    /// file. In Java it is three paths to the same end: empty input is
    /// rejected by Jackson with an exception, `null` gives `dto == null`.
    @Test(arguments: ["", "null\n", "---\n", "regions:\n", "regions: {}\n", "{}\n"])
    func emptyDocumentFallsBack(yaml: String) throws {
        let dir = try BandPlanTestDir.with(yaml)
        defer { BandPlanTestDir.remove(dir) }
        #expect(Self.isDefault(BandPlan.fromDir(dir)))
        #expect(BandPlanFile.read(dir).isEmpty)
    }

    /// A `nil` directory, a directory without a file and a `bandplan.yaml` that is a
    /// **directory** — all silently to the defaults.
    @Test func missingAndNonFileInputs() throws {
        #expect(Self.isDefault(BandPlan.fromDir(nil)))
        #expect(BandPlanFile.read(nil).isEmpty)

        let empty = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(empty) }
        #expect(Self.isDefault(BandPlan.fromDir(empty)))
        #expect(BandPlanFile.read(empty).isEmpty)

        let asDir = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(asDir) }
        try FileManager.default.createDirectory(
            at: asDir.appendingPathComponent("bandplan.yaml"), withIntermediateDirectories: true)
        #expect(Self.isDefault(BandPlan.fromDir(asDir)))
        #expect(BandPlanFile.read(asDir).isEmpty)
    }

    /// **An unknown key is ignored** — in a row and in the root (Java has
    /// `FAIL_ON_UNKNOWN_PROPERTIES` off). Keys are, however, **case-sensitive**:
    /// `CW:` is an unknown key, so the segment is not created.
    @Test func unknownKeysAreIgnored() throws {
        let inRow = try BandPlanTestDir.with("""
            regions:
              R1:
              - band: "40m"
                cw: "7000-7040"
                bogus: "nesmysl"
            """)
        defer { BandPlanTestDir.remove(inRow) }
        #expect(BandPlan.fromDir(inRow).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 7_000_000, 7_040_000)])
        #expect(BandPlanFile.read(inRow)
            == [BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040)])

        let atRoot = try BandPlanTestDir.with("""
            verze: 3
            regions:
              R1:
              - cw: "7000-7040"
            extra:
              a: 1
            """)
        defer { BandPlanTestDir.remove(atRoot) }
        #expect(BandPlan.fromDir(atRoot).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 7_000_000, 7_040_000)])

        // Jackson does not merge `<<`, it is an ordinary (and thus unknown) key.
        let merge = try BandPlanTestDir.with("regions:\n  R1:\n  - <<: 1\n    cw: \"7000-7040\"\n")
        defer { BandPlanTestDir.remove(merge) }
        #expect(BandPlan.fromDir(merge).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 7_000_000, 7_040_000)])

        // An uppercase letter in the mode key → unknown key → no segment → default.
        let upper = try BandPlanTestDir.with("regions:\n  R1:\n  - CW: \"7000-7040\"\n")
        defer { BandPlanTestDir.remove(upper) }
        #expect(Self.isDefault(BandPlan.fromDir(upper)))
        #expect(BandPlanFile.read(upper).isEmpty)
    }

    /// Values that Jackson **converts** to `String` (a number, `true`), and those
    /// that bring down the whole load (a map, a list). `cw: 7000` is the text "7000",
    /// i.e. a one-part range, i.e. no segment.
    @Test func scalarsAreCoercedStructuresAreNot() throws {
        for yaml in ["regions:\n  R1:\n  - cw: 7000\n",
                     "regions:\n  R1:\n  - cw: true\n",
                     "regions:\n  R1:\n  - cw: 7000.5\n"] {
            let dir = try BandPlanTestDir.with(yaml)
            defer { BandPlanTestDir.remove(dir) }
            #expect(Self.isDefault(BandPlan.fromDir(dir)), "\(yaml)")
            #expect(BandPlanFile.read(dir).isEmpty, "\(yaml)")
        }
        // An unquoted range is text and passes.
        let plain = try BandPlanTestDir.with("regions:\n  R1:\n  - cw: 7000-7040\n")
        defer { BandPlanTestDir.remove(plain) }
        #expect(BandPlan.fromDir(plain).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 7_000_000, 7_040_000)])
        // A number in `band` does not matter, `band` is not used anywhere.
        let band = try BandPlanTestDir.with("regions:\n  R1:\n  - band: 40\n    cw: \"7000-7040\"\n")
        defer { BandPlanTestDir.remove(band) }
        #expect(BandPlan.fromDir(band).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 7_000_000, 7_040_000)])
    }

    /// A BOM at the start and CRLF breaks are read by Java (SnakeYAML) — and by our reader
    /// too, so a file saved from Windows or from an editor with a BOM loads
    /// the same. Measured on Java 21 and here.
    @Test func bomAndCrlfAreRead() throws {
        for yaml in ["\u{feff}regions:\n  R1:\n  - cw: \"7000-7040\"\n",
                     "regions:\r\n  R1:\r\n  - cw: \"7000-7040\"\r\n"] {
            let dir = try BandPlanTestDir.with(yaml)
            defer { BandPlanTestDir.remove(dir) }
            #expect(BandPlan.fromDir(dir).segmentsIn(0, 100_000_000, .r1)
                == [Self.seg(.cw, 7_000_000, 7_040_000)], "\(yaml.debugDescription)")
            #expect(BandPlanFile.read(dir)
                == [BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040)],
                "\(yaml.debugDescription)")
        }
    }

    /// **A band plan with an anchor loads, it does not silently fall back to the built-in plan.**
    ///
    /// A divergence was once recorded here: the reader rejected the anchor
    /// and `fromDir`/`read` swallowed that error, so a hand-written file with an anchor was
    /// **silently** dropped, whereas the Java application loads it. That was exactly the
    /// dangerous direction (silent loss of the user's definition), so the
    /// **reader** was fixed — the anchor is read and discarded as in Java.
    @Test func anchorInBandplanFileIsLoadedNotSwallowed() throws {
        // An anchor on a value, on a row and on a region — all three levels at once.
        let dir = try BandPlanTestDir.with("""
            regions:
              R1: &s
              - &r
                cw: &c "7000-7040"
            """)
        defer { BandPlanTestDir.remove(dir) }
        #expect(BandPlan.fromDir(dir).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 7_000_000, 7_040_000)])
        #expect(BandPlanFile.read(dir)
            == [BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040)])
        #expect(!Self.isDefault(BandPlan.fromDir(dir)), "must not be the built-in plan")

        // Sharing segments via an **alias** Java cannot handle (`R2: *s` is in its
        // tree the text "s"), so it too falls back to the built-in plan there — and we
        // do too, just by a different route (the reader rejects an alias). Measured.
        let alias = try BandPlanTestDir.with("""
            regions:
              R1: &s
              - cw: "7000-7040"
              R2: *s
            """)
        defer { BandPlanTestDir.remove(alias) }
        #expect(Self.isDefault(BandPlan.fromDir(alias)))
        #expect(BandPlanFile.read(alias).isEmpty)
    }

    // MARK: - regions

    /// Unknown region `R4`: `BandPlan.fromDir` **drops** it, `BandPlanFile.read`
    /// **keeps** it (uppercase, without an enum check). That asymmetry
    /// is in Java and is visible in the editor: a row with R4 is shown in the UI, but has
    /// no effect on the plan.
    @Test func unknownRegionIsDroppedByPlanButKeptByFile() throws {
        let only = try BandPlanTestDir.with("regions:\n  R4:\n  - cw: \"7000-7040\"\n")
        defer { BandPlanTestDir.remove(only) }
        #expect(Self.isDefault(BandPlan.fromDir(only)))
        #expect(BandPlanFile.read(only)
            == [BandPlanFile.Segment(region: "R4", mode: "CW", fromKhz: 7000, toKhz: 7040)])

        let mixed = try BandPlanTestDir.with("""
            regions:
              R4:
              - cw: "7000-7040"
              R2:
              - cw: "7000-7040"
            """)
        defer { BandPlanTestDir.remove(mixed) }
        let plan = BandPlan.fromDir(mixed)
        #expect(plan.segmentsIn(0, 100_000_000, .r2) == [Self.seg(.cw, 7_000_000, 7_040_000)])
        // R1 and R3 are not in the file, they are filled in from the built-in plan.
        #expect(plan.segmentsIn(0, 100_000_000, .r1)
            == BandPlan.defaultPlan().segmentsIn(0, 100_000_000, .r1))
        #expect(BandPlanFile.read(mixed).map(\.region) == ["R4", "R2"])
    }

    /// The region name is trimmed by Java `trim()` and uppercased.
    /// A non-breaking space is **not dropped**, so `"\u{00A0}R2"` is not a region —
    /// `fromDir` drops it and `read` keeps `"\u{00A0}R2"` literally.
    @Test func regionKeyIsTrimmedAndUppercased() throws {
        for key in ["r2", "\" R2 \"", "\"R2\\t\""] {
            let dir = try BandPlanTestDir.with("regions:\n  \(key):\n  - cw: \"7000-7040\"\n")
            defer { BandPlanTestDir.remove(dir) }
            #expect(BandPlan.fromDir(dir).segmentsIn(0, 100_000_000, .r2)
                == [Self.seg(.cw, 7_000_000, 7_040_000)], "\(key)")
            #expect(BandPlanFile.read(dir).map(\.region) == ["R2"], "\(key)")
        }
        let nbsp = try BandPlanTestDir.with("regions:\n  \"\\u00a0R2\":\n  - cw: \"7000-7040\"\n")
        defer { BandPlanTestDir.remove(nbsp) }
        #expect(Self.isDefault(BandPlan.fromDir(nbsp)))
        #expect(BandPlanFile.read(nbsp).map(\.region) == ["\u{00a0}R2"])
    }

    /// Duplicate region: the **last** value wins (Jackson fills a
    /// `LinkedHashMap`), so nothing remains of the first `R1`.
    @Test func duplicateRegionKeepsTheLastOne() throws {
        let dir = try BandPlanTestDir.with("""
            regions:
              R1:
              - cw: "7000-7100"
              R1:
              - cw: "7200-7300"
            """)
        defer { BandPlanTestDir.remove(dir) }
        #expect(BandPlan.fromDir(dir).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 7_200_000, 7_300_000)])
        #expect(BandPlanFile.read(dir)
            == [BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7200, toKhz: 7300)])
    }

    /// A missing region is filled in from R1, and when R1 is not in the file, from the built-in
    /// plan. An empty segment list **does not count** as a supplied region.
    @Test func missingRegionsFallBack() throws {
        let onlyR2 = try BandPlanTestDir.with("""
            regions:
              R2:
              - band: "40m"
                cw: "7000-7040"
                digi: "7040-7080"
                phone: "7080-7300"
            """)
        defer { BandPlanTestDir.remove(onlyR2) }
        let plan = BandPlan.fromDir(onlyR2)
        #expect(plan.modeAt(7_250_000, .r2) == .phone)
        #expect(plan.modeAt(7_250_000, .r1) == nil)
        #expect(plan.modeAt(7_250_000, .r3) == nil)
        #expect(plan.modeAt(3_550_000, .r1) == .cw, "R1 has the built-in segments")
        #expect(plan.modeAt(3_550_000, .r2) == nil, "R2 from YAML knows only 40 m")

        // R1 supplied in the file becomes the fallback for R2 and R3.
        let onlyR1 = try BandPlanTestDir.with("regions:\n  R1:\n  - cw: \"7000-7100\"\n")
        defer { BandPlanTestDir.remove(onlyR1) }
        let shared = BandPlan.fromDir(onlyR1)
        for region in BandPlan.IaruRegion.allCases {
            #expect(shared.segmentsIn(0, 100_000_000, region)
                == [Self.seg(.cw, 7_000_000, 7_100_000)], "\(region)")
        }

        // An empty list at R1 → R1 is taken as not supplied → built-in segments.
        let emptyR1 = try BandPlanTestDir.with("""
            regions:
              R1: []
              R2:
              - cw: "7000-7100"
            """)
        defer { BandPlanTestDir.remove(emptyR1) }
        let mixed = BandPlan.fromDir(emptyR1)
        #expect(mixed.segmentsIn(0, 100_000_000, .r1)
            == BandPlan.defaultPlan().segmentsIn(0, 100_000_000, .r1))
        #expect(mixed.segmentsIn(0, 100_000_000, .r2) == [Self.seg(.cw, 7_000_000, 7_100_000)])
        #expect(mixed.segmentsIn(0, 100_000_000, .r3)
            == BandPlan.defaultPlan().segmentsIn(0, 100_000_000, .r1))

        // A region with `null` instead of a list is skipped (and does not crash).
        let nullRegion = try BandPlanTestDir.with("regions:\n  R1:\n  R2:\n  - cw: \"7000-7100\"\n")
        defer { BandPlanTestDir.remove(nullRegion) }
        #expect(BandPlan.fromDir(nullRegion).segmentsIn(0, 100_000_000, .r2)
            == [Self.seg(.cw, 7_000_000, 7_100_000)])
        #expect(BandPlanFile.read(nullRegion).map(\.region) == ["R2"])
    }

    /// All ranges in the file invalid → no region is filled in →
    /// the built-in plan.
    @Test func allRangesInvalidFallsBack() throws {
        let dir = try BandPlanTestDir.with("regions:\n  R1:\n  - cw: \"nesmysl\"\n")
        defer { BandPlanTestDir.remove(dir) }
        #expect(Self.isDefault(BandPlan.fromDir(dir)))
        #expect(BandPlanFile.read(dir).isEmpty)
    }

    /// A row with several modes gives segments in the order **CW, DIGI, PHONE** (that is
    /// the call order in Java, not the key order in the file) — and in `BandPlan` that same
    /// order decides who wins on a shared boundary: `cw: 7000-7040`
    /// and `digi: 7040-7080` overlap at 7040 kHz and CW wins.
    @Test func modesOfOneRowComeInCwDigiPhoneOrder() throws {
        let dir = try BandPlanTestDir.with("""
            regions:
              R2:
              - band: "40m"
                phone: "7080-7300"
                digi: "7040-7080"
                cw: "7000-7040"
            """)
        defer { BandPlanTestDir.remove(dir) }
        #expect(BandPlanFile.read(dir) == [
            BandPlanFile.Segment(region: "R2", mode: "CW", fromKhz: 7000, toKhz: 7040),
            BandPlanFile.Segment(region: "R2", mode: "DIGI", fromKhz: 7040, toKhz: 7080),
            BandPlanFile.Segment(region: "R2", mode: "PHONE", fromKhz: 7080, toKhz: 7300),
        ])
        let plan = BandPlan.fromDir(dir)
        #expect(plan.modeAt(7_040_000, .r2) == .cw, "CW is earlier, the boundary belongs to it")
        #expect(plan.modeAt(7_080_000, .r2) == .digi)
        #expect(plan.segmentsIn(7_000_000, 7_300_000, .r2) == [
            Self.seg(.cw, 7_000_000, 7_040_000),
            Self.seg(.digi, 7_040_001, 7_080_000),
            Self.seg(.phone, 7_080_001, 7_300_000),
        ])
    }

    // MARK: - partial result of `read`

    /// **`BandPlanFile.read` returns a half-written list, not an empty one.** The Java
    /// `catch` has `return out`, and `out` is already filled, so a `null` row
    /// (the only exception that falls **inside** the loop, not during binding)
    /// drops only the rest. `BandPlan.fromDir`, on the other hand, returns the whole default plan.
    /// Measured on Java 21; no Java test guards it.
    @Test func readKeepsSegmentsFoundBeforeTheNullRow() throws {
        let after = try BandPlanTestDir.with("""
            regions:
              R1:
              - cw: "7000-7040"
              - digi: "7040-7050"
              R2:
              - phone: "7050-7200"
              - 
            """)
        defer { BandPlanTestDir.remove(after) }
        #expect(BandPlanFile.read(after) == [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040),
            BandPlanFile.Segment(region: "R1", mode: "DIGI", fromKhz: 7040, toKhz: 7050),
            BandPlanFile.Segment(region: "R2", mode: "PHONE", fromKhz: 7050, toKhz: 7200),
        ])
        #expect(Self.isDefault(BandPlan.fromDir(after)), "the plan does not know a partial result")

        // A `null` row first → nothing remains.
        let before = try BandPlanTestDir.with("regions:\n  R1:\n  - \n  - cw: \"7000-7040\"\n")
        defer { BandPlanTestDir.remove(before) }
        #expect(BandPlanFile.read(before).isEmpty)
    }

    // MARK: - ranges

    /// Range `"low-high"`: Java `split("-")` + `Double.parseDouble`.
    /// The whole table is measured; `nil` means "Java does not make a segment from it".
    /// Inputs and results of the Java `parseRange`, measured on JDK 21.
    static let rangeCases: [(range: String, expected: (Double, Double)?)] = [
        ("7000-7040", (7000.0, 7040.0)),
        (" 7000 - 7040 ", (7000.0, 7040.0)),
        ("7000-7040 ", (7000.0, 7040.0)),
        ("7000.0-7040.0", (7000.0, 7040.0)),
        ("+7000-7040", (7000.0, 7040.0)),
        ("7000.5-7040.25", (7000.5, 7040.25)),
        ("1e3-2e3", (1000.0, 2000.0)),
        ("7000-7040.6667", (7000.0, 7040.6667)),
        ("7040-7000", (7040.0, 7000.0)),
        ("7000d-7040f", (7000.0, 7040.0)),
        // trailing empty parts are dropped by `split`, so a negative number is not read
        ("7000-7040-7080", nil),
        ("-7000-7040", nil),
        ("7000-", nil),
        ("7000--7040", nil),
        ("-", nil),
        ("", nil),
        ("   ", nil),
        ("abc-def", nil),
        ("7,5-8", nil),
        // hex without `p` and lowercase `inf`/`nan` Java does not accept
        ("0x10-0x20", nil),
        ("inf-7040", nil),
        ("nan-7040", nil),
        ("\u{00a0}7000-7040", nil),
    ]

    @Test(arguments: Self.rangeCases)
    func parseRangeTable(range: String, expected: (Double, Double)?) {
        let actual = BandPlanFile.parseRange(range)
        #expect(actual?.from == expected?.0, "\(range)")
        #expect(actual?.to == expected?.1, "\(range)")
        #expect((actual == nil) == (expected == nil), "\(range)")
    }

    /// Java accepts `Infinity` and `NaN` — and `Math.round` turns them into `Long.MAX_VALUE`
    /// and **zero**. A segment from 0 Hz out of the range `"NaN-7040"` is measured, not invented.
    @Test func infinityAndNaNSurviveIntoSegments() throws {
        #expect(BandPlanFile.parseRange("Infinity-7040")?.from == .infinity)
        #expect(BandPlanFile.parseRange("NaN-7040")?.from.isNaN == true)

        let nan = try BandPlanTestDir.with("regions:\n  R1:\n  - cw: \"NaN-7040\"\n")
        defer { BandPlanTestDir.remove(nan) }
        #expect(BandPlan.fromDir(nan).segmentsIn(0, 100_000_000, .r1)
            == [Self.seg(.cw, 0, 7_040_000)])

        let nanPlan = BandPlan.fromDir(nan)
        #expect(nanPlan.modeAt(0, .r1) == .cw, "the segment starts at 0 Hz")
        #expect(nanPlan.modeAt(-1, .r1) == nil)

        let inf = try BandPlanTestDir.with("regions:\n  R1:\n  - cw: \"Infinity-7040\"\n")
        defer { BandPlanTestDir.remove(inf) }
        let plan = BandPlan.fromDir(inf)
        // `Infinity` gives `lowHz = Long.MAX_VALUE`, i.e. a reversed segment —
        // it is in the plan but **is not visible anywhere**, not even at `Long.MAX_VALUE`
        // (it fails on `freqHz <= highHz` there). Measured.
        #expect(plan.segmentsIn(0, 100_000_000, .r1).isEmpty)
        #expect(plan.segmentsIn(Int64.min / 4, Int64.max / 4, .r1).isEmpty)
        #expect(plan.modeAt(Int64.max, .r1) == nil)
        #expect(plan.modeAt(7_020_000, .r1) == nil)
        #expect(!Self.isDefault(plan), "but the plan is not the default, the segment is in it")
    }

    /// Inputs and results of the Java `Math.round`, measured on JDK 21.
    static let roundCases: [(value: Double, expected: Int64)] = [
        (0.4, 0),
        (0.5, 1),
        (-0.5, 0),
        (0.49999999999999994, 0),
        (2.5, 3),
        (-2.5, -2),
        (7_040_666.7, 7_040_667),
        (Double.nan, 0),
        (Double.infinity, Int64.max),
        (-Double.infinity, Int64.min),
        (1e300, Int64.max),
        (-1e300, Int64.min),
    ]

    /// Java `Math.round(double)`: halves **up** (not away from zero, so `-0.5`
    /// is 0 and `-2.5` is −2), `NaN` is 0 and overflow is clamped to the extreme `long`.
    /// Swift `rounded()` would give `-1`, `-3` and would crash on `NaN`.
    @Test(arguments: Self.roundCases)
    func javaRoundTable(value: Double, expected: Int64) {
        #expect(BandPlan.javaRound(value) == expected)
    }

    /// And the same through `khz`, which in Java multiplies by a thousand and then rounds.
    @Test func khzRoundsAfterScaling() {
        #expect(BandPlan.khz(7040.6667) == 7_040_667)
        #expect(BandPlan.khz(0.0005) == 1, "0.0005 * 1000.0 is exactly 0.5 (measured)")
        #expect(BandPlan.khz(0.0004) == 0)
        #expect(BandPlan.khz(.nan) == 0)
        #expect(BandPlan.khz(.infinity) == Int64.max)
    }

    /// Java `String.split("-")`: trailing empty parts are dropped, middle ones are not,
    /// and text without a hyphen is returned whole (even empty).
    static let splitCases: [(text: String, expected: [String])] = [
        ("7000-7040", ["7000", "7040"]),
        ("7000-", ["7000"]),
        ("-7000", ["", "7000"]),
        ("-", [String]()),
        ("--", []),
        ("7000--7040", ["7000", "", "7040"]),
        ("", [""]),
        ("7000", ["7000"]),
        ("a-b-", ["a", "b"]),
    ]

    @Test(arguments: Self.splitCases)
    func splitOnDashMatchesJava(text: String, expected: [String]) {
        #expect(BandPlanFile.splitOnDash(text) == expected, "\(text)")
    }

    // MARK: - segmentsIn: overlaps

    /// A later segment that **wraps** an earlier one splits into two pieces
    /// — and after clipping the window both remain. Measured.
    @Test func laterSegmentWrappingAnEarlierOneSplitsInTwo() throws {
        let dir = try BandPlanTestDir.with("""
            regions:
              R1:
              - cw: "7050-7060"
              - phone: "7000-7100"
            """)
        defer { BandPlanTestDir.remove(dir) }
        let plan = BandPlan.fromDir(dir)
        #expect(plan.segmentsIn(0, 100_000_000, .r1) == [
            Self.seg(.phone, 7_000_000, 7_049_999),
            Self.seg(.cw, 7_050_000, 7_060_000),
            Self.seg(.phone, 7_060_001, 7_100_000),
        ])
        #expect(plan.segmentsIn(7_040_000, 7_070_000, .r1) == [
            Self.seg(.phone, 7_040_000, 7_049_999),
            Self.seg(.cw, 7_050_000, 7_060_000),
            Self.seg(.phone, 7_060_001, 7_070_000),
        ])
    }

    /// Three layers: PHONE is subtracted from CW **and** from DIGI and splits into three pieces.
    @Test func threeLayersSubtractCumulatively() throws {
        let dir = try BandPlanTestDir.with("""
            regions:
              R1:
              - cw: "7020-7030"
              - digi: "7050-7060"
              - phone: "7000-7100"
            """)
        defer { BandPlanTestDir.remove(dir) }
        #expect(BandPlan.fromDir(dir).segmentsIn(0, 100_000_000, .r1) == [
            Self.seg(.phone, 7_000_000, 7_019_999),
            Self.seg(.cw, 7_020_000, 7_030_000),
            Self.seg(.phone, 7_030_001, 7_049_999),
            Self.seg(.digi, 7_050_000, 7_060_000),
            Self.seg(.phone, 7_060_001, 7_100_000),
        ])
    }

    /// The output is **sorted by `lowHz`**, even though the file does not keep the order.
    @Test func outputIsSortedByLowFrequency() throws {
        let dir = try BandPlanTestDir.with("""
            regions:
              R1:
              - phone: "7100-7200"
              - cw: "7000-7040"
            """)
        defer { BandPlanTestDir.remove(dir) }
        #expect(BandPlan.fromDir(dir).segmentsIn(0, 100_000_000, .r1) == [
            Self.seg(.cw, 7_000_000, 7_040_000),
            Self.seg(.phone, 7_100_000, 7_200_000),
        ])
    }

    /// A reversed segment in the file (`"7040-7000"`) is not drawn and `modeAt` does
    /// not find it — but the plan is **not** the default, the segment is in it.
    @Test func reversedSegmentInFileIsInvisible() throws {
        let dir = try BandPlanTestDir.with("regions:\n  R1:\n  - cw: \"7040-7000\"\n")
        defer { BandPlanTestDir.remove(dir) }
        let plan = BandPlan.fromDir(dir)
        #expect(plan.segmentsIn(0, 100_000_000, .r1).isEmpty)
        #expect(plan.modeAt(7_020_000, .r1) == nil)
        #expect(!Self.isDefault(plan), "the segment is there, it is just not visible")
    }

    /// A zero-width window: on a segment it gives a single-point range, outside it gives empty.
    @Test func zeroWidthWindow() {
        let plan = BandPlan.defaultPlan()
        #expect(plan.segmentsIn(7_005_000, 7_005_000, .r1) == [Self.seg(.cw, 7_005_000, 7_005_000)])
        #expect(plan.segmentsIn(9_000_000, 9_000_000, .r1).isEmpty)
    }

    // MARK: - overlaps

    /// The `overlaps` table, fully measured. Touching at a boundary is **not** an overlap,
    /// the region is compared case-insensitively, a `nil` region does not crash
    /// and a `selfIndex` out of range simply never equals.
    @Test func overlapsTable() {
        let segs = [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040),
            BandPlanFile.Segment(region: "R1", mode: "DIGI", fromKhz: 7040, toKhz: 7050),
        ]
        #expect(BandPlanFile.overlaps(segs, "R1", 7030, 7045, -1))
        #expect(!BandPlanFile.overlaps(segs, "R1", 7050, 7100, -1))
        #expect(!BandPlanFile.overlaps(segs, "R2", 7000, 7040, -1))
        #expect(!BandPlanFile.overlaps(segs, "R1", 7000, 7040, 0))
        #expect(BandPlanFile.overlaps(segs, "R1", 7000, 7040, 1))
        #expect(BandPlanFile.overlaps(segs, "r1", 7000, 7040, -1))
        #expect(!BandPlanFile.overlaps(segs, "R1", 6900, 7000, -1), "touching from below")
        #expect(BandPlanFile.overlaps(segs, "R1", 7039.999, 7040, -1))
        #expect(BandPlanFile.overlaps(segs, "R1", 7010, 7010, -1), "point inside")
        #expect(!BandPlanFile.overlaps(segs, "R1", 7000, 7000, -1), "point at the lower boundary")
        #expect(!BandPlanFile.overlaps(segs, "R1", 7040, 7040, -1), "point at the boundary of two ranges")
        #expect(!BandPlanFile.overlaps(segs, "R1", 7045, 7030, -1), "reversed range")
        #expect(!BandPlanFile.overlaps([], "R1", 7000, 7040, -1))
        #expect(BandPlanFile.overlaps(segs, "R1", 7000, 7040, 99), "selfIndex out of range")
        #expect(!BandPlanFile.overlaps(segs, nil, 7000, 7040, -1), "region nil nespadne")
    }

    /// `Segment` is a `record` in Java, so `equals` compares `double` **bitwise**:
    /// `NaN` equals `NaN` and `0.0` does not equal `-0.0`. Swift synthesis does both
    /// the other way round, so `==` is written by hand.
    @Test func segmentEqualityFollowsJavaRecord() {
        let nanA = BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: .nan, toKhz: 7040)
        let nanB = BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: .nan, toKhz: 7040)
        #expect(nanA == nanB)
        let plus = BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 0.0, toKhz: 1)
        let minus = BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: -0.0, toKhz: 1)
        #expect(plus != minus)
    }

    // MARK: - writing

    /// **The exact bytes printed by the Java `write`.** The format is not ours — it is
    /// the format of the user's file, so the whole text is compared, not just the structure.
    /// The `band: ""` on every row comes from here.
    @Test func writeProducesJacksonBytes() throws {
        let dir = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(dir) }
        try BandPlanFile.write(dir, [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040),
            BandPlanFile.Segment(region: "R1", mode: "PHONE", fromKhz: 7050, toKhz: 7200),
            BandPlanFile.Segment(region: "R2", mode: "CW", fromKhz: 7000, toKhz: 7040),
        ])
        #expect(try Self.text(dir) == """
            ---
            regions:
              R1:
              - band: ""
                cw: "7000-7040"
              - band: ""
                phone: "7050-7200"
              R2:
              - band: ""
                cw: "7000-7040"

            """)
    }

    /// Further measured output shapes: an empty list, decimal numbers via Java
    /// `Double.toString`, a lowercase mode, mode `BAND` (overwrites the `band` key),
    /// a region with spaces (Jackson quotes the key **with single quotes**) and `(long)` overflow
    /// for huge values.
    @Test func writeEdgeCases() throws {
        let empty = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(empty) }
        try BandPlanFile.write(empty, [])
        #expect(try Self.text(empty) == "---\nregions: {}\n")

        let fractional = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(fractional) }
        try BandPlanFile.write(fractional, [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000.5, toKhz: 7040.25),
            BandPlanFile.Segment(region: "R1", mode: "DIGI", fromKhz: 0.1, toKhz: 1.0 / 3.0),
        ])
        #expect(try Self.text(fractional) == """
            ---
            regions:
              R1:
              - band: ""
                cw: "7000.5-7040.25"
              - band: ""
                digi: "0.1-0.3333333333333333"

            """)

        let lower = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(lower) }
        try BandPlanFile.write(lower, [
            BandPlanFile.Segment(region: "r1", mode: "cw", fromKhz: 7000, toKhz: 7040),
        ])
        #expect(try Self.text(lower) == "---\nregions:\n  R1:\n  - band: \"\"\n    cw: \"7000-7040\"\n")

        let collision = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(collision) }
        try BandPlanFile.write(collision, [
            BandPlanFile.Segment(region: "R1", mode: "BAND", fromKhz: 7000, toKhz: 7040),
        ])
        #expect(try Self.text(collision) == "---\nregions:\n  R1:\n  - band: \"7000-7040\"\n")
        #expect(BandPlanFile.read(collision).isEmpty, "and nothing can be read back from it")

        let spaced = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(spaced) }
        try BandPlanFile.write(spaced, [
            BandPlanFile.Segment(region: " r4 ", mode: "CW", fromKhz: 7000, toKhz: 7040),
        ])
        #expect(try Self.text(spaced)
            == "---\nregions:\n  ' R4 ':\n  - band: \"\"\n    cw: \"7000-7040\"\n")
        #expect(BandPlanFile.read(spaced).map(\.region) == ["R4"])

        let extremes = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(extremes) }
        try BandPlanFile.write(extremes, [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 1e20, toKhz: 1e21),
            BandPlanFile.Segment(region: "R1", mode: "DIGI", fromKhz: .infinity, toKhz: .nan),
            BandPlanFile.Segment(region: "R1", mode: "PHONE", fromKhz: -0.0, toKhz: 1e15),
        ])
        #expect(try Self.text(extremes) == """
            ---
            regions:
              R1:
              - band: ""
                cw: "9223372036854775807-9223372036854775807"
              - band: ""
                digi: "9223372036854775807-NaN"
              - band: ""
                phone: "0-1000000000000000"

            """)
    }

    /// Writing also creates a deep path and **overwrites** an existing file entirely.
    @Test func writeCreatesDirectoriesAndOverwrites() throws {
        let root = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(root) }
        let deep = root.appendingPathComponent("a/b/c")
        try BandPlanFile.write(deep, [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040),
        ])
        #expect(BandPlanFile.read(deep).count == 1)

        try BandPlanFile.write(deep, [
            BandPlanFile.Segment(region: "R3", mode: "DIGI", fromKhz: 1, toKhz: 2),
        ])
        #expect(try Self.text(deep) == "---\nregions:\n  R3:\n  - band: \"\"\n    digi: \"1-2\"\n")
    }

    // MARK: - the real contest-data/bandplan.yaml

    private static func fixtureDir() throws -> URL {
        try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
    }

    private static func text(_ dir: URL) throws -> String {
        try String(contentsOf: dir.appendingPathComponent("bandplan.yaml"), encoding: .utf8)
    }

    /// **`band` is an empty string in the whole file** — on all 54 rows.
    /// So the field carries nothing and no test can lean on it; the writer
    /// always puts `""` into it.
    @Test func bandFieldIsEmptyOnEveryRowOfTheRealFile() throws {
        let yaml = try Self.text(try Self.fixtureDir())
        let bandLines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("band:") }
        #expect(bandLines.count == 54)
        #expect(bandLines.allSatisfy { $0.trimmingCharacters(in: .whitespaces) == "- band: \"\"" })

        let document = try YamlParser.parse(yaml)
        let dto = try #require(try BandPlan.PlanDto.decode(document))
        let rows = try #require(dto.regions).flatMap { $0.rows ?? [] }
        #expect(rows.count == 54)
        #expect(rows.allSatisfy { $0?.band == "" })
    }

    /// The real file is read entirely: 18 segments per region.
    @Test func realFileReadsFiftyFourSegments() throws {
        let segs = BandPlanFile.read(try Self.fixtureDir())
        #expect(segs.count == 54)
        #expect(segs.filter { $0.region == "R1" }.count == 18)
        #expect(segs.filter { $0.region == "R2" }.count == 18)
        #expect(segs.filter { $0.region == "R3" }.count == 18)
        #expect(segs.prefix(3) == [
            BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 1810, toKhz: 1838),
            BandPlanFile.Segment(region: "R1", mode: "DIGI", fromKhz: 1838, toKhz: 1840),
            BandPlanFile.Segment(region: "R1", mode: "PHONE", fromKhz: 1840, toKhz: 2000),
        ])
        #expect(segs.last == BandPlanFile.Segment(region: "R3", mode: "PHONE",
                                                 fromKhz: 28300, toKhz: 29700))
    }

    /// **`write(read(file))` gives the same file byte for byte.** The strongest
    /// parity measure of the whole package: if the writer, the reader, `fmt`
    /// or the region order diverged, this fails. Measured on Java too (it holds there as well).
    @Test func writeAfterReadReproducesTheRealFileByteForByte() throws {
        let source = try Self.fixtureDir()
        let target = try BandPlanTestDir.empty()
        defer { BandPlanTestDir.remove(target) }
        try BandPlanFile.write(target, BandPlanFile.read(source))
        let written = try Self.text(target)
        let original = try Self.text(source)
        #expect(written == original)
    }

    /// The real file in `BandPlan`: R2 has digi **inside** cw on 80 m, so
    /// DIGI is not drawn, and on 40 m phone reaches up to 7300 kHz.
    @Test func realFileSegmentsPerRegion() throws {
        let plan = BandPlan.fromDir(try Self.fixtureDir())

        #expect(plan.segmentsIn(3_500_000, 4_000_000, .r1) == [
            Self.seg(.cw, 3_500_000, 3_570_000),
            Self.seg(.digi, 3_570_001, 3_600_000),
            Self.seg(.phone, 3_600_001, 3_800_000),
        ])
        #expect(plan.segmentsIn(3_500_000, 4_000_000, .r2) == [
            Self.seg(.cw, 3_500_000, 3_600_000),
            Self.seg(.phone, 3_600_001, 4_000_000),
        ])
        #expect(plan.segmentsIn(3_500_000, 4_000_000, .r3) == [
            Self.seg(.cw, 3_500_000, 3_600_000),
            Self.seg(.phone, 3_600_001, 3_900_000),
        ])
        #expect(plan.segmentsIn(7_000_000, 7_300_000, .r2) == [
            Self.seg(.cw, 7_000_000, 7_040_000),
            Self.seg(.digi, 7_040_001, 7_080_000),
            Self.seg(.phone, 7_080_001, 7_300_000),
        ])
        #expect(plan.modeAt(1_850_000, .r1) == .phone)
        #expect(plan.modeAt(14_060_000, .r3) == .cw)
        #expect(plan.modeAt(28_400_000, .r2) == .phone)
        #expect(plan.modeAt(7_250_000, .r2) == .phone)
        #expect(plan.modeAt(7_250_000, .r1) == nil)
    }
}
