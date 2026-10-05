import Foundation
import Testing
@testable import MCLCore

/// Port of `WorkedBeforeTest.java` — callsign check per band (N1MM Check /
/// DXLog "Check callsign"): on which bands and with which modes the callsign has already been
/// worked in the logbook (see `WorkedBefore.swift`).
@Suite struct WorkedBeforeTests {

    private static func qso(_ call: String, _ hz: Int, _ mode: Mode, _ at: String) -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = hz
        q.mode = mode
        q.timestampUtc = ISO8601DateFormatter().date(from: at)
        return q
    }

    // MARK: - `WorkedBeforeTest.bandsAndModesInOrder`

    @Test func bandsAndModesInOrder() {
        var deleted = Self.qso("DL1ABC", 3_510_000, .cw, "2026-11-28T13:00:00Z")
        deleted.deleted = true
        let log: [Qso] = [
            Self.qso("DL1ABC", 14_010_000, .cw, "2026-11-28T10:00:00Z"),
            Self.qso("dl1abc", 14_200_000, .ssb, "2026-11-28T11:00:00Z"),
            Self.qso("DL1ABC", 50_100_000, .cw, "2026-11-28T12:00:00Z"),
            Self.qso("OK1XX", 7_010_000, .cw, "2026-11-28T12:30:00Z"),
            deleted,
        ]

        let r = WorkedBefore.of(qsos: log, call: "DL1ABC", bandOrder: ["80m", "40m", "20m"])

        #expect(r.count == 3)
        #expect(r.last == ISO8601DateFormatter().date(from: "2026-11-28T12:00:00Z"))
        #expect(
            r.bands.map(\.band) == ["80m", "40m", "20m", "6m"],
            "band outside the contest (6 m) at the end, the deleted QSO on 80 m is not counted"
        )
        #expect(!r.bands[0].worked)
        // Order, not a set: Java has a `TreeSet`, the UI prints it via `joinToString("/")`.
        #expect(r.bands[2].modes == ["CW", "SSB"])
        #expect(r.bands.first(where: { $0.band == "6m" })?.modes == ["CW"])
        #expect(r.anyWorked)
    }

    // MARK: - Mode order = Java `TreeSet` (beyond `WorkedBeforeTest.java`)

    /// Pins that `modes` is sorted alphabetically, not in the order the QSOs arrived —
    /// Java `TreeSet<String>` and Kotlin `EntryPanel` (`joinToString("/")`) always show
    /// `CW/RTTY/SSB`. With a `Set<String>` (the state before the fix) this test cannot
    /// pass: `Set` has no order and comparing with an array would not even compile, or
    /// converting to an array would make the result vary between runs.
    @Test func modesAreSortedAlphabeticallyRegardlessOfLogOrder() {
        let log: [Qso] = [
            Self.qso("OK1XOE", 14_200_000, .ssb, "2026-11-28T10:00:00Z"),
            Self.qso("OK1XOE", 14_090_000, .rtty, "2026-11-28T10:10:00Z"),
            Self.qso("OK1XOE", 14_010_000, .cw, "2026-11-28T10:20:00Z"),
        ]

        let r = WorkedBefore.of(qsos: log, call: "OK1XOE", bandOrder: ["20m"])

        #expect(r.bands.map(\.band) == ["20m"])
        #expect(r.bands[0].modes == ["CW", "RTTY", "SSB"], "order is alphabetical, not logging order")
    }

    // MARK: - Unknown mode → `"?"` (Java `q.getMode() == null ? "?" : ...`)

    /// `"?"` is below the capital letters in ASCII, so the Java `TreeSet` puts it first.
    @Test func missingModeSortsFirstAsQuestionMark() {
        var noMode = Self.qso("OK1XOE", 14_010_000, .cw, "2026-11-28T10:00:00Z")
        noMode.mode = nil
        let log: [Qso] = [
            Self.qso("OK1XOE", 14_200_000, .ssb, "2026-11-28T10:30:00Z"),
            noMode,
        ]

        let r = WorkedBefore.of(qsos: log, call: "OK1XOE", bandOrder: ["20m"])

        #expect(r.bands[0].modes == ["?", "SSB"])
    }

    // MARK: - `WorkedBeforeTest.unknownCall`

    @Test func unknownCall() {
        let r = WorkedBefore.of(qsos: [], call: "W1AW", bandOrder: ["20m"])
        #expect(!r.anyWorked)
        #expect(r.bands.count == 1)
    }
}

// MARK: - Callsign normalization: Java `trim()`, not Swift `.whitespacesAndNewlines`

/// `WorkedBefore.java` normalizes the query via `call.trim().toUpperCase(Locale.ROOT)`.
/// Java `trim()` drops characters ≤ U+0020 and **keeps** the non-breaking space U+00A0 (and
/// U+2007 and DEL); Swift's `.whitespacesAndNewlines` does the opposite.
///
/// Measured on Java v1.1.1 (JDK 21, `-Duser.language=en`), logbook `[OK1XOE @ 20m CW]`:
/// | query | `count` |
/// |---|---|
/// | `ok1xoe` | 1 |
/// | `\u{0001}OK1XOE` | 1 |
/// | `\tOK1XOE` | 1 |
/// | `OK1XOE  ` | 1 |
/// | `\u{00A0}OK1XOE` | **0** |
/// | `OK1XOE\u{00A0}` | **0** |
/// | `OK1\u{00A0}XOE` | **0** |
/// | `\u{2007}OK1XOE` | **0** |
/// | `\u{007F}OK1XOE` | **0** |
@Suite struct WorkedBeforeCallNormalizationTests {

    private func qso(_ call: String, _ hz: Int, _ mode: Mode) -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = hz
        q.mode = mode
        q.timestampUtc = Date(timeIntervalSince1970: 1_767_225_600)
        return q
    }

    private let order = ["20m", "40m"]

    @Test func queryForPlainCallsignInLogbook() {
        let log = [qso("OK1XOE", 14_025_000, .cw)]
        #expect(WorkedBefore.of(qsos: log, call: "ok1xoe", bandOrder: order).count == 1)
        #expect(WorkedBefore.of(qsos: log, call: "\u{0001}OK1XOE", bandOrder: order).count == 1)
        #expect(WorkedBefore.of(qsos: log, call: "\tOK1XOE", bandOrder: order).count == 1)
        #expect(WorkedBefore.of(qsos: log, call: "OK1XOE  ", bandOrder: order).count == 1)
        #expect(WorkedBefore.of(qsos: log, call: "\u{00A0}OK1XOE", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: "OK1XOE\u{00A0}", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: "OK1\u{00A0}XOE", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: "\u{2007}OK1XOE", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: "\u{007F}OK1XOE", bandOrder: order).count == 0)
    }

    /// A logbook with a non-breaking space: Java measured `of("OK1XOE")` = 0,
    /// `of("\u{00A0}OK1XOE")` = 1.
    @Test func nonBreakingSpaceInLogbook() {
        let log = [qso("\u{00A0}OK1XOE", 14_025_000, .cw)]
        #expect(WorkedBefore.of(qsos: log, call: "OK1XOE", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: "\u{00A0}OK1XOE", bandOrder: order).count == 1)
    }

    /// An empty and whitespace-only query yields nothing; `\u{00A0}` alone neither,
    /// because there is no such callsign in the logbook (Java measured: count 0).
    @Test func emptyQuery() {
        let log = [qso("OK1XOE", 14_025_000, .cw)]
        #expect(WorkedBefore.of(qsos: log, call: "", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: "   ", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: "\u{00A0}", bandOrder: order).count == 0)
        #expect(WorkedBefore.of(qsos: log, call: nil, bandOrder: order).count == 0)
    }
}
