import Testing
@testable import MCLCore

/// Port of `dxcluster/GridCommentTest` (6).
@Suite struct GridCommentTests {

    // Centroids roughly corresponding to countries (lat, lon), with primaryPrefix.
    private func usa() -> DxccEntity {
        DxccEntity(entityCode: 291, name: "USA", countryCode: "K", continents: ["NA"], cq: [4], itu: [7],
                   lat: 39.5, lon: -98.5, primaryPrefix: "K")
    }

    private func germany() -> DxccEntity {
        DxccEntity(entityCode: 230, name: "Germany", countryCode: "DL", continents: ["EU"], cq: [14], itu: [28],
                   lat: 51.0, lon: 10.0, primaryPrefix: "DL")
    }

    @Test func extractsGridNearDxcc() {
        // KA1CVS is US → EM95PU (Kansas/Missouri) fits; FN55 (northeast) is US too.
        #expect(GridComment.extractGrid("KA1CVS EM95PU<ES>FN55 human", usa()) == "EM95PU")
    }

    @Test func picksGridMatchingDxccAmongMany() {
        // The EU grid JO60 (far from the US) is skipped, the US grid EM95 is taken.
        #expect(GridComment.extractGrid("op JO60 rig EM95 tnx", usa()) == "EM95")
    }

    @Test func rejectsGridFarFromDxcc() {
        // JO60 = Germany, far from the US → nothing.
        #expect(GridComment.extractGrid("nice sig JO60 cq", usa()) == nil)
    }

    @Test func germanGridForGermanStation() {
        #expect(GridComment.extractGrid("DL1ABC JO60 tnx", germany()) == "JO60")
    }

    @Test func picksDxGridNotSpotterGrid() {
        // JA2ODB (Japan): the comment "JN01<>PM94" — JN01 is the spotter's grid (Spain),
        // PM94 is the DX (Japan). It must pick PM94 by DXCC.
        let japan = DxccEntity(entityCode: 339, name: "Japan", countryCode: "JA", continents: ["AS"], cq: [25],
                               itu: [45], lat: 36.0, lon: 138.0, primaryPrefix: "JA")
        #expect(GridComment.extractGrid("JN01<>PM94 FT8 Sent: -11", japan) == "PM94")
    }

    @Test func noGridOrNoLatLon() {
        #expect(GridComment.extractGrid("CW 599 CQ 20 WPM", usa()) == nil)
        #expect(GridComment.extractGrid(nil, usa()) == nil)
        let noLatLon = DxccEntity(entityCode: 1, name: "X", countryCode: "X", continents: ["EU"], cq: [], itu: [],
                                  lat: .nan, lon: .nan, primaryPrefix: "X")
        #expect(GridComment.extractGrid("EM95 test", noLatLon) == nil)
    }
}
