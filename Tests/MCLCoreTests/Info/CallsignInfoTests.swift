import Foundation
import Testing
@testable import MCLCore

/// Ported Java `info/CallsignInfoTest` (9 tests, Java v1.1.1).
@Suite struct CallsignInfoTests {

    static let noon = JavaInstant(uncheckedSecond: 1_787_140_800, nano: 0) // 2026-08-19T12:00:00Z

    private static func entity(_ prefix: String, _ name: String, _ continent: String, _ cq: Int,
                               _ lat: Double, _ lon: Double) -> DxccEntity {
        DxccEntity(entityCode: 1, name: name, countryCode: prefix, continents: [continent], cq: [cq], itu: [28],
                   lat: lat, lon: lon, primaryPrefix: prefix)
    }

    /// `LocalTime.of(hour, minute).toNanoOfDay()`.
    private static func time(_ hour: Int64, _ minute: Int64) -> Int64 {
        (hour * 3600 + minute * 60) * 1_000_000_000
    }

    private static func near(_ actual: Int?, _ expected: Int, _ delta: Int) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) <= delta
    }

    @Test func dueEastIsNinetyDegreesAndAQuarterOfTheGlobe() throws {
        // From (0,0) to (0, 90°E): azimuth exactly 90°, distance a quarter of the Earth's circumference.
        let dx = Self.entity("XX", "TEST", "AS", 26, 0.0, 90.0)

        let info = try CallsignInfo.forEntity(dx, myLat: 0.0, myLon: 0.0, now: Self.noon)

        #expect(info.shortPathDeg == 90)
        #expect(info.longPathDeg == 270)
        #expect(Self.near(info.distanceKm, 10007, 20))
    }

    @Test func dueNorthIsZeroDegrees() throws {
        let dx = Self.entity("XX", "TEST", "EU", 14, 45.0, 0.0)

        let info = try CallsignInfo.forEntity(dx, myLat: 0.0, myLon: 0.0, now: Self.noon)

        #expect(info.shortPathDeg == 0)
        #expect(info.longPathDeg == 180)
        #expect(Self.near(info.distanceKm, 5004, 20))
    }

    @Test func milesAreReportedAlongsideKilometres() throws {
        let dx = Self.entity("XX", "TEST", "AS", 26, 0.0, 90.0)

        let info = try CallsignInfo.forEntity(dx, myLat: 0.0, myLon: 0.0, now: Self.noon)

        #expect(Self.near(info.distanceMiles, 6218, 20))
    }

    @Test func entityFieldsArePassedThrough() throws {
        let dx = Self.entity("GI", "NORTHERN IRELAND", "EU", 14, 54.6, -5.9)

        let info = try CallsignInfo.forEntity(dx, myLat: 50.088, myLon: 14.420, now: Self.noon)

        #expect(info.prefix == "GI")
        #expect(info.entityName == "NORTHERN IRELAND")
        #expect(info.continent == "EU")
        #expect(info.cqZone == 14)
    }

    @Test func dxLocalTimeComesFromLongitude() throws {
        // 90°E → time zone UTC+6, at 12:00Z it is 18:00 there, still Wednesday.
        let dx = Self.entity("XX", "TEST", "AS", 26, 0.0, 90.0)

        let info = try CallsignInfo.forEntity(dx, myLat: 0.0, myLon: 0.0, now: Self.noon)

        #expect(info.dxLocalTime == Self.time(18, 0))
        #expect(info.dxDayOfWeek == .wednesday)
    }

    @Test func dxLocalTimeRollsOverToTheNextDay() throws {
        // 150°E → UTC+10; at 22:00Z it is 08:00 of the following day there.
        let dx = Self.entity("VK", "AUSTRALIA", "OC", 30, -33.0, 150.0)
        let now = JavaInstant(uncheckedSecond: 1_787_176_800, nano: 0) // 2026-08-19T22:00:00Z

        let info = try CallsignInfo.forEntity(dx, myLat: 0.0, myLon: 0.0, now: now)

        #expect(info.dxLocalTime == Self.time(8, 0))
        #expect(info.dxDayOfWeek == .thursday)
    }

    @Test func sunTimesAreFilledForKnownCoordinates() throws {
        let dx = Self.entity("GI", "NORTHERN IRELAND", "EU", 14, 54.6, -5.9)

        let info = try CallsignInfo.forEntity(dx, myLat: 50.088, myLon: 14.420, now: Self.noon)

        #expect(info.sunrise != nil)
        #expect(info.sunset != nil)
    }

    @Test func entityWithoutCoordinatesStillReportsCountry() throws {
        // Some entities have no coordinates in the data — the row should be shown without an azimuth,
        // not disappear entirely.
        let dx = Self.entity("XX", "TEST", "AF", 33, Double.nan, Double.nan)

        let info = try CallsignInfo.forEntity(dx, myLat: 50.0, myLon: 14.0, now: Self.noon)

        #expect(info.entityName == "TEST")
        #expect(info.cqZone == 33)
        #expect(info.shortPathDeg == nil)
        #expect(info.longPathDeg == nil)
        #expect(info.distanceKm == nil)
        #expect(info.sunrise == nil)
        #expect(info.dxLocalTime == nil)
    }

    @Test func missingCqZoneIsNotInvented() throws {
        let dx = DxccEntity(entityCode: 1, name: "TEST", countryCode: "XX", continents: ["EU"], cq: [], itu: [],
                            lat: 50.0, lon: 14.0, primaryPrefix: "XX")

        #expect(try CallsignInfo.forEntity(dx, myLat: 50.0, myLon: 14.0, now: Self.noon).cqZone == nil)
    }
}

/// `CallsignInfo.forEntity` against Java v1.1.1 (maintainer-only probe,
/// table `CallsignInfoMeasured`): entities of the test fixture `scorecheck-cty-mini.dat` (Swift
/// `CtyDxccResolver`) and synthetic ones — lengths at half-hours (`Math.round(−2,5) = −2`), poles, `NaN`
/// and infinite coordinates, empty and `null` zones — × 6 of my positions × 6 instants incl. `Instant.MIN/MAX`
/// (`DateTimeException`).
@Suite struct CallsignInfoMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rawRows(CallsignInfoMeasured.rows, id)
    }

    /// Entities in probe order: the `cty.dat` of the fixture, then synthetic ones with codes from 1000.
    private static func entities() throws -> [DxccEntity] {
        let url = try #require(Bundle.module.url(forResource: "scorecheck-cty-mini", withExtension: "dat"))
        var list: [DxccEntity] = CtyDxccResolver.fromData(try Data(contentsOf: url)).entities()
        let lons: [Double] = [-37.5, -7.5, 7.5, 37.5, 172.5, -172.5, 180.0, -180.0, 0.0, -22.5, -52.5, 97.5,
                              -0.0, -7.499999999999999, 1.0e15, -1.0e15]
        var code = 1000
        for lon in lons {
            list.append(syn(code, "X\(code + 1)", "SYN", ["EU"], [14], 10.0, lon))
            code += 1
        }
        let inf: Double = .infinity
        let specs: [(String, String?, [String?], [Int?], Double, Double)] = [
            ("NP", "NORTH", ["EU"], [40], 89.0, 10.0),
            ("SP", "SOUTH", ["AN"], [39], -89.0, -10.0),
            ("NC", "NOCOORD", ["AF"], [33], .nan, .nan),
            ("NL", "NOLON", ["AF"], [33], 10.0, .nan),
            ("IL", "INFLAT", ["AF"], [33], inf, 10.0),
            ("IO", "INFLON", ["AF"], [33], 10.0, inf),
            ("IN", "NEGINFLON", ["AF"], [33], 10.0, -inf),
            ("EZ", "EMPTYZONES", [], [], 50.0, 14.0),
            ("NZ", nil, [nil], [nil, 5], 50.0, 14.0),
        ]
        for spec in specs {
            list.append(syn(code, spec.0, spec.1, spec.2, spec.3, spec.4, spec.5))
            code += 1
        }
        list.append(DxccEntity(entityCode: code, name: "NULLS", countryCode: nil, continents: nil, cq: nil,
                               itu: nil, lat: -33.0, lon: 150.0, primaryPrefix: nil))
        return list
    }

    private static func syn(_ code: Int, _ prefix: String, _ name: String?, _ cont: [String?], _ cq: [Int?],
                            _ lat: Double, _ lon: Double) -> DxccEntity {
        DxccEntity(entityCode: code, name: name, countryCode: prefix, continents: cont, cq: cq, itu: [28],
                   lat: lat, lon: lon, primaryPrefix: prefix)
    }

    /// Java `Double.parseDouble` for the shapes the probe prints (`NaN`, `Infinity`, `1.0E15`).
    private static func double(_ text: String) -> Double {
        switch text {
        case "NaN": return .nan
        case "Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: return Double(text) ?? .nan
        }
    }

    private static func same(_ a: Double, _ b: Double) -> Bool {
        a.isNaN ? b.isNaN : a.bitPattern == b.bitPattern
    }

    private static func s<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "null"
    }

    private static func list<T>(_ values: [T?]?) -> String {
        guard let values else { return "null" }
        return "[" + values.map { Self.s($0) }.joined(separator: ", ") + "]"
    }

    private static func describe(_ i: CallsignInfo) -> String {
        let cols: [String] = [
            s(i.prefix), s(i.entityName), s(i.continent), s(i.cqZone), s(i.shortPathDeg), s(i.longPathDeg),
            s(i.distanceKm), s(i.distanceMiles), s(i.sunrise), s(i.sunset), s(i.dxLocalTime),
            s(i.dxDayOfWeek?.javaName),
        ]
        return cols.joined(separator: "|")
    }

    @Test func entitiesMatchProbe() throws {
        let entities: [DxccEntity] = try Self.entities()
        let rows: [[String]] = Self.rows("INFO.entity")
        #expect(rows.count == entities.count)
        for (row, e) in zip(rows, entities) {
            let got: [String] = [String(e.entityCode), Self.s(e.primaryPrefix), Self.s(e.name),
                                 Self.list(e.continents), Self.list(e.cq)]
            #expect(Array(row.prefix(5)) == got)
            #expect(Self.same(e.lat, Self.double(row[5])), "\(row)")
            #expect(Self.same(e.lon, Self.double(row[6])), "\(row)")
        }
    }

    @Test func forEntityMatchesJava() throws {
        var byCode: [String: DxccEntity] = [:]
        for e in try Self.entities() {
            byCode[String(e.entityCode)] = e
        }
        let rows: [[String]] = Self.rows("INFO.for")
        #expect(rows.count == 1_152)
        var mismatches = 0
        for row in rows {
            let entity: DxccEntity = try #require(byCode[row[0]])
            let now: JavaInstant = try #require(JavaInstant.parseIsoInstant(row[3]))
            let got: String
            do {
                let info = try CallsignInfo.forEntity(entity, myLat: Self.double(row[1]),
                                                      myLon: Self.double(row[2]), now: now)
                got = Self.describe(info)
            } catch {
                got = "throws DateTimeException"
            }
            if got != row[4] {
                mismatches += 1
                if mismatches <= 15 {
                    Issue.record("INFO.for \(row): Swift \(got)")
                }
            }
        }
        #expect(mismatches == 0, "INFO.for: \(mismatches) mismatches")
    }

    /// Review focus: `Math.round` rounds a half toward +∞, Swift `rounded()` away from zero —
    /// −37.5° / 15 = −2.5 h → −2 (Java), not −3. At 12:00Z it is therefore 10:00 there, not 09:00.
    @Test func negativeHalfHourRoundsTowardPositiveInfinity() throws {
        let dx = DxccEntity(entityCode: 1, name: "SYN", countryCode: "X", continents: ["EU"], cq: [14], itu: [28],
                            lat: 10.0, lon: -37.5, primaryPrefix: "X")
        let info = try CallsignInfo.forEntity(dx, myLat: 50.0, myLon: 14.0, now: CallsignInfoTests.noon)
        let ten: Int64 = 10 * 3600 * 1_000_000_000
        #expect(info.dxLocalTime == ten)
        let west = DxccEntity(entityCode: 2, name: "SYN", countryCode: "X", continents: ["EU"], cq: [14], itu: [28],
                              lat: 10.0, lon: -7.5, primaryPrefix: "X")
        let info2 = try CallsignInfo.forEntity(west, myLat: 50.0, myLon: 14.0, now: CallsignInfoTests.noon)
        let twelve: Int64 = 12 * 3600 * 1_000_000_000
        #expect(info2.dxLocalTime == twelve)
    }
}
