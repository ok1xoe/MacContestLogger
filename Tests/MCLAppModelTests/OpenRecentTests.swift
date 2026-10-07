import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// File → Open recent: the last 9 opened contests of the open database, kept in the database, opened like the Open
/// contest dialog does, cleared by „Vymazat seznam".
@MainActor @Suite struct OpenRecentTests {

    private static func recentEntries(_ app: AppModel) throws -> [MenuEntry] {
        func find(_ entries: [MenuEntry]) -> MenuEntry? {
            for entry in entries {
                if entry.id == MenuModel.recentId {
                    return entry
                }
                if let found = find(entry.children) {
                    return found
                }
            }
            return nil
        }
        return try #require(find(app.menu.entries())).children
    }

    private func start(_ app: TestApp, _ definition: String) async throws {
        let started: Bool = await app.model.contest.createAndStart(definitionId: definition, setup: ContestSetup())
        try #require(started, "activation failed: \(app.model.status.message)")
    }

    @Test func aFreshDatabaseHasOneDisabledLine() async throws {
        let app = try await TestApp.make()
        let children: [MenuEntry] = try Self.recentEntries(app.model)
        #expect(children.map(\.id) == ["recent.none"])
        #expect(!children[0].enabled)
        #expect(app.model.contest.recent.isEmpty)
    }

    @Test func openedContestsAreListedNewestFirstAndOpenFromTheMenu() async throws {
        let app = try await TestApp.make()
        try await start(app, "cq-ww-cw")
        let first: String = try #require(app.model.contest.activeId)
        try await start(app, "cq-ww-ssb")
        let second: String = try #require(app.model.contest.activeId)
        #expect(app.model.contest.recent.map(\.contestId) == [second, first])

        let children: [MenuEntry] = try Self.recentEntries(app.model)
        #expect(children.map(\.id) == [MenuModel.recentOpenPrefix + second, MenuModel.recentOpenPrefix + first,
                                       "sep.recent", "recent.clear"])
        #expect(children[0].title.contains("CQ WW"))
        #expect(children.filter { !$0.isSeparator }.allSatisfy { $0.enabled })

        // Choosing the older one opens it (the path of the Open contest dialog) and moves it to the front.
        #expect(MenuActions.perform(MenuModel.recentOpenPrefix + first, app: app.model) == nil)
        await app.model.contest.recentOpenTask?.value
        #expect(app.model.contest.activeId == first)
        #expect(app.model.contest.recent.map(\.contestId) == [first, second])
    }

    @Test func theListKeepsTheLastNine() async throws {
        let app = try await TestApp.make()
        var ids: [String] = []
        for _ in 1...11 {
            try await start(app, "cq-ww-cw")
            ids.insert(try #require(app.model.contest.activeId), at: 0)
        }
        #expect(app.model.contest.recent.map(\.contestId) == Array(ids.prefix(9)))
        let children: [MenuEntry] = try Self.recentEntries(app.model)
        #expect(children.count == 9 + 2)
    }

    @Test func clearEmptiesTheListAndKeepsTheContests() async throws {
        let app = try await TestApp.make()
        try await start(app, "cq-ww-cw")
        try await start(app, "cq-ww-ssb")
        #expect(MenuActions.perform("recent.clear", app: app.model) == nil)
        await app.model.contest.clearRecent()
        #expect(app.model.contest.recent.isEmpty)
        #expect(try Self.recentEntries(app.model).map(\.id) == ["recent.none"])
        #expect(await app.model.contest.browserRows().count == 2)
        await app.model.contest.refreshRecent()
        #expect(app.model.contest.recent.isEmpty)
    }

    @Test func theListSurvivesARestart() async throws {
        let first = try await TestApp.make()
        try await start(first, "cq-ww-cw")
        let one: String = try #require(first.model.contest.activeId)
        try await start(first, "cq-ww-ssb")
        let two: String = try #require(first.model.contest.activeId)
        await first.model.shutdown()
        let again = AppModel.Environment(dataDir: first.dataDir, dxccDir: try Fixtures.dxccDir(in: first.dir),
                                         rescoreClock: ManualClock(), geometryClock: ManualClock(),
                                         backupClock: ManualClock())
        let second: AppModel = try await AppModel.bootstrap(again)
        #expect(second.contest.recent.map(\.contestId) == [two, one])
        await second.shutdown()
    }

    @Test func theListBelongsToTheDatabase() async throws {
        let app = try await TestApp.make()
        try await start(app, "cq-ww-cw")
        let id: String = try #require(app.model.contest.activeId)
        let original: String = app.model.database.currentName
        await app.model.database.create("other")
        await app.model.contest.settleActivations()
        #expect(app.model.contest.recent.isEmpty)
        #expect(try Self.recentEntries(app.model).map(\.id) == ["recent.none"])
        await app.model.database.open(original)
        await app.model.contest.settleActivations()
        #expect(app.model.contest.recent.map(\.contestId) == [id])
    }

    @Test func aContestRemovedFromTheDatabaseDropsOut() async throws {
        let app = try await TestApp.make()
        try await start(app, "cq-ww-cw")
        let id: String = try #require(app.model.contest.activeId)
        try await app.model.database.handle.run { access in
            let stored = RecentContests.decode(try access.repository.metaGet(RecentContests.metaKey))
            try access.repository.metaSet(RecentContests.metaKey,
                                          RecentContests.encode(["gone"] + stored))
        }
        await app.model.contest.refreshRecent()
        #expect(app.model.contest.recent.map(\.contestId) == [id])
    }
}
