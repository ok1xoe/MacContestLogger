import Foundation
import Testing
@testable import MCLCore

/// The info strip (`EP:1271-1307`): order, separator, texts. Items of other subsystems come from `nil` inputs; the full
/// input pins the order so they only fill them in.
@Suite struct InfoStripTests {

    @Test func emptyInputShowsNothing() {
        #expect(InfoStrip.extras(InfoStripInput()).isEmpty)
        #expect(InfoStrip.text([], .source) == "")
    }

    @Test func fullInputInKotlinOrder() throws {
        let tour = try #require(Tour.parse("1200/30"))
        let input = InfoStripInput(
            tour: tour, now: Date(timeIntervalSince1970: 13 * 3600 + 10 * 60), countyLine: ["NY", "AB"],
            roverQth: "XX", usesRoverQth: true, bonusStationCount: 3, cqRepeat: true, repeatSeconds: 2.25,
            recording: true, antennaName: "Yagi", clockOffsetMs: -2449, bandNote: "beacon", ritHz: 120, tuning: true,
            postContest: true, snsWaiting: true, stackedCalls: ["K1A", "W1AW"], sked: InfoStripSked(time: "1315Z", call: "DL1A"))
        let items = InfoStrip.extras(input)
        #expect(items.map(\.czech) == [
            "TOUR 1200/30 do 1330Z", "County line NY/AB", "Bonus 3", "RPT 2.3 s", "● REC", "ANT Yagi",
            "HODINY -2.4 s", "📝 beacon", "RIT +120", "LADĚNÍ", "DODATEČNÉ ZADÁNÍ", "SNS: čekám na číslo",
            "ZÁSOBNÍK K1A W1AW (Ctrl+Alt+K)", "SKED 1315Z DL1A",
        ])
        #expect(items[9] == ContestMessage("LADĚNÍ"))
        #expect(items[10] == ContestMessage("DODATEČNÉ ZADÁNÍ"))
        #expect(items[11] == ContestMessage("SNS: čekám na číslo"))
        #expect(items[12] == ContestMessage("ZÁSOBNÍK %s (Ctrl+Alt+K)", "K1A W1AW"))
        #expect(InfoStrip.text(Array(items.prefix(2)), .source) == " TOUR 1200/30 do 1330Z · County line NY/AB")
    }

    /// The local items alone (TOUR, county line / rover, bonus, RPT, post-contest, stack).
    @Test func roverOnlyWithoutCountyLineAndWhenTheContestUsesIt() {
        var input = InfoStripInput(roverQth: " ny", usesRoverQth: true)
        #expect(InfoStrip.extras(input).map(\.czech) == ["Rover  ny"])
        input.usesRoverQth = false
        #expect(InfoStrip.extras(input).isEmpty)
        input.usesRoverQth = true
        input.roverQth = "\u{00A0}"
        #expect(InfoStrip.extras(input).isEmpty)
    }

    /// Probe `clock` (`%+.1f`), probe `rpt` (`%.1f s`) and the RIT sign.
    @Test func numericFormats() {
        let clock: [(Int64, String)] = [
            (1001, "HODINY +1.0 s"), (-1001, "HODINY -1.0 s"), (1050, "HODINY +1.1 s"), (-2449, "HODINY -2.4 s"),
            (12345, "HODINY +12.3 s"), (-1500, "HODINY -1.5 s"),
        ]
        for (ms, text) in clock {
            #expect(InfoStrip.extras(InfoStripInput(clockOffsetMs: ms)).map(\.czech) == [text])
        }
        #expect(InfoStrip.extras(InfoStripInput(clockOffsetMs: 1000)).isEmpty)
        #expect(InfoStrip.extras(InfoStripInput(clockOffsetMs: -1000)).isEmpty)
        let rpt: [(Double, String)] = [(2.5, "2.5 s"), (1.8, "1.8 s"), (0.05, "0.1 s"), (2.25, "2.3 s"),
                                       (100.0, "100.0 s"), (1.0E-4, "0.0 s")]
        for (seconds, label) in rpt {
            #expect(EntryTexts.repeatLabel(seconds) == label)
        }
        #expect(InfoStrip.extras(InfoStripInput(ritHz: -50)).map(\.czech) == ["RIT -50"])
        #expect(InfoStrip.extras(InfoStripInput(ritHz: 0)).isEmpty)
    }

    /// Multiplier chip states (`EP:1888-1893`).
    @Test func shortStates() {
        #expect(EntryTexts.shortState(.knownNewMultiplier) == "NOVÝ")
        #expect(EntryTexts.shortState(.knownAlreadyWorked) == "už")
        #expect(EntryTexts.shortState(.unknownAccepted) == "neznámý")
        #expect(EntryTexts.shortState(.suspicious) == "podezřelý")
        #expect(EntryTexts.shortState(.invalidFormat) == "chybný")
    }

    /// The note key Kotlin really shows is spelt "Poznámka" and is translated by the shipped languages.
    @Test func entryTextKeysAreTranslated() {
        let en = LanguageCatalog.Translations(LanguageJsonReader.read(LanguageCatalog.bundledBytes("en") ?? []) ?? [:])
        for key in [EntryTexts.notePending, EntryTexts.noteTitleCurrent, EntryTexts.noteTitleLast, EntryTexts.noteHint,
                    EntryTexts.noteEmptyLog, EntryTexts.noteSaved, EntryTexts.forcedTitle, EntryTexts.forcedHint,
                    EntryTexts.paperTimeMissing, EntryTexts.unavailable] {
            #expect(en[key] != nil, "\(key)")
        }
        #expect(EntryTexts.forcedNote(" ") == "Forced QSO")
        #expect(EntryTexts.forcedNote("x") == "x")
    }
}
