import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `NetworkStatusWindow` (`netstatus` 760×320, `NetworkStatusWindow.kt:36-106`): the stations of the network
/// log with operator, band, mode, frequency, Run/S&P, QSO count and transmit state, and a „Předat" button per station
/// that passes the pending or typed call to it. Without a cluster session only the explanation shows.
struct NetworkStatusWindowView: View {
    static let id = "netstatus"

    /// Kotlin `HEADERS` widths (dp), in the order of `NetTexts.headers`.
    static let columnWidths: [Double] = [90, 90, 60, 60, 90, 50, 50, 130]

    let host: AppHost

    @StateObject private var session = WindowSession(id: NetworkStatusWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 760, height: 320))

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: NetTexts.windowTitle,
                                                binder: session.binder))
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 520, minHeight: 200)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let cluster: ClusterSyncModel = app.cluster
        // Kotlin reads `netRevision` to redraw on every change.
        _ = cluster.revision
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            if let stationId = cluster.stationId {
                stations(app, stationId: stationId)
            } else {
                Text(verbatim: language.tr(NetTexts.notConnected))
                    .windowFont(13)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("netstatus.notConnected")
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    @ViewBuilder private func stations(_ app: AppModel, stationId: String) -> some View {
        let language: LanguageModel = app.language
        let cluster: ClusterSyncModel = app.cluster
        let translator: Translator = language.translator
        let passCall: String = NetMessages.defaultPassCall(pending: app.network.passPending,
                                                           typedCall: cluster.sources.typedCall())
        let peers: [StationNetwork.Peer] = cluster.peers
        Text(verbatim: NetTexts.thisStation(stationId: stationId, connected: cluster.connected, translator: translator))
            .windowFont(14, weight: .medium)
            .accessibilityIdentifier("netstatus.thisStation")
        Text(verbatim: NetTexts.passHint(pending: app.network.passPending, typedCall: cluster.sources.typedCall(),
                                         translator: translator))
            .windowFont(12)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("netstatus.passHint")
        headerRow(language)
        Divider()
        if peers.isEmpty {
            Text(verbatim: language.tr(NetTexts.noOtherStation))
                .windowFont(13)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("netstatus.empty")
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(peers.enumerated()), id: \.offset) { _, peer in
                    row(app, peer: peer, passCall: passCall)
                }
            }
        }
    }

    private func headerRow(_ language: LanguageModel) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(NetTexts.headers.enumerated()), id: \.offset) { index, header in
                Text(verbatim: header.translate ? language.tr(header.text) : header.text)
                    .windowFont(13, weight: .bold)
                    .frame(width: width(index), alignment: .leading)
            }
        }
    }

    private func width(_ index: Int) -> CGFloat {
        WindowFont.size(Self.columnWidths[index], windowSize: session.fontSize)
    }

    private func row(_ app: AppModel, peer: StationNetwork.Peer, passCall: String) -> some View {
        let translator: Translator = app.language.translator
        let cells: [String] = NetTexts.peerCells(peer, translator: translator)
        let color: Color = Self.color(peer)
        let target: String = peer.status.stationId ?? ""
        return HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(verbatim: cell)
                    .windowFont(13)
                    .foregroundStyle(color)
                    .frame(width: width(index), alignment: .leading)
            }
            Button(app.language.tr(NetTexts.passButton)) {
                app.network.passCall(to: target, call: passCall)
            }
            .windowFont(13)
            .disabled(KotlinStrings.isBlank(passCall) || !peer.online)
            .accessibilityIdentifier("netstatus.pass.\(target)")
        }
        .padding(.vertical, 2)
    }

    /// A silent station is grey, a transmitting one red, the rest the normal text colour (Kotlin `NS:75-79`).
    static func color(_ peer: StationNetwork.Peer) -> Color {
        if !peer.online {
            return .secondary
        }
        if peer.status.transmitting {
            return Color(domain: DomainColors.dupe)
        }
        return .primary
    }
}
