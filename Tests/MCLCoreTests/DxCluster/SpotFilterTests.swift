import Foundation
import Testing
@testable import MCLCore

@Suite struct SpotFilterTests {

    typealias F = SpotAnalysisFixture

    static let cw = F.spot("DL1XX", 14_025_000, "DL1ABC", "")               // 20 m, CW segment
    static let ssb = F.spot("DL1XX", 14_250_000, "LU1ABC", "SSB")           // 20 m, phone
    static let ft8 = F.spot("DL1XX", 14_074_000, "VE3ABC", "")              // 20 m, digi frequency
    static let seventeen = F.spot("DL1XX", 18_075_000, "K1ABC", "CW")       // 17 m, CW
    static let unknown = F.spot("DL1XX", 5_354_000, "DL2ABC", "")           // 60 m, no mode known
    static let two = F.spot("DL1XX", 144_300_000, "OK1ABC", "")             // 2 m
    static let all: [DxSpot] = [cw, ssb, ft8, seventeen, unknown, two]

    static func calls(_ spots: [DxSpot]) -> [String] { spots.map(\.dxCall) }

    static func analyzerOutside() throws -> SpotAnalyzer { try F.environment().analyzer() }

    static func analyzerInCqww() throws -> SpotAnalyzer {
        let env = try F.environment()
        try env.activate("cq-ww-cw")
        return env.analyzer()
    }

    // MARK: - bands

    @Test func defaultFilterPassesEverythingWithoutAnalysis() {
        let filter = SpotFilter.default
        #expect(filter.isDefault)
        #expect(filter.apply(Self.all, analyzer: nil) == Self.all)
    }

    @Test func bandSwitchesHideTheirBand() throws {
        let a = try Self.analyzerOutside()
        var filter = SpotFilter.default
        filter.setBand(.m20, on: false)
        #expect(Self.calls(filter.apply(Self.all, analyzer: a)) == ["K1ABC", "DL2ABC", "OK1ABC"])
        filter.setBand(.m20, on: true)
        #expect(filter.apply(Self.all, analyzer: a) == Self.all)   // unhiding brings the spots back
    }

    @Test func groupButtonsToggleTheWholeGroup() {
        var filter = SpotFilter.default
        #expect(filter.isGroupOn(.hf))
        filter.toggleGroup(.hf)
        #expect(Set(SpotFilter.Group.hf.bands) == filter.hiddenBands)
        #expect(!filter.isGroupOn(.hf) && filter.isGroupOn(.vhf))
        filter.toggleGroup(.hf)                       // none on -> all on
        #expect(filter.isDefault)
        filter.setBand(.m80, on: false)
        filter.toggleGroup(.hf)                       // partly on -> all on
        #expect(filter.isGroupOn(.hf))
        filter.toggleGroup(.microwave)
        #expect(filter.hiddenBands == Set(SpotFilter.Group.microwave.bands))
    }

    @Test func groupsCoverEveryBandOnce() {
        let grouped: [Band] = SpotFilter.Group.allCases.flatMap(\.bands)
        #expect(Set(grouped) == Set(Band.allCases) && grouped.count == Band.allCases.count)
    }

    // MARK: - modes

    @Test func modeSwitchesUseTheInferredMode() throws {
        let a = try Self.analyzerOutside()
        var filter = SpotFilter.default
        filter.setMode(SpotModeCategory.phone, on: false)
        #expect(!Self.calls(filter.apply(Self.all, analyzer: a)).contains("LU1ABC"))
        filter.setMode(SpotModeCategory.digi, on: false)
        #expect(Self.calls(filter.apply(Self.all, analyzer: a)) == ["DL1ABC", "K1ABC", "DL2ABC", "OK1ABC"])
        filter.allModes()
        #expect(filter.apply(Self.all, analyzer: a) == Self.all)
    }

    @Test func unknownModeIsShownUnlessAllModesAreOff() throws {
        let a = try Self.analyzerOutside()
        #expect(a.spotModeCategory(Self.unknown) == nil)
        var filter = SpotFilter.default
        filter.setMode(SpotModeCategory.cw, on: false)
        #expect(filter.allows(Self.unknown, analyzer: a))
        filter.setMode(SpotModeCategory.phone, on: false)
        filter.setMode(SpotModeCategory.digi, on: false)
        #expect(!filter.allows(Self.unknown, analyzer: a))
    }

    // MARK: - contest

    @Test func contestOptionHidesWhatTheContestDoesNotAllow() throws {
        let a = try Self.analyzerInCqww()                    // bands 160-10 m, CW only
        let filter = SpotFilter(contestOnly: true)
        // 17 m, 60 m and 2 m are outside the contest; SSB and FT8 are not CW.
        #expect(Self.calls(filter.apply(Self.all, analyzer: a)) == ["DL1ABC"])
        #expect(SpotFilter.default.apply(Self.all, analyzer: a) == Self.all)
    }

    @Test func contestOptionHasNoEffectWithoutAContest() throws {
        let a = try Self.analyzerOutside()
        #expect(SpotFilter(contestOnly: true).apply(Self.all, analyzer: a) == Self.all)
        #expect(SpotFilter(hideNonWorkable: true).apply(Self.all, analyzer: a) == Self.all)
        #expect(SpotFilter(contestOnly: true).apply(Self.all, analyzer: nil) == Self.all)
    }

    @Test func nonWorkableSpotsHideLikeTheContestOptionAndDupesStay() throws {
        let env = try F.environment()
        try env.activate("cq-ww-cw")
        try env.log("DL1ABC", "20m", "CW", ("rst", "599"), ("zone", "14"))
        let a = env.analyzer()
        let filter = SpotFilter(hideNonWorkable: true)
        let kept = Self.calls(filter.apply(Self.all, analyzer: a))
        #expect(kept == ["DL1ABC"])                         // the dupe stays, coloured as a dupe elsewhere
        #expect(a.spotStatus(Self.cw).dupe)
    }

    // MARK: - own spots

    @Test func ownSpotsAreNeverHidden() throws {
        let a = try Self.analyzerInCqww()
        let mark = DxSpot(spotter: "OK1XOE", freqHz: 144_300_000, dxCall: "MARK", comment: "", selfSpotted: true)
        var filter = SpotFilter(contestOnly: true, spotterContinents: ["AS"], hideNonWorkable: true)
        filter.hiddenBands = Set(Band.allCases)
        filter.hiddenModes = Set(SpotFilter.modes)
        #expect(filter.allows(mark, analyzer: a))
        #expect(!filter.allows(Self.cw, analyzer: a))
    }

    // MARK: - spotter origin

    @Test func spotterOriginFiltersByContinentAndOwnCountry() throws {
        let a = try Self.analyzerOutside()
        let fromEU = F.spot("DL1XX", 14_025_000, "JA1AAA", "")
        let fromNA = F.spot("W3LPL", 14_025_000, "JA1BBB", "")
        let fromJA = F.spot("JA1ZZZ", 14_025_000, "JA1CCC", "")
        let fromOwn = F.spot("OK2ABC", 14_025_000, "JA1DDD", "")
        let skimmer = F.spot("DK0SK-#", 14_025_000, "JA1EEE", "CW 20 dB 25 WPM")
        let unresolved = F.spot("XX9ZZ", 14_025_000, "JA1FFF", "")
        let spots = [fromEU, fromNA, fromJA, fromOwn, skimmer, unresolved]
        func kept(_ f: SpotFilter) -> [String] { Self.calls(f.apply(spots, analyzer: a)) }

        #expect(kept(SpotFilter.default).count == 6)
        #expect(kept(SpotFilter(spotterContinents: ["EU"])) == ["JA1AAA", "JA1DDD", "JA1EEE"])
        #expect(kept(SpotFilter(spotterContinents: ["NA", "AS"])) == ["JA1BBB", "JA1CCC"])
        #expect(kept(SpotFilter(spotterOwnCountry: true)) == ["JA1DDD"])
        #expect(kept(SpotFilter(spotterContinents: ["NA"], spotterOwnCountry: true)) == ["JA1BBB", "JA1DDD"])
    }

    @Test func spotterSuffixesAreStripped() {
        #expect(SpotAnalyzer.baseCall("DK0SK-#") == "DK0SK")
        #expect(SpotAnalyzer.baseCall("w3lpl-2") == "W3LPL")
        #expect(SpotAnalyzer.baseCall("OK1ABC/P") == "OK1ABC/P")
        #expect(SpotAnalyzer.baseCall("DL1XX-AB") == "DL1XX-AB")
    }

    // MARK: - console lines

    @Test func onlySpotLinesOfTheConsoleAreFiltered() throws {
        let a = try Self.analyzerOutside()
        let lines: [String] = [
            "DX de DL1XX:     14025.0  DL1ABC       CW           1234Z",
            "DX de DL1XX:     50150.0  OK1AAA       6m           1234Z",
            "[RBN] DX de DK0SK-#:   50100.0  OK1BBB       CW 20 dB 25 WPM 1234Z",
            "  21150.0  K1ABC       7-Oct-2026 1824Z  CQ  <W3LPL>",
            "WWV de W0MU <18>: SFI=150",
            "SH/DX 5",
            "login: ",
        ]
        var filter = SpotFilter.default
        filter.setBand(.m6, on: false)
        let out = filter.applyToConsole(lines, analyzer: a)
        #expect(out == [lines[0], lines[3], lines[4], lines[5], lines[6]])
        #expect(SpotFilter.default.applyToConsole(lines, analyzer: a) == lines)
    }

    // MARK: - reset

    @Test func resetRestoresTheDefaults() {
        var filter = SpotFilter(hiddenBands: [.m20], hiddenModes: ["CW"], contestOnly: true,
                                spotterContinents: ["EU"], spotterOwnCountry: true, hideNonWorkable: true)
        #expect(!filter.isDefault)
        filter.reset()
        #expect(filter == .default)
    }

    // MARK: - configuration

    @Test func configRoundTripKeepsTheFilter() throws {
        var config = DxClusterConfig()
        let filter = SpotFilter(hiddenBands: [.m160, .cm9], hiddenModes: ["DIGI"], contestOnly: true,
                                spotterContinents: ["NA", "EU"], spotterOwnCountry: true, hideNonWorkable: true)
        config.spotFilter = filter
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(DxClusterConfig.self, from: data)
        #expect(back.spotFilter == filter)
        #expect(back == config)
        #expect(back.spotFilterHiddenBands == ["160m", "9cm"])
        #expect(back.spotFilterSpotterContinents == ["EU", "NA"])
    }

    @Test func oldConfigWithoutTheKeysLoadsUnchanged() throws {
        let json = Data(#"{"minSkimmers":2,"autoSplit":false,"spotBufferMinutes":45}"#.utf8)
        let config = try JSONDecoder().decode(DxClusterConfig.self, from: json)
        #expect(config.spotFilter == .default && config.spotFilter.isDefault)
        #expect(config.minSkimmers == 2 && config.spotBufferMinutes == 45)
    }

    @Test func unknownBandNamesInTheConfigAreIgnored() throws {
        let json = Data(#"{"spotFilterHiddenBands":["20m","nonsense"],"spotFilterHiddenModes":["CW","XX"]}"#.utf8)
        let config = try JSONDecoder().decode(DxClusterConfig.self, from: json)
        #expect(config.spotFilter.hiddenBands == [.m20] && config.spotFilter.hiddenModes == ["CW"])
    }
}
