import Foundation
import MCLCore

/// The band map's spot menu items of the N1MM Telnet window and View menu: the cluster queries about the spotted
/// station, its spot history and my own call's, and „Jump to this spot" (the DX Cluster window's right click).
extension BandmapModel {

    /// A cluster query about the spot's station (status when the cluster is not connected).
    public func query(_ query: ClusterCallQuery, call: String) {
        guard let cluster = dxCluster else { return }
        cluster.query(query, call: call)
    }

    /// „Show Telnet history" of `call`.
    public func showHistory(of call: String) {
        historyCall = KotlinStrings.trim(call).uppercased()
    }

    /// „My call spot history".
    public func showMyHistory() {
        guard let call = dxCluster?.myCall, !KotlinStrings.isBlank(call) else {
            statusLine?.show(ContestMessage("Není zadaná vlastní značka (Nastavení → Stanice)"))
            return
        }
        showHistory(of: call)
    }

    /// N1MM „Jump to this spot": the active radio to the spot, as a click on it in the band map.
    public func jumpToSpot(_ spot: DxSpot) {
        rig.tuneToSpot(spot, fillCall: !config.config.dxCluster.callFrame)
    }
}
