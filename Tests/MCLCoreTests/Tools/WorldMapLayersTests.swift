import Testing
@testable import MCLCore

/// N1MM Grayline setup: the most recent spots, the cleared ones and the Equator / meridian positions.
@Suite struct WorldMapLayersTests {

    private static func spot(_ call: String) -> DxSpot {
        DxSpot(spotter: "OK1RR", freqHz: 14_030_000, dxCall: call, comment: "")
    }

    @Test func theNewestSpotsAreKeptAndClearedOnesDropped() {
        let spots: [DxSpot] = ["A1A", "B1B", "C1C", "D1D"].map(Self.spot)
        #expect(WorldMapModel.shownSpots(spots, count: -1, cleared: []) == spots)
        #expect(WorldMapModel.shownSpots(spots, count: 2, cleared: []).map(\.dxCall) == ["C1C", "D1D"])
        #expect(WorldMapModel.shownSpots(spots, count: 0, cleared: []).isEmpty)
        let cleared: Set<DxSpot> = [Self.spot("D1D"), Self.spot("B1B")]
        #expect(WorldMapModel.shownSpots(spots, count: 2, cleared: cleared).map(\.dxCall) == ["A1A", "C1C"])
        #expect(WorldMapModel.spotCountOptions == [-1, 0, 50, 100, 150, 200])
    }

    @Test func theEquatorAndTheMeridianFollowTheProjection() {
        let map = WorldMapModel(centerLon: 0)
        #expect(map.meridianX(width: 360) == 180)
        #expect(map.equatorY(height: 165) == 90)
        // Centred on 90° E the meridian moves a quarter to the left.
        #expect(WorldMapModel(centerLon: 90).meridianX(width: 360) == 90)
        #expect(WorldMapLayer.defaults == ["sun", "home"])
    }
}
