import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `NetworkStatusWindow` (`netstatus` 760×320, `NetworkStatusWindow.kt:36-106`): the stations of the network
/// log with operator, type (RUN/RUN1/RUN2/MULT), band, mode, frequency, Run/S&P, pass frequency, QSO count, rates of
/// the last 10 / 100 QSOs, last QSO and transmit state, and a „Předat" button per station that passes the pending or
/// typed call to it. The „Sloupce" menu chooses and orders the columns (N1MM: right-click the header). Without a
/// cluster session only the explanation shows.
struct NetworkStatusWindowView: View {
    static let id = "netstatus"

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
            WindowTopBar(size: $session.fontSize, language: language) {
                columnsMenu(app)
            }
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
        let columns: [NetworkStationColumn] = app.network.columns
        let extras: [String: NetworkStationExtras] = app.network.stationExtras()
        Text(verbatim: NetTexts.thisStation(stationId: stationId, connected: cluster.connected, translator: translator))
            .windowFont(14, weight: .medium)
            .accessibilityIdentifier("netstatus.thisStation")
        Text(verbatim: NetTexts.passHint(pending: app.network.passPending, typedCall: cluster.sources.typedCall(),
                                         translator: translator))
            .windowFont(12)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("netstatus.passHint")
        if peers.isEmpty {
            Text(verbatim: language.tr(NetTexts.noOtherStation))
                .windowFont(13)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("netstatus.empty")
        }
        // Many columns are wider than the window: the table scrolls sideways, the rows downwards.
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                headerRow(language, columns: columns)
                Divider()
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(peers.enumerated()), id: \.offset) { _, peer in
                            row(app, peer: peer, passCall: passCall, columns: columns,
                                extras: extras[peer.status.stationId ?? ""] ?? NetworkStationExtras())
                        }
                    }
                }
            }
        }
    }

    private func headerRow(_ language: LanguageModel, columns: [NetworkStationColumn]) -> some View {
        HStack(spacing: 8) {
            ForEach(columns, id: \.self) { column in
                Text(verbatim: Self.title(column, language))
                    .windowFont(13, weight: .bold)
                    .frame(width: width(column), alignment: .leading)
            }
        }
    }

    static func title(_ column: NetworkStationColumn, _ language: LanguageModel) -> String {
        column.header.translate ? language.tr(column.header.text) : column.header.text
    }

    private func width(_ column: NetworkStationColumn) -> CGFloat {
        WindowFont.size(column.width, windowSize: session.fontSize)
    }

    /// N1MM's header right-click: show or hide a column, move it left or right, back to the default.
    private func columnsMenu(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let network: NetworkModel = app.network
        let shown: [NetworkStationColumn] = network.columns
        return Menu {
            ForEach(NetworkStationColumn.allCases.filter { $0 != .station }, id: \.self) { column in
                Toggle(isOn: Binding(get: { shown.contains(column) }, set: { _ in network.toggleColumn(column) })) {
                    Text(verbatim: Self.title(column, language))
                }
            }
            Divider()
            Menu(language.tr("Pořadí sloupců")) {
                ForEach(shown.filter { $0 != .station }, id: \.self) { column in
                    Menu(Self.title(column, language)) {
                        Button(language.tr("Posunout doleva")) { network.moveColumn(column, by: -1) }
                        Button(language.tr("Posunout doprava")) { network.moveColumn(column, by: 1) }
                    }
                }
            }
            Button(language.tr("Výchozí sloupce")) { network.resetColumns() }
        } label: {
            Text(verbatim: language.tr("Sloupce"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("netstatus.columns")
    }

    private func row(_ app: AppModel, peer: StationNetwork.Peer, passCall: String, columns: [NetworkStationColumn],
                     extras: NetworkStationExtras) -> some View {
        let translator: Translator = app.language.translator
        let color: Color = Self.color(peer)
        let target: String = peer.status.stationId ?? ""
        return HStack(spacing: 8) {
            ForEach(columns, id: \.self) { column in
                Text(verbatim: NetTexts.cell(column, peer, extras: extras, translator: translator))
                    .windowFont(13)
                    .foregroundStyle(color)
                    .frame(width: width(column), alignment: .leading)
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
