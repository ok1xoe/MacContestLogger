import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The parallel DX cluster connections: they connect at start-up without a window, log in by
/// themselves after 1,500 ms, share the buffer and the traffic log (`[tag] `), lost ones are dropped and reopened by
/// the plan, removed favourites end with „Souběžné spojení ukončeno", and the main connection is not duplicated.
@MainActor @Suite struct ParallelClustersTests {

    @Test func aParallelFavouriteConnectsAtStartAndLogsInByItself() async throws {
        let sleeper = TestSleeper()
        sleeper.hold()
        let spot = try await SpotApp.make(configure: { config, server in
            config.dxCluster.favorites = [server.favorite(name: "RBN", login: "OK1XXX", parallel: true)]
        }, adjust: { environment in
            environment.network.makeSession = NetworkPorts.sessions(sleep: sleeper.sleep)
        })
        await eventually("connected") { spot.dx.parallel.values.first?.connected == true }
        #expect(spot.dx.parallelKeys == ["127.0.0.1:\(spot.server.port)"])
        #expect(!spot.dx.connected)
        await eventually("auto-login wait") { sleeper.requests == [1_500] }
        #expect(spot.server.lines(0).isEmpty)
        sleeper.release()
        await eventually("login sent") { spot.server.lines(0) == ["OK1XXX"] }

        spot.server.push("DX de OK1ABC:     14030.0  OH2AS         CQ up 2          1234Z")
        await eventually("shared buffer") { spot.dx.spots.snapshot().map(\.dxCall) == ["OH2AS"] }
        await eventually("tagged line") {
            spot.logText.contains("[RBN] DX de OK1ABC:     14030.0  OH2AS")
        }
        spot.server.push("OK1XXX de RBN >")
        await eventually("logged in") { spot.dx.parallel.values.first?.loggedIn == true }
        #expect(ClusterTexts.parallelItem(spot.dx.parallelSnapshots[0]) == "RBN ✓")
    }

    @Test func aLostParallelConnectionIsReopenedByThePlan() async throws {
        let spot = try await SpotApp.make { config, server in
            config.dxCluster.favorites = [server.favorite(name: "", parallel: true)]
        }
        await eventually("connected") { spot.dx.parallel.values.first?.connected == true }
        await eventually("accepted") { spot.server.connectionCount == 1 }
        spot.server.dropAll()
        await eventually("lost") { spot.dx.parallel.values.first?.connected == false }
        spot.dx.syncParallelClusters()
        await eventually("reopened") { spot.server.connectionCount == 2 }
        await eventually("connected again") { spot.dx.parallel.values.first?.connected == true }
        #expect(spot.dx.parallelKeys.count == 1)
        await spot.settle()
        #expect(spot.logText.contains("Spojení ztraceno: DX cluster ukončil spojení"))
    }

    /// A queued connect counts as connecting (Kotlin sets `connecting` synchronously): plans run back to back open
    /// one connection, not one per plan.
    @Test func backToBackPlansOpenOneConnection() async throws {
        let spot = try await SpotApp.make()
        spot.model.config.config.dxCluster.favorites = [spot.server.favorite(name: "RBN", parallel: true)]
        spot.dx.syncParallelClusters()
        spot.dx.syncParallelClusters()
        spot.dx.syncParallelClusters()
        await eventually("connected") { spot.dx.parallel.values.first?.connected == true }
        await spot.settle()
        #expect(spot.dx.parallelKeys.count == 1)
        #expect(spot.server.connectionCount == 1)
        await eventually("dropped lanes pruned") { spot.dx.retiredLanes.isEmpty }
    }

    @Test func aRemovedFavouriteIsDisconnected() async throws {
        let spot = try await SpotApp.make { config, server in
            config.dxCluster.favorites = [server.favorite(name: "Skimmer", parallel: true)]
        }
        await eventually("connected") { spot.dx.parallel.values.first?.connected == true }
        spot.model.config.config.dxCluster.favorites = []
        spot.dx.syncParallelClusters()
        #expect(spot.dx.parallel.isEmpty)
        #expect(spot.dx.parallelKeys.isEmpty)
        await spot.settle()
        #expect(spot.logText.contains("· Souběžné spojení ukončeno"))
        await eventually("closed") { spot.server.openConnections == 0 }
        // A late state of the dropped connection does not come back.
        #expect(spot.dx.parallel.isEmpty)
        await eventually("dropped lane pruned") { spot.dx.retiredLanes.isEmpty }
    }

    @Test func theMainConnectionIsNotDuplicated() async throws {
        let spot = try await SpotApp.make()
        let fav: DxClusterFavorite = spot.server.favorite(name: "Node", parallel: true)
        await spot.connectMain(fav)
        spot.model.config.config.dxCluster.favorites = [fav]
        spot.dx.syncParallelClusters()
        #expect(spot.dx.parallel.isEmpty)
        await spot.settle()
        #expect(spot.server.connectionCount == 1)
    }

    @Test func parallelSelfSpotsAndMyCallFollowSettings() async throws {
        let spot = try await SpotApp.make { config, server in
            config.dxCluster.favorites = [server.favorite(name: "RBN", parallel: true)]
        }
        await eventually("connected") { spot.dx.parallel.values.first?.connected == true }
        spot.server.push(DxClusterModelTests.ownRbnSpot)
        await eventually("message") { spot.model.messages.lines.count == 1 }

        let settings: SettingsModel = spot.model.settings
        settings.open()
        await settings.settle()
        var draft: ConfigurerDraft = try #require(settings.draft)
        draft.call = "OK1XXX"
        settings.draft = draft
        #expect(await settings.confirm())
        await spot.settle()
        let key: String = try #require(spot.dx.parallelKeys.first)
        #expect(spot.dx.parallelLanes[key]?.lane.session.myCall == "OK1XXX")
        #expect(spot.dx.mainLane.session.myCall == "OK1XXX")
        spot.server.push(DxClusterModelTests.ownRbnSpot)
        await spot.settle()
        #expect(spot.model.messages.lines.count == 1)
    }
}
