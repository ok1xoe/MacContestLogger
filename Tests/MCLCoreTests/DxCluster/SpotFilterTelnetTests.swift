import Foundation
import Testing
@testable import MCLCore

/// The N1MM Telnet filter options added to the spot filter: spotter prefixes and call areas, call history / worked,
/// NCDXF beacons, busted spots and preferred spotters, and their configuration keys.
@Suite struct SpotFilterTelnetTests {

    typealias F = SpotAnalysisFixture

    static func calls(_ spots: [DxSpot]) -> [String] { spots.map(\.dxCall) }

    // MARK: - spotter origin

    @Test func prefixesAndCallAreasWidenTheOriginFilter() throws {
        let a = try F.environment().analyzer()
        let fromDL = F.spot("DL1XX", 14_025_000, "JA1AAA", "")
        let fromW = F.spot("W3LPL-2", 14_025_000, "JA1BBB", "")
        let fromOK1 = F.spot("OK1ABC", 14_025_000, "JA1CCC", "")
        let fromOK2 = F.spot("OK2ABC-#", 14_025_000, "JA1DDD", "CW 20 dB 25 WPM")
        let fromOK2P = F.spot("OK1XYZ/2", 14_025_000, "JA1EEE", "")
        let unknown = F.spot("XX9ZZ", 14_025_000, "JA1FFF", "")
        let spots = [fromDL, fromW, fromOK1, fromOK2, fromOK2P, unknown]
        func kept(_ f: SpotFilter) -> [String] { Self.calls(f.apply(spots, analyzer: a)) }

        var filter = SpotFilter.default
        filter.spotterPrefixText = "w3, xx9 dl1x"
        #expect(filter.spotterPrefixes == ["W3", "XX9", "DL1X"])
        #expect(filter.spotterFilterOn)
        #expect(kept(filter) == ["JA1AAA", "JA1BBB", "JA1FFF"])

        filter = .default
        filter.setCallArea("2", on: true)
        filter.setCallArea("x", on: true)
        #expect(filter.spotterCallAreas == ["2"])
        #expect(kept(filter) == ["JA1DDD", "JA1EEE"])

        filter.setContinent("NA", on: true)
        #expect(kept(filter) == ["JA1BBB", "JA1DDD", "JA1EEE"])
        #expect(Self.calls(filter.apply(spots, analyzer: nil)) == [])
    }

    @Test func theCallAreaIsThePortableDigitOrThePrefixDigit() {
        #expect(SpotFilter.callArea("OK1ABC") == "1")
        #expect(SpotFilter.callArea("W1AW/4") == "4")
        #expect(SpotFilter.callArea("DL/OK1ABC") == "1")
        #expect(SpotFilter.callArea("S51A") == "1")
        #expect(SpotFilter.callArea("ABC") == nil)
    }

    // MARK: - call history, worked, beacons

    @Test func callHistoryAndWorkedAskTheContext() {
        let spots = [F.spot("DL1XX", 14_025_000, "OK1AAA", ""), F.spot("DL1XX", 14_026_000, "OK1BBB", ""),
                     F.spot("DL1XX", 14_027_000, "OK1CCC", "", true)]
        var filter = SpotFilter.default
        filter.onlyCallHistory = true
        #expect(filter.needsContext)
        #expect(Self.calls(filter.apply(spots, analyzer: nil)) == ["OK1AAA", "OK1BBB", "OK1CCC"])
        let context = SpotFilterContext(inCallHistory: { $0 == "OK1AAA" }, worked: { $0 == "OK1BBB" })
        #expect(Self.calls(filter.apply(spots, analyzer: nil, context: context)) == ["OK1AAA", "OK1CCC"])
        filter = .default
        filter.onlyWorked = true
        #expect(Self.calls(filter.apply(spots, analyzer: nil, context: context)) == ["OK1BBB", "OK1CCC"])
    }

    @Test func beaconSpotsCanBeHidden() {
        let spots = [F.spot("DL1XX", 14_100_000, "4U1UN", "NCDXF"), F.spot("DL1XX", 28_200_000, "ZS6DN/B", ""),
                     F.spot("DL1XX", 14_100_000, "OK1ABC", "")]
        var filter = SpotFilter.default
        #expect(Self.calls(filter.apply(spots, analyzer: nil)).count == 3)
        filter.hideBeacons = true
        #expect(Self.calls(filter.apply(spots, analyzer: nil)) == ["OK1ABC"])
        #expect(NcdxfBeacons.calls.count == 18)
        #expect(NcdxfBeacons.isBeacon(" yv5b "))
    }

    // MARK: - busted spots

    @Test func theEditDistanceStopsAtItsLimit() {
        #expect(BustedSpots.distance("OK1XOE", "OK1XOE", limit: 1) == 0)
        #expect(BustedSpots.distance("OK1XOE", "OK1XOF", limit: 1) == 1)
        #expect(BustedSpots.distance("OK1XOE", "OK1XE", limit: 1) == 1)
        #expect(BustedSpots.distance("OK1XOE", "OK1XOEE", limit: 1) == 1)
        #expect(BustedSpots.distance("OK1XOE", "OK1XAF", limit: 1) == 2)
        #expect(BustedSpots.distance("OK1XOE", "OK1XAF", limit: 2) == 2)
        #expect(BustedSpots.distance("OK1XOE", "DL1ABC", limit: 2) == 3)
        #expect(BustedSpots.distance("K1A", "K1ABCDE", limit: 2) == 3)
    }

    @Test func theLessReportedOfTwoSimilarCallsOnOneFrequencyIsBusted() {
        let good = F.spot("DK0SK-#", 14_025_000, "OK1XOE", "CW 20 dB")
        let bust = F.spot("W3LPL-#", 14_025_100, "OK1XOF", "CW 18 dB")
        let far = F.spot("W3LPL-#", 14_026_000, "OK1XOG", "CW 18 dB")
        let other = F.spot("W3LPL-#", 14_025_050, "DL1ABC", "CW")
        let own = F.spot("OK1XOE", 14_025_020, "OK1XOD", "self", true)
        let reports: [String: Int] = ["OK1XOE": 5, "OK1XOF": 1, "OK1XOG": 1, "DL1ABC": 1]
        let busted = BustedSpots.busted([bust, good, far, other, own], reports: { reports[$0] ?? 1 },
                                        toleranceHz: { _ in 300 }, twoCharacters: false)
        #expect(busted == ["OK1XOF"])
    }

    @Test func aTieKeepsTheFirstSpotAndTwoCharactersAreOptional() {
        let first = F.spot("A", 7_025_000, "OK1XOE", "")
        let second = F.spot("B", 7_025_200, "OK1XOF", "")
        let twoOff = F.spot("C", 7_025_100, "OK1XAF", "")
        let short = [F.spot("D", 3_525_000, "K1A", ""), F.spot("E", 3_525_000, "K1B", "")]
        let one = BustedSpots.busted([first, second] + short, reports: { _ in 1 }, toleranceHz: { _ in 300 },
                                     twoCharacters: false)
        #expect(one == ["OK1XOF"])
        let narrow = BustedSpots.busted([first, second], reports: { _ in 1 }, toleranceHz: { _ in 100 },
                                        twoCharacters: false)
        #expect(narrow.isEmpty)
        let reports: [String: Int] = ["OK1XOE": 4]
        let two = BustedSpots.busted([first, twoOff], reports: { reports[$0] ?? 1 }, toleranceHz: { _ in 300 },
                                     twoCharacters: true)
        #expect(two == ["OK1XAF"])
        #expect(BustedSpots.busted([first, twoOff], reports: { _ in 1 }, toleranceHz: { _ in 300 },
                                   twoCharacters: false).isEmpty)
    }

    @Test func theFilterHidesTheBustedCallsOfItsContext() {
        let spots = [F.spot("A", 7_025_000, "OK1XOE", ""), F.spot("B", 7_025_200, "OK1XOF", "")]
        var filter = SpotFilter.default
        filter.removeBusted = true
        #expect(filter.needsContext)
        #expect(Self.calls(filter.apply(spots, analyzer: nil, context: SpotFilterContext(busted: ["OK1XOF"])))
            == ["OK1XOE"])
        let lines = ConsoleLine.lines(["DX de A: 7025.2 OK1XOF CW 1200Z"], filter: filter, analyzer: nil,
                                      context: SpotFilterContext(busted: ["OK1XOF"]))
        #expect(lines.map(\.tint) == [.filtered])
    }

    // MARK: - preferred spotters

    @Test func preferredSpottersMatchTheirVariantsAndAreNoFilter() {
        var filter = SpotFilter.default
        filter.preferredSpotters = ["wz7i", "OK1XOE", "DL1ABC", "OK2ABC", "WZ7I"]
        #expect(filter.preferredSpotters == ["WZ7I", "OK1XOE", "DL1ABC"])
        #expect(filter.isDefault)
        #expect(filter.isPreferred("WZ7I-2"))
        #expect(filter.isPreferred("wz7i-#"))
        #expect(filter.isPreferred("WZ7I/3"))
        #expect(!filter.isPreferred("WZ7IA"))
        #expect(!filter.isPreferred("OK2ABC"))
        filter.hideBeacons = true
        filter.reset()
        #expect(filter.preferredSpotters == ["WZ7I", "OK1XOE", "DL1ABC"])
        let lines = ConsoleLine.lines(["DX de WZ7I-#: 14025.0 OK1ABC CW 1200Z", "DX de K1AB: 14025.0 OK1ABD CW 1200Z"],
                                      filter: filter, analyzer: nil)
        #expect(lines.map(\.preferred) == [true, false])
    }

    // MARK: - configuration

    @Test func theNewOptionsRoundTripThroughTheConfiguration() throws {
        var filter = SpotFilter.default
        filter.spotterPrefixes = ["OK", "OM"]
        filter.setCallArea("3", on: true)
        filter.setCallArea("1", on: true)
        filter.onlyCallHistory = true
        filter.onlyWorked = true
        filter.hideBeacons = true
        filter.removeBusted = true
        filter.bustedTwoChars = true
        filter.preferredSpotters = ["OK1XOE"]
        var config = DxClusterConfig()
        config.spotFilter = filter
        config.blacklistEnabled = false
        #expect(config.spotFilterSpotterCallAreas == ["1", "3"])
        let back = try JSONDecoder().decode(DxClusterConfig.self, from: JSONEncoder().encode(config))
        #expect(back.spotFilter == filter)
        #expect(!back.blacklistEnabled)
        let empty = try JSONDecoder().decode(DxClusterConfig.self, from: Data("{}".utf8))
        #expect(empty.spotFilter == .default)
        #expect(empty.blacklistEnabled)
    }
}
