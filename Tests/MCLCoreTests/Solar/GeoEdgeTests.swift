import Darwin
import Foundation
import Testing
@testable import MCLCore

/// Geometry edges measured on JDK 21: the constants `Math.toRadians`/`toDegrees`, the `LocalDate` range,
/// the convenience overload with `Date` and `WorldMapGeo.loadDefault` only over a regular file.
@Suite struct GeoEdgeTests {

    @Test func angleConstantsAreJdkBits() {
        // `Double.doubleToRawLongBits` konstant DEGREES_TO_RADIANS / RADIANS_TO_DEGREES.
        #expect(JavaMath.toRadians(1).bitPattern == 4_580_687_790_476_533_049)
        #expect(JavaMath.toDegrees(1).bitPattern == 4_633_260_481_411_531_256)
        // Java: toRadians(0.009) and toDegrees(0.05) differ from `x * π / 180` resp. `x * 180 / π`.
        #expect(JavaMath.toRadians(0.009).bitPattern == 4_549_927_239_583_292_162)
        #expect((0.009 * Double.pi / 180).bitPattern == 4_549_927_239_583_292_161)
        #expect(JavaMath.toDegrees(0.05).bitPattern == 4_613_633_350_081_642_900)
        #expect((0.05 * 180 / Double.pi).bitPattern == 4_613_633_350_081_642_899)
    }

    @Test func dayOutsideLocalDateRangeGivesNothing() {
        #expect(SolarTimes.forLocation(50, 14, epochDay: SolarTimes.maxEpochDay + 1) == nil)
        #expect(SolarTimes.forLocation(50, 14, epochDay: SolarTimes.minEpochDay - 1) == nil)
        #expect(SolarTimes.forLocation(50, 14, epochDay: Int64.max) == nil)
        #expect(SolarTimes.forLocation(50, 14, epochDay: Int64.min) == nil)
        #expect(SolarTimes.forLocation(50, 14, epochDay: SolarTimes.maxEpochDay) != nil)
        #expect(SolarTimes.forLocation(50, 14, epochDay: SolarTimes.minEpochDay) != nil)
    }

    @Test func dateOverloadUsesUtcDay() {
        let day: Int64 = JavaLocalDate.epochDay(year: 2026, month: 6, day: 21)
        let lateEvening = Date(timeIntervalSince1970: TimeInterval(day * 86_400 + 86_399))
        let byDate = SolarTimes.forLocation(50.088, 14.420, at: lateEvening)
        #expect(byDate != nil)
        #expect(byDate == SolarTimes.forLocation(50.088, 14.420, epochDay: day))
        let beforeEpoch = Date(timeIntervalSince1970: -0.5)
        #expect(SolarTimes.forLocation(0, 0, at: beforeEpoch) == SolarTimes.forLocation(0, 0, epochDay: -1))
    }

    @Test func loadDefaultReadsOnlyRegularFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("geo-edge-\(UUID().uuidString)")
        let dir = home.appendingPathComponent("dxcc-world-map")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = dir.appendingPathComponent("dxcc.geojson")

        #expect(WorldMapGeo.loadDefault(home: home).rings.isEmpty) // missing

        // FIFO: Java `Files.isRegularFile` → false; opening would block.
        #expect(mkfifo(file.path, 0o600) == 0)
        #expect(WorldMapGeo.loadDefault(home: home).rings.isEmpty)
        try FileManager.default.removeItem(at: file)

        var text: String = "{\"features\":[{\"geometry\":{\"type\":\"Polygon\","
        text += "\"coordinates\":[[[1,2],[3,4]]]}}]}"
        try Data(text.utf8).write(to: file)
        #expect(WorldMapGeo.loadDefault(home: home).rings.count == 1)
    }
}
