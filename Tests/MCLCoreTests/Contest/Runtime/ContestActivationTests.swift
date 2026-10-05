import Foundation
import Testing
@testable import MCLCore

/// `ContestActivation` against the Kotlin `AppState` (v1.1.1): `parseEpoch`, browser date formatting and
/// `modeCategory` measured on the JVM (maintainer-only probe), the activation effect order and the
/// create/continue/open flows read from `AppState.kt` (`createAndStartContest`, `activateContest`, …).
@Suite struct ContestActivationTests {

    @Test func parseEpochMatchesJava() {
        for (input, expected) in Measured.parseEpoch {
            #expect(ContestActivation.parseEpoch(input) == expected, "\(input.debugDescription)")
        }
    }

    @Test func browserDatesMatchJava() {
        for (millis, date, year) in Measured.fmtDate {
            #expect(ContestActivation.fmtDate(millis) == date, "\(millis)")
            #expect(ContestActivation.fmtYear(millis) == year, "\(millis)")
        }
    }

    @Test func modeCategoryMatchesKotlin() {
        for (mode, category) in Measured.modeCategory {
            #expect(ContestActivation.modeCategory(mode) == category, "\(mode.debugDescription)")
        }
    }

    // MARK: - plan

    static func row(_ id: String = "c-1", setupJson: String? = nil) throws -> ContestStore.ContestRow {
        let yaml = try #require(ContestRuntime.rawYaml(
            contestsDir: SessionFixture.contestData().appendingPathComponent("contests"), definitionId: "cq-ww-cw"))
        return ContestStore.ContestRow(contestId: id, definitionId: "cq-ww-cw", name: "CQ WW DX Contest — CW",
                                       startedAt: nil, endedAt: nil, definitionYaml: yaml, setupJson: setupJson,
                                       stationJson: nil)
    }

    static let configStore = ConfigStore(file: URL(fileURLWithPath: "/nonexistent/config.json"))

    @Test func planKeepsKotlinOrder() throws {
        var setup = ContestSetup()
        setup.tour = "0000/60"
        setup.bonusStations = ["OK1BON"]
        let row = try Self.row(setupJson: Self.configStore.toJSON(setup))
        let definition = try ContestRuntime.parseDefinition(row.definitionYaml)
        let plan = ContestActivation.plan(row: row, definition: definition, stationCall: "OK1XOE",
                                          configStore: Self.configStore)
        #expect(plan.contestId == "c-1")
        #expect(plan.setup == setup)
        let tour = try Tour(startMinute: 0, durationMinutes: 60)
        let bands: Set<Band> = [.m160, .m80, .m40, .m20, .m15, .m10]
        let json = PluginEventJson.contestOpened(contestId: "c-1", name: "CQ WW DX Contest — CW", call: "OK1XOE")
        #expect(plan.effects == [
            .setSessionExtras(tour: tour, bonusStations: ["OK1BON"]),
            .activateDefinition,
            .setActiveContest,
            .setLastContestId,
            .setDefaultSpotFilters(bands: bands, modes: ["CW"]),
            .reloadQtcs,
            .firePlugin(.contestOpened, json: json),
            .replayLog,
            .refreshFromLogbook,
            .startClusterIfIdle,
        ])
    }

    @Test func planWithoutSetupUsesDefinitionSessions() throws {
        let row = try Self.row(setupJson: "{not json")
        var definition = try ContestRuntime.parseDefinition(row.definitionYaml)
        definition.period?.sessions = ContestDefinition.Sessions(start: "0000", minutes: 30)
        definition.modes = ["CW", "usb", nil, "FT8"]
        definition.bands = ["20m", "bogus", nil]
        let plan = ContestActivation.plan(row: row, definition: definition, stationCall: "OK1XOE",
                                          configStore: Self.configStore)
        #expect(plan.setup == nil)
        #expect(plan.effects[0] == .setSessionExtras(tour: try Tour(startMinute: 0, durationMinutes: 30),
                                                     bonusStations: []))
        #expect(plan.effects[4] == .setDefaultSpotFilters(bands: [.m20], modes: ["CW", "PHONE", "DIGI"]))
    }

    @Test func tourOffDisablesDefinitionSessions() throws {
        var setup = ContestSetup()
        setup.tour = "off"
        let row = try Self.row(setupJson: Self.configStore.toJSON(setup))
        var definition = try ContestRuntime.parseDefinition(row.definitionYaml)
        definition.period?.sessions = ContestDefinition.Sessions(start: "0000", minutes: 30)
        let plan = ContestActivation.plan(row: row, definition: definition, stationCall: "", configStore: Self.configStore)
        #expect(plan.effects[0] == .setSessionExtras(tour: nil, bonusStations: []))
    }

    @Test func replayOrderPutsTimelessFirstAndIsStable() {
        func q(_ call: String, _ second: TimeInterval?) -> Qso {
            var qso = Qso()
            qso.call = call
            qso.timestampUtc = second.map { Date(timeIntervalSince1970: $0) }
            return qso
        }
        let ordered = ContestActivation.replayOrder([q("A", 20), q("B", nil), q("C", 10), q("D", 20), q("E", nil)])
        #expect(ordered.map(\.call) == ["B", "E", "C", "A", "D"])
    }

    // MARK: - create, continue, open, label, browser

    static func stores() throws -> (LogbookRepository, ContestStore) {
        let repository = try LogbookRepository.inMemory()
        return (repository, try ContestStore(repository))
    }

    @Test func createContestInsertsSnapshotRow() throws {
        let (_, store) = try Self.stores()
        let contests = try SessionFixture.contestData().appendingPathComponent("contests")
        var setup = ContestSetup()
        setup.startedAt = " 2026-11-28 00:00 "
        setup.endedAt = "garbage"
        var station = StationConfig()
        station.call = "OK1XOE"
        let yaml = ContestRuntime.rawYaml(contestsDir: contests, definitionId: "cq-ww-cw")
        let result = try ContestActivation.createContest(definitionId: "cq-ww-cw", yaml: yaml, setup: setup,
                                                         station: station, configStore: Self.configStore,
                                                         store: store, makeId: { "id-1" })
        let opening = try result.get()
        #expect(opening.startedMessage?.czech == "Spuštěn závod CQ WW DX Contest — CW")
        let row = try #require(try store.find("id-1"))
        #expect(row == opening.row)
        #expect(row.definitionId == "cq-ww-cw")
        #expect(row.name == "CQ WW DX Contest — CW")
        #expect(row.startedAt == 1_795_824_000_000)
        #expect(row.endedAt == nil)
        #expect(row.definitionYaml == yaml)
        #expect(Self.configStore.fromJSON(row.setupJson, as: ContestSetup.self) == setup)
        #expect(Self.configStore.fromJSON(row.stationJson, as: StationConfig.self)?.call == "OK1XOE")
    }

    @Test func createContestErrors() throws {
        let (_, store) = try Self.stores()
        let missing = try ContestActivation.createContest(definitionId: "nope", yaml: nil, setup: ContestSetup(),
                                                          station: StationConfig(), configStore: Self.configStore,
                                                          store: store)
        #expect(missing == .failure(ContestMessage("Nelze načíst definici závodu '%s' pro snapshot.", "nope")))
        let broken = try ContestActivation.createContest(definitionId: "x", yaml: "::: [", setup: ContestSetup(),
                                                         station: StationConfig(), configStore: Self.configStore,
                                                         store: store)
        guard case .failure(let message) = broken else {
            Issue.record("expected a failure")
            return
        }
        #expect(message.key == "Definice závodu je nečitelná (%s).")
        #expect(try store.listSummaries().isEmpty)
    }

    @Test func createdIdIsLowercaseUuid() throws {
        let (_, store) = try Self.stores()
        let row = try Self.row()
        let opening = try ContestActivation.createContest(definitionId: "cq-ww-cw", yaml: row.definitionYaml,
                                                          setup: ContestSetup(), station: StationConfig(),
                                                          configStore: Self.configStore, store: store).get()
        let id = opening.row.contestId
        #expect(UUID(uuidString: id) != nil)
        #expect(id == id.lowercased())
    }

    @Test func openContinueAndLabel() throws {
        let (repository, store) = try Self.stores()
        #expect(try ContestActivation.lastContestLabel(repository: repository, store: store) == nil)
        #expect(try ContestActivation.continueLastContest(repository: repository, store: store) == nil)
        #expect(try ContestActivation.openContest(contestId: "c-1", store: store)
                == .failure(ContestMessage("Závod nenalezen v databázi")))

        try store.insert(try Self.row())
        var broken = try Self.row("c-2")
        broken.definitionYaml = "::: ["
        try store.insert(broken)

        let opened = try ContestActivation.openContest(contestId: "c-1", store: store).get()
        #expect(opened.startedMessage?.czech == "Otevřen závod CQ WW DX Contest — CW")
        #expect(opened.definition.id == "cq-ww-cw")
        #expect(try ContestActivation.openContest(contestId: "c-2", store: store)
                == .failure(ContestMessage("Poškozená definice závodu — nelze otevřít")))

        try repository.metaSet("last_contest_id", "c-2")
        #expect(try ContestActivation.continueLastContest(repository: repository, store: store) == nil)
        #expect(try ContestActivation.lastContestLabel(repository: repository, store: store) == "CQ WW DX Contest — CW")
        try repository.metaSet("last_contest_id", "c-1")
        let continued = try #require(try ContestActivation.continueLastContest(repository: repository, store: store))
        #expect(continued.row.contestId == "c-1")
        #expect(continued.startedMessage == nil, "Kotlin leaves the status untouched")
        try repository.metaSet("last_contest_id", "gone")
        #expect(try ContestActivation.lastContestLabel(repository: repository, store: store) == nil)
    }

    @Test func browserRowFields() {
        func summary(started: Int64?, ended: Int64?, first: Int64?, last: Int64?,
                     bands: [String]) -> ContestStore.ContestSummary {
            ContestStore.ContestSummary(contestId: "c", definitionId: "d", name: "N", startedAt: started,
                                        endedAt: ended, qsoCount: 7, bands: bands, firstQso: first, lastQso: last)
        }
        var setup = ContestSetup()
        setup.category = ["OPERATOR": "SINGLE-OP", "POWER": "\u{00A0}"]
        let full = ContestActivation.browserRow(summary(started: 1_790_899_200_000, ended: 1_791_072_000_000,
                                                        first: nil, last: nil, bands: ["M20", "M40"]), setup: setup)
        #expect(full == ContestBrowserRow(contestId: "c", name: "N", dateRange: "2026-10-02 – 2026-10-04",
                                          year: "2026", qsoCount: 7, bands: "M20, M40", category: "SINGLE-OP",
                                          power: "—"))
        let fromQsos = ContestActivation.browserRow(summary(started: nil, ended: nil, first: 0, last: nil,
                                                            bands: []), setup: nil)
        #expect(fromQsos.dateRange == "1970-01-01")
        #expect(fromQsos.year == "1970")
        #expect(fromQsos.bands == "—")
        #expect(fromQsos.category == "—")
        let empty = ContestActivation.browserRow(summary(started: nil, ended: 5, first: nil, last: nil,
                                                         bands: [" "]), setup: nil)
        #expect(empty.dateRange == "—")
        #expect(empty.year == "—")
        #expect(empty.bands == "—")
    }

    @Test func browserRowsReadSetupPerContest() throws {
        let (repository, store) = try Self.stores()
        var setup = ContestSetup()
        setup.category = ["OPERATOR": "MULTI-OP", "POWER": "HIGH"]
        var first = try Self.row("c-1", setupJson: Self.configStore.toJSON(setup))
        first.startedAt = 2_000
        try store.insert(first)
        var second = try Self.row("c-2", setupJson: "{broken")
        second.startedAt = 1_000
        try store.insert(second)
        var qso = Qso()
        qso.call = "W1AW"
        qso.freqHz = 14_000_000
        qso.contestId = "c-2"
        qso.timestampUtc = Date(timeIntervalSince1970: 1_790_899_200)
        _ = try repository.insert(&qso)
        let rows = try ContestActivation.browserRows(store: store, configStore: Self.configStore)
        #expect(rows.map(\.contestId) == ["c-1", "c-2"])
        #expect(rows[0].category == "MULTI-OP")
        #expect(rows[0].power == "HIGH")
        #expect(rows[1].category == "—")
        #expect(rows[1].qsoCount == 1)
        #expect(rows[1].bands != "—")
    }

    enum Measured {
        static let parseEpoch: [(String, Int64?)] = [
            ("2026-10-02 00:00", 1790899200000),
            ("2026-10-02 12:34", 1790944440000),
            ("2026-10-02T12:34", 1790944440000),
            ("2026-10-02t12:34", 1790944440000),
            ("  2026-10-02 12:34  ", 1790944440000),
            ("\u{0009}2026-10-02 12:34\u{000A}", 1790944440000),
            ("\u{00A0}2026-10-02 12:34\u{00A0}", 1790944440000),
            ("\u{2003}2026-10-02 12:34", 1790944440000),
            ("\u{3000}2026-10-02 12:34", 1790944440000),
            ("\u{0001}2026-10-02 12:34", nil),
            ("2026-10-02 12:34:56", 1790944496000),
            ("2026-10-02 12:34:56.789", 1790944496789),
            ("2026-10-02 12:34:56.123456789", 1790944496123),
            ("2026-10-02 12:34:56.1234567891", nil),
            ("2026-10-02 12:34:56.", 1790944496000),
            ("2026-10-02 12:34:", nil),
            ("2026-10-02 12", nil),
            ("2026-10-02", nil),
            ("2026-10-02  12:34", nil),
            ("2026-10-02 1:34", nil),
            ("2026-10-02 24:00", nil),
            ("2026-10-02 23:60", nil),
            ("2026-10-02 23:59:60", nil),
            ("2026-02-29 00:00", nil),
            ("2024-02-29 00:00", 1709164800000),
            ("2026-04-31 00:00", nil),
            ("2026-13-01 00:00", nil),
            ("2026-1-01 00:00", nil),
            ("02-10-2026 00:00", nil),
            ("+10000-01-01 00:00", 253402300800000),
            ("10000-01-01 00:00", nil),
            ("+2026-01-01 00:00", nil),
            ("-0001-01-01 00:00", -62198755200000),
            ("-0000-01-01 00:00", nil),
            ("0000-01-01 00:00", -62167219200000),
            ("1969-12-31 23:59:59.999", -1),
            ("1970-01-01 00:00", 0),
            ("+999999999-12-31 23:59", nil),
            ("-999999999-01-01 00:00", nil),
            ("+292278994-08-17 07:12", 9223372036854720000),
            ("+292278994-08-17 07:13", nil),
            ("-292275055-05-16 16:47", nil),
            ("-292275055-05-16 16:48", -9223372036854720000),
            ("\u{FF12}026-10-02 12:34", nil),
            ("2026-10-02 12:34Z", nil),
            ("2026-10-02 12:34 ", 1790944440000),
            ("2026-10-02 12 34", nil),
            ("", nil),
            ("   ", nil),
            ("\u{00A0}", nil),
            ("x", nil),
            ("2026-10-02T 12:34", nil),
        ]
        static let fmtDate: [(Int64, String, String)] = [
            (0, "1970-01-01", "1970"),
            (1, "1970-01-01", "1970"),
            (-1, "1969-12-31", "1969"),
            (1790000000000, "2026-09-21", "2026"),
            (1790035199999, "2026-09-21", "2026"),
            (-62135596800000, "0001-01-01", "1"),
            (-62135596800001, "0000-12-31", "0"),
            (-62167219200000, "0000-01-01", "0"),
            (-62167219200001, "-0001-12-31", "-1"),
            (253402300799999, "9999-12-31", "9999"),
            (253402300800000, "+10000-01-01", "10000"),
            (9223372036854775807, "+292278994-08-17", "292278994"),
            (Int64.min, "-292275055-05-16", "-292275055"),
        ]
        static let modeCategory: [(String, String)] = [
            ("CW", "CW"),
            ("cw", "CW"),
            (" CW ", "CW"),
            ("\u{00A0}CW\u{00A0}", "CW"),
            ("SSB", "PHONE"),
            ("USB", "PHONE"),
            ("LSB", "PHONE"),
            ("PH", "PHONE"),
            ("PHONE", "PHONE"),
            ("FM", "PHONE"),
            ("AM", "PHONE"),
            ("RTTY", "DIGI"),
            ("FT8", "DIGI"),
            ("DIGITAL", "DIGI"),
            ("", "DIGI"),
            ("ph", "PHONE"),
            ("\u{0131}", "DIGI"),
            ("Ph\u{00A0}", "PHONE"),
        ]
    }
}
