import Foundation
import MCLCore

/// N1MM's cluster queries about one station and its spot history (the band map's spot menu and the DX Cluster
/// window's right click on a spot line).
extension DxClusterModel {

    /// Sends `query` about `call` to the main connection (formatted for the node); the status says when the cluster
    /// is not connected. A text that is no callsign sends nothing.
    public func query(_ query: ClusterCallQuery, call: String) {
        guard !closed else { return }
        guard main.connected else {
            status.show(ContestMessage("DX Cluster není připojen"))
            return
        }
        guard let command = query.command(call: call, software: software) else { return }
        send(command)
    }

    /// The received spots of `call`, oldest first.
    public func history(of call: String) -> [SpotHistory.Entry] {
        spotHistory.entries(of: call)
    }

    /// My own call (the station call) for „My call spot history".
    public var myCall: String {
        config.config.station.call
    }
}
