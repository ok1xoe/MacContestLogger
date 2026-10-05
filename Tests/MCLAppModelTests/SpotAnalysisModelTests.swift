import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The rebuild triggers of the current spot analyzer: each one gives a new
/// analyzer that sees the change and raises `revision`; with nothing changed the cached one is reused.
@MainActor @Suite struct SpotAnalysisModelTests {

    /// The analysis after the grid data have loaded (so trigger 6 does not interfere with the others).
    static func loaded(_ app: TestApp) async -> SpotAnalysisModel {
        let analysis: SpotAnalysisModel = app.model.spotAnalysis
        _ = analysis.current()
        await app.model.callbook.settle()
        _ = analysis.current()
        return analysis
    }

    @Test func nothingChangedReusesTheAnalyzer() async throws {
        let app = try await TestApp.make()
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        let builds: Int = analysis.buildCount
        _ = analysis.current()
        _ = analysis.current()
        #expect(analysis.buildCount == builds)
    }

    /// Trigger 1: an activation rebuilds and clears the grid decision log.
    @Test func activationRebuildsAndResetsTheGridLog() async throws {
        let app = try await TestApp.make()
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        #expect(analysis.current().definition == nil)
        #expect(analysis.gridLog.claim("OH2AS"))
        #expect(!analysis.gridLog.claim("OH2AS"))
        let revision: Int = analysis.revision
        try await app.startCqWwCw()
        #expect(analysis.revision > revision)
        #expect(analysis.current().definition?.id == "cq-ww-cw")
        #expect(analysis.gridLog.claim("OH2AS"))
    }

    /// Trigger 2: a deactivation.
    @Test func deactivationRebuilds() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        #expect(analysis.current().definition != nil)
        let revision: Int = analysis.revision
        app.model.contest.deactivate()
        await runMainQueue()
        #expect(analysis.revision > revision)
        #expect(analysis.current().definition == nil)
    }

    /// Trigger 3: a rescore adopts a fresh session.
    @Test func aRescoreRebuilds() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        await app.logContestQso(call: "DL1ABC", zone: "14")
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        let before: UInt64 = analysis.current().sessionGeneration
        app.model.contest.requestRescore(manual: true)
        await app.model.contest.settleRescore()
        let after: SpotAnalyzer = analysis.current()
        #expect(after.sessionGeneration != before)
        #expect(after.isCurrent(for: app.model.contest.runtime))
    }

    /// Trigger 4: my station call or grid.
    @Test func aStationChangeRebuilds() async throws {
        let app = try await TestApp.make()
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        let revision: Int = analysis.revision
        app.model.config.config.station.gridSquare = "JO70"
        await runMainQueue()
        #expect(analysis.revision > revision)
        #expect(analysis.current().myGrid == "JO70")
        app.model.config.config.station.call = "OK1XXX"
        #expect(analysis.current().myCall == "OK1XXX")
    }

    /// Trigger 5: a band-data reload.
    @Test func aBandDataReloadRebuilds() async throws {
        let app = try await TestApp.make()
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        let builds: Int = analysis.buildCount
        let revision: Int = analysis.revision
        await app.model.contest.reloadBandData()
        await runMainQueue()
        #expect(analysis.revision > revision)
        _ = analysis.current()
        #expect(analysis.buildCount == builds + 1)
    }

    /// Trigger 6: the offline grid data arrive after the first analysis.
    @Test func theGridDataRebuild() async throws {
        let app = try await TestApp.make()
        let analysis: SpotAnalysisModel = app.model.spotAnalysis
        #expect(analysis.current().gridDatabase.size == 0)
        let revision: Int = analysis.revision
        await app.model.callbook.settle()
        await runMainQueue()
        #expect(analysis.revision > revision)
        #expect(analysis.current().gridDatabase.size > 0)
    }

    /// A contest-data reload builds a new runtime (Kotlin: a new controller with an empty grid log).
    @Test func aNewRuntimeRebuildsAndResetsTheGridLog() async throws {
        let app = try await TestApp.make()
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        let runtime: ContestRuntime = app.model.contest.runtime
        #expect(analysis.gridLog.claim("OH2AS"))
        let builds: Int = analysis.buildCount
        await app.model.contest.reloadContestData()
        try #require(app.model.contest.runtime !== runtime)
        await runMainQueue()
        _ = analysis.current()
        #expect(analysis.buildCount == builds + 1)
        #expect(analysis.gridLog.claim("OH2AS"))
    }

    /// Trigger 7: the callbook closure reads the live cache — a new record needs no rebuild.
    @Test func newCallbookRecordsNeedNoRebuild() async throws {
        let app = try await TestApp.make()
        let analysis: SpotAnalysisModel = await Self.loaded(app)
        let analyzer: SpotAnalyzer = analysis.current()
        let builds: Int = analysis.buildCount
        let record = HamQthRecord(grid: "KP20", name: "", cqZone: "15", ituZone: "")
        app.model.callbook.cache.store("OH2AS", record, generation: app.model.callbook.cache.generation)
        #expect(analyzer.callbook("oh2as") == record)
        _ = analysis.current()
        #expect(analysis.buildCount == builds)
    }
}
