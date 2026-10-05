import Foundation
import Testing
@testable import MCLCore

/// A port of the Java `contest/engine/OperatingGuardTest` (3 tests).
@Suite struct OperatingGuardTests {

    private static let t0: JavaInstant = JavaInstant.parseIsoInstant("2026-11-28T12:00:00Z")!

    private static func qso(_ minute: Int, _ freqHz: Int) -> Qso {
        var q = Qso()
        q.call = "K" + String(minute) + "AA"
        q.freqHz = freqHz
        q.timestampUtc = t0.plus(seconds: Int64(minute) * 60)!.date
        return q
    }

    private static func at(_ minute: Int64) -> JavaInstant {
        t0.plus(seconds: minute * 60)!
    }

    @Test func tenMinuteRule() {
        let s = ContestStats.of([Self.qso(0, 14_025_000), Self.qso(4, 14_026_000)])
        let ten = ContestDefinition.BandChange(minimumMinutes: 10, perHour: nil)
        #expect(OperatingGuard.check(s, ten, .m40, Self.at(5), .run, false)?.contains("zbývá 5") == true)
        #expect(OperatingGuard.check(s, ten, .m40, Self.at(11), .run, false) == nil)
        #expect(OperatingGuard.check(s, ten, .m20, Self.at(5), .run, false) == nil, "the same band is always fine")
    }

    @Test func changesPerHourLimit() {
        let s = ContestStats.of([Self.qso(1, 14_025_000), Self.qso(2, 7_025_000), Self.qso(3, 14_025_000)])
        let two = ContestDefinition.BandChange(minimumMinutes: nil, perHour: 2)
        #expect(OperatingGuard.check(s, two, .m40, Self.at(4), .run, false)?.contains("2/2") == true)
    }

    @Test func multStationOnlyNewMultipliers() {
        let s = ContestStats.of([Self.qso(0, 14_025_000)])
        #expect(OperatingGuard.check(s, nil, .m20, Self.t0, .mult, false) != nil)
        #expect(OperatingGuard.check(s, nil, .m20, Self.t0, .mult, true) == nil)
        #expect(OperatingGuard.check(s, nil, .m20, Self.t0, .run, false) == nil)
    }
}
