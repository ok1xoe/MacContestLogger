import Testing
@testable import MCLCore

/// Port of the Java `cat/RigModelFilterTest` + `RMF.*` measurements (maintainer-only probe).
@Suite struct RigModelFilterTests {

    private let models: [RigModel] = [
        RigModel(number: 1, mfg: "Hamlib", model: "Dummy"),
        RigModel(number: 2014, mfg: "Kenwood", model: "TS-590S"),
        RigModel(number: 2037, mfg: "Kenwood", model: "TS-590SG"),
        RigModel(number: 2011, mfg: "Kenwood", model: "TS-570"),
        RigModel(number: 1035, mfg: "Yaesu", model: "FT-991A"),
        RigModel(number: 3073, mfg: "Icom", model: "IC-7300"),
    ]

    @Test func manufacturersAreDistinctAndSorted() {
        #expect(RigModelFilter.manufacturers(models) == ["Hamlib", "Icom", "Kenwood", "Yaesu"])
    }

    @Test func searchByPartialNumberFindsAcrossManufacturers() {
        let found = RigModelFilter.filter(models, manufacturer: nil, query: "590")
        #expect(found.count == 2)
        #expect(found.contains { $0.model == "TS-590S" })
        #expect(found.contains { $0.model == "TS-590SG" })
    }

    @Test func searchIgnoresManufacturerFilter() {
        // even with Yaesu selected, searching "590" finds the Kenwoods (searches globally)
        let found = RigModelFilter.filter(models, manufacturer: "Yaesu", query: "590")
        #expect(found.count == 2)
    }

    @Test func manufacturerFilterNarrowsWhenNoQuery() {
        let found = RigModelFilter.filter(models, manufacturer: "Kenwood", query: "")
        #expect(found.count == 3)
        #expect(found.allSatisfy { $0.mfg == "Kenwood" })
    }

    @Test func nullManufacturerReturnsAllSorted() {
        let found = RigModelFilter.filter(models, manufacturer: nil, query: nil)
        #expect(found.count == 6)
        // sorted by manufacturer, then model: Hamlib, Icom, Kenwood(570,590S,590SG), Yaesu
        #expect(found[0].mfg == "Hamlib")
        #expect(found[2].model == "TS-570")
        #expect(found[5].mfg == "Yaesu")
    }

    // MARK: - Measurements (JDK 21.0.2, en_US)

    /// Probe models: manufacturers differing only in letter case, `É`/`ß`/`İ`, `_` and `[` (between upper
    /// and lower case ASCII — `CASE_INSENSITIVE_ORDER` compares after conversion to upper and lower case).
    private static let probeModels: [RigModel] = [
        RigModel(number: 1, mfg: "Hamlib", model: "Dummy"), RigModel(number: 2, mfg: "hamlib", model: "NET rigctl"),
        RigModel(number: 3, mfg: "\u{00C9}lan", model: "X"), RigModel(number: 4, mfg: "elan", model: "y"),
        RigModel(number: 5, mfg: "Zeta", model: "a"), RigModel(number: 6, mfg: "\u{00DF}", model: "S"),
        RigModel(number: 7, mfg: "SS", model: "s"), RigModel(number: 8, mfg: "Kenwood", model: "TS-590SG"),
        RigModel(number: 9, mfg: "kenwood", model: "ts-590s"), RigModel(number: 10, mfg: "I\u{0130}", model: "z"),
        RigModel(number: 11, mfg: "_x", model: "z"), RigModel(number: 12, mfg: "[x", model: "z"),
    ]

    /// `TreeSet(CASE_INSENSITIVE_ORDER)`: first occurrence wins (`Hamlib`, not `hamlib`), `ß` ≠ `SS`, `[x` < `_x`.
    @Test func measuredManufacturers() {
        let expected: [String] = ["[x", "_x", "elan", "Hamlib", "I\u{0130}", "Kenwood", "SS", "Zeta", "\u{00DF}", "\u{00C9}lan"]
        let actual = RigModelFilter.manufacturers(Self.probeModels)
        #expect(actual.map { Array($0.utf16) } == expected.map { Array($0.utf16) })
    }

    /// `RMF.filter`: model numbers in result order. `İ` searches for `i̇` (two units after `toLowerCase`),
    /// so it finds only model 10 (in `tr_TR` it would also find `hamlib` — a deliberate divergence).
    @Test func measuredFilter() {
        let cases: [(String?, String?, [Int])] = [
            (nil, nil, [12, 11, 4, 1, 2, 10, 9, 8, 7, 5, 6, 3]),
            ("", "", [12, 11, 4, 1, 2, 10, 9, 8, 7, 5, 6, 3]),
            ("kenwood", "", [9, 8]),
            (" Kenwood ", nil, [9, 8]),
            ("Yaesu", "590", [9, 8]),
            (nil, "SS", [7]),
            (nil, "\u{00DF}", [6]),
            (nil, " net ", [2]),
            (nil, "\u{0130}", [10]),
            ("ELAN", "", [4]),
            (nil, "\u{00E9}lan x", [3]),
        ]
        for (manufacturer, query, expected) in cases {
            let found = RigModelFilter.filter(Self.probeModels, manufacturer: manufacturer, query: query)
            #expect(found.map(\.number) == expected, "\(String(describing: manufacturer)) / \(String(describing: query))")
        }
    }

    /// `RigModel.toString()` with an em dash U+2014.
    @Test func modelDescription() {
        #expect(RigModel(number: 2037, mfg: "Kenwood", model: "TS-590SG").description == "2037 \u{2014} Kenwood TS-590SG")
    }
}
