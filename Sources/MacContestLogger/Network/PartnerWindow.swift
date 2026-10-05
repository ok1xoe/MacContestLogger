import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The partner window's own state (Kotlin `remember`): the chosen runner and the call.
@MainActor
final class PartnerWindowState: ObservableObject {
    @Published var target: String = ""
    @Published var call: String = ""
}

/// Kotlin `PartnerWindow` (`partner` 520×280, `PartnerWindow.kt:38-93`): the second operator picks an online runner,
/// sees what the runner types and where, and sends calls into the runner's stack.
struct PartnerWindowView: View {
    static let id = "partner"

    let host: AppHost

    @StateObject private var session = WindowSession(id: PartnerWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 520, height: 280))
    @StateObject private var state = PartnerWindowState()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: NetTexts.partnerTitle,
                                                binder: session.binder))
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        _ = app.cluster.revision
        return VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $session.fontSize, language: language)
            if app.cluster.isRunning {
                runner(app)
            } else {
                Text(verbatim: language.tr(NetTexts.partnerNotConnected))
                    .windowFont(13)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("partner.notConnected")
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    @ViewBuilder private func runner(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let peers: [StationNetwork.Peer] = app.cluster.peers.filter { $0.online }
        Text(verbatim: language.tr(NetTexts.partnerRunnerLabel))
            .windowFont(14, weight: .medium)
        HStack(spacing: 6) {
            if peers.isEmpty {
                Text(verbatim: language.tr(NetTexts.partnerNoOnline))
                    .windowFont(13)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("partner.noOnline")
            }
            ForEach(peers.compactMap { $0.status.stationId }, id: \.self) { id in
                NetworkChip(label: id, selected: state.target == id, identifier: "partner.runner.\(id)") {
                    state.target = id
                }
            }
        }
        if let selected = peers.first(where: { $0.status.stationId == state.target }) {
            Text(verbatim: NetTexts.partnerLine(selected.status, translator: language.translator))
                .windowFont(13, design: .monospaced)
                .accessibilityIdentifier("partner.line")
        }
        HStack(spacing: 6) {
            TextField(language.tr(NetTexts.partnerPlaceholder),
                      text: Binding(get: { state.call }, set: { state.call = NetworkModel.partnerCallFilter($0) }))
                .textFieldStyle(.roundedBorder)
                .windowFont(13)
                .onSubmit { send(app) }
                .accessibilityIdentifier("partner.input")
            Button(language.tr(NetTexts.partnerButton)) { send(app) }
                .windowFont(13)
                .disabled(KotlinStrings.isBlank(state.target) || KotlinStrings.isBlank(state.call))
                .accessibilityIdentifier("partner.stack")
        }
        Text(verbatim: language.tr(NetTexts.partnerHint))
            .windowFont(10)
            .foregroundStyle(.secondary)
    }

    private func send(_ app: AppModel) {
        app.network.stackCall(to: state.target, call: state.call)
        state.call = ""
    }
}
