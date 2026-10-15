import Testing
@testable import MCLCore

/// A canonical state replaces the stored QSO as a whole — cleared fields are cleared — but the fields the network
/// does not carry stay as the station logged them: the run mode (never on the wire) and the radio number when the
/// state comes without it (the v1.1.1 authority re-reads every command into its own record and drops the extension).
@Suite struct SyncLocalFieldsTests {

    private static func wire(_ call: String, comment: String?, radioNr: Int32? = nil) -> QsoWire {
        QsoWire(timestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:00Z"), call: call, freqHz: 14_025_000,
                band: "M20", mode: "CW", rstSent: "599", rstRcvd: "599", exchangeSent: nil, exchangeRcvd: "14",
                serialSent: nil, serialRcvd: nil, operator: nil, comment: comment, dxccEntity: nil, dxccName: nil,
                continent: "EU", radioNr: radioNr)
    }

    private static func state(_ uuid: String, _ version: Int64, _ qso: QsoWire, from station: String = "OP1")
        -> QsoState {
        QsoState(uuid: uuid, stationId: station, version: version,
                 updatedAtUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:01Z"), deleted: false, qso: qso)
    }

    private static func fixture() throws -> (LogbookRepository, LogbookService, SyncCoordinator) {
        let repo = try LogbookRepository.inMemory()
        let logbook = LogbookService(repository: repo)
        logbook.activeContestId = "test-contest"
        let coordinator = SyncCoordinator(logbook: logbook, transport: InMemorySyncTransport(), stationId: "OP1",
                                          onChange: nil)
        return (repo, logbook, coordinator)
    }

    @Test func theOwnEchoKeepsTheRunModeAndTheRadioButClearsWhatTheEditCleared() throws {
        let (repo, logbook, coordinator) = try Self.fixture()
        defer { repo.close() }
        var own = Qso()
        own.call = "DL1ABC"
        own.freqHz = 14_025_000
        own.comment = "tnx"
        own.operator = "OK1XYZ"
        own.runMode = .searchAndPounce
        own.radioNr = 2
        own.uuid = "u1"
        own.stationId = "OP1"
        own.contestId = "test-contest"
        _ = try repo.insert(&own)

        // The edit cleared the comment and the operator; the authority's state has no radio number.
        try coordinator.onState(Self.state("u1", 1, Self.wire("DL2XYZ", comment: nil)))
        var stored = try #require(try logbook.findAll().first)
        #expect(stored.call == "DL2XYZ")
        #expect(stored.comment == "")
        #expect(stored.operator == "")
        #expect(stored.runMode == .searchAndPounce)
        #expect(stored.radioNr == 2)
        #expect(stored.version == 1)

        // A state that carries the radio number sets it.
        try coordinator.onState(Self.state("u1", 2, Self.wire("DL2XYZ", comment: "x", radioNr: 1)))
        stored = try #require(try logbook.findAll().first)
        #expect(stored.radioNr == 1)
        #expect(stored.comment == "x")
        #expect(stored.runMode == .searchAndPounce)

        // Another station's edit without a radio number: not known; the run mode stays.
        try coordinator.onState(Self.state("u1", 3, Self.wire("DL2XYZ", comment: nil), from: "OP2"))
        stored = try #require(try logbook.findAll().first)
        #expect(stored.radioNr == 0)
        #expect(stored.stationId == "OP2")
        #expect(stored.runMode == .searchAndPounce)

        // An older version changes nothing.
        try coordinator.onState(Self.state("u1", 3, Self.wire("OLD", comment: nil)))
        #expect(try logbook.findAll().first?.call == "DL2XYZ")
    }

    @Test func aQsoNewToTheReplicaTakesTheDefaults() throws {
        let (repo, logbook, coordinator) = try Self.fixture()
        defer { repo.close() }
        try coordinator.onState(Self.state("u2", 1, Self.wire("OK2ABC", comment: nil)))
        let stored = try #require(try logbook.findAll().first)
        #expect(stored.runMode == .run)
        #expect(stored.radioNr == 0)
    }
}
