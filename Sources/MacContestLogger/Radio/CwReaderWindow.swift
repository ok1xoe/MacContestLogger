import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `CwReaderWindow` (`cwreader` 620×300, `CwReaderWindow.kt:42-117`, DXLog CW Reader): the tone field
/// (200…3000 Hz), the speed „~N WPM", „Vymazat", the audio error, up to six decoded calls (a click puts the call
/// into the call field), the decoded text (or a hint while there is none) scrolled to its end, and the hint line.
/// The window holds the receiver audio while it is open.
///
/// `radio` 1 (`cwreader2`, N1MM's second reader in SO2V / SO2R) decodes radio 2's audio input — chosen in the window —
/// and its calls go into the VFO B / rig 2 window.
struct CwReaderWindowView: View {
    static let id = "cwreader"
    static let id2 = "cwreader2"

    let host: AppHost
    let radio: Int

    @StateObject private var session: WindowSession
    @StateObject private var holder = WindowModelHolder<CwReaderModel>()

    init(host: AppHost, radio: Int = 0) {
        self.host = host
        self.radio = radio
        _session = StateObject(wrappedValue: WindowSession(id: radio == 1 ? Self.id2 : Self.id, persistSize: true,
                                                           defaultSize: CGSize(width: 620, height: 300)))
    }

    private var windowId: String { radio == 1 ? Self.id2 : Self.id }

    var body: some View {
        Group {
            if let app = host.model {
                let model: CwReaderModel = holder.model { radio == 1 ? app.makeCwReader2() : app.makeCwReader() }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: windowId,
                                                title: radio == 1 ? "CW Reader 2" : "CW Reader",
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
            if radio == 1 {
                Radio2InputRow(app: app) {
                    model.close()
                    Task { await model.open() }
                }
                .trailingFontStepper(size: $session.fontSize, language: language)
            }
            toneRow(language, model)
                .trailingFontStepper(size: $session.fontSize, language: language, shown: radio != 1)
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
                    Text(verbatim: model.shownText.isEmpty
                         ? RadioWindowTexts.readerPlaceholder(model.pitchText)
                            .text(language.translator, decimalSeparator: language.decimalSeparator)
                         : model.shownText)
                        .windowFont(16, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .onChange(of: model.shownText) {
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
                model.toggleScrollPause()
            } label: {
                Text(verbatim: language.tr(model.scrollPaused ? "Pokračovat" : "Pozastavit posuv")).windowFont(14)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("cwreader.pause")
            Button {
                model.clear()
            } label: {
                Text(verbatim: "Vymazat").windowFont(14)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Radio 2's audio input (SO2R: the second CW Reader and spectrum window), saved with the SO2R options; a change
/// reopens the input.
struct Radio2InputRow: View {
    let app: AppModel
    let changed: () -> Void

    var body: some View {
        let language: LanguageModel = app.language
        let fallback: String = language.tr(SettingsTools.systemDefaultDevice)
        let current: String = app.config.config.so2r.text(.rx2AudioDevice)
        HStack(spacing: 6) {
            Text(verbatim: language.tr("Vstup rádia 2"))
                .windowFont(12)
                .foregroundStyle(.secondary)
            SettingsDropdown(label: current.isEmpty ? fallback : current, options: app.settingsTools.inputDevices,
                             language: language) { picked in
                app.setRadio2AudioDevice(picked == fallback ? "" : picked)
                changed()
            }
        }
    }
}
