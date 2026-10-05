import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Move Multipliers window (`MoveMultipliersWindow.kt`, `AS:1621-1642`): the candidate rows, "QSY?" (CW sends
/// `PSE QSY` through the keyer, any other mode only hints) and "→" (retune). Only a button press sends or tunes.
/// The key is a recording Winkeyer, the rig is not connected.
@MainActor @Suite struct MoveMultsModelTests {

    private static func make() async throws -> KeyingApp {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwKeyer.speed = 30
        })
        app.entry.setMode(.cw)
        return app
    }

    private static func qso(_ call: String, mode: Mode) -> Qso {
        var qso = Qso()
        qso.call = call
        qso.mode = mode
        qso.band = .m20
        return qso
    }

    private static func sent(_ app: KeyingApp) -> [String] {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }
    }

    @Test func outsideAContestTheWindowIsEmpty() async throws {
        let app = try await Self.make()
        #expect(!app.model.moveMults.isContestActive)
        #expect(app.model.moveMults.rows.isEmpty)
    }

    /// The latest QSOs with at least one candidate band are listed, newest first; reading them sends nothing.
    @Test func aWorkedStationHasCandidateBandsAndNothingIsSentByItself() async throws {
        let app = try await Self.make()
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "DL1ABC", zone: "14")
        await app.settle()
        let moves: MoveMultsModel = app.model.moveMults
        #expect(moves.isContestActive)
        let rows: [MoveMultsModel.Row] = moves.rows
        #expect(rows.count == 1)
        let row: MoveMultsModel.Row = try #require(rows.first)
        #expect(row.qso.call == "DL1ABC")
        #expect(!row.candidates.isEmpty)
        #expect(!row.candidates.contains { $0.band == "20m" })
        // Neither listing the rows nor logging sent or tuned anything.
        #expect(app.keying.openedKeyers.isEmpty)
        #expect(app.keying.events.isEmpty)
    }

    /// CW: `PSE QSY <kHz>` to the station through the keyer; without a frequency on the band, the upper-cased band.
    @Test func cwRequestSendsPseQsyThroughTheKeyer() async throws {
        let app = try await Self.make()
        let moves: MoveMultsModel = app.model.moveMults
        moves.request(Self.qso("DL1ABC", mode: .cw), band: "40m")
        await app.settle()
        #expect(app.status == "DL1ABC: odesláno PSE QSY 40M")
        #expect(Self.sent(app) == ["send PSE QSY 40M@30"])

        // With my CQ frequency on the band: its kHz, `%.0f`.
        app.model.operating.onCqSent(7_025_000)
        moves.request(Self.qso("OK2XYZ", mode: .cw), band: "40m")
        await app.settle()
        #expect(app.status == "OK2XYZ: odesláno PSE QSY 7025")
        #expect(Self.sent(app).last == "send PSE QSY 7025@30")
    }

    /// Any other mode: a hint only — nothing is sent, the keyer is not even opened.
    @Test func aPhoneRequestOnlyHints() async throws {
        let app = try await Self.make()
        let moves: MoveMultsModel = app.model.moveMults
        moves.request(Self.qso("DL1ABC", mode: .ssb), band: "40m")
        await app.settle()
        #expect(app.status == "DL1ABC: požádej o QSY na 40m (nový násobič)")
        app.model.operating.onCqSent(7_074_500)
        moves.request(Self.qso("DL1ABC", mode: .ssb), band: "40m")
        #expect(app.status == "DL1ABC: požádej o QSY na \(CatStatusLine.khz(7_074_500)) (nový násobič)")
        #expect(app.keying.openedKeyers.isEmpty)
        #expect(app.keying.events.isEmpty)
    }

    @Test func anUnknownBandDoesNothing() async throws {
        let app = try await Self.make()
        app.model.status.showVerbatim("before")
        app.model.moveMults.request(Self.qso("DL1ABC", mode: .cw), band: "99m")
        await app.settle()
        #expect(app.status == "before")
        #expect(app.keying.openedKeyers.isEmpty)
    }

    /// "→": the rig is retuned to my CQ frequency / the last one on the band; without one the status says so.
    @Test func theArrowRetunesOrSaysThereIsNoFrequency() async throws {
        let app = try await Self.make()
        let moves: MoveMultsModel = app.model.moveMults
        moves.tune(band: "40m")
        #expect(app.status == "Na 40m ještě nemám frekvenci — přelaď ručně (Ctrl+PgUp/PgDn)")
        app.model.operating.onCqSent(7_025_000)
        moves.tune(band: "40m")
        #expect(app.model.rig.tuning.tunedFreqHz == 7_025_000)
        #expect(app.keying.openedKeyers.isEmpty)
    }
}
