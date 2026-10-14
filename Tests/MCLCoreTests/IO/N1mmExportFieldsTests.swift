import Foundation
import Testing
@testable import MCLCore

/// N1MM's ADIF fields (export and import), the text export sorted by band and the Cabrillo 3.0 categories
/// (Swift-only).
@Suite struct N1mmExportFieldsTests {

    private static func qso(_ call: String, _ band: Band, at seconds: TimeInterval, run: RunMode = .run) -> Qso {
        var q = Qso()
        q.call = call
        q.band = band
        q.freqHz = band.lowHz
        q.mode = .cw
        q.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000 + seconds)
        q.exchangeRcvd = " 15 "
        q.points = 3
        q.runMode = run
        q.uuid = "u-" + call
        return q
    }

    @Test func n1mmFieldsAreWrittenOnlyWhenAsked() {
        let q = Self.qso("W1AW", .m20, at: 0, run: .searchAndPounce)
        let plain = AdifWriter().record(q)
        #expect(!plain.contains("PFX"))
        #expect(!plain.contains("APP_N1MM_POINTS"))
        var writer = AdifWriter()
        writer.n1mmFields = true
        writer.multipliers = ["u-W1AW": ["5", "K", "W1", "extra"]]
        let full = writer.record(q)
        for field in ["<PFX:2>W1 ", "<APP_N1MM_EXCHANGE1:2>15 ", "<APP_N1MM_POINTS:1>3 ", "<APP_N1MM_ISRUNQSO:1>0 ",
                      "<APP_N1MM_MULT1:1>5 ", "<APP_N1MM_MULT2:1>K ", "<APP_N1MM_MULT3:2>W1 ",
                      "<APP_N1MM_RUNNING:1>N "] {
            #expect(full.contains(field), "\(field)")
        }
        #expect(!full.contains("APP_N1MM_MULT4"))
    }

    @Test func n1mmFieldsAreReadBack() throws {
        let adif = "<EOH><CALL:4>W1AW <QSO_DATE:8>20261001 <TIME_ON:4>1200 <BAND:3>20m <MODE:2>CW "
            + "<APP_N1MM_EXCHANGE1:5>15 MA <APP_N1MM_ISRUNQSO:1>0 <EOR>"
            + "<CALL:5>DL1AB <QSO_DATE:8>20261001 <TIME_ON:4>1201 <BAND:3>20m <MODE:2>CW "
            + "<SRX_STRING:2>14 <APP_N1MM_EXCHANGE1:2>99 <APP_N1MM_RUNNING:1>N <EOR>"
            + "<CALL:5>OK1AB <QSO_DATE:8>20261001 <TIME_ON:4>1202 <BAND:3>20m <MODE:2>CW <EOR>"
        let qsos: [Qso] = try AdifReader().read(adif)
        #expect(qsos.count == 3)
        #expect(qsos[0].exchangeRcvd == "15 MA")
        #expect(qsos[0].runMode == .searchAndPounce)
        #expect(qsos[1].exchangeRcvd == "14")
        #expect(qsos[1].runMode == .run)   // APP_N1MM_RUNNING is ignored on import (v1.1.1)
        #expect(qsos[2].runMode == .run)
    }

    @Test func textListingSortedByBand() {
        let qsos = [Self.qso("A", .m20, at: 0), Self.qso("B", .m40, at: 60), Self.qso("C", .m20, at: 120),
                    Self.qso("D", .m80, at: 180)]
        let text = LogExports.textByBand("T", qsos)
        let calls = ["A", "B", "C", "D"].map { call in text.range(of: " " + call + " ")!.lowerBound }
        // 80 m (D), 40 m (B), then 20 m in time order (A, C).
        #expect(calls[3] < calls[1] && calls[1] < calls[0] && calls[0] < calls[2])
        #expect(LogExports.text("T", qsos) != text)
    }

    @Test func cabrilloThreeCategoriesAreOffered() throws {
        let dims = CategoryCatalog.fixed()
        #expect(dims.first { $0.key == "TIME" }?.options.contains("8-HOURS") == true)
        let station = try #require(dims.first { $0.key == "STATION" })
        for value in ["DISTRIBUTED", "EXPLORER", "ROVER-LIMITED", "ROVER-UNLIMITED"] {
            #expect(station.options.contains(value))
        }
        let overlay = try #require(dims.first { $0.key == "OVERLAY" })
        #expect(overlay.options.contains("YL") && overlay.options.contains("YOUTH"))
    }
}
