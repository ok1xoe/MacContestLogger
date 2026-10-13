import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM Telnet filter options in the app: busted spots hidden from the band map's feed and greyed in the console,
/// preferred spotters marked ★, beacons hidden, and the blacklists' switch, Clear, Import and Export.
@MainActor @Suite struct TelnetFiltersTests {

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func spot(_ call: String, _ freqHz: Int, spotter: String = "DL1XX", comment: String = "CW") -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: comment)
    }

    @Test func bustedSpotsLeaveTheFeedAndGreyInTheConsole() async throws {
        let app = try await TestApp.make(fixedNow: Self.now)
        let model: AppModel = app.model
        let buffer: SpotBuffer = model.dxCluster.spots
        buffer.add(Self.spot("OK1XOE", 14_025_000))
        buffer.add(Self.spot("OK1XOE", 14_025_000, spotter: "W3LPL"))
        buffer.add(Self.spot("OK1XOF", 14_025_100))
        buffer.add(Self.spot("DL1ABC", 14_025_050))
        #expect(model.spotFeed.filteredSnapshot().map(\.dxCall) == ["OK1XOE", "OK1XOF", "DL1ABC"])
        var filter = SpotFilter.default
        filter.removeBusted = true
        model.dxCluster.setSpotFilter(filter)
        #expect(model.spotFeed.filteredSnapshot().map(\.dxCall) == ["OK1XOE", "DL1ABC"])

        try model.dxCluster.log.rx("DX de DL1XX:     14025.1  OK1XOF       CW             1200Z")
        try model.dxCluster.log.rx("DX de DL1XX:     14025.0  OK1XOE       CW             1200Z")
        let analysis: SpotAnalysisModel = model.spotAnalysis
        let lines: [ConsoleLine] = model.dxCluster.consoleLines(
            analyzer: analysis.current(), analysisRevision: analysis.revision,
            context: model.spotFeed.context(for: filter), contextRevision: model.spotFeed.revision)
        #expect(lines.compactMap { $0.spot == nil ? nil : $0.tint } == [.filtered, .cw])

        filter.removeBusted = false
        model.dxCluster.setSpotFilter(filter)
        #expect(model.spotFeed.filteredSnapshot().count == 3)
    }

    @Test func preferredSpottersAreStarredAndBeaconsHidden() async throws {
        let app = try await TestApp.make(fixedNow: Self.now)
        let model: AppModel = app.model
        let preferred: DxSpot = Self.spot("OK1ABC", 14_025_000, spotter: "OK1XOE-#", comment: "CW 20 dB 25 WPM CQ")
        let other: DxSpot = Self.spot("DL2ABC", 14_030_000, spotter: "W3LPL-2")
        model.dxCluster.spots.add(preferred)
        model.dxCluster.spots.add(other)
        model.dxCluster.spots.add(Self.spot("4U1UN", 14_100_000, comment: "NCDXF"))
        var filter = SpotFilter.default
        filter.preferredSpotters = ["OK1XOE"]
        filter.hideBeacons = true
        model.dxCluster.setSpotFilter(filter)
        let label: String = model.bandmap.drawnLabel(preferred)
        #expect(label.hasPrefix("OK1ABC") && label.contains("★"))
        #expect(!model.bandmap.drawnLabel(other).contains("★"))
        #expect(model.spotFeed.filteredSnapshot().map(\.dxCall) == ["OK1ABC", "DL2ABC"])
        let row = SpotRow(call: "OK1ABC", freqHz: 14_025_000, azimuth: nil, mode: "CW", newMultCount: 0, dupe: false,
                          snr: nil, points: 1, spotter: "OK1XOE-#")
        #expect(model.availMult.isPreferred(row))
        #expect(model.config.config.dxCluster.spotFilterPreferredSpotters == ["OK1XOE"])
    }

    @Test func theBlacklistsCanBeSwitchedClearedImportedAndExported() async throws {
        let app = try await TestApp.make(fixedNow: Self.now)
        let blacklist: BlacklistModel = app.model.blacklist
        let buffer: SpotBuffer = app.model.dxCluster.spots
        #expect(blacklist.importText(isCall: true, "# pirates\nok1aaa, ok1bbb\n\n OK1CCC \nOK1AAA\n") == 3)
        #expect(blacklist.entries(isCall: true).map(\.value) == ["OK1AAA", "OK1BBB", "OK1CCC"])
        #expect(blacklist.exportText(isCall: true) == "OK1AAA\nOK1BBB\nOK1CCC\n")
        buffer.add(Self.spot("OK1AAA", 14_025_000))
        #expect(buffer.snapshot().isEmpty)

        blacklist.setEnabled(false)
        #expect(!app.model.config.config.dxCluster.blacklistEnabled)
        buffer.add(Self.spot("OK1AAA", 14_025_000))
        #expect(buffer.snapshot().map(\.dxCall) == ["OK1AAA"])
        #expect(blacklist.entries(isCall: true).count == 3)
        blacklist.setEnabled(true)
        #expect(buffer.snapshot().isEmpty)

        blacklist.clear(isCall: true)
        #expect(blacklist.entries(isCall: true).isEmpty)
        let saved: AppConfig = await app.savedConfigFlushed()
        #expect(saved.dxCluster.callBlacklist.isEmpty)
        #expect(saved.dxCluster.blacklistEnabled)
    }
}
