import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `MultiplierSetRegistryTest` (5 cases): the registry over
/// the real sets in `contest-data/multipliers/` and the shared DXCC fixture
/// `dxcc-test.json`.
@Suite struct MultiplierSetRegistryTests {

    let registry: MultiplierSetRegistry

    init() throws {
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        registry = try MultiplierSetRegistry(dxcc: dxcc)
            .loadDir(root.appendingPathComponent("multipliers"))
    }

    @Test func allBundledSetsLoaded() {
        let ids = registry.ids
        for id in ["cq_zones", "dxcc_entities", "wpx_prefixes", "na_areas", "ok_om_districts"] {
            #expect(ids.contains(id), "\(id)")
        }
    }

    @Test func cqZonesEnumeratesAndValidates() throws {
        let zones = try registry.get("cq_zones")
        #expect(zones.values.count == 40)
        #expect(zones.isExpected("14"))
        #expect(!zones.isExpected("50"))
        #expect(zones.normalize("14").isValid)
        #expect(zones.normalize("07").key == "7")            // INTEGER canonicalisation
        #expect(!zones.normalize("41").isValid)              // out of range per the pattern
        #expect(!zones.normalize("abc").isValid)             // non-numeric
    }

    @Test func dxccDerivesFromCallsign() throws {
        let dxcc = try registry.get("dxcc_entities")
        #expect(dxcc.enumerable)
        #expect(!dxcc.values.isEmpty)
        let resolution = dxcc.deriveFromCallsign("OK1XOE")
        #expect(resolution.isValid)
        #expect(resolution.key == "503")                     // entityCode CZ from the fixture
    }

    @Test func wpxIsOpenSet() throws {
        let wpx = try registry.get("wpx_prefixes")
        #expect(!wpx.enumerable)
        #expect(wpx.isExpected("ANY"))                       // open set
        #expect(wpx.deriveFromCallsign("OK1XOE").key == "OK1")
    }

    @Test func naAreasFromCsv() throws {
        let areas = try registry.get("na_areas")
        #expect(areas.values.count > 50)
        #expect(areas.isExpected("CA"))                      // California
        #expect(areas.isExpected("ON"))                      // Ontario
    }

    // The whole registry against Java (order of `ids`, classes, all values) is guarded by the gate
    // `JavaDefinitionParityTests.readArmMatchesJava`.
}
