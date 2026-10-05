import Foundation
import Testing
@testable import MCLCore

/// `NewContestForm` against the Kotlin `NewContestWindow.kt` (v1.1.1): the prefill read from the source,
/// `fmt` and `defaultFor` measured on the JVM (maintainer-only probe).
@Suite struct NewContestFormTests {

    static func definition(_ id: String) throws -> ContestDefinition {
        try SessionFixture.definition("@\(id).yaml")
    }

    /// 2026-10-02 13:45:12 UTC.
    static let now = Date(timeIntervalSince1970: 1_790_948_712)

    @Test func prefillWithoutSavedSetup() throws {
        let form = NewContestForm.prefill(definition: try Self.definition("iaru-hf"), saved: nil,
                                          stationCall: "OK1XOE", now: Self.now)
        #expect(form.category == [
            "OPERATOR": "SINGLE-OP", "POWER": "LOW", "OVERLAY": "N/A", "STATION": "FIXED",
            "ASSISTED": "NON-ASSISTED", "TRANSMITTER": "ONE", "TIME": "N/A", "BAND": "ALL", "MODE": "MIXED",
        ])
        #expect(form.sentExchange == ["exch": ""])
        #expect(form.operators == "OK1XOE")
        #expect(form.soapbox == "")
        #expect(form.startedAt == "2026-10-02 00:00")
        #expect(form.endedAt == "2026-10-03 00:00")
    }

    @Test func singleModeDefaultsToItsMode() throws {
        let form = NewContestForm.prefill(definition: try Self.definition("cq-ww-cw"), saved: nil,
                                          stationCall: "", now: Self.now)
        #expect(form.category["MODE"] == "CW")
        #expect(form.sentExchange == ["zone": ""])
        #expect(form.operators == "")
        #expect(form.endedAt == "2026-10-04 00:00")

        var noModes = try Self.definition("cq-ww-cw")
        noModes.modes = nil
        noModes.period = nil
        let bare = NewContestForm.prefill(definition: noModes, saved: nil, stationCall: "", now: Self.now)
        #expect(bare.category["MODE"] == "")
        #expect(bare.endedAt == "", "no duration → no end")
    }

    @Test func savedSetupWinsExceptBlankOperatorsAndTimes() throws {
        var saved = ContestSetup()
        saved.category = ["OPERATOR": "MULTI-OP", "POWER": "", "BAND": "20M", "MODE": "CW"]
        saved.sentExchange = ["exch": "28", "stale": "x"]
        saved.operators = "\u{00A0}"
        saved.soapbox = "73"
        saved.startedAt = " "
        saved.endedAt = "2026-07-12 12:00"
        saved.tour = "0000/60"
        let form = NewContestForm.prefill(definition: try Self.definition("iaru-hf"), saved: saved,
                                          stationCall: "OK1XOE", now: Self.now)
        #expect(form.category["OPERATOR"] == "MULTI-OP")
        #expect(form.category["POWER"] == "", "a stored empty value is kept")
        #expect(form.category["STATION"] == "FIXED")
        #expect(form.category["BAND"] == "20M")
        #expect(form.category["MODE"] == "CW")
        #expect(form.sentExchange == ["exch": "28"], "only the definition's sent fields")
        #expect(form.operators == "OK1XOE", "blank operators fall back to my callsign")
        #expect(form.soapbox == "73")
        #expect(form.startedAt == "2026-10-02 00:00")
        #expect(form.endedAt == "2026-07-12 12:00")

        let setup = form.setup()
        #expect(setup.category == form.category)
        #expect(setup.sentExchange == form.sentExchange)
        #expect(setup.startedAt == form.startedAt)
        #expect(setup.tour == "", "Kotlin builds a fresh ContestSetup: TOUR is dropped")
    }

    @Test func endIsTodayPlusDurationNotSavedStart() throws {
        var saved = ContestSetup()
        saved.startedAt = "2026-11-28 00:00"
        let form = NewContestForm.prefill(definition: try Self.definition("cq-ww-cw"), saved: saved,
                                          stationCall: "", now: Self.now)
        #expect(form.startedAt == "2026-11-28 00:00")
        #expect(form.endedAt == "2026-10-04 00:00")
    }

    @Test func midnightBeforeEpoch() {
        #expect(NewContestForm.todayMidnightUtc(Date(timeIntervalSince1970: -1)) == -86_400)
        #expect(NewContestForm.todayMidnightUtc(Date(timeIntervalSince1970: -86_400)) == -86_400)
        #expect(NewContestForm.todayMidnightUtc(Date(timeIntervalSince1970: 86_399.9)) == 0)
    }

    @Test func formatMatchesJava() {
        for (year, month, day, hours, expected) in Measured.fmtEnd {
            let midnight: Int64 = JavaLocalDate.epochDay(year: year, month: month, day: day) * 86_400
            #expect(NewContestForm.format(epochSecond: midnight + hours * 3_600) == expected,
                    "\(year)-\(month)-\(day) + \(hours) h")
        }
    }

    @Test func defaultForMatchesKotlin() {
        for (key, value) in Measured.defaultFor {
            #expect(NewContestForm.defaultFor(key) == value, "\(key)")
        }
    }

    @Test func uniqueLabels() throws {
        let ww = try Self.definition("cq-ww-cw")
        var twin = try Self.definition("cq-wpx-cw")
        twin.metadata?.name = ww.metadata?.name
        let iaru = try Self.definition("iaru-hf")
        var unnamed = try Self.definition("iaru-hf")
        unnamed.metadata = nil
        unnamed.id = "solo"
        let labels = NewContestForm.labels([ww, iaru, twin, unnamed])
        #expect(labels == [
            .init(text: "CQ WW DX Contest — CW (cq-ww-cw)", id: "cq-ww-cw"),
            .init(text: "IARU HF Championship", id: "iaru-hf"),
            .init(text: "CQ WW DX Contest — CW (cq-wpx-cw)", id: "cq-wpx-cw"),
            .init(text: "solo", id: "solo"),
        ])
        #expect(NewContestForm.selectedLabel(labels, definition: twin) == "CQ WW DX Contest — CW (cq-wpx-cw)")
        var other = try Self.definition("rdxc")
        other.id = "elsewhere"
        #expect(NewContestForm.selectedLabel(labels, definition: other) == other.metadata?.name)
    }

    @Test func repeatedLabelKeepsFirstPositionAndLastId() throws {
        var a = try Self.definition("cq-ww-cw")
        a.metadata?.name = "Same (z)"
        a.id = "a1"
        var b = a
        b.metadata?.name = "Same"
        b.id = "z"
        var c = b
        c.id = "q"
        let labels = NewContestForm.labels([a, try Self.definition("iaru-hf"), b, c])
        #expect(labels == [
            .init(text: "Same (z)", id: "z"),
            .init(text: "IARU HF Championship", id: "iaru-hf"),
            .init(text: "Same (q)", id: "q"),
        ])
    }

    enum Measured {
        static let fmtEnd: [(Int64, Int64, Int64, Int64, String)] = [
            (2026, 10, 2, 0, "2026-10-02 00:00"),
            (2026, 10, 2, 1, "2026-10-02 01:00"),
            (2026, 10, 2, 24, "2026-10-03 00:00"),
            (2026, 10, 2, 48, "2026-10-04 00:00"),
            (2026, 10, 2, -1, "2026-10-01 23:00"),
            (2026, 10, 2, 100000, "2038-02-27 16:00"),
            (2026, 10, 2, -100000, "2015-05-06 08:00"),
            (2026, 10, 2, 2147483647, "+247010-07-11 07"),
            (2026, 10, 2, -2147483648, "-242958-12-24 16"),
            (1970, 1, 1, 0, "1970-01-01 00:00"),
            (1970, 1, 1, 1, "1970-01-01 01:00"),
            (1970, 1, 1, 24, "1970-01-02 00:00"),
            (1970, 1, 1, 48, "1970-01-03 00:00"),
            (1970, 1, 1, -1, "1969-12-31 23:00"),
            (1970, 1, 1, 100000, "1981-05-29 16:00"),
            (1970, 1, 1, -100000, "1958-08-05 08:00"),
            (1970, 1, 1, 2147483647, "+246953-10-09 07"),
            (1970, 1, 1, -2147483648, "-243014-03-24 16"),
            (9999, 12, 31, 0, "9999-12-31 00:00"),
            (9999, 12, 31, 1, "9999-12-31 01:00"),
            (9999, 12, 31, 24, "+10000-01-01 00:"),
            (9999, 12, 31, 48, "+10000-01-02 00:"),
            (9999, 12, 31, -1, "9999-12-30 23:00"),
            (9999, 12, 31, 100000, "+10011-05-28 16:"),
            (9999, 12, 31, -100000, "9988-08-03 08:00"),
            (9999, 12, 31, 2147483647, "+254983-10-08 07"),
            (9999, 12, 31, -2147483648, "-234984-03-23 16"),
            (10000, 1, 1, 0, "+10000-01-01 00:"),
            (10000, 1, 1, 1, "+10000-01-01 01:"),
            (10000, 1, 1, 24, "+10000-01-02 00:"),
            (10000, 1, 1, 48, "+10000-01-03 00:"),
            (10000, 1, 1, -1, "9999-12-31 23:00"),
            (10000, 1, 1, 100000, "+10011-05-29 16:"),
            (10000, 1, 1, -100000, "9988-08-04 08:00"),
            (10000, 1, 1, 2147483647, "+254983-10-09 07"),
            (10000, 1, 1, -2147483648, "-234984-03-24 16"),
            (-1, 6, 15, 0, "-0001-06-15 00:0"),
            (-1, 6, 15, 1, "-0001-06-15 01:0"),
            (-1, 6, 15, 24, "-0001-06-16 00:0"),
            (-1, 6, 15, 48, "-0001-06-17 00:0"),
            (-1, 6, 15, -1, "-0001-06-14 23:0"),
            (-1, 6, 15, 100000, "0010-11-10 16:00"),
            (-1, 6, 15, -100000, "-0012-01-17 08:0"),
            (-1, 6, 15, 2147483647, "+244983-03-23 07"),
            (-1, 6, 15, -2147483648, "-244985-09-06 16"),
            (0, 1, 1, 0, "0000-01-01 00:00"),
            (0, 1, 1, 1, "0000-01-01 01:00"),
            (0, 1, 1, 24, "0000-01-02 00:00"),
            (0, 1, 1, 48, "0000-01-03 00:00"),
            (0, 1, 1, -1, "-0001-12-31 23:0"),
            (0, 1, 1, 100000, "0011-05-29 16:00"),
            (0, 1, 1, -100000, "-0012-08-04 08:0"),
            (0, 1, 1, 2147483647, "+244983-10-09 07"),
            (0, 1, 1, -2147483648, "-244984-03-24 16"),
            (2024, 2, 28, 0, "2024-02-28 00:00"),
            (2024, 2, 28, 1, "2024-02-28 01:00"),
            (2024, 2, 28, 24, "2024-02-29 00:00"),
            (2024, 2, 28, 48, "2024-03-01 00:00"),
            (2024, 2, 28, -1, "2024-02-27 23:00"),
            (2024, 2, 28, 100000, "2035-07-26 16:00"),
            (2024, 2, 28, -100000, "2012-10-01 08:00"),
            (2024, 2, 28, 2147483647, "+247007-12-07 07"),
            (2024, 2, 28, -2147483648, "-242960-05-21 16"),
        ]
        static let defaultFor: [(String, String)] = [
            ("OPERATOR", "SINGLE-OP"),
            ("POWER", "LOW"),
            ("OVERLAY", "N/A"),
            ("STATION", "FIXED"),
            ("ASSISTED", "NON-ASSISTED"),
            ("TRANSMITTER", "ONE"),
            ("TIME", "N/A"),
            ("BAND", ""),
            ("MODE", ""),
            ("operator", ""),
            ("", ""),
        ]
    }
}
