import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `WorldMapGeoTest` (3).
@Suite struct WorldMapGeoTests {

    private func geo(_ text: String) -> WorldMapGeo {
        WorldMapGeo.fromData(Data(text.utf8))
    }

    @Test func parsesPolygonAndMultiPolygon() {
        var text: String = "{\"type\":\"FeatureCollection\",\"features\":["
        text += "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Polygon\","
        text += "\"coordinates\":[[[0,0],[10,0],[10,10],[0,0]]]}},"
        text += "{\"type\":\"Feature\",\"geometry\":{\"type\":\"MultiPolygon\","
        text += "\"coordinates\":[[[[20,20],[30,20],[30,30],[20,20]]]]}}"
        text += "]}"
        let geo1 = geo(text)
        #expect(geo1.rings.count == 2)
        // The first ring has 4 points → 8 float values (lon,lat pairs).
        #expect(geo1.rings[0].count == 8)
        #expect(geo1.rings[0][0] == Float(0)) // lon of the first point
        #expect(geo1.rings[1][0] == Float(20)) // MultiPolygon
        // Each ring comes from a different feature → a different group (0, 1).
        #expect(geo1.ringGroups.count == 2)
        #expect(geo1.ringGroups[0] == 0)
        #expect(geo1.ringGroups[1] == 1)
    }

    @Test func ringsOfSameFeatureShareGroup() {
        // One feature (a MultiPolygon with two islands) → both rings have the same group.
        var text: String = "{\"type\":\"FeatureCollection\",\"features\":["
        text += "{\"type\":\"Feature\",\"geometry\":{\"type\":\"MultiPolygon\","
        text += "\"coordinates\":[[[[0,0],[1,0],[1,1],[0,0]]],[[[5,5],[6,5],[6,6],[5,5]]]]}}"
        text += "]}"
        let g = geo(text)
        #expect(g.rings.count == 2)
        #expect(g.ringGroups[0] == g.ringGroups[1])
    }

    @Test func emptyOnGarbage() {
        let g = geo("not json")
        #expect(g.rings.isEmpty)
    }
}
