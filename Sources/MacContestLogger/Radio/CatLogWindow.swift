import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `CatLogWindow` (`catLog` 740×440, `CatLogWindow.kt:44-98`): the live CAT / serial traffic of
/// `CatTrafficLog` — the header „CAT / sériový provoz" with „Vymazat", then the lines in a fixed 12 pt monospaced
/// font (Kotlin `fontSize = 12.sp`, not scaled by the stepper), selectable and scrolled to the last line.
struct CatLogWindowView: View {
    static let id = "catLog"

    let host: AppHost

    @StateObject private var session = WindowSession(id: CatLogWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 740, height: 440))

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "CAT log",
                                                binder: session.binder))
                    .onAppear { app.catLog.open() }
                    .onDisappear { app.catLog.close() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        return VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: language.tr("CAT / sériový provoz"))
                    .windowFont(14, weight: .bold)
                Spacer(minLength: 0)
                Button {
                    app.catLog.clear()
                } label: {
                    Text(verbatim: "Vymazat")
                        .windowFont(14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            DigitalRxTextView(text: Self.lines(app.catLog.lines), accessibilityText: app.language.tr("CAT log"),
                              inset: NSSize(width: 12, height: 2))
        }
        .environment(\.windowFontSize, session.fontSize)
    }

    /// The lines as one text: 12 pt monospaced, one line per entry with a little space between them (Kotlin
    /// `padding(vertical = 1.dp)`).
    static func lines(_ lines: [String]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        return NSAttributedString(string: lines.joined(separator: "\n"), attributes: attributes)
    }
}
