import AppKit
import Carbon.HIToolbox
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `DigitalInterfaceWindow` (`digitalinterface` 680×340, `DigitalInterfaceWindow.kt:67-228`, N1MM Digital
/// Interface): the modem status („modem · trx", „—") with „Vymazat" in the top row, the error line, the last calls
/// heard, fldigi's decoded text with the calls (primary) and the exchange words (tertiary) underlined — a click
/// puts them into the active entry window — and the hint line. F1–F12, Enter and Esc go to the active entry window
/// (the focus stays here).
struct DigitalInterfaceWindowView: View {
    static let id = "digitalinterface"

    let host: AppHost

    @StateObject private var session = WindowSession(id: DigitalInterfaceWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 680, height: 340))
    @StateObject private var holder = WindowModelHolder<DigitalInterfaceModel>()
    @StateObject private var keys = WindowKeyMonitor()

    var body: some View {
        Group {
            if let app = host.model {
                let model: DigitalInterfaceModel = holder.model { app.makeDigitalInterface() }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Digitální rozhraní",
                                                binder: session.binder))
                    .background(WindowAccessor { window in
                        keys.handler = { key in Self.handle(key, model: model) }
                        keys.install(window: window)
                    })
                    .onAppear { model.open() }
                    .onDisappear { model.close() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }

    /// `DIGI_FUNCTION_KEYS` (F1–F12 in order), Enter, Esc.
    private static let functionKeys: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]

    private static func handle(_ key: WindowKey, model: DigitalInterfaceModel) -> Bool {
        let code = Int(key.keyCode)
        if let index = functionKeys.firstIndex(of: code) {
            return model.key(.function(index), down: key.down, shift: key.shift)
        }
        switch code {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return model.key(.enter, down: key.down, shift: key.shift)
        case kVK_Escape:
            return model.key(.escape, down: key.down, shift: key.shift)
        default:
            return false
        }
    }

    private func content(_ app: AppModel, _ model: DigitalInterfaceModel) -> some View {
        let language: LanguageModel = app.language
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language) {
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: model.status.isEmpty ? "—" : model.status)
                        .windowFont(16)
                    Button {
                        model.clear()
                    } label: {
                        Text(verbatim: "Vymazat").windowFont(14)
                    }
                    .buttonStyle(.borderless)
                }
            }
            if let error = model.error {
                Text(verbatim: error.text(language.translator, decimalSeparator: language.decimalSeparator))
                    .windowFont(14)
                    .foregroundStyle(Color(domain: DomainColors.dupe))
            }
            HStack(spacing: 6) {
                ForEach(model.recentCalls, id: \.self) { call in
                    SettingsChip(label: call, selected: false) { model.take(call) }
                }
            }
            DigitalRxTextView(text: Self.annotated(model.text, spans: model.spans, size: session.fontSize),
                              accessibilityText: language.tr("Dekódovaný text"),
                              onTap: { offset in model.tap(offset: offset) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(verbatim: language.tr(
                "Klik na volačku ji vloží do pole volačky, klik na jinak podtržené slovo do výměny. Text dekóduje fldigi."))
                .windowFont(11)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    /// The text in the window's monospaced body size with the calls (primary) and exchange words (tertiary)
    /// underlined (`buildAnnotatedString`).
    static func annotated(_ text: String, spans: [DigitalInterfaceModel.Span], size: Int) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: WindowFont.size(16, windowSize: size), weight: .regular)
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor,
        ])
        let length: Int = result.length
        for span in spans where span.start >= 0 && span.end <= length && span.start < span.end {
            let color: NSColor
            switch span.kind {
            case .call:
                color = DomainColors.primary
            case .exchange:
                color = DomainColors.tertiary
            }
            result.addAttributes([.foregroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue],
                                 range: NSRange(location: span.start, length: span.end - span.start))
        }
        return result
    }
}
