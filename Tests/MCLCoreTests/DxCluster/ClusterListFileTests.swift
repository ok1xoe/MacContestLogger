import Foundation
import Testing
@testable import MCLCore

/// The cluster list file, the randomized spot frequency and the spots saved across a restart.
@Suite struct ClusterListFileTests {

    static let node = DxClusterFavorite(name: "OK0DXH", host: "ok0dxh.example", port: 41112, login: "OK1XOE",
                                        password: "secret")
    static let rbn = DxClusterFavorite(name: "RBN, CW", host: "telnet.rbn.example", port: 7000, login: "",
                                       password: "")

    @Test func theListIsWrittenWithoutPasswords() {
        let text: String = ClusterListFile.encode([Self.node, Self.rbn])
        #expect(text == ClusterListFile.header + "\nOK0DXH,ok0dxh.example:41112,OK1XOE\nRBN  CW,telnet.rbn.example:7000\n")
        #expect(!text.contains("secret"))
        let back: [DxClusterFavorite] = ClusterListFile.decode(text)
        #expect(back.map(\.name) == ["OK0DXH", "RBN  CW"])
        #expect(back[0].login == "OK1XOE" && back[0].password == "" && back[0].port == 41112)
        #expect(back[1].host == "telnet.rbn.example")
    }

    @Test func badLinesAreSkipped() {
        let text = "# comment\r\nno port,host\nbad,host:0\nempty,:23\nok,host.example:23\r\n"
        #expect(ClusterListFile.decode(text).map(\.name) == ["ok"])
    }

    @Test func importAddsOnlyNewServers() {
        var config = AppConfig()
        config.dxCluster.favorites = [Self.node]
        var draft = ConfigurerDraft(config: config, bandSegments: [], digi: DigiFreqFile.Table(channels: []),
                                    defaultContestDataDir: "")
        let added: Int = draft.importDxFavorites("Same,OK0DXH.example:41112\nRBN,telnet.rbn.example:7000\nAgain,telnet.rbn.example:7000\n")
        #expect(added == 1)
        #expect(draft.dxFavorites.map { $0.name } == ["OK0DXH", "RBN"])
        #expect(draft.dxFavoritesFileText.contains("RBN,telnet.rbn.example:7000"))
    }

    @Test func theJitterIsNeverZeroAndStaysInItsRange() {
        #expect(SpotFrequencyJitter.offsetHz(phone: false, draw: { $0 == 0...1 ? 0 : $0.lowerBound }) == -50)
        #expect(SpotFrequencyJitter.offsetHz(phone: false, draw: { $0 == 0...1 ? 1 : $0.upperBound }) == 150)
        #expect(SpotFrequencyJitter.offsetHz(phone: true, draw: { $0 == 0...1 ? 1 : $0.upperBound }) == 250)
        #expect(SpotFrequencyJitter.offsetHz(phone: true, draw: { $0 == 0...1 ? 0 : 0 }) == -100)
        for _ in 0..<200 {
            let cw: Int = SpotFrequencyJitter.offsetHz(phone: false, draw: { Int.random(in: $0) })
            #expect(SpotFrequencyJitter.cwRange.contains(abs(cw)))
        }
    }

    @Test func theBufferExportsAndRestoresItsEntries() throws {
        let clock = MutableDate(Date(timeIntervalSince1970: 1_000_000))
        let buffer = SpotBuffer(maxAgeMinutes: 60, clock: { clock.value })
        buffer.add(DxSpot(spotter: "DL1XX", freqHz: 14_025_000, dxCall: "OK1ABC", comment: "CW"))
        buffer.add(DxSpot(spotter: "DL1XX", freqHz: 14_025_000, dxCall: "OK1ABC", comment: "again"))
        clock.value = clock.value.addingTimeInterval(60)
        buffer.add(DxSpot(spotter: "DK0SK-#", freqHz: 14_030_000, dxCall: "W1AW", comment: "CW 20 dB 25 WPM CQ"))
        buffer.add(DxSpot(spotter: "DL2YY-#", freqHz: 14_030_100, dxCall: "W1AW", comment: "CW 18 dB 25 WPM CQ"))
        let saved: [SpotBuffer.Stored] = buffer.exportEntries()
        #expect(saved.map(\.dxCall) == ["OK1ABC", "W1AW"])
        #expect(saved[0].count == 2 && saved[1].skimmers == ["DK0SK-#", "DL2YY-#"])
        let data: Data = try SavedSpotsFile.encode(saved)
        #expect(SavedSpotsFile.decode(data) == saved)
        #expect(SavedSpotsFile.decode(Data("nonsense".utf8)) == nil)

        // 60.5 minutes after OK1ABC, in a new buffer: the original times stay, OK1ABC's spot is too old.
        clock.value = clock.value.addingTimeInterval(60 * 59 + 30)
        let fresh = SpotBuffer(maxAgeMinutes: 60, clock: { clock.value })
        fresh.add(DxSpot(spotter: "DL1XX", freqHz: 7_010_000, dxCall: "K1ABC", comment: ""))
        #expect(fresh.importEntries(saved) == 1)
        #expect(fresh.snapshot().map(\.dxCall) == ["K1ABC", "W1AW"])
        #expect(fresh.skimmerCount("W1AW") == 2)
        #expect(fresh.find("W1AW")?.spottedAt == Date(timeIntervalSince1970: 1_000_060))
        #expect(fresh.importEntries(saved) == 0)
        let blocked = SpotBuffer(maxAgeMinutes: 600, clock: { clock.value })
        blocked.setBlacklist(calls: ["W1AW"], spotters: [])
        #expect(blocked.importEntries(saved) == 1)
        #expect(blocked.snapshot().map(\.dxCall) == ["OK1ABC"])
    }
}

/// A settable clock value for the buffer tests.
final class MutableDate: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var value: Date {
        get { lock.withLock { date } }
        set { lock.withLock { date = newValue } }
    }
}
