import Foundation
import Testing
@testable import MCLCore

/// The Telnet window's node software, the commands MCL formats for it, the button macros, the button files and the
/// console's colour-coded lines.
@Suite struct ClusterCommandsTests {

    typealias F = SpotAnalysisFixture

    // MARK: - software

    @Test func theGreetingNamesTheSoftware() {
        #expect(ClusterSoftware.detect("Hello OK1XOE, this is OK0DXH in Prague running DXSpider V1.57") == .dxSpider)
        #expect(ClusterSoftware.detect("Welcome to the AR-Cluster node Telnet port!") == .arCluster)
        #expect(ClusterSoftware.detect("Running CC Cluster software version 3.101") == .ccCluster)
        #expect(ClusterSoftware.detect("CC-Cluster") == .ccCluster)
        #expect(ClusterSoftware.detect("login:") == nil)
    }

    @Test func aChosenSoftwareWinsOverTheDetectedOne() {
        #expect(ClusterSoftware.effective(configured: .auto, detected: nil) == .dxSpider)
        #expect(ClusterSoftware.effective(configured: .auto, detected: .arCluster) == .arCluster)
        #expect(ClusterSoftware.effective(configured: .ccCluster, detected: .dxSpider) == .ccCluster)
        #expect(ClusterSoftware.from("ARCLUSTER") == .arCluster)
        #expect(ClusterSoftware.from("bogus") == .auto)
    }

    @Test func showDxIsFormattedForTheNode() {
        #expect(ClusterCommandFormat.showDx(count: 30, software: .dxSpider) == "SH/DX 30")
        #expect(ClusterCommandFormat.showDx(count: 30, software: .auto) == "SH/DX 30")
        #expect(ClusterCommandFormat.showDx(count: 25, software: .arCluster) == "SH/DX/25")
        #expect(ClusterCommandFormat.showDx(count: 10, call: " ok1abc ", software: .ccCluster) == "SH/DX/10 OK1ABC")
        #expect(ClusterCommandFormat.showDx(count: 10, call: "DL1ABC/P", software: .dxSpider) == "SH/DX 10 DL1ABC/P")
        #expect(ClusterCommandFormat.showDx(count: 0, software: .dxSpider) == "SH/DX 1")
        #expect(ClusterCommandFormat.showDx(count: 500, software: .dxSpider) == "SH/DX 100")
    }

    @Test func aCallThatIsNotACallIsLeftOut() {
        #expect(ClusterCommandFormat.cleanCall("OK1ABC; BYE") == nil)
        #expect(ClusterCommandFormat.cleanCall("OK1ABC\r\nBYE") == nil)
        #expect(ClusterCommandFormat.cleanCall("   ") == nil)
        #expect(ClusterCommandFormat.showDx(count: 5, call: "a b", software: .dxSpider) == "SH/DX 5")
    }

    // MARK: - button macros

    @Test func waitAndConnSplitAButton() {
        #expect(ClusterButtonMacro.steps("SH/DX") == [.send("SH/DX")])
        #expect(ClusterButtonMacro.steps("SH/WWV{WAIT}SH/WCY") == [.send("SH/WWV"), .wait, .send("SH/WCY")])
        #expect(ClusterButtonMacro.steps("{conn} RBN") == [.connect("RBN")])
        #expect(ClusterButtonMacro.steps("{CONN} RBN {WAIT} SET/SKIMMER") == [.connect("RBN"), .wait,
                                                                              .send("SET/SKIMMER")])
        #expect(ClusterButtonMacro.steps("   ") == [])
        #expect(ClusterButtonMacro.steps("{WAIT}") == [.wait])
    }

    @Test func connFindsTheFavouriteByNameOrHost() {
        let favorites: [DxClusterFavorite] = [
            DxClusterFavorite(name: "OK0DXH", host: "ok0dxh.example", port: 41112, login: "", password: ""),
            DxClusterFavorite(name: "RBN", host: "telnet.reversebeacon.example", port: 7000, login: "", password: ""),
        ]
        #expect(ClusterButtonMacro.favorite(named: "rbn", in: favorites)?.port == 7000)
        #expect(ClusterButtonMacro.favorite(named: "ok0dxh.example", in: favorites)?.name == "OK0DXH")
        #expect(ClusterButtonMacro.favorite(named: "telnet.reversebeacon.example:7000", in: favorites)?.name == "RBN")
        #expect(ClusterButtonMacro.favorite(named: "none", in: favorites) == nil)
    }

    // MARK: - button files

    @Test func aButtonSetRoundTripsThroughItsFile() {
        var commands: [DxClusterCommand] = DxClusterConfig.defaultCommands()
        commands[0] = DxClusterCommand(label: "RBN, CW", command: "{CONN} RBN")
        let text: String = ClusterButtonFile.encode(commands)
        #expect(text.hasPrefix(ClusterButtonFile.header + "\n"))
        let decoded = ClusterButtonFile.decode(text)
        #expect(decoded?.count == DxClusterConfig.commandCount)
        #expect(decoded?[0] == DxClusterCommand(label: "RBN  CW", command: "{CONN} RBN"))
        #expect(decoded?[1] == commands[1])
    }

    @Test func aShortFileIsPaddedWithTheDefaults() {
        let decoded = ClusterButtonFile.decode("# comment\r\nWWV,SH/WWV 5\r\n\r\nBYE\n")
        #expect(decoded?[0] == DxClusterCommand(label: "WWV", command: "SH/WWV 5"))
        #expect(decoded?[1] == DxClusterCommand(label: "BYE", command: "BYE"))
        #expect(decoded?[2] == DxClusterConfig.defaultCommands()[2])
        #expect(ClusterButtonFile.decode("# only a comment\n") == nil)
    }

    // MARK: - configuration

    @Test func theOptionsHaveN1mmDefaultsAndRoundTrip() throws {
        let empty = try JSONDecoder().decode(DxClusterConfig.self, from: Data("{}".utf8))
        #expect(empty.clusterSoftware == "auto")
        #expect(!empty.autoLogon)
        #expect(empty.showButtons)
        #expect(empty.showDxCount == 30)
        var config = DxClusterConfig()
        config.clusterSoftware = "arcluster"
        config.autoLogon = true
        config.showButtons = false
        config.showDxCount = 250
        #expect(config.showDxCount == 100)
        let back = try JSONDecoder().decode(DxClusterConfig.self, from: JSONEncoder().encode(config))
        #expect(back == config)
        let clamped = try JSONDecoder().decode(DxClusterConfig.self, from: Data(#"{"showDxCount": -3}"#.utf8))
        #expect(clamped.showDxCount == 1)
    }

    // MARK: - console lines

    @Test func spotLinesAreTintedByModeAndGreyedWhenFiltered() throws {
        let analyzer: SpotAnalyzer = try F.environment().analyzer()
        let log: [String] = [
            "12:00:00  DX de DL1XX:     14025.0  DL1ABC       CW                             1200Z",
            "12:00:01  DX de DL1XX:     14250.0  LU1ABC       SSB                            1200Z",
            "12:00:02  DX de DL1XX:     14074.0  VE3ABC       FT8                            1200Z",
            "12:00:03  » SH/DX",
            "12:00:04  [RBN] DX de DL1XX-#: 28025.0  K1ABC  CW 20 dB 25 WPM CQ  1200Z",
        ]
        let plain: [ConsoleLine] = ConsoleLine.lines(log, filter: .default, analyzer: analyzer)
        #expect(plain.map(\.tint) == [.cw, .phone, .digi, .plain, .cw])
        #expect(plain[3].spot == nil)
        #expect(plain[0].spot?.dxCall == "DL1ABC")
        var filter = SpotFilter.default
        filter.setBand(.m10, on: false)
        filter.setMode(SpotModeCategory.phone, on: false)
        let filtered: [ConsoleLine] = ConsoleLine.lines(log, filter: filter, analyzer: analyzer)
        #expect(filtered.map(\.tint) == [.cw, .filtered, .digi, .plain, .filtered])
        #expect(filtered.map(\.text) == log)
    }
}

/// N1MM's queries about one station and the session's spot history.
@Suite struct ClusterCallQueryTests {

    @Test func queriesAreFormattedForTheNode() {
        #expect(ClusterCallQuery.lastSpots.command(call: "ok1abc", software: .dxSpider) == "SH/DX 10 OK1ABC")
        #expect(ClusterCallQuery.lastSpots.command(call: "OK1ABC", software: .arCluster) == "SH/DX/10 OK1ABC")
        #expect(ClusterCallQuery.station.command(call: "OK1ABC", software: .dxSpider) == "SH/STATION OK1ABC")
        #expect(ClusterCallQuery.qsl.command(call: "3B8/OK1ABC", software: .dxSpider) == "SH/QSL 3B8/OK1ABC")
        #expect(ClusterCallQuery.sun.command(call: "VK9X", software: .ccCluster) == "SH/SUN VK9X")
        #expect(ClusterCallQuery.qrz.command(call: "OK1ABC", software: .dxSpider) == "SH/QRZ OK1ABC")
        #expect(ClusterCallQuery.qrz.command(call: "OK1ABC BYE", software: .dxSpider) == nil)
        #expect(ClusterCallQuery.allCases.count == 5)
    }

    @Test func theHistoryKeepsTheNewestSpotsOfACall() {
        let history = SpotHistory(capacity: 3)
        let at = Date(timeIntervalSince1970: 1_000)
        history.add(DxSpot(spotter: "DL1XX", freqHz: 14_025_000, dxCall: "OK1ABC", comment: "CW"), at: at, source: "")
        history.add(DxSpot(spotter: "W3LPL", freqHz: 7_025_000, dxCall: "K1ABC", comment: ""), at: at, source: "RBN")
        history.add(DxSpot(spotter: "DL2XX", freqHz: 14_026_000, dxCall: "ok1abc", comment: ""), at: at, source: "RBN")
        #expect(history.entries(of: " OK1ABC ").map(\.spot.spotter) == ["DL1XX", "DL2XX"])
        #expect(history.entries(of: "OK1ABC").last?.source == "RBN")
        history.add(DxSpot(spotter: "DL3XX", freqHz: 14_027_000, dxCall: "OK1ABC", comment: ""), at: at, source: "")
        #expect(history.count == 3)
        #expect(history.entries(of: "OK1ABC").map(\.spot.spotter) == ["DL2XX", "DL3XX"])
        #expect(history.entries(of: "  ").isEmpty)
        history.clear()
        #expect(history.count == 0)
    }
}
