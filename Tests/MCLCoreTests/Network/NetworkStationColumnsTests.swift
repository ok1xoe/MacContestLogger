import Foundation
import Testing
@testable import MCLCore

/// N1MM Network Status → Stations: the chosen and ordered columns, the rates and the last QSO from the shared log,
/// the pass frequency, and the Run1/Run2 type a numbered RUN station announces.
@Suite struct NetworkStationColumnsTests {

    @Test func savedColumnsResolveWithTheStationFirstAndUnknownNamesDropped() {
        #expect(NetworkStationColumn.resolve([]) == NetworkStationColumn.defaultOrder)
        #expect(NetworkStationColumn.resolve(["rate10", "bogus", "band", "rate10"]) == [.station, .rate10, .band])
        #expect(NetworkStationColumn.resolve(["band", "station"]) == [.station, .band])
        #expect(NetworkStationColumn.resolve(["bogus"]) == NetworkStationColumn.defaultOrder)
    }

    @Test func toggledColumnsKeepTheDefaultPlaceAndTheStation() {
        let few: [NetworkStationColumn] = [.station, .band, .state]
        #expect(NetworkStationColumn.toggled(few, .band) == [.station, .state])
        #expect(NetworkStationColumn.toggled(few, .rate10) == [.station, .band, .rate10, .state])
        #expect(NetworkStationColumn.toggled(few, .operator) == [.station, .operator, .band, .state])
        #expect(NetworkStationColumn.toggled(few, .station) == few)
    }

    @Test func movedColumnsStayBehindTheStation() {
        let cols: [NetworkStationColumn] = [.station, .band, .mode, .state]
        #expect(NetworkStationColumn.moved(cols, .mode, by: -1) == [.station, .mode, .band, .state])
        #expect(NetworkStationColumn.moved(cols, .band, by: -1) == cols)
        #expect(NetworkStationColumn.moved(cols, .state, by: 1) == cols)
        #expect(NetworkStationColumn.moved(cols, .station, by: 1) == cols)
        #expect(NetworkStationColumn.moved(cols, .rate10, by: 1) == cols)
    }

    static func qso(_ call: String, _ station: String, _ minute: Int, deleted: Bool = false) -> Qso {
        var q = Qso()
        q.call = call
        q.band = .m20
        q.stationId = station
        q.deleted = deleted
        q.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000 + Double(minute) * 60)
        return q
    }

    @Test func extrasCountRatesAndTheLastQsoPerStation() {
        // OP2: 11 QSOs one every 6 minutes = 10 per hour; OP3 one QSO; a deleted one and one without origin skipped.
        var qsos: [Qso] = (0...10).map { Self.qso("K\($0)AA", "OP2", $0 * 6) }
        qsos.append(Self.qso("DL1ABC", "OP3", 3))
        qsos.append(Self.qso("DL9ZZZ", "OP3", 90, deleted: true))
        qsos.append(Self.qso("OK1XYZ", "", 95))
        let extras = NetworkStationExtras.compute(qsos, passFrequencies: ["OP3": 7_012_500, "OP9": 0])
        #expect(extras["OP2"]?.rate10 == 10)
        #expect(extras["OP2"]?.rate100 == 10)
        #expect(extras["OP2"]?.lastQso.hasPrefix("K10AA ") == true)
        #expect(extras["OP3"] == NetworkStationExtras(rate10: 0, rate100: 0,
                                                       lastQso: "DL1ABC " + MacroTime.format(qsos[11].timestampUtc!, "HHmm"),
                                                       passHz: 7_012_500))
        #expect(extras["OP9"] == nil)
        #expect(extras[""] == nil)
    }

    @Test func cellsOfTheNewColumns() {
        var peer = NetworkSendTests.peers(op2: true, op3: false, op4: false, op5: false)[0]
        let extras = NetworkStationExtras(rate10: 120, rate100: 85, lastQso: "DL1ABC 1234", passHz: 14_123_500)
        let row = NetworkStationColumn.defaultOrder.map { NetTexts.cell($0, peer, extras: extras, translator: .source) }
        #expect(row == ["OP2", "Tom", "", "20m", "CW", "14025.0", "RUN", "14123.5", "10", "120", "85", "DL1ABC 1234",
                        "online"])
        let none = NetTexts.cell(.pass, peer, extras: NetworkStationExtras(), translator: .source)
        #expect(none == "")
        var status = peer.status
        status.stationType = "RUN2"
        peer = StationNetwork.Peer(status: status, receivedAt: peer.receivedAt, online: peer.online, age: peer.age)
        #expect(NetTexts.cell(.type, peer, extras: extras, translator: .source) == "RUN2")
        // The old eight cells are the same as v1.1.1's.
        let old: [NetworkStationColumn] = [.station, .operator, .band, .mode, .freq, .runMode, .qsos, .state]
        #expect(old.map { NetTexts.cell($0, peer, extras: extras, translator: .source) }
            == NetTexts.peerCells(peer, translator: .source))
    }

    @Test func aNumberedRunStationAnnouncesRun1OrRun2() {
        var cluster = ClusterConfig()
        #expect(cluster.announcedStationType == "")
        cluster.stationType = .run
        #expect(cluster.announcedStationType == "RUN")
        cluster.runNumber = 2
        #expect(cluster.announcedStationType == "RUN2")
        cluster.runNumber = 7
        #expect(cluster.announcedStationType == "RUN")
        cluster.runNumber = 1
        cluster.stationType = .mult
        #expect(cluster.announcedStationType == "MULT")
        let status = StationStatusBuilder.status(stationId: "OP1", operatorCall: "OK1XOE", stationType: .run,
                                                 catFreqHz: 14_000_000, catMode: .cw, tunedFreqHz: 0, runMode: .run,
                                                 qsoCount: 1, sending: false, typedCall: "", runNumber: 1)
        #expect(status.stationType == "RUN1")
    }
}
