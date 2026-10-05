import Testing
@testable import MCLCore

/// Row drafts, `gridLatLon` and the band-plan overlap. Values marked "probe" are measured on the JVM by
/// a maintainer-only probe (`settings-probe.tsv`); the rest is read from
/// `ui/configurer/ConfigurerDraft.kt:536-673`, `AntennasTab.kt:81-88`, `BandPlanTab.kt:34-46`.
@Suite struct ConfigurerRowsTests {

    /// Probe `num`: `numStr` through `BandSegmentDraft`.
    @Test func numStrMatchesKotlin() {
        let cases: [(Double, String)] = [
            (7040.0, "7040"), (7040.5, "7040.5"), (0.0, "0"), (-0.0, "0"), (1.0e7, "10000000"),
            (1.0e-4, "1.0E-4"), (144174.25, "144174.25"), (.nan, "NaN"), (.infinity, "9223372036854775807"),
            (-.infinity, "-9223372036854775808"), (1.0e20, "9223372036854775807"), (-3.0, "-3"), (0.1, "0.1"),
            (10000000.5, "1.00000005E7"),
        ]
        for (value, text) in cases {
            #expect(ConfigurerRows.numStr(value) == text)
            #expect(BandSegmentDraft(region: "R1", mode: "CW", fromKhz: value, toKhz: value).fromKhz == text)
        }
    }

    /// Probe `grid`.
    @Test func gridLatLonMatchesKotlin() {
        let cases: [(String, (String, String)?)] = [
            ("", nil), ("JN79", ("49.5000", "15.0000")), ("JN79FX", ("49.9792", "14.4583")),
            ("jn79fx", ("49.9792", "14.4583")), (" JN79FX ", ("49.9792", "14.4583")), ("JN7", nil),
            ("AA00aa", ("-89.9792", "-179.9583")), ("RR99XX", ("89.9792", "179.9583")), ("ZZ00", nil),
        ]
        for (grid, expected) in cases {
            let got = GridLatLon.of(grid)
            #expect(got?.latitude == expected?.0, "\(grid)")
            #expect(got?.longitude == expected?.1, "\(grid)")
        }
    }

    /// `toSegment`: bounds trimmed and parsed by Kotlin `toDoubleOrNull`, region and mode as they are.
    @Test func segmentConversion() {
        var row = BandSegmentDraft(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040)
        #expect(row.toSegment() == BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040))
        row.fromKhz = " 7000.5 "
        row.toKhz = "1e4"
        #expect(row.toSegment() == BandPlanFile.Segment(region: "R1", mode: "CW", fromKhz: 7000.5, toKhz: 10000))
        row.toKhz = ""
        #expect(row.toSegment() == nil)
        row.toKhz = "7040,5"
        #expect(row.toSegment() == nil)
    }

    /// Probe `digi`: a blank mode or a non-numeric bound → `nil`, the mode is trimmed.
    @Test func channelConversion() {
        func channel(_ mode: String, _ from: String, _ to: String) -> DigiFreqFile.Channel? {
            var row = DigiChannelDraft(mode: "X", fromKhz: 0, toKhz: 0)
            row.mode = mode
            row.fromKhz = from
            row.toKhz = to
            return row.toChannel()
        }
        #expect(channel("FT8", "7074", "7077") == DigiFreqFile.Channel(mode: "FT8", fromKhz: 7074, toKhz: 7077))
        #expect(channel(" FT4 ", "7047.5", "7050") == DigiFreqFile.Channel(mode: "FT4", fromKhz: 7047.5, toKhz: 7050))
        #expect(channel(" ", "1", "2") == nil)
        #expect(channel("FT8", "a", "2") == nil)
    }

    /// Probe `trv`: Kotlin `toLongOrNull` without trimming, `hi <= lo` → `nil`, the name trimmed.
    @Test func transverterConversion() {
        func entry(_ lo: String, _ hi: String, _ off: String) -> TransverterEntry? {
            var row = TransverterDraft(TransverterEntry(name: " 2m ", ifLowKHz: 1, ifHighKHz: 2, offsetKHz: 3, enabled: true))
            row.ifLow = lo
            row.ifHigh = hi
            row.offset = off
            return row.toEntry()
        }
        let twoMetres = TransverterEntry(name: "2m", ifLowKHz: 28000, ifHighKHz: 30000, offsetKHz: 116000, enabled: true)
        #expect(entry("28000", "30000", "116000") == twoMetres)
        #expect(entry("30000", "28000", "1") == nil)
        #expect(entry("28000", "28000", "1") == nil)
        #expect(entry(" 28000", "30000", "1") == nil)
        #expect(entry("+1", "2", "-3") == TransverterEntry(name: "2m", ifLowKHz: 1, ifHighKHz: 2, offsetKHz: -3, enabled: true))
        #expect(entry("1", "x", "1") == nil)
        #expect(entry("1", "2", "") == nil)
        let draft = TransverterDraft(twoMetres)
        #expect([draft.ifLow, draft.ifHigh, draft.offset] == ["28000", "30000", "116000"])
    }

    /// Probe `ant`: code `toIntOrNull() ?: 0` (untrimmed) clamped to 0…15, texts trimmed.
    @Test func antennaConversion() {
        let cases: [(String, Int)] = [("3", 3), (" 3", 0), ("-1", 0), ("16", 15), ("x", 0), ("", 0)]
        for (code, expected) in cases {
            var row = AntennaDraft(AntennaEntry(code: 0, name: " Yagi ", bands: " 20 ", sector: " 0-90 "))
            row.code = code
            #expect(row.toEntry() == AntennaEntry(code: expected, name: "Yagi", bands: "20", sector: "0-90"))
        }
    }

    /// `FunctionKeyDraft.toMessage` trims both fields.
    @Test func functionKeyMessageIsTrimmed() {
        let row = FunctionKeyDraft(label: " CQ ", text: " CQ {MYCALL} ")
        #expect(row.toMessage() == FunctionKeyMessage(label: "CQ", text: "CQ {MYCALL}"))
    }

    /// `applyTo` of a favorite (`ConfigurerDraft.kt:451-459`): name/host trimmed, port untrimmed with the default
    /// port as fallback, login/password untouched, the parallel flag kept.
    @Test func dxFavoriteConversion() {
        var fav = DxClusterFavorite(name: " Node ", host: " dx.example ", port: 8000, login: " me ", password: " pw ")
        fav.parallel = true
        var row = DxFavoriteDraft(fav)
        #expect(row.port == "8000")
        #expect(row.isParallel)
        var expected = DxClusterFavorite(name: "Node", host: "dx.example", port: 8000, login: " me ", password: " pw ")
        expected.parallel = true
        #expect(row.toFavorite() == expected)
        row.port = " 8000"
        #expect(row.toFavorite().port == DxClusterFavorite.defaultPort)
    }

    /// `overlaps` of the Band plan tab: same region exactly, strict bounds, non-numeric rows ignored.
    @Test func bandPlanOverlap() {
        let rows = [
            BandSegmentDraft(region: "R1", mode: "CW", fromKhz: 7000, toKhz: 7040),
            BandSegmentDraft(region: "R1", mode: "DIGI", fromKhz: 7040, toKhz: 7050),
            BandSegmentDraft(region: "R1", mode: "PHONE", fromKhz: 7045, toKhz: 7200),
            BandSegmentDraft(region: "r1", mode: "CW", fromKhz: 7000, toKhz: 7100),
            BandSegmentDraft(region: "R2", mode: "CW", fromKhz: 7000, toKhz: 7300),
        ]
        #expect(!BandPlanOverlap.overlaps(rows, 0))
        #expect(BandPlanOverlap.overlaps(rows, 1))
        #expect(BandPlanOverlap.overlaps(rows, 2))
        #expect(!BandPlanOverlap.overlaps(rows, 3))
        #expect(!BandPlanOverlap.overlaps(rows, 4))
        var broken = rows
        broken[2].toKhz = "x"
        #expect(!BandPlanOverlap.overlaps(broken, 1))
        #expect(!BandPlanOverlap.overlaps(broken, 2))
        #expect(!BandPlanOverlap.overlaps(rows, 9))
    }

    @Test func rowEqualityIgnoresIdentity() {
        let a = BandSegmentDraft(region: "R1", mode: "CW", fromKhz: 1, toKhz: 2)
        let b = BandSegmentDraft(region: "R1", mode: "CW", fromKhz: 1, toKhz: 2)
        #expect(a.id != b.id)
        #expect(a == b)
    }

    /// The catalogues in Kotlin order (`HardwareTab.kt:65, 133, 136`, `BandPlanTab.kt:30-31`, `ModeTabs.kt:62, 167-169,
    /// 261-266`, `ScoreReportingTab.kt:69-72`, `MapStyle.kt:21-42`).
    @Test func catalogues() {
        #expect(ConfigurerCatalogs.baudRates == [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200])
        #expect(ConfigurerCatalogs.regions == ["R1", "R2", "R3"])
        #expect(ConfigurerCatalogs.bandPlanModes == ["CW", "DIGI", "PHONE"])
        #expect(ConfigurerCatalogs.dataModes == ["DIGITAL", "FT8", "FT4", "RTTY", "PSK", "JT65"])
        #expect(ConfigurerCatalogs.footswitchPins == ["CTS", "DSR", "DCD"])
        #expect(ConfigurerCatalogs.footswitchActions == ["PTT", "ENTER", "F1"])
        #expect(ConfigurerCatalogs.accents.map(\.key) == ["TEAL", "BLUE", "ORANGE", "CONTRAST"])
        #expect(ConfigurerCatalogs.accentLabelKey("BLUE") == "Modrá")
        #expect(ConfigurerCatalogs.accentLabelKey("PINK") == "Tyrkysová")
        #expect(ConfigurerCatalogs.scoreboards.map(\.url) == [
            "https://contestonlinescore.com/post/", "https://cqcontest.net/post.php",
        ])
        #expect(ConfigurerCatalogs.mapSchemes.map(\.key) == ["green", "gray", "sepia", "slate"])
        #expect(ConfigurerCatalogs.themeModes.map(\.key) == ["SYSTEM", "LIGHT", "DARK"])
    }
}
