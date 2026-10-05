import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The six Settings ports of the spot windows (`CD:573-592`, `AS:3726-3732`): after OK the station call reaches every
/// cluster connection, the parallel plan runs, the buffer age and the skimmer threshold apply, the blacklist is
/// re-applied and the callbook clients are new with an empty cache.
@MainActor @Suite struct SpotSettingsPortsTests {

    @Test func okRunsTheSixSpotPorts() async throws {
        let recorder = EffectRecorder()
        let now = TestNow(Date(timeIntervalSince1970: 1_800_000_000))
        let spot = try await SpotApp.make(now: now, configure: { config, _ in
            CallbookModelTests.credentials(&config, qrz: false)
        }, adjust: { environment in
            environment.settingsServices = recorder.services { nil }
        })
        spot.http.hamQth(call: "OK1ABC", grid: "JO70")
        spot.model.callbook.lookup("OK1ABC", typedCall: { "OK1ABC" })
        await spot.model.callbook.settle()
        #expect(spot.model.callbook.cache.contains("OK1ABC"))
        let buffer: SpotBuffer = spot.dx.spots
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: ""))
        buffer.add(DxSpot(spotter: "DL1ABC-#", freqHz: 14_025_000, dxCall: "DL5XX", comment: "CW 21 dB 25 WPM CQ"))
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 7_010_000, dxCall: "OK2ZZ", comment: ""))
        now.advance(seconds: 6 * 60)

        let settings: SettingsModel = spot.model.settings
        settings.open()
        await settings.settle()
        var draft: ConfigurerDraft = try #require(settings.draft)
        draft.call = "OK1XXX"
        draft.dxFavorites = [DxFavoriteDraft(spot.server.favorite(name: "Skimmer", parallel: true))]
        draft.spotBufferMinutes = "10"
        draft.minSkimmers = "0"
        draft.blacklistedCalls = ["OK2ZZ"]
        settings.draft = draft
        #expect(await settings.confirm())

        let effects: [ConfigEffect] = recorder.effects
        for effect: ConfigEffect in [.saveInner(.dxMyCall), .saveInner(.parallelClusters), .spotBuffer, .minSkimmers,
                                     .blacklist, .hamQth] {
            #expect(effects.contains(effect))
        }
        // `minSkimmers` 0 hides the skimmer spot, the blacklist drops OK2ZZ, the 10 minutes keep the 6 minutes old one.
        #expect(buffer.snapshot().map(\.dxCall) == ["OH2AS"])
        #expect(!spot.model.callbook.cache.contains("OK1ABC"))
        await eventually("parallel connected") { spot.dx.parallel.values.first?.connected == true }
        await spot.settle()
        #expect(spot.dx.mainLane.session.myCall == "OK1XXX")
        let key: String = try #require(spot.dx.parallelKeys.first)
        #expect(spot.dx.parallelLanes[key]?.lane.session.myCall == "OK1XXX")
    }
}
