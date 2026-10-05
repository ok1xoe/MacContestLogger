import Testing
@testable import MCLCore

@Suite struct QsoTests {
    @Test func settingFrequencyDerivesBand() {
        var qso = Qso()
        qso.freqHz = 21_205_000
        #expect(qso.band == .m15)
    }

    @Test func frequencyOutsideHamBandsKeepsPreviousBand() {
        var qso = Qso()
        qso.freqHz = 21_205_000
        qso.freqHz = 100_000
        #expect(qso.band == .m15)
    }

    @Test func callIsTrimmedAndUppercased() {
        var qso = Qso()
        qso.call = "  ok1xoe "
        #expect(qso.call == "OK1XOE")
    }

    /// The callsign trim is Java `trim()`, not Swift `.whitespacesAndNewlines`.
    /// All values are measured on Java v1.1.1 (`Qso.setCall`).
    @Test func callIsTrimmedWithJavaTrim() {
        func normalized(_ input: String) -> String {
            var q = Qso()
            q.call = input
            return q.call
        }
        // Non-breaking spaces are NOT dropped by `trim()` — the callsign then stays
        // untranslatable and the QSO correctly goes out without a country.
        #expect(normalized("\u{00A0}OK1XOE") == "\u{00A0}OK1XOE")
        #expect(normalized("OK1XOE\u{00A0}") == "OK1XOE\u{00A0}")
        #expect(normalized("\u{2007}OK1XOE") == "\u{2007}OK1XOE")
        #expect(normalized("\u{202F}OK1XOE") == "\u{202F}OK1XOE")
        #expect(normalized("\u{00A0}") == "\u{00A0}")
        // Other Unicode separators are not dropped by `trim()` either (they are > U+0020).
        #expect(normalized("\u{2000}OK1XOE") == "\u{2000}OK1XOE")
        // Control characters, on the contrary, MUST be dropped — `trim()` takes everything ≤ U+0020,
        // otherwise a callsign with a control character would be stored in the log.
        #expect(normalized("\u{0001}OK1XOE") == "OK1XOE")
        #expect(normalized("OK1XOE\u{0001}") == "OK1XOE")
        #expect(normalized("\u{0001}\u{0002} ok1xoe \u{001F}") == "OK1XOE")
        #expect(normalized("\u{0001}").isEmpty)
        #expect(normalized("\tOK1XOE\n") == "OK1XOE")
        #expect(normalized("\u{000B}OK1XOE\u{000C}") == "OK1XOE")
    }

    @Test func emptyStationHasBlankFields() {
        #expect(Station.empty.call.isEmpty)
        #expect(Station.empty.name.isEmpty)
    }
}
