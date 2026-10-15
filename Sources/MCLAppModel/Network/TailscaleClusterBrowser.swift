import Foundation
import MCLCore

/// Looks for the multi-op cluster (its MQTT broker) among the peers of the Tailscale tailnet and answers once on a
/// thread of its own. Only started by the operator (Settings → Cluster → „Najít cluster přes Tailscale"); never under
/// `MCL_INERT_NETWORK`.
public typealias TailscaleClusterDiscoverer = @Sendable (_ ports: [TailscaleProbePort],
                                                         _ done: @escaping @Sendable (TailscaleClusterSearch.Outcome) -> Void)
    -> Void

enum TailscaleClusterBrowser {

    /// The inert discoverer: answers „not installed" at once, runs nothing.
    @Sendable static func inert(_ ports: [TailscaleProbePort],
                                _ done: @escaping @Sendable (TailscaleClusterSearch.Outcome) -> Void) {
        done(.notInstalled)
    }

    /// `tailscale status --json`, then the MQTT probe of every online peer (blocking, so on its own thread).
    @Sendable static func live(_ ports: [TailscaleProbePort],
                               _ done: @escaping @Sendable (TailscaleClusterSearch.Outcome) -> Void) {
        let thread = Thread {
            done(TailscaleClusterSearch(provider: TailscaleCli()).run(ports: ports))
        }
        thread.name = "mcl.tailscale-cluster-search"
        thread.start()
    }
}
