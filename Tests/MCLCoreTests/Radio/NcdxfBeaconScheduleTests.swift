import Foundation
import Testing
@testable import MCLCore

/// The NCDXF/IARU beacon schedule (N1MM shows the beacon sending now when you listen on a beacon frequency): 10 s per
/// beacon and band, a 3-minute cycle from 00:00:00 UTC, the beacon on 18110 kHz is the one that was on 14100 kHz in the
/// slot before.
@Suite struct NcdxfBeaconScheduleTests {

    /// 2026-10-15 00:00:00 UTC — a whole 3 minutes.
    static let midnight = Date(timeIntervalSince1970: 1_792_022_400)

    @Test func theCycleStartsWith4U1UNOn20Metres() throws {
        #expect(Int64(Self.midnight.timeIntervalSince1970) % 180 == 0)
        #expect(NcdxfBeacons.transmitting(freqHz: 14_100_000, at: Self.midnight)?.call == "4U1UN")
        #expect(NcdxfBeacons.transmitting(freqHz: 18_110_000, at: Self.midnight)?.call == "YV5B")
        #expect(NcdxfBeacons.transmitting(freqHz: 21_150_000, at: Self.midnight)?.call == "OA4B")
        #expect(NcdxfBeacons.transmitting(freqHz: 24_930_000, at: Self.midnight)?.call == "LU4AA")
        #expect(NcdxfBeacons.transmitting(freqHz: 28_200_000, at: Self.midnight)?.call == "CS3B")
        let later = Self.midnight.addingTimeInterval(10)
        #expect(NcdxfBeacons.transmitting(freqHz: 14_100_000, at: later)?.call == "VE8AT")
        #expect(NcdxfBeacons.transmitting(freqHz: 18_110_000, at: later)?.call == "4U1UN")
        let lastSlot = Self.midnight.addingTimeInterval(179.9)
        #expect(NcdxfBeacons.transmitting(freqHz: 14_100_000, at: lastSlot)?.call == "YV5B")
        #expect(NcdxfBeacons.transmitting(freqHz: 14_100_000, at: Self.midnight.addingTimeInterval(180))?.call
            == "4U1UN")
    }

    @Test func everyBeaconVisitsEveryBandOncePerCycle() {
        for band in NcdxfBeacons.frequenciesHz {
            var calls: [String] = []
            for slot in 0..<18 {
                let at = Self.midnight.addingTimeInterval(Double(slot * 10 + 5))
                if let beacon = NcdxfBeacons.transmitting(freqHz: Int64(band), at: at) {
                    calls.append(beacon.call)
                }
            }
            #expect(Set(calls) == NcdxfBeacons.calls, "\(band)")
            #expect(calls.count == 18)
        }
    }

    @Test func onlyNearABeaconFrequency() {
        #expect(NcdxfBeacons.transmitting(freqHz: 14_100_900, at: Self.midnight)?.call == "4U1UN")
        #expect(NcdxfBeacons.transmitting(freqHz: 14_099_000, at: Self.midnight)?.call == "4U1UN")
        #expect(NcdxfBeacons.transmitting(freqHz: 14_102_000, at: Self.midnight) == nil)
        #expect(NcdxfBeacons.transmitting(freqHz: 7_100_000, at: Self.midnight) == nil)
    }

    @Test func theInfoStripShowsIt() {
        var input = InfoStripInput()
        #expect(InfoStrip.extras(input).isEmpty)
        input.beacon = NcdxfBeacons.stripText(NcdxfBeacons.beacons[0])
        #expect(InfoStrip.extras(input) == [.verbatim("NCDXF 4U1UN (United Nations NY)")])
    }
}
