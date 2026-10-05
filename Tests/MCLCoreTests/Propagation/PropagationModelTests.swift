import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `PropagationModelTest` (3).
@Suite struct PropagationModelTests {

    // Prague → New York
    private static let ok: (lat: Double, lon: Double) = (50.08, 14.42)
    private static let w2: (lat: Double, lon: Double) = (40.71, -74.0)

    /// The instant `2026-11-28` + `hour`:`minute` UTC.
    private func nov28(_ hour: Int64, _ minute: Int64) -> Date {
        let epochDay: Int64 = JavaLocalDate.epochDay(year: 2026, month: 11, day: 28)
        let seconds: Int64 = epochDay * 86_400 + hour * 3_600 + minute * 60
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    @Test func sfiToSsn() {
        #expect(abs(PropagationModel.ssnFromSfi(60) - 0) <= 1e-9)
        #expect(abs(PropagationModel.ssnFromSfi(176.5) - 155) <= 1)
    }

    @Test func distanceAndMidpoint() {
        let ok = Self.ok
        let w2 = Self.w2
        let d: Double = PropagationModel.distanceKm(ok.lat, ok.lon, w2.lat, w2.lon)
        #expect(abs(d - 6570) <= 60)
        let p = PropagationModel.pointAt(ok.lat, ok.lon, w2.lat, w2.lon, km: d)
        #expect(abs(p.lat - w2.lat) <= 0.1)
    }

    @Test func highSunHighBandsOpenAtMiddayNotAtNight() {
        let ok = Self.ok
        let w2 = Self.w2
        let ssn: Double = PropagationModel.ssnFromSfi(180)
        let f: [[Band: PropagationModel.Level]] = PropagationModel.forecast(
            ok.lat, ok.lon, w2.lat, w2.lon, from: nov28(0, 0), ssn: ssn, bands: [.m80, .m20, .m10])
        #expect(f.count == 24)
        // 13:30 UTC (light at both control points): 20 m open, 80 m closed (D-layer absorption).
        #expect(f[13][.m20] == .open)
        #expect(f[13][.m80] == .closed)
        // Night on the path: 10 m closed, 80 m open.
        #expect(f[3][.m10] == .closed)
        #expect(f[3][.m80] == .open)
        let noonMillis: Int64 = Int64(nov28(13, 30).timeIntervalSince1970) * 1_000
        #expect(PropagationModel.muf(ok.lat, ok.lon, w2.lat, w2.lon, epochMillis: noonMillis, ssn: ssn) > 20)
    }
}
