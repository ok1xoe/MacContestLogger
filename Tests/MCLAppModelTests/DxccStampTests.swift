import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// N1MM: a database whose country table is older than the current country data is reported when it is opened; the
/// stamp of the DXCC data lives in the database's `meta` (`DxccDataStamp`).
@MainActor @Suite struct DxccStampTests {

    static let old = DxccDataStamp(source: .ctyDat, date: Date(timeIntervalSince1970: 946_684_800))

    static func stored(_ app: TestApp) async throws -> String? {
        try await app.model.database.handle.run { try $0.repository.metaGet(DxccDataStamp.metaKey) }
    }

    static func store(_ app: TestApp, _ value: String) async throws {
        try await app.model.database.handle.run { try $0.repository.metaSet(DxccDataStamp.metaKey, value) }
    }

    static func warning(_ app: TestApp, current: DxccDataStamp) -> String {
        app.model.language.text(DataToolsModel.outdatedDxccWarning(stored: old, current: current))
    }

    /// The fixture data has a date (the file's), and the new empty database gets it at start-up, silently.
    @Test func aNewDatabaseGetsTheCurrentStampAtStartUp() async throws {
        let app = try await TestApp.make()
        let current: DxccDataStamp = try #require(app.model.contest.environment.dxccStamp)
        #expect(current.source == .ctyDat || current.source == .dxccJson)
        #expect(try await Self.stored(app) == current.encoded)
        #expect(app.model.messages.lines.isEmpty)
    }

    @Test func withoutDxccDataNothingIsStored() async throws {
        let app = try await TestApp.make(withDxcc: false)
        #expect(app.model.contest.environment.dxccStamp == nil)
        #expect(await app.model.dataTools.checkDxccStamp() == nil)
        #expect(try await Self.stored(app) == nil)
    }

    /// A log filled with an older table: the status line and the Info messages say so, the stamp stays until the
    /// refill, which records the current one (no warning afterwards).
    @Test func anOlderTableWarnsUntilTheLogIsRefilled() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let current: DxccDataStamp = try #require(model.contest.environment.dxccStamp)
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        try await Self.store(app, Self.old.encoded)

        let decision = await model.dataTools.checkDxccStamp()

        #expect(decision == .warn(stored: Self.old, current: current))
        let text: String = Self.warning(app, current: current)
        #expect(text.contains("2000-01-01"))
        #expect(model.status.message == text)
        #expect(model.messages.lines.last?.text == text)
        #expect(try await Self.stored(app) == Self.old.encoded)

        await model.dataTools.refillDxcc()
        #expect(try await Self.stored(app) == current.encoded)
        #expect(await model.dataTools.checkDxccStamp() == .keep)
    }

    /// An empty log with an older stamp is simply restamped; a log without a stamp is not flagged.
    @Test func emptyOrUnstampedLogsAreStampedSilently() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let current: DxccDataStamp = try #require(model.contest.environment.dxccStamp)
        try await Self.store(app, Self.old.encoded)
        #expect(await model.dataTools.checkDxccStamp() == .store(current))
        #expect(try await Self.stored(app) == current.encoded)

        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        try await model.database.handle.run { try $0.repository.metaSet(DxccDataStamp.metaKey, "") }
        #expect(await model.dataTools.checkDxccStamp() == .store(current))
        #expect(model.messages.lines.isEmpty)
    }

    /// Opening a database checks it after „Otevřena databáze": the warning has the last word.
    @Test func openingAnOutdatedDatabaseWarns() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        let current: DxccDataStamp = try #require(model.contest.environment.dxccStamp)
        let first: String = model.database.currentName
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        try await Self.store(app, Self.old.encoded)

        await model.database.create("Druha")
        #expect(model.database.currentName == "Druha")
        #expect(try await Self.stored(app) == current.encoded, "the new empty database is stamped")
        #expect(model.messages.lines.isEmpty)

        await model.database.open(first)
        #expect(model.status.message == Self.warning(app, current: current))
        #expect(model.messages.lines.last?.text == Self.warning(app, current: current))
    }
}
