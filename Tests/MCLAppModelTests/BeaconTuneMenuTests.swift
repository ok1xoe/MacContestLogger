import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Tools → „Naladit maják NCDXF pro pásmo" (N1MM „Tune to beacon for this band"): the rig (a fake `rigctld` on a
/// loopback port) goes to the band's beacon frequency in CW and the status names the beacon and its bearing.
@MainActor @Suite struct BeaconTuneMenuTests {

    @Test func tunesToTheBandsBeacon() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000, mode: "USB")
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
            config.station.gridSquare = "JN79"
        }
        await rigApp.connect()
        await rigApp.settle()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        MenuActions.tuneBeacon(app: rigApp.model, now: now)
        #expect(rigApp.entry.form.freqKHz == "14100.00")
        #expect(rigApp.entry.form.mode == .cw)
        await eventually("rig tuned") { fake.frequency == 14_100_000 }
        let beacon: NcdxfBeacons.Beacon = try #require(NcdxfBeacons.transmitting(freqHz: 14_100_000, at: now))
        #expect(rigApp.status.contains(beacon.call))
        #expect(rigApp.status.contains("°"))
    }

    @Test func otherBandsAreRefused() async throws {
        let app = try await TestApp.make()
        app.model.entry.setFrequency("7025")
        #expect(MenuActions.perform("tools.tuneBeacon", app: app.model) == nil)
        #expect(app.model.entry.form.freqKHz == "7025")
        #expect(app.model.status.message.contains("20, 17, 15, 12"))
    }
}
