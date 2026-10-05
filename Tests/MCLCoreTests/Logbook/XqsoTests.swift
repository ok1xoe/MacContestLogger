import Foundation
import Testing
@testable import MCLCore

/// Port of `XqsoTest.java` — X-QSO (`Qso.xqso`, Cabrillo `X-QSO:`): in the log, but
/// not counted towards the score. **Not the same as a tombstone (`Qso.deleted`)** — that removes the QSO
/// completely from the network and from `findAll()`, `xqso` only excludes it from the score and it stays
/// visible.
///
/// Java has three tests: `xqsoAndNoteArePersisted` (repository round-trip) and two
/// covering the cluster sync wire — `xqsoTravelsOverTheWire`
/// and `oldJsonWithoutFlagMeansCounted` (`WireMapper`, `QsoWire`/`QsoState`, `WireJson`).
@Suite struct XqsoTests {

    private func qso(_ x: Bool) -> Qso {
        var q = Qso()
        q.call = "DL1ABC"
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-11-28T12:00:00Z")
        q.freqHz = 14_025_000
        q.mode = .cw
        q.comment = "zkontrolovat zónu"
        q.xqso = x
        return q
    }

    // MARK: - `XqsoTest.xqsoAndNoteArePersisted`

    @Test func xqsoAndNoteArePersisted() throws {
        let repo = try LogbookRepository.inMemory()
        var q = qso(true)
        _ = try repo.insert(&q)
        var back = try repo.findAllIncludingDeleted()[0]
        #expect(back.xqso == true)
        #expect(back.comment == "zkontrolovat zónu")

        back.xqso = false
        try repo.update(back)
        #expect(try repo.findAllIncludingDeleted()[0].xqso == false)
    }

    // MARK: - `XqsoTest.xqsoTravelsOverTheWire`

    @Test func xqsoTravelsOverTheWire() {
        let wire: QsoWire = WireMapper.toWire(qso(true))
        let state = QsoState(uuid: "u1", stationId: "st1", version: 1, updatedAtUtc: JavaInstant.now(), deleted: false,
                             qso: wire)

        #expect(WireMapper.toQso(state).xqso)
        #expect(!WireMapper.toQso(QsoState(uuid: "u2", stationId: "st1", version: 1, updatedAtUtc: JavaInstant.now(),
                                           deleted: false, qso: WireMapper.toWire(qso(false)))).xqso)
    }

    // MARK: - `XqsoTest.oldJsonWithoutFlagMeansCounted`

    @Test func oldJsonWithoutFlagMeansCounted() throws {
        let old = QsoWire(timestampUtc: JavaInstant.parseIsoInstant("2026-11-28T12:00:00Z"), call: "DL1ABC",
                          freqHz: 14_025_000, band: "M20", mode: "CW", rstSent: "599", rstRcvd: "599", exchangeSent: nil,
                          exchangeRcvd: "599 14", serialSent: 1, serialRcvd: nil, operator: nil, comment: nil,
                          dxccEntity: nil, dxccName: nil, continent: nil)
        let json: String = WireJson.toJson(old)

        let stripped: String = json.replacingOccurrences(of: ",\"xqso\":null", with: "")
        let back = try #require(try WireJson.fromBytes(Array(stripped.utf8), as: QsoWire.self))

        #expect(back.xqso == nil)
        #expect(!WireMapper.toQso(QsoState(uuid: "u", stationId: "s", version: 1, updatedAtUtc: JavaInstant.now(),
                                           deleted: false, qso: back)).xqso)
    }

    // MARK: - New test without a Java ancestor: `deleted`/`xqso` must not be confused

    /// `xqso=true` is still an active QSO — `findAll()` shows it (it just does not count towards
    /// the score); `deleted=true` is a tombstone and `findAll()` hides it. Independent fields.
    @Test func xqsoDoesNotHideFromFindAllUnlikeDeleted() throws {
        let repo = try LogbookRepository.inMemory()
        var xqso = qso(true)
        _ = try repo.insert(&xqso)

        var tomb = qso(false)
        tomb.call = "W1AW"
        tomb.deleted = true
        _ = try repo.insert(&tomb)

        let active = try repo.findAll()
        #expect(active.count == 1) // xqso is still active, the tombstone is not
        #expect(active[0].call == "DL1ABC")
        #expect(active[0].xqso == true)
        #expect(active[0].deleted == false)
    }
}
