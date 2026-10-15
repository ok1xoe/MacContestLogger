import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// The entry window's free-form exchange box (N1MM Sweepstakes) and the received county line (N1MM 7QP).
@MainActor @Suite struct FreeFormExchangeTests {

    static let sweepstakes = """
        schemaVersion: 1
        id: test-ss
        metadata: { name: "Test SS" }
        bands: [80m, 40m, 20m]
        modes: [CW]
        exchange:
          freeForm: true
          sent:
            - { id: nr,   type: SERIAL, source: AUTO_SERIAL }
          received:
            - { id: nr,   type: SERIAL, required: true }
            - { id: prec, type: TEXT,   required: true, validation: { regex: "^[QABUMS]$" } }
            - { id: ck,   type: TEXT,   required: true, validation: { regex: "^[0-9]{2}$" } }
            - { id: sec,  type: TEXT,   required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 2 }
          total: "qsoPoints"
        dupe: { scope: ONCE }
        """

    static let countyParty = """
        schemaVersion: 1
        id: test-7qp
        metadata: { name: "Test 7QP" }
        bands: [40m, 20m]
        modes: [CW]
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst,  type: RST,  required: true }
            - { id: cnty, type: TEXT, required: true, split: true, validation: { regex: "^[A-Z]{5}$" } }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        dupe: { scope: PER_BAND_MODE }
        """

    @Test func oneBoxFillsTheFieldsAndACallInItIsLogged() async throws {
        let app = try await PortedApp.make(contests: ["test-ss": Self.sweepstakes])
        try await app.start("test-ss")
        #expect(app.entry.freeFormExchange)
        #expect(app.entry.focusFields.map(\.id) == [ExchangeFreeForm.boxId])
        app.entry.setFrequency("7030")
        app.entry.callChanged("K1ABD")
        app.entry.editContestField(ExchangeFreeForm.boxId, "123a k1abc 72oh")
        #expect(app.entry.form.contestExchange["nr"] == "123")
        #expect(app.entry.form.contestExchange["sec"] == "OH")
        #expect(app.entry.freeFormText == "123A K1ABC 72OH")
        #expect(app.entry.freeFormPreview == "nr 123 · prec A · ck 72 · sec OH · call K1ABC")
        #expect(app.entry.contestReady)
        app.entry.submit()
        await app.settle()
        let row = try #require(app.model.logbook.rows.last)
        #expect(row.call == "K1ABC")
        #expect(row.exchangeRcvd == "123 A 72 OH")
        #expect(app.entry.freeFormText == "")
    }

    @Test func valuesFilledElsewhereShowInTheBox() async throws {
        let app = try await PortedApp.make(contests: ["test-ss": Self.sweepstakes])
        try await app.start("test-ss")
        app.entry.editContestField(ExchangeFreeForm.boxId, "5 B")
        app.entry.form.contestExchange.put("sec", "WMA")
        #expect(app.entry.freeFormText == "5 B WMA")
    }

    @Test func aCountyLineExchangeLogsOneQsoPerCounty() async throws {
        let app = try await PortedApp.make(contests: ["test-7qp": Self.countyParty])
        try await app.start("test-7qp")
        app.entry.setFrequency("14030")
        app.entry.callChanged("W7XYZ")
        app.entry.editContestField("cnty", "ordes/jef")
        #expect(app.entry.contestReady)
        app.entry.submit()
        await app.settle()
        #expect(app.model.logbook.rows.map(\.exchangeRcvd) == ["599 ORDES", "599 ORJEF"])
        #expect(app.model.logbook.rows.map(\.call) == ["W7XYZ", "W7XYZ"])
    }
}
