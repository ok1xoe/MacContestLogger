import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The keying options reach the open keyer once and again after every change; a followed Winkeyer pot sets the CW
/// speed. Fakes only (the Winkeyer opener returns a `FakeCwKeyer`).
@MainActor @Suite struct KeyerOptionsTests {

    @Test func optionsAreAppliedOnOpenAndAfterAChange() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.sendCwText("TEST")
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        #expect(keyer.configured == [CwKeyingOptions()])
        app.keyer.sendCwText("AGN")
        await app.settle()
        #expect(keyer.configured.count == 1)
        app.model.config.config.cwKeyer.options.weight = 60
        app.keyer.sendCwText("TU")
        await app.settle()
        #expect(keyer.configured.map(\.weight) == [50, 60])
        #expect(app.keying.openedKeyers.count == 1)
    }

    @Test func followedPotSetsTheSpeed() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwKeyer.options.wkSendSettings = true
            config.cwKeyer.options.wkPotMode = .follow
        })
        app.keyer.sendCwText("TEST")
        await app.settle()
        let keyer: FakeCwKeyer = try #require(app.keying.lastKeyer)
        keyer.turnPot(33)
        for _ in 0..<10_000 where app.keyer.cwSpeed != 33 {
            await Task.yield()
        }
        #expect(app.keyer.cwSpeed == 33)
        await app.settle()
        #expect(keyer.events.last == "speed 33")
    }

    @Test func ignoredPotLeavesTheSpeed() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in winkeyerConfig(&config) })
        app.keyer.sendCwText("TEST")
        await app.settle()
        app.keyer.potSpeedChanged(40)
        #expect(app.keyer.cwSpeed == 28)
    }
}
