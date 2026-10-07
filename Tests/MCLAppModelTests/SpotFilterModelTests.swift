import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The spot filter in the app: the band map, Available Mults and spot navigation read the filtered view, the buffer
/// and the share path stay raw, a change applies at once and is saved. Fakes only (a local fake telnet server).
@MainActor @Suite struct SpotFilterModelTests {

    static func spot(_ call: String, _ freqHz: Int, spotter: String = "OK1RR") -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: "")
    }

    @Test func aChangedFilterAppliesToTheExistingSpotsAndIsSaved() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let buffer: SpotBuffer = model.dxCluster.spots
        buffer.add(Self.spot("DL1ABC", 14_025_000))
        buffer.add(Self.spot("OK1XYZ", 7_010_000))
        await runMainQueue()
        let before: Int = model.spotFeed.revision

        var filter = model.dxCluster.spotFilter
        filter.setBand(.m20, on: false)
        model.dxCluster.setSpotFilter(filter)
        #expect(model.spotFeed.revision > before)
        #expect(model.spotFeed.filteredSnapshot().map(\.dxCall) == ["OK1XYZ"])
        #expect(model.spotFeed.snapshot().map(\.dxCall) == ["DL1ABC", "OK1XYZ"])   // the buffer is intact
        #expect(model.config.config.dxCluster.spotFilterHiddenBands == ["20m"])

        model.dxCluster.setSpotFilter(.default)
        #expect(model.spotFeed.filteredSnapshot().map(\.dxCall) == ["DL1ABC", "OK1XYZ"])
    }

    @Test func theBandmapFollowsTheFilter() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.dxCluster.spots.add(Self.spot("DL1ABC", 14_025_000))
        model.dxCluster.spots.add(Self.spot("OK1XYZ", 7_010_000))
        await runMainQueue()
        #expect(model.bandmap.spots().count == 2)
        model.dxCluster.setSpotFilter(SpotFilter(hiddenBands: [.m40]))
        #expect(model.bandmap.spots().map(\.dxCall) == ["DL1ABC"])
    }

    @Test func navigationSkipsHiddenSpots() async throws {
        let spot = try await SpotNavigationTests.contestApp()
        let model: AppModel = spot.model
        let buffer: SpotBuffer = model.dxCluster.spots
        buffer.add(Self.spot("DL2XYZ", 14_025_000))
        buffer.add(Self.spot("W1AW", 14_030_000))
        model.rig.qsy(14_020_000)
        model.dxCluster.setSpotFilter(SpotFilter(spotterContinents: ["AS"]))   // spotter OK1RR is in EU
        model.spotNavigation.jump(direction: 1)
        #expect(model.rig.tuning.tunedFreqHz == 14_020_000)
        #expect(model.status.message == "Žádný spot výš na pásmu")
        // An own spot still counts.
        buffer.add(DxSpot(spotter: "OK1XOE", freqHz: 14_040_000, dxCall: "OK2SELF", comment: "", selfSpotted: true))
        model.spotNavigation.jump(direction: 1)
        #expect(model.rig.tuning.tunedFreqHz == 14_040_000)
        model.rig.qsy(14_020_000)
        model.dxCluster.setSpotFilter(.default)
        model.spotNavigation.jump(direction: 1)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
    }

    @Test func availableMultsApplyTheGlobalFilterBeforeTheirOwn() async throws {
        let spot = try await AvailMultModelTests.app()
        let model: AppModel = spot.model
        let avail: AvailMultModel = model.availMult
        #expect(avail.snapshot().rows.map(\.call) == ["OK1XYZ", "DL1ABC", "DL2XYZ", "W1AW"])
        model.dxCluster.setSpotFilter(SpotFilter(hiddenBands: [.m40]))
        #expect(avail.snapshot().rows.map(\.call) == ["DL1ABC", "DL2XYZ", "W1AW"])
        // The window's own filter works on top: 20 m only, then nothing on 40 m although 40 m is its choice.
        avail.bands = [.m40]
        #expect(avail.snapshot().rows.isEmpty)
        model.dxCluster.setSpotFilter(.default)
        #expect(avail.snapshot().rows.map(\.call) == ["OK1XYZ"])
    }

    @Test func theContestOptionFollowsTheActiveContest() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.dxCluster.spots.add(Self.spot("DL1ABC", 14_025_000))
        model.dxCluster.spots.add(Self.spot("K1ABC", 18_075_000))
        await runMainQueue()
        model.dxCluster.setSpotFilter(SpotFilter(contestOnly: true))
        #expect(model.spotFeed.filteredSnapshot().count == 2)            // no contest: no effect
        try await spot.app.startCqWwCw()
        #expect(model.spotFeed.filteredSnapshot().map(\.dxCall) == ["DL1ABC"])   // 17 m is not a CQ WW band
    }

    @Test func spotsAreSharedAndSentToPluginsUnfiltered() async throws {
        let spot = try await SpotApp.make()
        let log = SpotPortLog()
        spot.dx.pluginSpot = { log.add("plugin " + $0.dxCall) }
        spot.dx.spotShare = { log.add("share " + $0.dxCall) }
        spot.dx.setSpotFilter(SpotFilter(hiddenBands: [.m20]))
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.server.push("DX de OK1ABC:     14030.0  OH2AS         CQ up 2          1234Z")
        await eventually("ports ran") { log.entries.count == 2 }
        #expect(log.entries == ["plugin OH2AS", "share OH2AS"])
        #expect(spot.dx.spots.snapshot().map(\.dxCall) == ["OH2AS"])
        #expect(spot.model.spotFeed.filteredSnapshot().isEmpty)
    }
}
