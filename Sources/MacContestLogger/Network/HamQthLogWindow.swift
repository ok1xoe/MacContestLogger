import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `HamQthLogWindow` (`hamqthLog` 760×460, `HamQthLogWindow.kt:51-111`): the live dump of the callbook HTTP
/// traffic (requests with the password masked, the responses) in a fixed 12 pt monospaced `NSTextView`, requests blue
/// and responses green, with „Kopírovat" and „Vymazat". The log's listener is registered while the window is open.
struct HamQthLogWindowView: View {
    static let id = "hamqthLog"

    let host: AppHost

    @StateObject private var session = WindowSession(id: HamQthLogWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 760, height: 460))
    @StateObject private var holder = WindowModelHolder<HamQthLogModel>()

    var body: some View {
        Group {
            if let app = host.model {
                let model: HamQthLogModel = holder.model { HamQthLogModel(log: app.callbook.hamQthLog) }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "HamQTH log",
                                                binder: session.binder))
                    .onAppear { model.open() }
                    .onDisappear { model.close() }
                    .onChange(of: app.windows.isOpen(Self.id)) { _, open in
                        if open {
                            model.open()
                        } else {
                            model.close()
                        }
                    }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 240)
    }

    private func content(_ app: AppModel, _ model: HamQthLogModel) -> some View {
        let language: LanguageModel = app.language
        return VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            HStack(alignment: .center, spacing: 6) {
                Text(verbatim: language.tr("HamQTH — dohledávání gridu"))
                    .windowFont(14, weight: .bold)
                Spacer(minLength: 0)
                Button(language.tr("Kopírovat")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.clipboardText, forType: .string)
                }
                .windowFont(13)
                .accessibilityIdentifier("hamqthlog.copy")
                Button("Vymazat") { model.clear() }
                    .windowFont(13)
                    .accessibilityIdentifier("hamqthlog.clear")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            DigitalRxTextView(text: Self.text(model.lines), accessibilityText: language.tr("HamQTH log"),
                              inset: NSSize(width: 12, height: 2))
                .accessibilityIdentifier("hamqthlog.text")
        }
        .environment(\.windowFontSize, session.fontSize)
    }

    /// Kotlin `lineColor`: a request line blue, a response line green, the rest the text colour.
    static func color(_ line: String) -> NSColor {
        if line.contains("\u{2192} GET") {
            return SpotColors.good
        }
        if line.contains("\u{2190} [") {
            return SpotColors.multiMult
        }
        return NSColor.labelColor
    }

    /// The lines as one text: 12 pt monospaced (Kotlin `fontSize = 12.sp`, not scaled), one colour per entry.
    static func text(_ lines: [String]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 2
        let font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color(line), .paragraphStyle: paragraph,
            ]
            result.append(NSAttributedString(string: index == 0 ? line : "\n" + line, attributes: attributes))
        }
        return result
    }
}
