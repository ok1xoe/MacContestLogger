import Foundation
import MCLCore

extension DxClusterModel {

    /// Kotlin `syncParallelClusters()` (`AS:351-369`): at start-up (the favourites with „Souběžně" connect
    /// right after the app starts, without a window or a contest, and log in by themselves after 1,500 ms) and after
    /// every Settings OK (the port `parallelClusters`).
    ///
    /// 1. Connections that are neither connected nor connecting (lost, failed) are dropped — the plan opens them again.
    /// 2. `ParallelClusterPlan` over the favourites, the open keys and the main connection's key.
    /// 3. Each key to close: dropped from the map and `disconnect(tr("Souběžné spojení ukončeno"))` on its lane (a
    ///    late state of it no longer reaches `parallel`).
    /// 4. Each favourite to open: a session over the shared buffer and log with `tag = name.ifBlank { host }`, wired
    ///    like the main one, `connect(fav, autoLogin = true)`.
    /// Nothing after the quit's `shutdown()`.
    public func syncParallelClusters() {
        guard !closed else { return }
        for key in parallelKeys {
            guard let lane = parallelLanes[key]?.lane else { continue }
            let state: DxClusterSession.Snapshot = lane.session.snapshot
            if !lane.connectPending && !state.connected && !state.connecting {
                dropParallel(key)
            }
        }
        let primary: String? = mainLane.session.snapshot.currentFavorite?.connectionKey
        let plan: ParallelClusterPlan.Plan = ParallelClusterPlan.plan(config.config.dxCluster.favorites,
                                                                       open: parallelKeys, primary: primary)
        let ended: String = language.tr("Souběžné spojení ukončeno")
        for key in plan.toDisconnect {
            guard let lane = dropParallel(key) else { continue }
            lane.run { session in try session.disconnect(ended) }
        }
        for fav in plan.toConnect {
            let tag: String = KotlinStrings.isBlank(fav.name) ? fav.host : fav.name
            let created: (token: Int, lane: ClusterLane) = makeLane(tag: tag, name: "dxcluster-parallel")
            let key: String = fav.connectionKey
            parallelLanes[key] = created
            parallelKeys.append(key)
            parallel[key] = created.lane.session.snapshot
            created.lane.connect(fav, autoLogin: true)
        }
    }

    /// One favourite the DX Cluster window offers a parallel switch for.
    public struct ParallelChoice: Equatable, Identifiable, Sendable {
        /// Index in the configured favourites (names may repeat).
        public let id: Int
        public let favorite: DxClusterFavorite
        public let isOn: Bool
        /// `✓` / `…` / `✗` for a switched-on favourite, `nil` when it is off.
        public let mark: String?
    }

    /// The favourites that can run in parallel: all with a server except the one the main connection uses (no
    /// duplicate session with the same login) and later duplicates of the same server.
    public var parallelChoices: [ParallelChoice] {
        let primary: String? = mainLane.session.snapshot.currentFavorite?.connectionKey
        var seen: Set<String> = []
        var result: [ParallelChoice] = []
        for (index, fav) in config.config.dxCluster.favorites.enumerated() {
            let key: String = fav.connectionKey
            guard !KotlinStrings.isBlank(fav.host), key != primary, seen.insert(key).inserted else { continue }
            result.append(ParallelChoice(id: index, favorite: fav, isOn: fav.parallel,
                                         mark: fav.parallel ? ClusterTexts.stateMark(parallel[key]) : nil))
        }
        return result
    }

    /// The window's switch: sets the favourite's `parallel` flag (as Settings → DX Cluster → „Souběžně"), saves the
    /// configuration and runs the same sync (closes it with „Souběžné spojení ukončeno", or connects and logs in).
    /// Ignored for the favourite of the main connection, a blank server or an unknown index.
    public func setParallel(_ on: Bool, favoriteAt index: Int) {
        guard !closed, config.config.dxCluster.favorites.indices.contains(index) else { return }
        let fav: DxClusterFavorite = config.config.dxCluster.favorites[index]
        guard !KotlinStrings.isBlank(fav.host),
              fav.connectionKey != mainLane.session.snapshot.currentFavorite?.connectionKey else { return }
        guard fav.parallel != on else { return }
        config.config.dxCluster.favorites[index].parallel = on
        config.saveSilently()
        syncParallelClusters()
    }

    /// The parallel connections' states in the map's order (the DX Cluster window's summary).
    public var parallelSnapshots: [DxClusterSession.Snapshot] {
        parallelKeys.compactMap { parallel[$0] }
    }

    /// Removes `key` from the map (its lane is kept until it has settled); `nil` when it was not open.
    @discardableResult
    private func dropParallel(_ key: String) -> ClusterLane? {
        guard let entry = parallelLanes.removeValue(forKey: key) else { return nil }
        parallelKeys.removeAll { $0 == key }
        parallel[key] = nil
        let lane: ClusterLane = entry.lane
        retiredLanes.append(lane)
        // Kept until its queued work and threads have finished (the quit waits for it meanwhile), then forgotten.
        Task { [weak self] in
            await lane.idle()
            self?.retiredLanes.removeAll { $0 === lane }
        }
        return lane
    }
}
