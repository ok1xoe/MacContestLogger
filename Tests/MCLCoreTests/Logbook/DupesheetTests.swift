import Testing
@testable import MCLCore

/// Port of Java `DupesheetTest` (3 cases). Edge cases (X-QSO, Unicode digits, UTF-16
/// ordering, all scopes) are in `LogbookMeasuredTests`.
@Suite struct DupesheetTests {

    static func qso(_ call: String, _ hz: Int, _ mode: Mode) -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = hz
        q.mode = mode
        return q
    }

    let log: [Qso] = [
        qso("OK1XOE", 14_010_000, .cw),
        qso("ok1abc", 14_020_000, .cw),
        qso("DL/OK1XOE", 14_030_000, .cw), // same area 1, different callsign
        qso("W2XX", 14_200_000, .ssb),
        qso("OK1XOE", 14_040_000, .cw),     // the duplicate is not repeated
        qso("DL5ABC", 7_010_000, .cw),
    ]

    @Test func perBandGroupsByAreaDigit() {
        let s = Dupesheet.build(log, band: "20m", mode: "CW", scope: .PER_BAND)
        #expect(s["1"] == ["DL/OK1XOE", "OK1ABC", "OK1XOE"])
        #expect(s["2"] == ["W2XX"], "PER_BAND = another mode too")
        #expect(s["5"] == nil, "different band")
    }

    @Test func perBandModeAndOnce() {
        #expect(Dupesheet.build(log, band: "20m", mode: "CW", scope: .PER_BAND_MODE)["2"] == nil)
        #expect(Dupesheet.build(log, band: "20m", mode: "CW", scope: .ONCE)["5"] == ["DL5ABC"])
    }

    @Test func areaDigit() {
        #expect(Dupesheet.areaDigit("OK1XOE/P") == "1")
        #expect(Dupesheet.areaDigit("VP2E/K7ABC") == "7")
        #expect(Dupesheet.areaDigit("RAEM") == Dupesheet.noDigit)
    }

    /// Decision 9: X-QSO stays in the Dupesheet (as in Java), a deleted QSO does not.
    @Test func xqsoStaysDeletedGoes() {
        var x = Self.qso("OK2XQ", 14_010_000, .cw)
        x.xqso = true
        var d = Self.qso("OK3DEL", 14_010_000, .cw)
        d.deleted = true
        let s = Dupesheet.build([x, d], band: "20m", mode: "CW", scope: nil)
        #expect(s.columns.map(\.key) == ["2"])
        #expect(s["2"] == ["OK2XQ"])
        #expect(s["3"] == nil)
    }

    /// Columns and callsigns in UTF-16 order: `#` (0x23) before `0`, KELVIN SIGN separately from `K`.
    @Test func columnsAndCallsSortByUtf16() {
        let s = Dupesheet.build([Self.qso("\u{212A}1ABC", 14_010_000, .cw), Self.qso("K1ABC", 14_010_000, .cw),
                                 Self.qso("RAEM", 14_010_000, .cw), Self.qso("OK\u{0661}A", 14_010_000, .cw)],
                                band: nil, mode: nil, scope: .ONCE)
        #expect(s.columns.map(\.key) == ["#", "1", "\u{0661}"])
        #expect(s["1"] == ["K1ABC", "\u{212A}1ABC"])
        #expect(s["\u{212A}"] == nil)
    }
}

/// The Swift-only suffix order (N1MM Visible Dupesheet: "each call area is sorted by suffix").
@Suite struct DupesheetSuffixOrderTests {

    static func qso(_ call: String) -> Qso {
        DupesheetTests.qso(call, 14_010_000, .cw)
    }

    @Test func suffixIsWhatFollowsTheLastDigitOfTheBaseCall() {
        #expect(Dupesheet.suffix("OK1XOE") == "XOE")
        #expect(Dupesheet.suffix("DL/OK1XOE/P") == "XOE")
        #expect(Dupesheet.suffix("3DA0RU") == "RU")
        #expect(Dupesheet.suffix("S50A") == "A")
        #expect(Dupesheet.suffix("RAEM") == "RAEM", "no digit: the whole call")
        #expect(Dupesheet.suffix("OK1") == "")
    }

    @Test func eachColumnIsSortedBySuffixThenByCall() {
        let log: [Qso] = ["DL1ZZ", "OK1ABC", "W1AW", "DK1ZZ", "OK1XOE", "K2AA", "RAEM", "G0AAA"].map(Self.qso)
        let sheet = Dupesheet.build(log, band: "20m", mode: "CW", scope: .PER_BAND, order: .suffix)
        #expect(sheet["1"] == ["OK1ABC", "W1AW", "OK1XOE", "DK1ZZ", "DL1ZZ"])
        #expect(sheet["2"] == ["K2AA"])
        #expect(sheet["0"] == ["G0AAA"])
        #expect(sheet["#"] == ["RAEM"])
        #expect(sheet.columns.map(\.key) == ["#", "0", "1", "2"], "the columns keep their order")
    }

    @Test func theDefaultOrderIsStillTheWholeCall() {
        let log: [Qso] = ["DL1ZZ", "OK1ABC", "DK1ZZ"].map(Self.qso)
        #expect(Dupesheet.build(log, band: nil, mode: nil, scope: .ONCE)["1"] == ["DK1ZZ", "DL1ZZ", "OK1ABC"])
        #expect(Dupesheet.build(log, band: nil, mode: nil, scope: .ONCE, order: .call)["1"]
                == ["DK1ZZ", "DL1ZZ", "OK1ABC"])
    }

    @Test func theViewPassesTheOrderOn() {
        let log: [Qso] = ["DL1ZZ", "OK1ABC"].map(Self.qso)
        let byCall = StatsViews.dupesheet(qsos: log, scope: nil, band: "20m", mode: "CW", typedCall: "")
        let bySuffix = StatsViews.dupesheet(qsos: log, scope: nil, band: "20m", mode: "CW", typedCall: "",
                                            order: .suffix)
        #expect(byCall.columns.first { $0.digit == "1" }?.calls.map(\.text) == ["DL1ZZ", "OK1ABC"])
        #expect(bySuffix.columns.first { $0.digit == "1" }?.calls.map(\.text) == ["OK1ABC", "DL1ZZ"])
    }
}
