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
