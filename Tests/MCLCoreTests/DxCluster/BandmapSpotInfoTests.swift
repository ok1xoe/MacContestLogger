import Foundation
import Testing
@testable import MCLCore

/// The band map's N1MM spot marks, tooltip, call-frame and callsign search (`BandmapSpotInfo`) and the packet spot
/// mode of a spot.
@Suite struct BandmapSpotInfoTests {

    static func spot(_ call: String, _ freqHz: Int, spotter: String = "OK1RR", comment: String = "",
                     selfSpotted: Bool = false) -> DxSpot {
        DxSpot(spotter: spotter, freqHz: freqHz, dxCall: call, comment: comment, selfSpotted: selfSpotted)
    }

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func skimmerMarks() {
        #expect(BandmapSpotInfo.skimmerMark(Self.spot("K1ZZ", 14_025_000, spotter: "DL8LAS-#"), myCall: "OK1XOE") == "#")
        #expect(BandmapSpotInfo.skimmerMark(Self.spot("K1ZZ", 14_025_000, spotter: "ok1xoe-#"), myCall: "OK1XOE") == "!")
        #expect(BandmapSpotInfo.skimmerMark(Self.spot("K1ZZ", 14_025_000, comment: "19 dB 28 WPM CQ"),
                                            myCall: "") == "#")
        #expect(BandmapSpotInfo.skimmerMark(Self.spot("K1ZZ", 14_025_000), myCall: "OK1XOE") == nil)
        #expect(BandmapSpotInfo.skimmerMark(Self.spot("K1ZZ", 14_025_000, spotter: "OK1XOE-#", selfSpotted: true),
                                            myCall: "OK1XOE") == nil)
    }

    @Test func newIsYoungerThanThreeMinutes() {
        #expect(BandmapSpotInfo.isNew(spottedAt: Self.t0, now: Self.t0))
        #expect(BandmapSpotInfo.isNew(spottedAt: Self.t0, now: Self.t0.addingTimeInterval(179)))
        #expect(!BandmapSpotInfo.isNew(spottedAt: Self.t0, now: Self.t0.addingTimeInterval(180)))
        #expect(!BandmapSpotInfo.isNew(spottedAt: nil, now: Self.t0))
    }

    @Test func qsxFromTheComment() {
        #expect(BandmapSpotInfo.qsxHz(Self.spot("K1ZZ", 14_025_000, comment: "UP 2")) == 14_027_000)
        #expect(BandmapSpotInfo.qsxHz(Self.spot("K1ZZ", 14_195_000, comment: "SSB UP")) == 14_200_000)
        #expect(BandmapSpotInfo.qsxHz(Self.spot("K1ZZ", 14_025_000, comment: "CW UP")) == 14_026_000)
        #expect(BandmapSpotInfo.qsxHz(Self.spot("K1ZZ", 14_025_000, comment: "QSX 027.5")) == 14_027_500)
        #expect(BandmapSpotInfo.qsxHz(Self.spot("K1ZZ", 14_025_000, comment: "tnx")) == nil)
        #expect(BandmapSpotInfo.qsxText(14_027_500) == "027")
        #expect(BandmapSpotInfo.qsxText(7_003_000) == "003")
        #expect(BandmapSpotInfo.qsxText(50_101_000) == "50101")
    }

    @Test func grayLineIsHalfAnHourAroundSunriseAndSunset() throws {
        let lat = 50.08
        let lon = 14.42
        let epochDay = Int64(Self.t0.timeIntervalSince1970 / 86_400)
        let times = try #require(SolarTimes.forLocation(lat, lon, epochDay: epochDay))
        let sunrise = Date(timeIntervalSince1970: Double(epochDay) * 86_400 + Double(times.sunrise))
        let sunset = Date(timeIntervalSince1970: Double(epochDay) * 86_400 + Double(times.sunset))
        #expect(BandmapSpotInfo.onGrayLine(lat: lat, lon: lon, now: sunrise.addingTimeInterval(-1_700)))
        #expect(BandmapSpotInfo.onGrayLine(lat: lat, lon: lon, now: sunset.addingTimeInterval(1_700)))
        #expect(!BandmapSpotInfo.onGrayLine(lat: lat, lon: lon, now: sunrise.addingTimeInterval(1_900)))
        #expect(!BandmapSpotInfo.onGrayLine(lat: lat, lon: lon, now: sunrise.addingTimeInterval(4 * 3_600)))
    }

    @Test func theDrawnLabel() {
        #expect(BandmapSpotInfo.label(call: "K1ZZ", azimuth: 291, skimmers: 3, skimmerMark: "#", grayLine: true,
                                      qsxHz: 14_027_000, isNew: true) == "K1ZZ#\u{a4} 291° ×3 QSX 027 NEW")
        #expect(BandmapSpotInfo.label(call: "K1ZZ", azimuth: nil, skimmers: 0, skimmerMark: nil, grayLine: false,
                                      qsxHz: nil, isNew: false) == "K1ZZ")
    }

    @Test func theTooltip() {
        let spot = Self.spot("K1ZZ", 14_025_300, comment: "UP 2", selfSpotted: false)
        let facts = BandmapSpotInfo.TooltipFacts(spottedAt: Self.t0, now: Self.t0.addingTimeInterval(4 * 60 + 10),
                                                 count: 3, skimmers: 2, azimuth: 291, grayLine: true,
                                                 qsxHz: 14_027_300)
        #expect(BandmapSpotInfo.tooltip(spot, facts: facts) == """
            K1ZZ   14025.3 kHz
            Spotter: OK1RR
            Před 4 min
            Komentář: UP 2
            QSX 14027.3 kHz
            Spotováno 3x
            Skimmerů: 2
            Azimut: 291°
            \u{a4} u stanice vychází nebo zapadá slunce
            """)
        let own = Self.spot("OK1XOE", 7_010_000, spotter: "", selfSpotted: true)
        #expect(BandmapSpotInfo.tooltip(own, facts: .init(spottedAt: nil, now: Self.t0)) == """
            OK1XOE   7010.0 kHz
            Vlastní spot
            """)
    }

    @Test func callFrameTakesTheNearestWithinTheTolerance() {
        let spots = [Self.spot("A1", 14_025_000), Self.spot("B2", 14_025_250), Self.spot("C3", 14_024_800)]
        #expect(BandmapSpotInfo.callFrameSpot(spots, freqHz: 14_025_100, toleranceHz: 300)?.dxCall == "A1")
        #expect(BandmapSpotInfo.callFrameSpot(spots, freqHz: 14_025_200, toleranceHz: 300)?.dxCall == "B2")
        #expect(BandmapSpotInfo.callFrameSpot(spots, freqHz: 14_025_600, toleranceHz: 300) == nil)
        #expect(BandmapSpotInfo.callFrameSpot(spots, freqHz: 14_025_000, toleranceHz: 0)?.dxCall == "A1")
        #expect(BandmapSpotInfo.callFrameSpot(spots, freqHz: 0, toleranceHz: 300) == nil)
    }

    @Test func findGoesUpAndWraps() {
        let spots = [Self.spot("K1ABC", 14_010_000), Self.spot("DL1ABC", 14_100_000), Self.spot("W1AW", 14_050_000),
                     Self.spot("JA1ABC", 7_010_000)]
        #expect(BandmapSpotInfo.find("abc", in: spots, fromHz: 14_025_000)?.dxCall == "DL1ABC")
        #expect(BandmapSpotInfo.find("ABC", in: spots, fromHz: 14_100_000)?.dxCall == "JA1ABC")
        #expect(BandmapSpotInfo.find("ABC", in: spots, fromHz: 7_010_000)?.dxCall == "K1ABC")
        #expect(BandmapSpotInfo.find(" w1aw ", in: spots, fromHz: 0)?.dxCall == "W1AW")
        #expect(BandmapSpotInfo.find("XYZ", in: spots, fromHz: 0) == nil)
        #expect(BandmapSpotInfo.find("  ", in: spots, fromHz: 0) == nil)
    }

    @Test func toleranceByMode() {
        var config = DxClusterConfig()
        config.tuningToleranceCwHz = 100
        config.tuningToleranceSsbHz = 500
        config.tuningToleranceDigiHz = 50
        #expect(config.tuningToleranceHz(.cw) == 100)
        #expect(config.tuningToleranceHz(.ssb) == 500)
        #expect(config.tuningToleranceHz(.fm) == 500)
        #expect(config.tuningToleranceHz(.rtty) == 50)
        #expect(config.tuningToleranceHz(.ft8) == 50)
        config.tuningToleranceCwHz = 99_999
        config.tuningToleranceSsbHz = -5
        #expect(config.tuningToleranceCwHz == 20_000)
        #expect(config.tuningToleranceSsbHz == 0)
        let defaults = DxClusterConfig()
        #expect(defaults.callFrame)
        #expect(!defaults.spotModeOnTune)
        #expect(defaults.tuningToleranceHz(.cw) == 300)
    }

    @Test func oldConfigurationsDecodeTheDefaults() throws {
        let decoded = try JSONDecoder().decode(DxClusterConfig.self, from: Data("{}".utf8))
        #expect(decoded == DxClusterConfig())
        let tuned = try JSONDecoder().decode(DxClusterConfig.self, from: Data(
            #"{"callFrame": false, "tuningToleranceSsbHz": 50000, "spotModeOnTune": true}"#.utf8))
        #expect(!tuned.callFrame)
        #expect(tuned.tuningToleranceSsbHz == 20_000)
        #expect(tuned.spotModeOnTune)
    }

    @Test func packetSpotModeComesFromTheCommentThenTheBandPlan() {
        let runtime = ContestRuntime(dxcc: nil, registry: nil, available: [], contestsDir: nil,
                                     myCall: { "OK1XOE" }, myGrid: { "JO70" })
        let analyzer = SpotAnalyzer(runtime: runtime)
        #expect(analyzer.packetSpotMode(Self.spot("K1ZZ", 14_200_000, comment: "CW 22 wpm")) == .cw)
        #expect(analyzer.packetSpotMode(Self.spot("K1ZZ", 14_025_000, comment: "FT8 -10")) == .ft8)
        #expect(analyzer.packetSpotMode(Self.spot("K1ZZ", 14_025_000)) == .cw)
        #expect(analyzer.packetSpotMode(Self.spot("K1ZZ", 14_250_000)) == .ssb)
        #expect(analyzer.packetSpotMode(Self.spot("K1ZZ", 144_000)) == nil)
    }
}
