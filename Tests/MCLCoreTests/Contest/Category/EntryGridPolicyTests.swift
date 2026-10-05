import Testing
@testable import MCLCore

/// Port of the Java `EntryGridPolicyTest` (11 tests) + new cases
/// (probe `ProbeCat`, a maintainer-only probe).
@Suite struct EntryGridPolicyTests {

    typealias Column = EntryGridPolicy.ModeColumn

    // MARK: - Java EntryGridPolicyTest

    @Test func columnOfMapsEachMode() {
        #expect(EntryGridPolicy.columnOf("CW") == .CW)
        #expect(EntryGridPolicy.columnOf("SSB") == .PH)
        #expect(EntryGridPolicy.columnOf("FM") == .PH)
        #expect(EntryGridPolicy.columnOf("AM") == .PH)
        #expect(EntryGridPolicy.columnOf("RTTY") == .RY)
        #expect(EntryGridPolicy.columnOf("DIGITAL") == .DI)
        #expect(EntryGridPolicy.columnOf("PSK") == .DI)
        #expect(EntryGridPolicy.columnOf("FT8") == .DI)
        #expect(EntryGridPolicy.columnOf("FT4") == .DI)
        #expect(EntryGridPolicy.columnOf("DIGI") == .DI)
    }

    @Test func columnOfCaseInsensitive() {
        #expect(EntryGridPolicy.columnOf("cw") == .CW)
        #expect(EntryGridPolicy.columnOf(" ssb ") == .PH)
    }

    @Test func columnOfUnknownIsNull() {
        #expect(EntryGridPolicy.columnOf("XYZ") == nil)
        #expect(EntryGridPolicy.columnOf("") == nil)
        #expect(EntryGridPolicy.columnOf(nil) == nil)
    }

    @Test func columnsForSingleMode() {
        #expect(EntryGridPolicy.columnsFor("CW", ["CW"]) == [.CW])
        #expect(EntryGridPolicy.columnsFor("SSB", ["SSB"]) == [.PH])
        #expect(EntryGridPolicy.columnsFor("RTTY", ["RTTY"]) == [.RY])
        #expect(EntryGridPolicy.columnsFor("DIGITAL", ["DIGITAL"]) == [.DI])
    }

    @Test func columnsForMixedIsUnionOfDefinitionModes() {
        #expect(EntryGridPolicy.columnsFor("MIXED", ["CW", "SSB"]) == [.CW, .PH])
        #expect(EntryGridPolicy.columnsFor("MIXED", ["SSB", "DIGITAL"]) == [.PH, .DI])
        #expect(EntryGridPolicy.columnsFor("MIXED", ["CW", "SSB", "RTTY"]) == [.CW, .PH, .RY])
    }

    @Test func columnsForEmptyOrUnknownIsAll() {
        let all = Set(Column.allCases)
        #expect(EntryGridPolicy.columnsFor(nil, []) == all)
        #expect(EntryGridPolicy.columnsFor("", []) == all)
        #expect(EntryGridPolicy.columnsFor("XYZ", []) == all)
    }

    @Test func bandsForAllUsesDefinitionBands() {
        #expect(EntryGridPolicy.bandsFor("ALL", ["160m", "80m"]) == [.m160, .m80])
    }

    /// Entry grid rows are taken from the definition's bands (`bandsFor("ALL", …)`), so free
    /// logging must map WARC and VHF/UHF too — otherwise the grid would have no row for them.
    @Test func bandsForAllMapsWarcAndVhfBands() {
        #expect(EntryGridPolicy.bandsFor("ALL", ["160m", "80m", "60m", "40m", "30m", "20m",
                                                 "17m", "15m", "12m", "10m", "6m", "2m", "70cm"])
                == [.m160, .m80, .m60, .m40, .m30, .m20, .m17, .m15, .m12, .m10, .m6, .m2, .cm70])
    }

    @Test func bandsForSpecificBandOnlyThatBand() {
        #expect(EntryGridPolicy.bandsFor("20M", ["160m", "80m", "20m"]) == [.m20])
        #expect(EntryGridPolicy.bandsFor("160m", ["160m"]) == [.m160])
    }

    @Test func bandsForEmptyFallsBackToDefinitionBands() {
        #expect(EntryGridPolicy.bandsFor(nil, ["40m", "20m"]) == [.m40, .m20])
        #expect(EntryGridPolicy.bandsFor("", ["40m"]) == [.m40])
    }

    @Test func bandsForUnknownBandStringIsEmpty() {
        #expect(EntryGridPolicy.bandsFor("999X", ["160m"]).isEmpty)
    }

    // MARK: - new, everything measured by a probe

    @Test func columnOfTrimsJavaWhitespaceOnly() {
        #expect(EntryGridPolicy.columnOf("\tcw\n") == .CW)          // ≤ U+0020 is trimmed
        #expect(EntryGridPolicy.columnOf("\u{00A0}cw") == nil)       // NBSP ne
    }

    @Test func columnOfUsesFullCaseMapping() {
        #expect(EntryGridPolicy.columnOf("\u{017F}sb") == .PH)       // ſ → S
        #expect(EntryGridPolicy.columnOf("rtty") == .RY)
        #expect(EntryGridPolicy.columnOf("ft8") == .DI)
        #expect(EntryGridPolicy.columnOf("\u{FB01}") == nil)         // ligatura „fi" → „FI"
    }

    /// The Java `switch` on a string compares by UTF-16 units; Swift `==` compares canonically,
    /// and KELVIN SIGN U+212A canonically decomposes to "K" — "PS\u{212A}" would be "PSK".
    @Test func columnOfIsNotCanonicalEquivalence() {
        #expect(EntryGridPolicy.columnOf("PS\u{212A}") == nil)
        #expect(EntryGridPolicy.columnOf("ps\u{212A}") == nil)
        #expect(EntryGridPolicy.columnOf("PSK") == .DI)
    }

    @Test func columnsForMixedMatchesJavaIgnoreCaseAndTrim() {
        #expect(EntryGridPolicy.columnsFor(" mixed ", ["CW", "SSB"]) == [.CW, .PH])
        // dotless ı behaves like "i" in Java `equalsIgnoreCase` → so it is MIXED (union = CW only)
        #expect(EntryGridPolicy.columnsFor("m\u{0131}xed", ["CW"]) == [.CW])
        // MIXED with an empty definition or only unknown modes → all columns
        #expect(EntryGridPolicy.columnsFor(" mixed ", []) == Set(Column.allCases))
        #expect(EntryGridPolicy.columnsFor("MIXED", ["XYZ"]) == Set(Column.allCases))
    }

    @Test func columnsForSingleModeIgnoresDefinitionModes() {
        #expect(EntryGridPolicy.columnsFor("CW", nil) == [.CW])
        #expect(EntryGridPolicy.columnsFor("CW", ["SSB"]) == [.CW])
    }

    @Test func bandsForTrimsAndIsCaseInsensitive() {
        #expect(EntryGridPolicy.bandsFor("\t20m ", []) == [.m20])
        #expect(EntryGridPolicy.bandsFor("70CM", []) == [.cm70])
        #expect(EntryGridPolicy.bandsFor("  ", ["40m"]) == [.m40])        // empty after trim → definition bands
        #expect(EntryGridPolicy.bandsFor("aLl", ["40m", "40M", " 40m "]) == [.m40])
    }

    @Test func bandsForUnknownIsEmptyNotFallback() {
        #expect(EntryGridPolicy.bandsFor("999X", ["40m", "20m"]).isEmpty)
    }

    // MARK: - nil lists: Java NPE, Swift lenient (a deliberate divergence from Java v1.1.1)

    @Test func nilDefinitionModesWithMixedAreEmptyUnionSoAllColumns() {
        // Java: NPE (`for (String dm : defModes)`)
        #expect(EntryGridPolicy.columnsFor("MIXED", nil) == Set(Column.allCases))
    }

    @Test func nilElementInDefinitionModesIsIgnored() {
        // Java: `columnOf(null)` = null, no crash
        #expect(EntryGridPolicy.columnsFor("MIXED", ["CW", nil]) == [.CW])
    }

    @Test func nilDefinitionBandsWithAllIsEmpty() {
        // Java: NPE
        #expect(EntryGridPolicy.bandsFor("ALL", nil).isEmpty)
        #expect(EntryGridPolicy.bandsFor("20M", nil) == [.m20]) // a concrete band does not read the list
    }

    @Test func nilElementInDefinitionBandsIsIgnored() {
        // Java: `Band.fromAdif(null)` = empty, no crash
        #expect(EntryGridPolicy.bandsFor("ALL", ["20m", nil]) == [.m20])
    }
}
