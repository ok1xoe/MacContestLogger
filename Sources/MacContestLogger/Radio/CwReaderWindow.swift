import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `CwReaderWindow` (`cwreader` 620×300, `CwReaderWindow.kt:42-117`, DXLog CW Reader): the tone field
/// (200…3000 Hz), the speed „~N WPM", „Vymazat", the audio error, up to six decoded calls (a click puts the call
/// into the call field), the decoded text (or a hint while there is none) scrolled to its end, and the hint line.
/// The window holds the receiver audio while it is open.
struct CwReaderWindowView: View {
    static let id = "cwreader"

    let host: AppHost

    @StateObject private var session = WindowSession(id: CwReaderWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 620, height: 300))
    @StateObject private var holder = WindowModelHolder<CwReaderModel>()

    var body: some View {
        Group {
            if let app = host.model {
                let model: CwReaderModel = holder.model { app.makeCwReader() }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "CW Reader",
                                                binder: session.binder))
                    .task { await model.open() }
                    .onDisappear { model.close() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }

    private func content(_ app: AppModel, _ model: CwReaderModel) -> some View {
        let language: LanguageModel = app.language
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            toneRow(language, model)
            if let error = model.error {
                Text(verbatim: RadioWindowTexts.readerAudioError(error))
                    .windowFont(14)
                    .foregroundStyle(Color(domain: DomainColors.dupe))
            }
            HStack(spacing: 6) {
                ForEach(model.calls, id: \.self) { call in
                    SettingsChip(label: call, selected: false) { model.take(call) }
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    Text(verbatim: model.text.isEmpty
                         ? RadioWindowTexts.readerPlaceholder(model.pitchText)
                            .text(language.translator, decimalSeparator: language.decimalSeparator)
                         : model.text)
                        .windowFont(16, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .onChange(of: model.text) {
                    proxy.scrollTo(Self.bottom, anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)
            Text(verbatim: language.tr("Klik na volačku ji vloží do pole volačky."))
                .windowFont(11)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    private static let bottom = "bottom"

    /// „Tón (Hz)", „~N WPM", „Vymazat".
    private func toneRow(_ language: LanguageModel, _ model: CwReaderModel) -> some View {
        let tone = Binding<String>(get: { model.pitchText }, set: { model.pitchChanged($0) })
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: language.tr("Tón (Hz)"))
                    .windowFont(11)
                    .foregroundStyle(.secondary)
                TextField(text: tone) {
                    Text(verbatim: language.tr("Tón (Hz)"))
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .windowFont(14)
            }
            .frame(width: 120)
            Text(verbatim: RadioWindowTexts.readerWpm(model.wpm))
                .windowFont(16)
            Button {
                model.clear()
            } label: {
                Text(verbatim: "Vymazat").windowFont(14)
            }
            .buttonStyle(.borderless)
        }
    }
}
