import Foundation
import Testing
@testable import MCLCore

/// The Check window's matching: partial and one-edit matches, character marks, ordering.
@Suite struct CheckMatcherTests {

    private func marks(_ match: CheckMatcher.Match?) -> String {
        guard let match else { return "-" }
        return match.segments.map { segment in
            switch segment.mark {
            case .same: return segment.text
            case .extra: return "+" + segment.text + "+"
            case .wrong: return "!" + segment.text + "!"
            }
        }.joined()
    }

    @Test func partialMatchesMarkTheCompletingCharactersGreen() {
        #expect(marks(CheckMatcher.match("ok1x", call: "OK1XOE")) == "OK1X+OE+")
        #expect(marks(CheckMatcher.match("1XO", call: "OK1XOE")) == "+OK+1XO+E+")
        #expect(CheckMatcher.match("OK1XOE", call: "ok1xoe")?.kind == .exact)
        #expect(CheckMatcher.match("OK1XOE", call: "OK1XOE")?.segments == [CheckMatcher.Segment(text: "OK1XOE",
                                                                                                 mark: .same)])
    }

    @Test func oneEditMatchesMarkTheDifferenceRed() {
        // A substitution.
        #expect(marks(CheckMatcher.match("OK1XDE", call: "OK1XOE")) == "OK1X!O!E")
        #expect(CheckMatcher.match("OK1XDE", call: "OK1XOE")?.kind == .oneEdit)
        // The call has a character more (inside: not a partial).
        #expect(marks(CheckMatcher.match("OK1OE", call: "OK1XOE")) == "OK1+X+OE")
        // The call lacks a typed character.
        #expect(marks(CheckMatcher.match("OK1XXOE", call: "OK1XOE")) == "OK1X!O!E")
        #expect(marks(CheckMatcher.match("OK1XOEE", call: "OK1XO")) == "-")
        // Two edits away or too short for one-edit search.
        #expect(CheckMatcher.match("OK1ABC", call: "OK1XOE") == nil)
        #expect(CheckMatcher.match("OK", call: "OM") == nil)
    }

    @Test func ordersExactPrefixInnerOneEdit() {
        let found: [String] = CheckMatcher.matches("OK1XO", candidates: [
            "OK1XD", "DL/OK1XOE", "OK1XOE", "ok1xo", "OK1XOEA", "OK1XOE",
        ]).map(\.call)
        #expect(found == ["OK1XO", "OK1XOE", "OK1XOEA", "DL/OK1XOE", "OK1XD"])
    }

    @Test func favourEndCharacterDifferencesRanksLateDifferencesFirst() {
        let candidates: [String] = ["OK1AOE", "OK1XDE", "OK1XOF"]
        #expect(CheckMatcher.matches("OK1XOE", candidates: candidates).map(\.call)
            == ["OK1AOE", "OK1XDE", "OK1XOF"])
        #expect(CheckMatcher.matches("OK1XOE", candidates: candidates, favorEnd: true).map(\.call)
            == ["OK1XOF", "OK1XDE", "OK1AOE"])
    }

    @Test func shortQueryAndLimit() {
        #expect(CheckMatcher.matches("O", candidates: ["OK1XOE"]).isEmpty)
        #expect(CheckMatcher.matches("OK", candidates: ["OK1A", "OK1B", "OK1C"], limit: 2).count == 2)
    }
}

@Suite struct CheckWindowCoreTests {

    private let records: [CheckReverseLookup.Record] = [
        CheckReverseLookup.Record(call: "W1AW", values: ["name": "Hiram", "state": "CT"]),
        CheckReverseLookup.Record(call: "K1ABC", values: ["name": "Hank", "state": "MA"]),
        CheckReverseLookup.Record(call: "N1HA", values: ["name": "Shane", "state": "CT"]),
    ]

    @Test func reverseLookupFromStartOrAnywhereWithThreshold() {
        #expect(CheckReverseLookup.search(entered: ["name": "ha"], records: records, partialCall: "",
                                          threshold: 2, fromStart: true) == ["K1ABC"])
        #expect(CheckReverseLookup.search(entered: ["name": "ha"], records: records, partialCall: "",
                                          threshold: 2, fromStart: false) == ["K1ABC", "N1HA"])
        // Below the threshold nothing is searched.
        #expect(CheckReverseLookup.search(entered: ["name": "h"], records: records, partialCall: "",
                                          threshold: 2, fromStart: true).isEmpty)
        // Every entered value must match; a partly typed call narrows the result.
        #expect(CheckReverseLookup.search(entered: ["name": "h", "state": "ct"], records: records, partialCall: "",
                                          threshold: 1, fromStart: true) == ["W1AW"])
        #expect(CheckReverseLookup.search(entered: ["state": "CT"], records: records, partialCall: "1H",
                                          threshold: 2, fromStart: true) == ["N1HA"])
        #expect(CheckReverseLookup.search(entered: ["state": "CT"], records: records, partialCall: "",
                                          threshold: 2, fromStart: true, limit: 1) == ["N1HA"])
    }

    @Test func reverseLookupRecordsOfACallHistory() {
        let history: CallHistory = CallHistory.parse(["!!Order!!,Call,Name,State", "W1AW,Hiram,CT", "K1ABC,Hank,MA"])
        let fields: [ContestDefinition.ExchangeField] = [
            ContestDefinition.ExchangeField(id: "rst", type: .RST, required: true, source: nil, appliesWhen: nil,
                                            validation: nil),
            ContestDefinition.ExchangeField(id: "st", type: .STATE, required: true, source: nil, appliesWhen: nil,
                                            validation: nil),
        ]
        let found: [CheckReverseLookup.Record] = CheckReverseLookup.records(history, fields: fields)
        #expect(found == [CheckReverseLookup.Record(call: "W1AW", values: ["st": "CT"]),
                          CheckReverseLookup.Record(call: "K1ABC", values: ["st": "MA"])])
        #expect(history.calls == ["W1AW", "K1ABC"])
    }

    @Test func exchangeValuesMatchKeyThenLabel() {
        let values: [CheckExchange.Value] = [
            CheckExchange.Value(key: "PHA", label: "Praha"), CheckExchange.Value(key: "BRN", label: "Brno"),
            CheckExchange.Value(key: "APH", label: "Alpha"), CheckExchange.Value(key: "PR", label: "Prerov"),
        ]
        #expect(CheckExchange.matches("pr", values: values).map(\.key) == ["PR", "PHA"])
        #expect(CheckExchange.matches("PH", values: values).map(\.key) == ["PHA", "APH"])
        #expect(CheckExchange.matches(" ", values: values).isEmpty)
    }

    @Test func settingsRoundTripThroughTheConfig() {
        var config = AppConfig()
        #expect(CheckSettings(config) == CheckSettings())
        var settings = CheckSettings(config)
        settings.hidden = [.telnet]
        settings.weights = [.scp: 3, .log: 1]
        settings.moveInYankOrder(.scp, by: -1)
        settings.yankAllowsDupes = true
        settings.favorEnd = true
        settings.telnetMinSpots = 2
        settings.reverseThreshold = 4
        settings.reverseFromStart = false
        settings.apply(to: &config)
        #expect(config.checkHiddenPanes == ["telnet"])
        #expect(config.checkPaneWeights == ["scp": 3])
        #expect(config.checkYankOrder == ["scp", "log", "telnet", "callHistory", "reverse"])
        var expected = settings
        expected.weights = [.scp: 3]
        #expect(CheckSettings(config) == expected)
    }

    @Test func settingsIgnoreUnknownNamesAndCompleteTheYankOrder() {
        var config = AppConfig()
        config.checkHiddenPanes = ["nonsense", "scp"]
        config.checkPaneWeights = ["log": 99, "x": 2]
        config.checkYankOrder = ["callHistory", "exchange", "callHistory"]
        config.checkTelnetMinSpots = 0
        let settings = CheckSettings(config)
        #expect(settings.hidden == [.scp])
        #expect(settings.weights == [.log: 10])
        #expect(settings.yankOrder == [.callHistory, .log, .scp, .telnet, .reverse])
        #expect(settings.telnetMinSpots == 1)
    }

    @Test func settingsSurviveAJsonRoundTrip() throws {
        var config = AppConfig()
        config.checkPaneWeights = ["scp": 2]
        config.checkYankAllowDupes = true
        config.showUnmatchedCallMark = false
        let data: Data = try JSONEncoder().encode(config)
        let decoded: AppConfig = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.checkPaneWeights == ["scp": 2])
        #expect(decoded.checkYankAllowDupes)
        #expect(!decoded.showUnmatchedCallMark)
    }

    @Test func yankCyclesWhileTheFieldKeepsTheYankedCall() {
        let panes: [CheckPane: [String]] = [.log: ["OK1AA", "OK1AB"], .scp: ["OK1AB", "OK1AC", "OK1AD"]]
        let candidates: [String] = CheckYank.candidates(panes: panes, order: [.scp, .log], typed: "OK1A",
                                                        allowDupes: false) { $0 == "OK1AC" }
        #expect(candidates == ["OK1AB", "OK1AD", "OK1AA"])
        #expect(CheckYank.candidates(panes: panes, order: [.log, .scp], typed: "OK1AA", allowDupes: true) { _ in true }
            == ["OK1AB", "OK1AC", "OK1AD"])
        var yank = CheckYank()
        #expect(yank.next(typed: "OK1A") { candidates } == "OK1AB")
        #expect(yank.next(typed: "OK1AB") { [] } == "OK1AD")
        #expect(yank.next(typed: "OK1AD") { [] } == "OK1AA")
        #expect(yank.next(typed: "OK1AA") { [] } == "OK1AB")
        // Typing something else starts a new cycle.
        #expect(yank.next(typed: "DL") { ["DL1A"] } == "DL1A")
        #expect(yank.next(typed: "X") { [] } == nil)
        #expect(!yank.continues("X"))
    }

    @Test func spotBufferCountsReSpotsWhileTheSpotLives() {
        let clock = DxTestClock("2026-07-09T10:00:00Z")
        let buffer = SpotBuffer(maxAgeMinutes: 10, clock: clock.source)
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "oh2as", comment: ""))
        buffer.add(DxSpot(spotter: "OK1DEF", freqHz: 14_025_000, dxCall: "OH2AS", comment: ""))
        buffer.add(DxSpot(spotter: "OK1GHI", freqHz: 7_005_000, dxCall: "W1AW", comment: ""))
        #expect(buffer.spotCounts() == ["OH2AS": 2, "W1AW": 1])
        clock.set("2026-07-09T10:11:00Z")
        #expect(buffer.spotCounts().isEmpty)
        // A spot after the old one died starts counting again.
        buffer.add(DxSpot(spotter: "OK1ABC", freqHz: 14_025_000, dxCall: "OH2AS", comment: ""))
        #expect(buffer.spotCounts() == ["OH2AS": 1])
    }
}
