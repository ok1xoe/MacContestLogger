import Testing
@testable import MCLCore

/// Port of `SyncCoordinatorTest.java` (5 tests): merging the canonical state into the replica (LWW, tombstone, bootstrap
/// from the retained state) and publishing a local QSO via the `InMemorySyncTransport` loop.
@Suite struct SyncCoordinatorTests {

    final class Fixture {
        let repo: LogbookRepository
        let logbook: LogbookService
        let transport = InMemorySyncTransport()
        let changes = Counter()

        init() throws {
            repo = try LogbookRepository.inMemory()
            logbook = LogbookService(repository: repo)
            logbook.activeContestId = "test-contest"
        }

        deinit {
            repo.close()
        }

        @discardableResult
        func coordinator() throws -> SyncCoordinator {
            let changes = self.changes
            let c = SyncCoordinator(logbook: logbook, transport: transport, stationId: "OP2",
                                    onChange: { changes.increment() })
            try c.start()
            return c
        }
    }

    private static func wire(_ call: String) -> QsoWire {
        QsoWire(timestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:00Z"), call: call, freqHz: 14_025_000,
                band: "M20", mode: "CW", rstSent: "599", rstRcvd: "599", exchangeSent: nil, exchangeRcvd: "042",
                serialSent: nil, serialRcvd: 42, operator: nil, comment: "", dxccEntity: nil, dxccName: nil,
                continent: "EU")
    }

    private static func cmd(_ uuid: String, _ call: String) -> QsoCommand {
        QsoCommand(stationId: "OP1", uuid: uuid, clientTimestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:01Z"),
                   qso: wire(call))
    }

    @Test func appliesReceivedStateToReplica() throws {
        let f = try Fixture()
        try f.coordinator()
        try f.transport.publishInsert(Self.cmd("uuid-A", "DL1ABC")) // another station

        #expect(try f.logbook.findAll().count == 1)
        #expect(try f.logbook.findAll()[0].call == "DL1ABC")
        #expect(f.changes.value >= 1)
    }

    @Test func laterUpdateWinsByVersion() throws {
        let f = try Fixture()
        try f.coordinator()
        try f.transport.publishInsert(Self.cmd("uuid-A", "DL1ABC"))
        try f.transport.publishUpdate(Self.cmd("uuid-A", "DL1XYZ"))

        #expect(try f.logbook.findAll().count == 1)
        #expect(try f.logbook.findAll()[0].call == "DL1XYZ")
    }

    @Test func deleteStateRemovesFromActiveButKeepsTombstone() throws {
        let f = try Fixture()
        try f.coordinator()
        try f.transport.publishInsert(Self.cmd("uuid-A", "DL1ABC"))
        try f.transport.publishDelete(DeleteCommand(stationId: "OP1", uuid: "uuid-A",
                                                    clientTimestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:40:00Z")))

        #expect(try f.logbook.findAll().isEmpty)
        #expect(try f.logbook.findAllIncludingDeleted().count == 1)
        #expect(try f.logbook.findAllIncludingDeleted()[0].deleted)
    }

    @Test func bootstrapsFromRetainedStateOnStart() throws {
        let f = try Fixture()
        f.transport.connect()
        try f.transport.publishInsert(Self.cmd("uuid-A", "DL1ABC")) // before the station connects
        try f.coordinator() // subscribe → retained replay

        #expect(try f.logbook.findAll().count == 1)
        #expect(try f.logbook.findAll()[0].call == "DL1ABC")
    }

    @Test func publishInsertRoundTripsLocalQso() throws {
        let f = try Fixture()
        let c = try f.coordinator()
        var q = Qso()
        q.call = "OK1XOE"
        q.freqHz = 14_025_000 // derives M20
        q.mode = .cw
        q.uuid = "uuid-Z"

        try c.publishInsert(q)

        // the loopback emits the state → the coordinator applies it back into the replica
        let back: Qso = try f.logbook.findAll()[0]
        #expect(back.call == "OK1XOE")
        #expect(back.mode == .cw)
        #expect(back.version == 1)
        #expect(!back.deleted)
    }
}
