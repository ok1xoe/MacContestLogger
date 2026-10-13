import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM „Save Spots" (the buffer saved at quit and restored at start, in a temporary data directory) and „Randomize
/// incoming spot frequencies" (tuning to a spot with an injected random draw). No network, no rig.
@MainActor @Suite struct SpotKeepingTests {

    @Test func spotsSurviveARestartWhenAsked() async throws {
        let first = try await TestApp.make(configure: { config, _ in config.dxCluster.saveSpots = true })
        first.model.dxCluster.spots.add(DxSpot(spotter: "DL1XX", freqHz: 14_025_000, dxCall: "OK1ABC", comment: "CW"))
        await first.model.shutdown()
        let file: URL = first.dataDir.appendingPathComponent(SavedSpotsFile.fileName)
        let data: Data = try Data(contentsOf: file)
        var saved: [SpotBuffer.Stored] = try #require(SavedSpotsFile.decode(data))
        #expect(saved.map(\.dxCall) == ["OK1ABC"])
        let old = DxSpot(spotter: "DL1XX", freqHz: 7_010_000, dxCall: "K1OLD", comment: "")
        saved.append(SpotBuffer.Stored(spot: old, at: Date().addingTimeInterval(-3 * 3_600), until: nil,
                                       skimmers: [], count: 1))
        let payload: Data = try SavedSpotsFile.encode(saved)

        let second = try await TestApp.make(configure: { config, dir in
            config.dxCluster.saveSpots = true
            config.dxCluster.spotBufferMinutes = 60
            try payload.write(to: dir.appendingPathComponent(SavedSpotsFile.fileName))
        })
        #expect(second.model.dxCluster.spots.snapshot().map(\.dxCall) == ["OK1ABC"])

        let off = try await TestApp.make(configure: { config, dir in
            try payload.write(to: dir.appendingPathComponent(SavedSpotsFile.fileName))
        })
        #expect(off.model.dxCluster.spots.snapshot().isEmpty)
        await off.model.shutdown()
        #expect(!FileManager.default.fileExists(atPath: off.dataDir.appendingPathComponent(SavedSpotsFile.fileName).path))
        await second.model.shutdown()
    }

    @Test func tuningToASpotIsRandomizedOnlyWhenAsked() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        model.rig.spotSources.draw = { $0 == 0...1 ? 1 : $0.upperBound }
        let cw = DxSpot(spotter: "DL1XX", freqHz: 14_025_000, dxCall: "OK1ABC", comment: "CW")
        model.rig.tuneToSpot(cw)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)

        model.dxCluster.setRandomizeSpotFrequencies(true)
        #expect(model.config.config.dxCluster.randomizeSpotFrequencies)
        model.rig.tuneToSpot(cw)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_150)
        model.rig.tuneToSpot(DxSpot(spotter: "DL1XX", freqHz: 14_250_000, dxCall: "LU1ABC", comment: "SSB"))
        #expect(model.rig.tuning.tunedFreqHz == 14_250_250)
        model.rig.tuneToSpot(DxSpot(spotter: "OK1XOE", freqHz: 14_030_000, dxCall: "W1AW", comment: "self",
                                    selfSpotted: true))
        #expect(model.rig.tuning.tunedFreqHz == 14_030_000)
        model.dxCluster.setSaveSpots(true)
        #expect(model.config.config.dxCluster.saveSpots)
    }
}
