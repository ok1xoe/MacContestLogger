import Foundation
import Testing
@testable import MCLCore

/// Port of `hamqth/GridFieldMapTest` (3) over the shared fixture `dxcc-test.json`.
@Suite struct GridFieldMapTests {

    private func build(_ csv: String) throws -> GridFieldMap {
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        return GridFieldMap.build(Data(csv.utf8), dxcc)
    }

    @Test func mapsGridFieldToDxccEntities() throws {
        // OK1XOE→Czech(503), DL1ABC→Germany(230) both from field JO; W1AW→USA(291) from field FN.
        let map = try build("znacka;lokator;pocet\nOK1XOE;JO70;5\nDL1ABC;JO60;2\nW1AW;FN31;9\n")
        #expect(map.known("JO"))
        #expect(map.matches("JO", entityCode: 503), "Czech transmits from JO")
        #expect(map.matches("JO", entityCode: 230), "Germany transmits from JO")
        #expect(map.matches("FN", entityCode: 291), "USA transmits from FN")
    }

    @Test func rejectsFieldNotBelongingToEntity() throws {
        let map = try build("znacka;lokator;pocet\nOK1XOE;JO70;5\nW1AW;FN31;9\n")
        #expect(!map.matches("FN", entityCode: 503), "Czech does not transmit from FN")
        #expect(!map.matches("JO", entityCode: 291), "USA does not transmit from JO")
    }

    @Test func unknownFieldIsNotKnown() throws {
        let map = try build("znacka;lokator;pocet\nOK1XOE;JO70;5\n")
        #expect(!map.known("XX"))
        #expect(!map.matches("XX", entityCode: 503))
    }
}
