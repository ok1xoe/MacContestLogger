import Foundation
import Testing
@testable import MCLCore

/// Check partial, N+1 and worked-before (`EP:623-651, 1193-1246, 1406-1440`). Spots are empty here.
@Suite struct EntrySuggestionsTests {

    private static let scp = ScpDatabase.of(["OK1ABC", "OK1ABD", "OK1AB", "W1AW", "OK2ABC", "DL1ABC"])

    @Test func partialNeedsTwoUntrimmedUnits() {
        #expect(EntrySuggestions.partial(query: "O", logCalls: [], spotCalls: [], scp: Self.scp).isEmpty)
        // Kotlin checks `query.length` of the raw text: " O" passes the gate (merge trims it).
        let spaced = EntrySuggestions.partial(query: " O", logCalls: [], spotCalls: [], scp: Self.scp)
        #expect(spaced == PartialCheck.merge(" O", logCalls: [], spotCalls: [],
                                             scpMatches: Self.scp.find(" O", limit: 8), limit: 8))
    }

    @Test func partialIsMergeOfLogSpotsAndScp() {
        let log = ["OK1ABC", "OK1XYZ"]
        let out = EntrySuggestions.partial(query: "1AB", logCalls: log, spotCalls: [], scp: Self.scp)
        #expect(out == PartialCheck.merge("1AB", logCalls: log, spotCalls: [],
                                          scpMatches: Self.scp.find("1AB", limit: 8), limit: 8))
        #expect(out.first == PartialCheck.Suggestion(call: "OK1ABC", source: .LOG))
        #expect(out.count <= EntrySuggestions.limit)
    }

    @Test func nPlusOneDistinctSortedTakeEight() {
        #expect(EntrySuggestions.nPlusOne(query: "OK", logCalls: [], spotCalls: [], scp: Self.scp).isEmpty)
        // `trim()` before the length gate.
        #expect(EntrySuggestions.nPlusOne(query: " OK ", logCalls: ["OKA"], spotCalls: [], scp: Self.scp).isEmpty)
        let out = EntrySuggestions.nPlusOne(query: " ok1abc ", logCalls: ["OK1ABD", "OK1ABX"], spotCalls: [],
                                            scp: Self.scp)
        #expect(out == ["OK1AB", "OK1ABD", "OK1ABX", "OK2ABC"])
        // Log + SCP duplicates collapse; UTF-16 order (digits before letters).
        let many: [String] = (0..<12).map { "OK1AB" + String(UnicodeScalar(UInt8(65 + $0))) }
        let capped = EntrySuggestions.nPlusOne(query: "OK1ABC", logCalls: many + ["OK1AB9"], spotCalls: [],
                                               scp: Self.scp)
        #expect(capped.count == 8)
        #expect(capped.first == "OK1AB")
        #expect(capped == capped.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) })
    }

    private static func qso(_ call: String, _ freqHz: Int, _ mode: Mode, _ at: TimeInterval) -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = freqHz
        q.mode = mode
        q.timestampUtc = Date(timeIntervalSince1970: at)
        return q
    }

    @Test func workedBefore() throws {
        let qsos = [Self.qso("OK1ABC", 14_025_000, .cw, 3600 * 13 + 60 * 5), Self.qso("OK1ABC", 7_025_000, .ssb, 60)]
        #expect(EntrySuggestions.workedBefore(qsos: qsos, call: "OK", contestBandOrder: nil) == nil)
        #expect(EntrySuggestions.workedBefore(qsos: qsos, call: "W1AW", contestBandOrder: nil) == nil)
        let result = try #require(EntrySuggestions.workedBefore(qsos: qsos, call: "ok1abc", contestBandOrder: nil))
        #expect(result.bands.map(\.band).prefix(6) == ["160m", "80m", "40m", "20m", "15m", "10m"])
        #expect(EntrySuggestions.workedBeforeCaption(result).czech == "Pracováno 2×, naposledy 1305Z:")
        #expect(EntrySuggestions.workedBeforeCaption(result).parts.first == ContestMessage("Pracováno %s×", 2))
        let chips = result.bands.map(EntrySuggestions.workedBeforeChip)
        #expect(chips.prefix(6) == ["160", "80", "40 SSB", "20 CW", "15", "10"])
        let contest = try #require(EntrySuggestions.workedBefore(qsos: qsos, call: "OK1ABC",
                                                                 contestBandOrder: ["20m", "40m"]))
        #expect(contest.bands.map(\.band).prefix(2) == ["20m", "40m"])
    }

    @Test func workedBeforeWithoutTime() throws {
        var q = Qso()
        q.call = "OK1ABC"
        let result = try #require(EntrySuggestions.workedBefore(qsos: [q], call: "OK1ABC", contestBandOrder: nil))
        #expect(EntrySuggestions.workedBeforeCaption(result).czech == "Pracováno 1×:")
    }
}
