import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The chat window's own state (Kotlin `remember`): the recipient and the text.
@MainActor
final class ChatWindowState: ObservableObject {
    @Published var to: String = ""
    @Published var text: String = ""
}

/// Kotlin `ChatWindow` (`chat` 560×380, `ChatWindow.kt:39-94`): the lines (own ones lighter, the others semi-bold), the
/// recipient chips („Všem" and the stations) and the message field; Enter or „Odeslat" sends. Showing the window (and
/// a line arriving while it is open) reads the unread messages.
struct ChatWindowView: View {
    static let id = "chat"

    let host: AppHost

    @StateObject private var session = WindowSession(id: ChatWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 560, height: 380))
    @StateObject private var state = ChatWindowState()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: NetTexts.chatTitle,
                                                binder: session.binder))
                    .onAppear { app.network.markChatRead() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 400, minHeight: 240)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let lines: [ChatLine] = app.network.chat.lines
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            linesView(language: language, lines: lines)
            recipients(app)
            inputRow(app)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    private func linesView(language: LanguageModel, lines: [ChatLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(verbatim: NetTexts.chatRow(line, translator: language.translator))
                            .windowFont(13, weight: line.own ? .regular : .semibold)
                            .foregroundStyle(line.own ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
            }
            .onChange(of: lines.count) { _, count in
                if count > 0 {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .accessibilityIdentifier("chat.lines")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recipients(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        _ = app.cluster.revision
        let ids: [String] = app.cluster.peers.compactMap { $0.status.stationId }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                NetworkChip(label: language.tr(NetTexts.chatEveryone), selected: KotlinStrings.isBlank(state.to),
                            identifier: "chat.to.all") { state.to = "" }
                ForEach(ids, id: \.self) { id in
                    NetworkChip(label: id, selected: state.to == id, identifier: "chat.to.\(id)") { state.to = id }
                }
            }
        }
    }

    private func inputRow(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let connected: Bool = app.cluster.isRunning
        let placeholder: String = connected ? language.tr(NetTexts.chatPlaceholder)
                                            : language.tr(NetTexts.chatNotConnectedPlaceholder)
        return HStack(spacing: 6) {
            TextField(placeholder, text: Binding(get: { state.text }, set: { state.text = $0 }))
                .textFieldStyle(.roundedBorder)
                .windowFont(13)
                .onSubmit { send(app) }
                .accessibilityIdentifier("chat.input")
            Button(NetTexts.chatSend) { send(app) }
                .windowFont(13)
                .disabled(!connected || KotlinStrings.isBlank(state.text))
                .accessibilityIdentifier("chat.send")
        }
    }

    private func send(_ app: AppModel) {
        app.network.sendChat(to: state.to, text: state.text)
        state.text = ""
    }
}
