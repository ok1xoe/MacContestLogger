import Foundation
import Testing
@testable import MCLCore

/// Geometry: the first 5 + 7 tests are a port of the Java `GreatCircleTest` and `MaidenheadTest`
/// (same tolerances as in Java), the rest is a table measured on Java
/// (maintainer-only probe, JDK 21.0.2, `GeometryMeasured.swift`).
///
/// Whole kilometres (`ceil`, `Math.round` — which go into points via `perKm`) match exactly;
/// raw `double`s have a tolerance, because `Math.sin`/`Math.cos` are intrinsics in HotSpot
/// and Darwin libm differs from them by units up to tens of ulp (a deliberate divergence from Java v1.1.1).
@Suite struct GeometryTests {

    // MARK: - port of the Java GreatCircleTest (5)

    @Test func dueNorthIsZero() {
        #expect(abs(GreatCircle.bearingDeg(0, 0, 10, 0) - 0.0) <= 0.5)
    }

    @Test func dueEastIsNinety() {
        #expect(abs(GreatCircle.bearingDeg(0, 0, 0, 10) - 90.0) <= 0.5)
    }

    @Test func dueSouthIsOneEighty() {
        #expect(abs(GreatCircle.bearingDeg(10, 0, 0, 0) - 180.0) <= 0.5)
    }

    @Test func dueWestIsTwoSeventy() {
        #expect(abs(GreatCircle.bearingDeg(0, 0, 0, -10) - 270.0) <= 0.5)
    }

    @Test func resultInZeroTo360() {
        let b = GreatCircle.bearingDeg(50.0, 14.0, -33.9, 151.2) // Praha → Sydney
        #expect(b >= 0.0 && b < 360.0)
    }

    // MARK: - port of the Java MaidenheadTest (7)

    @Test func distanceBetweenGridCenters() {
        // JO70 (Czechia, 50.5N 15E) → FN31 (Connecticut, 41.5N 73W) ≈ 6464 km
        let d = Maidenhead.distanceKm("JO70", "FN31")
        #expect(d > 6400 && d < 6550, "expected ~6464 km, got \(d)")
    }

    @Test func shortDistance() {
        let d = Maidenhead.distanceKm("JO70", "JO31")
        #expect(d > 500 && d < 650, "expected ~570 km, got \(d)")
    }

    @Test func sameGridIsZero() {
        #expect(abs(Maidenhead.distanceKm("JO70", "JO70") - 0.0) <= 1.0)
    }

    @Test func sixCharLocatorParses() {
        let d = Maidenhead.distanceKm("JO70AB", "FN31")
        #expect(d > 6300 && d < 6650, "a 6-character locator should parse, got \(d)")
    }

    @Test func fourCharCenterIsFieldCenter() throws {
        let c = try #require(Maidenhead.centerLatLon("JO70"))
        #expect(abs(c.lat - 50.5) <= 1e-6)
        #expect(abs(c.lon - 15.0) <= 1e-6)
    }

    @Test func sixCharCenterIsSubsquareCenter() throws {
        // FN15IJ → centre of the subsquare, as N1MM computes it (45.3958°, -77.2917°)
        let c = try #require(Maidenhead.centerLatLon("FN15IJ"))
        #expect(abs(c.lat - 45.395833) <= 1e-4)
        #expect(abs(c.lon - -77.291667) <= 1e-4)
    }

    @Test func invalidGridReturnsNegative() {
        #expect(Maidenhead.distanceKm("XYZ", "JO70") < 0)
        #expect(Maidenhead.distanceKm(nil, "JO70") < 0)
        #expect(Maidenhead.distanceKm("9999", "JO70") < 0)
    }

    // MARK: - table measured on Java

    @Test(arguments: GeometryMeasured.grids)
    func gridRowMatchesJava(_ row: GeometryMeasured.GridRow) {
        let ca = Maidenhead.centerLatLon(row.a)
        let cb = Maidenhead.centerLatLon(row.b)
        // Centres in Java and in Swift are just arithmetic without sin/cos → bit-for-bit equal.
        #expect(ca?.lat.bitPattern == row.centerA?.lat.bitPattern)
        #expect(ca?.lon.bitPattern == row.centerA?.lon.bitPattern)
        #expect(cb?.lat.bitPattern == row.centerB?.lat.bitPattern)
        #expect(cb?.lon.bitPattern == row.centerB?.lon.bitPattern)
        let km = Maidenhead.distanceKm(row.a, row.b)
        #expect(abs(km - row.km) <= 1e-8, "raw distance \(km) vs \(row.km)")
        // Whole km go into points via CEIL/ROUND: must match exactly.
        #expect(JavaMath.d2l(km.rounded(.up)) == row.ceilKm)
        #expect(JavaMath.round(km) == row.roundKm)
    }

    @Test(arguments: GeometryMeasured.circles)
    func circleRowMatchesJava(_ row: GeometryMeasured.CircleRow) {
        let bearing = GreatCircle.bearingDeg(row.lat1, row.lon1, row.lat2, row.lon2)
        // Bearing: for points on opposite poles/convergence an ulp difference can flip 360 → 0.
        let diff = abs(bearing - row.bearing)
        #expect(min(diff, 360 - diff) <= 1e-8, "azimut \(bearing) vs \(row.bearing)")
        let km = GreatCircle.distanceKm(row.lat1, row.lon1, row.lat2, row.lon2)
        #expect(abs(km - row.km) <= 1e-8, "distance \(km) vs \(row.km)")
        #expect(JavaMath.d2l(km.rounded(.up)) == row.ceilKm)
        #expect(JavaMath.round(km) == row.roundKm)
    }

    // MARK: - hard cases outside the table

    @Test func earthRadiiDiffer() {
        // GreatCircle 6371.0, Maidenhead 6371.0088: the two radii must not be unified.
        let great = GreatCircle.distanceKm(0, 0, 0, 10)
        #expect(abs(great - 1111.9492664455872) <= 1e-8)
        let grid = Maidenhead.distanceKm("JJ00", "KJ00")   // centre of JJ00 = (0.5, 1), centre of KJ00 = (0.5, 21)
        let same = GreatCircle.distanceKm(0.5, 1, 0.5, 21)
        #expect(grid / same > 1.0 + 1e-7)
        #expect(grid / same < 1.0 + 3e-6)
    }

    @Test func whitespaceAndCaseFollowJava() {
        #expect(Maidenhead.centerLatLon("\u{9}jo70ab\u{A}")?.lat == Maidenhead.centerLatLon("JO70AB")?.lat)
        #expect(Maidenhead.centerLatLon("JO70\u{A0}") == nil)      // NBSP trim nestrhne
        #expect(Maidenhead.centerLatLon("\u{1}JO70") != nil)       // trim strips ≤ U+0020
        #expect(Maidenhead.centerLatLon("\u{131}O70")?.lon == -5.0) // toUpperCase: ı → I
    }
}
