import Foundation
import Testing
@testable import MCLCore

/// The `clublog` rows of `IntegrationsProbe.java` (the private `queueClubLog` of the Kotlin v1.1.1 with a
/// `ClubLogConfig` of each shape) and the sender's decisions from `AppState` — the queue loop is not callable
/// without the application, so its branches are pinned from the source.
@Suite struct ClubLogQueuePolicyTests {

    typealias F = IntegrationsFixture

    @Test func queueGateMatchesJvm() {
        let rows = F.rows("clublog")
        #expect(rows.count == 6)
        let configs: [(Bool, String, String, String, String)] = [
            (false, "a@b.cz", "pw", "OK1XOE", "key"), (true, "", "pw", "OK1XOE", "key"),
            (true, "a@b.cz", "pw", "", "key"), (true, "a@b.cz", "pw", "OK1XOE", "key"),
            (true, "a@b.cz", "", "OK1XOE", "key"), (true, "a@b.cz", "pw", "OK1XOE", ""),
        ]
        var qso = Qso()
        qso.call = "DL1ABC"
        qso.timestampUtc = Date(timeIntervalSince1970: 1_791_021_600)
        qso.freqHz = 14_025_000
        qso.mode = .cw
        for (row, config) in zip(rows, configs) {
            var cl = ClubLogConfig()
            cl.enabled = config.0
            cl.email = config.1
            cl.appPassword = config.2
            cl.callsign = config.3
            cl.apiKey = config.4
            let configured: Bool = cl.configured()
            let queued = ClubLogQueuePolicy.shouldQueue(configured: configured)
            #expect(String(configured) == row[2], "row \(row[1])")
            #expect(queued == (row[3] == "1"), "row \(row[1])")
            let record: String = queued ? F.escape(AdifWriter().record(qso)) : "-"
            #expect(record == row[4], "row \(row[1])")
            #expect(F.escape(Translator.source.translate(ClubLogQueuePolicy.idleStatus)) == row[5])
        }
    }

    @Test func okIsDoneAndCountsTheRemainingQueue() {
        let r = ClubLogQueuePolicy.handle(.OK, queued: 3)
        #expect(r.action == .done)
        #expect(r.status.czech == "Club Log: QSO odesláno (ve frontě 3)")
        #expect(ClubLogQueuePolicy.handle(.OK, queued: 0).status.czech == "Club Log: QSO odesláno (ve frontě 0)")
    }

    @Test func rejectedIsDroppedWithoutDelay() {
        let r = ClubLogQueuePolicy.handle(.REJECTED, queued: 5)
        #expect(r.action == .drop)
        #expect(r.status.czech == "Club Log odmítl QSO (přihlášení nebo data) — zkontroluj nastavení")
    }

    /// RETRY puts the record back at the front (so it is counted again) and waits a minute.
    @Test func retryPutsTheRecordBackAndWaitsAMinute() {
        let r = ClubLogQueuePolicy.handle(.RETRY, queued: 0)
        #expect(r.action == .retryFront(delayMs: 60_000))
        #expect(r.status.czech == "Club Log nedostupný — zkusím znovu (ve frontě 1)")
        #expect(ClubLogQueuePolicy.handle(.RETRY, queued: 4).status.czech == "Club Log nedostupný — zkusím znovu (ve frontě 5)")
        #expect(ClubLogQueuePolicy.retryDelayMs == 60_000)
        #expect(ClubLogQueuePolicy.pollSeconds == 5)
    }

    @Test func callsignFallsBackToTheStationWhenBlank() {
        #expect(ClubLogQueuePolicy.callsign(configured: "", stationCall: "OK1XOE") == "OK1XOE")
        #expect(ClubLogQueuePolicy.callsign(configured: " \u{00A0}", stationCall: "OK1XOE") == "OK1XOE")
        #expect(ClubLogQueuePolicy.callsign(configured: "OK1ABC", stationCall: "OK1XOE") == "OK1ABC")
    }
}
