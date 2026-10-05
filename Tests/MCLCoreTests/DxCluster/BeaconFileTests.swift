import Foundation
import Testing
@testable import MCLCore

/// Port of `dxcluster/BeaconFileTest` (2).
@Suite struct BeaconFileTests {

    /// A sample from the N1MM manual (BEACONS).
    private static let sample: String = [
        "# Hours to stay in bandmap (mostly > 24 or > 48)",
        "60",
        "# call beacon;frequency;locator;comment",
        "OZ7IGY/B;144471,1;JO55WM;",
        "PI7CIS/B;144416,2;JO22DC;Should always be heard",
        "DL0PR/B;144486,3;JO44JH;Switches power!",
        "GB3VHF/B;144430.4;JO01DH;QRG with a .",
        "ON0VHF/B;144418,5;JO20;4 digit grid",
        "broken line without semicolons",
        "",
    ].joined(separator: "\n")

    @Test func parsesN1mmSample() {
        let b = BeaconFile.parse(Self.sample)

        #expect(b.hours == 60)
        #expect(b.beacons.count == 5)
        let oz = b.beacons[0]
        #expect(oz.dxCall == "OZ7IGY/B")
        #expect(oz.freqHz == 144_471_100)
        #expect(oz.comment == "JO55WM")
        #expect(b.beacons[3].freqHz == 144_430_400, "decimal point")
        #expect(b.beacons[1].comment == "JO22DC Should always be heard")
        #expect(b.skipped.count == 1)
    }

    @Test func beaconsOutliveNormalSpots() {
        let now = DxTestClock("2026-11-28T12:00:00Z")
        let buffer = SpotBuffer(maxAgeMinutes: 30, clock: now.source)
        buffer.add(DxSpot(spotter: "OK1XOE", freqHz: 14_025_000, dxCall: "DL1ABC", comment: ""))
        buffer.addUntil(DxSpot(spotter: BeaconFile.spotter, freqHz: 144_471_100, dxCall: "OZ7IGY/B", comment: ""),
                        until: now.now.addingTimeInterval(60 * 3600))

        now.set(now.now.addingTimeInterval(2 * 3600))

        #expect(buffer.snapshot().count == 1)
        #expect(buffer.find("OZ7IGY/B") != nil)
        #expect(buffer.find("DL1ABC") == nil)

        now.set(now.now.addingTimeInterval(59 * 3600))
        #expect(buffer.snapshot().isEmpty, "after 60 h even the beacon disappears")
    }
}
