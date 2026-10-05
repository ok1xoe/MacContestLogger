import Foundation
import MCLCore

/// The TX interlock of the network log (`AppState.txAllowed` and `announceTx`, `AS:3111-3135`; N1MM „Interlock",
/// DXLog „Interlock and inband operation"): while another station of the network transmits, this one does not —
/// at all (`ALL`) or only on the same band (`SAME_BAND`).
///
/// Safety: the gate only **forbids**. It reads the peers the station network already holds in memory — no network
/// call, no wait, nothing that can fail — and answers `nil` (allowed) without a network, with the scope `NONE`, or
/// when no online peer transmits; a refusal is a status text and nothing is keyed. It is consulted by the CW, voice,
/// digital and tune paths before they transmit and by the CQ repeat; it is never consulted by the release of a PTT
/// or a carrier (Kotlin has no gate there either), and `announce` only schedules the status publish, so nothing here
/// ever delays the local release of the transmitter.
@MainActor
public final class TxInterlock {

    private let cluster: ClusterSyncModel
    private let config: ConfigModel

    public init(cluster: ClusterSyncModel, config: ConfigModel) {
        self.cluster = cluster
        self.config = config
    }

    /// `nil` = transmitting is allowed; otherwise the status to show (`tr("TX LOCKOUT: vysílá %s — nevysílám")`).
    public func gate() -> EntryStatus? {
        guard let network = cluster.stationNetwork else { return nil }
        let scope: Interlock.Scope = config.config.cluster.interlock
        if scope == .none {
            return nil
        }
        let band: String = cluster.ownBand()
        guard let blocker = Interlock.lockedBy(network.peers(), scope, band) else { return nil }
        return .tr("TX LOCKOUT: vysílá %s — nevysílám", .string(blocker))
    }

    /// After a transmission starts: the own status goes out at once (50 ms later), so the others lock out early.
    public func announce() {
        cluster.announceTx()
    }
}
