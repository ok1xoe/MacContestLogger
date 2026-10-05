import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `CategoryCatalogTest` (5 tests) + new cases
/// (probe `ProbeCat`, a maintainer-only probe).
@Suite struct CategoryCatalogTests {

    private func bundled(_ name: String) throws -> ContestDefinition {
        try ContestDefinitionLoaderTests.bundled(name)
    }

    // MARK: - Java CategoryCatalogTest

    @Test func fixedHasStandardCabrilloDims() {
        let dims = CategoryCatalog.fixed()
        #expect(dims.map(\.key) == ["OPERATOR", "POWER", "OVERLAY", "STATION", "ASSISTED", "TRANSMITTER", "TIME"])
        #expect(dims[0].options == ["SINGLE-OP", "MULTI-OP", "CHECKLOG"])
        #expect(dims[0].label == "Operátor")
        #expect(dims[2].options == ["N/A", "CLASSIC", "ROOKIE", "TB-WIRES", "YOUTH", "YL"])
        #expect(dims[3].options == ["FIXED", "MOBILE", "PORTABLE", "ROVER", "EXPEDITION", "HQ", "SCHOOL"])
        #expect(dims[6].options == ["N/A", "6-HOURS", "12-HOURS", "24-HOURS"])
    }

    @Test func bandOptionsAllPlusUppercaseBands() throws {
        #expect(CategoryCatalog.bandOptions(try bundled("cq-160-cw.yaml")) == ["ALL", "160M"])
        #expect(CategoryCatalog.bandOptions(try bundled("cq-ww-cw.yaml"))
                == ["ALL", "160M", "80M", "40M", "20M", "15M", "10M"])
    }

    @Test func modeOptionsSingleNoMixed() throws {
        #expect(CategoryCatalog.modeOptions(try bundled("cq-160-cw.yaml")) == ["CW"])
    }

    @Test func modeOptionsMultiAddsMixed() {
        let definition = ContestDefinition(schemaVersion: 1, id: "x", modes: ["CW", "SSB"])
        #expect(CategoryCatalog.modeOptions(definition) == ["CW", "SSB", "MIXED"])
        #expect(CategoryCatalog.bandOptions(definition) == ["ALL"]) // bands nil → ALL only
    }

    @Test func sentFieldsOnlyFromStationOrManual() throws {
        let ids = CategoryCatalog.sentFields(try bundled("cq-160-cw.yaml")).map(\.id)
        #expect(ids == ["qth"]) // rst is AUTO_RST → omitted
    }

    // MARK: - new

    @Test func modeOptionsWithDuplicatesKeepsThem() {
        let definition = ContestDefinition(id: "x", modes: ["CW", "CW"])
        #expect(CategoryCatalog.modeOptions(definition) == ["CW", "CW", "MIXED"])
    }

    @Test func modeOptionsDoNotTrimOrDeduplicate() {
        // Java: `toUpperCase()` without `trim()` — the space stays inside the choice
        let definition = ContestDefinition(id: "x", modes: [" cw", "ssb"])
        #expect(CategoryCatalog.modeOptions(definition) == [" CW", "SSB", "MIXED"])
    }

    @Test func bandOptionsUppercaseUsesFullUnicodeMapping() {
        // Java `"ßm".toUpperCase()` = "SSM"
        #expect(CategoryCatalog.bandOptions(ContestDefinition(id: "x", bands: ["ßm"])) == ["ALL", "SSM"])
    }

    @Test func sentFieldsWithNilSourceAreSkipped() {
        let field = ContestDefinition.ExchangeField(
            id: "q", type: nil, required: false, source: nil, appliesWhen: nil, validation: nil)
        let definition = ContestDefinition(id: "x", exchange: .init(sent: [field], received: nil))
        #expect(CategoryCatalog.sentFields(definition).isEmpty)
    }

    @Test func sentFieldsKeepsOrderOfManualAndStation() {
        func field(_ id: String, _ source: ContestDefinition.FieldSource) -> ContestDefinition.ExchangeField {
            .init(id: id, type: nil, required: false, source: source, appliesWhen: nil, validation: nil)
        }
        let definition = ContestDefinition(id: "x", exchange: .init(
            sent: [field("a", .MANUAL), field("b", .AUTO_SERIAL), field("c", .FROM_STATION),
                   field("d", .DERIVED), field("e", .ROVER_QTH)],
            received: nil))
        #expect(CategoryCatalog.sentFields(definition).map(\.id) == ["a", "c"])
    }

    // MARK: - nil elements: Java NPE, Swift lenient (a deliberate divergence from Java v1.1.1)

    @Test func nilElementInBandsIsSkipped() {
        // Java: NPE (`b.toUpperCase()`)
        #expect(CategoryCatalog.bandOptions(ContestDefinition(id: "x", bands: ["20m", nil])) == ["ALL", "20M"])
    }

    @Test func nilElementInModesIsSkipped() {
        // Java: NPE (`m.toUpperCase()`); the skipped element does not count towards "more than one"
        #expect(CategoryCatalog.modeOptions(ContestDefinition(id: "x", modes: ["CW", nil])) == ["CW"])
        #expect(CategoryCatalog.modeOptions(ContestDefinition(id: "x", modes: [nil])).isEmpty)
    }

    @Test func nilElementInSentFieldsIsSkipped() {
        let field = ContestDefinition.ExchangeField(
            id: "q", type: nil, required: false, source: .MANUAL, appliesWhen: nil, validation: nil)
        let definition = ContestDefinition(id: "x", exchange: .init(sent: [field, nil], received: nil))
        // Java: NPE (`f.source()`)
        #expect(CategoryCatalog.sentFields(definition).map(\.id) == ["q"])
    }
}
