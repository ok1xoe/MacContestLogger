import Foundation
import Testing
@testable import MCLCore

/// Port of the Kotlin `ContestControllerTest` (4 tests, names kept) + the rest of `ContestController` that moved
/// into `ContestRuntime` (activation errors, definition queries, replay, adopt), read from
/// `ui/contest/ContestController.kt` (v1.1.1).
@Suite struct ContestRuntimeTests {

    /// Kotlin `controller()`: DXCC from `dxcc-test.json`, sets from `contest-data/multipliers`, definitions from
    /// `contest-data/contests`, my callsign OK1XOE.
    static func runtime(myCall: String = "OK1XOE") throws -> ContestRuntime {
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc)
        let contests = try SessionFixture.contestData().appendingPathComponent("contests")
        return ContestRuntime(dxcc: dxcc, registry: registry, contestsDir: contests, myCall: { myCall })
    }

    static func exchange(_ pairs: (String?, String?)...) -> JavaLinkedMap<String> {
        JavaLinkedMap(pairs)
    }

    static func qso(_ minute: Int, _ call: String, _ freqHz: Int, _ exch: String, mode: Mode = .cw) -> Qso {
        var q = ScoreBreakdownTests.qso(minute, call, freqHz, exch)
        q.mode = mode
        return q
    }

    // MARK: - Kotlin ContestControllerTest

    @Test func activatesAndExposesDynamicFields() throws {
        let c = try Self.runtime()
        #expect(c.engineAvailable)
        _ = c.activate(id: "cq-ww-cw")
        #expect(c.isActive)
        let ids = try c.exchangeFields(call: "DL1ABC").map(\.id)
        #expect(ids == ["rst", "zone"])
    }

    @Test func previewSurfacesMultiplierStates() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        try c.preview(call: "DL1ABC", band: "20m", mode: "CW", exchange: Self.exchange(("zone", "14")))
        let preview = try #require(c.lastPreview)
        var states: [String?: MultiplierEvalResult.MultiplierState] = [:]
        for m in preview.multipliers {
            states[m.bindingId] = m.state
        }
        #expect(states["zones"] == .knownNewMultiplier)
        #expect(states["countries"] == .knownNewMultiplier)
    }

    @Test func logUpdatesScore() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        try c.log(call: "DL1ABC", band: "20m", mode: "CW", exchange: Self.exchange(("zone", "14")))
        try c.log(call: "W1AW", band: "20m", mode: "CW", exchange: Self.exchange(("zone", "5")))
        let score = try #require(c.score)
        #expect(score.qsoCount == 2)
        #expect(score.qsoPoints == 4)   // 1 + 3
        #expect(score.multTotal == 4)   // zones {14,5} + countries {DE,US}
    }

    @Test func deactivateClears() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        c.deactivate()
        #expect(!c.isActive)
    }

    // MARK: - activation

    @Test func activationErrorsAreKotlinTexts() throws {
        let c = try Self.runtime()
        #expect(c.activate(id: "nope")?.czech == "Závod 'nope' nenalezen.")
        #expect(!c.isActive)

        var definition = try SessionFixture.definition("@cq-ww-cw.yaml")
        definition.multipliers?[0]?.set = "missing_a"
        definition.multipliers?[1]?.set = "missing_b"
        let error = c.activate(contestId: "x", definition: definition)
        #expect(error?.czech == "Chybí multiplikátorové sady: missing_a, missing_b")
        #expect(error?.key == "Chybí multiplikátorové sady: %s")

        let noEngine = ContestRuntime(dxcc: nil, registry: nil, available: [], contestsDir: nil, myCall: { "" })
        #expect(!noEngine.engineAvailable)
        #expect(noEngine.activate(id: "cq-ww-cw")?.czech == "Contest engine není dostupný.")
        #expect(noEngine.activate(contestId: "x", definition: definition)?.czech == "Contest engine není dostupný.")
    }

    @Test func activationFromSnapshotUsesContestIdAndName() throws {
        let c = try Self.runtime()
        let definition = try SessionFixture.definition("@cq-ww-cw.yaml")
        #expect(c.activate(contestId: "uuid-1", definition: definition) == nil)
        #expect(c.activeId == "uuid-1")
        #expect(c.activeName == "CQ WW DX Contest — CW")
        #expect(c.score?.qsoCount == 0)
        #expect(c.definition == definition)
    }

    @Test func translatedActivationError() throws {
        let c = try Self.runtime()
        let error = try #require(c.activate(id: "nope"))
        let english = Translator(language: "en", translations: LanguageCatalog.Translations(
            [JavaStringKey("Závod '%s' nenalezen."): "Contest '%s' not found."]))
        #expect(error.text(english) == "Contest 'nope' not found.")
        let wrapped = ContestActivation.failure(error)
        #expect(wrapped.czech == "Nelze aktivovat závod: Závod 'nope' nenalezen.")
    }

    // MARK: - definition queries

    @Test func definitionQueriesOutsideContest() throws {
        let c = try Self.runtime()
        #expect(c.usesSerial)
        #expect(c.usesExchangeBeyondRst)
        #expect(!c.usesRoverQth)
        #expect(c.primaryMode == .cw)
        #expect(!c.isMultiMode)
        #expect(c.dupeScope == nil)
        #expect(c.bandOrder.isEmpty)
        #expect(try c.exchangeFields(call: "DL1ABC").isEmpty)
        #expect(try !c.isComplete(call: "DL1ABC", exchange: Self.exchange(("rst", "599"), ("zone", "14"))))
    }

    @Test func definitionQueriesOfActiveContest() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        #expect(!c.usesSerial)
        #expect(c.usesExchangeBeyondRst)
        #expect(c.dupeScope == .PER_BAND)
        #expect(c.bandOrder == ["160m", "80m", "40m", "20m", "15m", "10m"])
        #expect(c.primaryMode == .cw)
        #expect(!c.isMultiMode)
        #expect(try c.isComplete(call: "DL1ABC", exchange: Self.exchange(("rst", "599"), ("zone", "14"))))
        #expect(try !c.isComplete(call: "DL1ABC", exchange: Self.exchange(("rst", "599"))))
        #expect(try !c.isComplete(call: " \u{00A0}", exchange: Self.exchange(("rst", "599"), ("zone", "14"))))

        _ = c.activate(id: "cq-wpx-cw")
        #expect(c.usesSerial)
        #expect(c.usesExchangeBeyondRst, "a serial number is beyond the report")

        var reportOnly = try SessionFixture.definition("@cq-ww-cw.yaml")
        let rst = reportOnly.exchange?.received?[0]
        reportOnly.exchange?.received = [rst, nil]
        _ = c.activate(contestId: "r", definition: reportOnly)
        #expect(!c.usesExchangeBeyondRst, "RST only (a nil field is skipped)")

        _ = c.activate(id: "iaru-hf")
        #expect(c.isMultiMode)
        #expect(c.primaryMode == .cw)
    }

    /// Kotlin `usesExchangeBeyondRst` (`ContestController.kt:476-481`): RS (the phone report) counts as a report too.
    @Test func phoneReportOnlyIsNotBeyondTheReport() throws {
        let c = try Self.runtime()
        var phone = try SessionFixture.definition("@cq-ww-cw.yaml")
        var rs = try #require(phone.exchange?.received?[0])
        rs.type = .RS
        phone.exchange?.received = [rs]
        #expect(c.activate(contestId: "rs", definition: phone) == nil)
        #expect(!c.usesExchangeBeyondRst, "RS only")
        var zone = try #require(try SessionFixture.definition("@cq-ww-cw.yaml").exchange?.received?[1])
        zone.type = .RS
        phone.exchange?.received = [rs, zone]
        #expect(c.activate(contestId: "rs2", definition: phone) == nil)
        #expect(!c.usesExchangeBeyondRst, "RS and RS")
        zone.type = .CQ_ZONE
        phone.exchange?.received = [rs, zone]
        #expect(c.activate(contestId: "rs3", definition: phone) == nil)
        #expect(c.usesExchangeBeyondRst, "RS + zone")
    }

    @Test func activeContestWithoutExchangeSection() throws {
        let c = try Self.runtime()
        var definition = try SessionFixture.definition("@cq-ww-cw.yaml")
        definition.exchange = nil
        #expect(c.activate(contestId: "x", definition: definition) == nil)
        #expect(!c.usesSerial)
        #expect(!c.usesExchangeBeyondRst)
    }

    @Test func primaryModeByNameThenAdifThenCw() throws {
        let c = try Self.runtime()
        var definition = try SessionFixture.definition("@cq-ww-cw.yaml")
        definition.modes = ["usb"]
        _ = c.activate(contestId: "x", definition: definition)
        #expect(c.primaryMode == .ssb)
        definition.modes = ["BOGUS", "CW"]
        _ = c.activate(contestId: "x", definition: definition)
        #expect(c.primaryMode == .cw)
        #expect(c.isMultiMode)
        definition.modes = [nil, "SSB"]
        _ = c.activate(contestId: "x", definition: definition)
        #expect(c.primaryMode == .cw)
        definition.modes = ["RTTY"]
        _ = c.activate(contestId: "x", definition: definition)
        #expect(c.primaryMode == .rtty)
    }

    // MARK: - replay, recount, adopt

    @Test func replayLoggedSkipsXqsoAndCountsNothingWithoutBand() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        var x = Self.qso(0, "DL1ABC", 14_000_000, "599 14")
        x.xqso = true
        var noBand = Self.qso(1, "W1AW", 0, "599 5")
        noBand.band = nil
        let ok = Self.qso(2, "W1AW", 14_010_000, "599 5")
        c.replayLogged([x, noBand, ok])
        #expect(c.score?.qsoCount == 1)
        #expect(c.score?.qsoPoints == 3)
    }

    @Test func freshScoreAndMarksLeaveLiveSession() throws {
        let c = try Self.runtime()
        #expect(try c.freshScore([]) == nil)
        #expect(c.qsoMarks([]).isEmpty)
        #expect(c.replayed([]) == nil)
        #expect(c.freshSession() == nil)

        _ = c.activate(id: "cq-ww-cw")
        var a = Self.qso(0, "DL1ABC", 14_000_000, "599 14")
        a.id = 1
        var b = Self.qso(1, "W1AW", 14_010_000, "599 5")
        b.id = 2
        let fresh = try #require(try c.freshScore([a, b]))
        #expect(fresh.qsoCount == 2)
        #expect(c.score?.qsoCount == 0)
        let marks = c.qsoMarks([a, b])
        #expect(marks[1]?.points == 1)
        #expect(marks[2]?.points == 3)
        #expect(c.score?.qsoCount == 0)
    }

    @Test func adoptOnlyForTheActiveContest() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        let a = Self.qso(0, "DL1ABC", 14_000_000, "599 14")
        let outcome = try #require(c.replayed([a]))
        #expect(!c.adopt(outcome, forContestId: nil))
        #expect(!c.adopt(outcome, forContestId: "other"))
        #expect(c.score?.qsoCount == 0)
        try c.preview(call: "W1AW", band: "20m", mode: "CW", exchange: Self.exchange(("zone", "5")))
        #expect(c.lastPreview != nil)
        #expect(c.adopt(outcome, forContestId: "cq-ww-cw"))
        #expect(c.score?.qsoCount == 1)
        #expect(c.lastPreview == nil)

        c.deactivate()
        #expect(!c.adopt(outcome, forContestId: "cq-ww-cw"))
    }

    @Test func activationReplayOffTheOwnerThenAdopt() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        let session = try #require(c.freshSession())
        ContestRuntime.replayLogged([Self.qso(0, "W1AW", 14_000_000, "599 5")], into: session)
        #expect(c.score?.qsoCount == 0)
        #expect(c.adopt(session: session, forContestId: "other", replayedRevision: 1, currentRevision: 1)
                == .otherContest)
        #expect(c.adopt(session: session, forContestId: "cq-ww-cw", replayedRevision: 1, currentRevision: 1)
                == .adopted)
        #expect(c.score?.qsoCount == 1)
    }

    /// A QSO logged into the live session while the activation replay runs off the owner must not be lost.
    @Test func staleActivationReplayIsReplayedAgain() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        var log: [Qso] = [Self.qso(0, "W1AW", 14_000_000, "599 5")]
        var revision: Int64 = 1

        let snapshot = log
        let replayedRevision = revision
        let first = try #require(c.freshSession())
        ContestRuntime.replayLogged(snapshot, into: first)

        // Meanwhile on the owner: a new QSO is written and counted into the live session.
        log.append(Self.qso(1, "DL1ABC", 14_010_000, "599 14"))
        revision += 1
        try c.log(call: "DL1ABC", band: "20m", mode: "CW", exchange: Self.exchange(("zone", "14")))

        #expect(c.adopt(session: first, forContestId: "cq-ww-cw", replayedRevision: replayedRevision,
                        currentRevision: revision) == .stale)
        #expect(c.score?.qsoCount == 1, "the live session (with the new QSO) is kept")

        let second = try #require(c.freshSession())
        ContestRuntime.replayLogged(log, into: second)
        #expect(c.adopt(session: second, forContestId: "cq-ww-cw", replayedRevision: revision,
                        currentRevision: revision) == .adopted)
        #expect(c.score?.qsoCount == 2, "the re-replay includes the QSO logged meanwhile")
    }

    /// Divergence: Kotlin throws the score-formula error out of `activate` (and keeps the previous score); Swift
    /// activates, leaves `score` nil and keeps the error in `scoreError`.
    @Test func scoreFormulaErrorIsKeptNotThrown() throws {
        let c = try Self.runtime()
        var broken = try SessionFixture.definition("@cq-ww-cw.yaml")
        broken.scoring?.total = "qsoPoints * #"
        #expect(c.activate(contestId: "b", definition: broken) == nil)
        #expect(c.isActive)
        #expect(c.score == nil)
        #expect(c.scoreError != nil)
        try c.log(call: "W1AW", band: "20m", mode: "CW", exchange: Self.exchange(("zone", "5")))
        #expect(c.score == nil)
        #expect(c.scoreError != nil)

        #expect(c.activate(id: "cq-ww-cw") == nil)
        #expect(c.score?.qsoCount == 0)
        #expect(c.scoreError == nil, "cleared by a valid state")

        _ = c.activate(contestId: "b", definition: broken)
        #expect(c.scoreError != nil)
        c.deactivate()
        #expect(c.scoreError == nil)
        #expect(c.score == nil)
    }

    @Test func extrasApplyToLiveAndFreshSessions() throws {
        let c = try Self.runtime()
        let tour = try Tour(startMinute: 0, durationMinutes: 60)
        c.setSessionExtras(tour: tour, bonusStations: ["OK1BON"])
        c.setQtcCount(3)
        _ = c.activate(id: "wae-cw")
        let fresh = try #require(c.freshSession())
        #expect(fresh.tour == tour)
        #expect(fresh.bonusStations == ["OK1BON"])
        #expect(fresh.qtcCount == 3)
        #expect(c.qtcConfig != nil)
        c.setQtcCount(5)
        #expect(c.freshSession()?.qtcCount == 5)
    }

    @Test func previewAndLogOutsideContest() throws {
        let c = try Self.runtime()
        try c.preview(call: "DL1ABC", band: "20m", mode: "CW", exchange: Self.exchange())
        #expect(c.lastPreview == nil)
        #expect(try c.log(call: "DL1ABC", band: "20m", mode: "CW", exchange: Self.exchange()) == nil)
        #expect(c.score == nil)
    }

    @Test func logWithoutBandOrInForeignModeIsNotCounted() throws {
        let c = try Self.runtime()
        _ = c.activate(id: "cq-ww-cw")
        let noBand = try c.log(call: "DL1ABC", band: "", mode: "CW", exchange: Self.exchange(("zone", "14")))
        #expect(noBand?.counted == false)
        let ft8 = try c.log(call: "DL1ABC", band: "20m", mode: "FT8", exchange: Self.exchange(("zone", "14")))
        #expect(ft8?.counted == false)
        #expect(c.score?.qsoCount == 0)
    }

    // MARK: - snapshot

    @Test func rawYamlAndParse() throws {
        let c = try Self.runtime()
        let yaml = try #require(c.rawYaml(definitionId: "cq-ww-cw"))
        let parsed = try ContestRuntime.parseDefinition(yaml)
        #expect(parsed.id == "cq-ww-cw")
        #expect(c.rawYaml(definitionId: "nope") == nil)
        #expect(ContestRuntime.rawYaml(contestsDir: nil, definitionId: "cq-ww-cw") == nil)
        #expect(throws: ContestDefinitionError.self) { try ContestRuntime.parseDefinition("::: [") }
    }

    @Test func myGridAndItuZoneBlankBecomeNil() throws {
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc)
        let contests = try SessionFixture.contestData().appendingPathComponent("contests")
        let c = ContestRuntime(dxcc: dxcc, registry: registry, contestsDir: contests, myCall: { "OK1XOE" },
                               myGrid: { "\u{00A0}" }, myItuZone: { "" })
        #expect(c.activate(id: "cq-ww-cw") == nil)
        #expect(c.stationCall == "OK1XOE")
    }
}
