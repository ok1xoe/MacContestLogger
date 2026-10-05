import Carbon.HIToolbox
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `CwKeyboardWindow` (`cwkeyboard` 560×220, `CwKeyboardWindow.kt:41-93`, Ctrl+K): „Po slovech" / „Po Enteru",
/// „Stop (Esc)", the field (upper case, monospaced) whose finished words go out as CW, Enter sends the rest, Esc stops
/// sending and clears; the hint line says „vysílá se…" while a CW message is out. The field has the focus when the
/// window opens.
struct CwKeyboardWindowView: View {
    static let id = "cwkeyboard"

    let host: AppHost

    @StateObject private var session = WindowSession(id: CwKeyboardWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 560, height: 220))
    @StateObject private var holder = WindowModelHolder<CwKeyboardModel>()
    @StateObject private var keys = WindowKeyMonitor()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if let app = host.model {
                let model: CwKeyboardModel = holder.model { app.makeCwKeyboard() }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "CW z klávesnice",
                                                binder: session.binder))
                    .background(WindowAccessor { window in
                        keys.handler = { key in Self.handle(key, model: model) }
                        keys.install(window: window)
                    })
                    .onAppear { fieldFocused = true }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 320, minHeight: 160)
    }

    /// Kotlin `onPreviewKeyEvent` of the field: Enter and Esc on the press, consumed.
    private static func handle(_ key: WindowKey, model: CwKeyboardModel) -> Bool {
        guard key.down else { return false }
        switch Int(key.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.enter()
            return true
        case kVK_Escape:
            model.escape()
            return true
        default:
            return false
        }
    }

    private func content(_ app: AppModel, _ model: CwKeyboardModel) -> some View {
        let language: LanguageModel = app.language
        let text = Binding<String>(get: { model.text }, set: { model.textChanged($0) })
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            HStack(spacing: 6) {
                SettingsChip(label: "Po slovech", selected: model.wordByWord) { model.wordByWord = true }
                SettingsChip(label: "Po Enteru", selected: !model.wordByWord) { model.wordByWord = false }
                Button {
                    model.escape()
                } label: {
                    Text(verbatim: "Stop (Esc)").windowFont(14)
                }
                .buttonStyle(.borderless)
            }
            TextField(text: text, axis: .vertical) {
                Text(verbatim: language.tr("Piš text — makra jako v F-klávesách (* = moje volačka, ! = jeho)"))
            }
            .textFieldStyle(.plain)
            .windowFont(16, design: .monospaced)
            .focused($fieldFocused)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
            Text(verbatim: model.isSending ? language.tr("vysílá se…")
                : language.tr("Ctrl+K otevře okno ze zadávacího okna"))
                .windowFont(11)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }
}
