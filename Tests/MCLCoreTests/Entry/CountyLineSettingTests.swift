import Testing
@testable import MCLCore

/// COUNTYLINE / BONUS / ROVERQTH (`AS:3879-3943`); splits from probe `county`, `bonus`, `rover`.
@Suite struct CountyLineSettingTests {

    /// Probe `county`: `uppercase().split(Regex("[,;/\\s]+")).filter { isNotBlank }.distinct()`.
    @Test func countySplitAsMeasured() {
        let table: [(String, [String])] = [
            ("", []), (" ", []), ("a,b", ["A", "B"]), ("a, b;c/d e", ["A", "B", "C", "D", "E"]), ("a,,a", ["A"]),
            ("A\tB\nC", ["A", "B", "C"]), ("a\u{00A0}b", ["A\u{00A0}B"]), ("\u{00A0}", []), ("a/A", ["A"]),
            ("ß", ["SS"]), ("ı,i", ["I"]), ("a\u{2003}b", ["A\u{2003}B"]), (",x,", ["X"]), ("w1aw / w1aw", ["W1AW"]),
            ("a\u{000B}b\u{000C}c", ["A", "B", "C"]),
        ]
        for (input, counties) in table {
            let out = CountyLineSetting.apply(text: input, usesRoverQth: true) { _ in nil }
            #expect(out.counties == counties, "\(input)")
        }
    }

    /// Probe `bonus`: a slash stays inside a call.
    @Test func bonusSplitAsMeasured() {
        let table: [(String, [String])] = [
            ("", []), ("w1aw, k1a", ["W1AW", "K1A"]), ("a/b,c", ["A/B", "C"]), ("a;;b", ["A", "B"]),
            ("w1aw w1aw", ["W1AW"]), ("a\u{00A0}b", ["A\u{00A0}B"]),
        ]
        for (input, calls) in table {
            #expect(CountyLineSetting.bonusStations(input).calls == calls, "\(input)")
        }
        #expect(CountyLineSetting.bonusStations(" ").status == .tr("Bonusové stanice smazány"))
        #expect(CountyLineSetting.bonusStations("a b").status == .verbatim("Bonusové stanice (2): A B"))
    }

    /// Probe `rover`: Kotlin `trim` at the ends (NBSP too), ASCII `\s+` removed inside.
    @Test func roverAsMeasured() {
        let table: [(String, String)] = [
            ("", ""), (" ny ", "NY"), ("n y", "NY"), ("n\u{00A0}y", "N\u{00A0}Y"), ("a\tb", "AB"), ("ß", "SS"),
            ("\u{00A0}ny\u{00A0}", "NY"),
        ]
        for (input, output) in table {
            #expect(CountyLineSetting.roverQth(input) == output, "\(input)")
        }
    }

    @Test func roverStatuses() {
        #expect(CountyLineSetting.roverQthStatus("", usesRoverQth: true, isKnownLocation: nil)
                == .tr("Rover QTH smazáno"))
        #expect(CountyLineSetting.roverQthStatus("NY", usesRoverQth: false, isKnownLocation: false).czech
                == "Rover QTH: NY (závod okres ve výměně nemá — jen pro makro {ROVERQTH})")
        #expect(CountyLineSetting.roverQthStatus("NY", usesRoverQth: true, isKnownLocation: false).czech
                == "Rover QTH: NY — pozor: NY není v seznamu okresů závodu")
        #expect(CountyLineSetting.roverQthStatus("NY", usesRoverQth: true, isKnownLocation: nil).czech
                == "Rover QTH: NY")
    }

    /// The three county-line texts (`AS:3931-3939`).
    @Test func countyLineStatuses() {
        #expect(CountyLineSetting.off().status == .verbatim("County line vypnuto"))
        #expect(CountyLineSetting.off().counties.isEmpty)
        let notUsed = CountyLineSetting.apply(text: "a,b", usesRoverQth: false) { _ in false }
        #expect(notUsed.status == .tr("County line %s — pozor: závod okres ve výměně nemá, QSO se zapíše jen jednou",
                                      "A/B"))
        let used = CountyLineSetting.apply(text: "a,b,c", usesRoverQth: true) { $0 == "A" ? true : ($0 == "B" ? false : nil) }
        #expect(used.status.czech == "County line A/B/C: každé QSO se zapíše 3× — pozor, není v seznamu okresů: B")
        let known = CountyLineSetting.apply(text: "a", usesRoverQth: true) { _ in true }
        #expect(known.status == .tr("County line %s: každé QSO se zapíše %s×", "A", 1))
    }
}
