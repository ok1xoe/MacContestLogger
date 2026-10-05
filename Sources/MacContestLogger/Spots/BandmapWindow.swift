import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The spot font field of the window (Kotlin `fontText`, kept as typed: the font is `toIntOrNull()` coerced to
/// 8…28, 11 for a non-number).
@MainActor
final class BandmapFontField: ObservableObject {
    @Published var text: String = String(BandmapViewport.defaultSpotFont)
}

/// Kotlin `BandmapWindow` (`bandmap` 460×640, `BandmapWindow.kt:75-360`): the window stepper top-right,
/// the tuned frequency with the zoom buttons and the spot font field, then the band map. Without a tuned band only
/// the hint „Bandmapa — nalaď pásmo" shows.
struct BandmapWindowView: View {
    static let id = "bandmap"

    let host: AppHost

    @StateObject private var session = WindowSession(id: BandmapWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 460, height: 640))
    @StateObject private var font = BandmapFontField()

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Bandmapa",
                                                binder: session.binder))
                    .onAppear { app.bandmap.windowOpened() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 320, minHeight: 240)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let model: BandmapModel = app.bandmap
        let drawState: BandmapDrawState? = BandmapDrawState(model)
        return VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            if let drawState {
                controls(model: model, language: language)
                BandmapView(model: model, language: language, state: drawState)
            } else {
                Text(verbatim: language.tr("Bandmapa — nalaď pásmo"))
                    .windowFont(14, weight: .semibold)
                    .foregroundStyle(Color(domain: DomainColors.primary))
                    .padding(8)
                Spacer(minLength: 0)
            }
        }
        .environment(\.windowFontSize, session.fontSize)
    }

    /// The control row: the tuned frequency, the zoom buttons and the spot font field with its arrows.
    private func controls(model: BandmapModel, language: LanguageModel) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(verbatim: model.tunedText)
                .windowFont(18, weight: .bold, design: .monospaced)
                .foregroundStyle(Color(domain: DomainColors.primary))
            Spacer(minLength: 0)
            iconButton("plus", language.tr("Přiblížit")) { model.zoomIn() }
            iconButton("minus", language.tr("Oddálit")) { model.zoomOut() }
            iconButton("arrow.clockwise", language.tr("Reset zobrazení")) { model.resetView() }
            fontField(model: model, language: language)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping @MainActor () -> Void) -> some View {
        IconButton(symbol: symbol, label: label, size: CGSize(width: 28, height: 28), outlined: true, action: action)
            .buttonStyle(.plain)
    }

    /// The number field and the two half-height arrows (+ above −), the spot font (8…28).
    private func fontField(model: BandmapModel, language: LanguageModel) -> some View {
        let field: BandmapFontField = font
        let text = Binding<String>(get: { field.text }, set: { value in
            let digits: String = String(value.filter(\.isNumber).prefix(2))
            field.text = digits
            model.setSpotFont(Int(digits) ?? BandmapViewport.defaultSpotFont)
        })
        return HStack(spacing: 2) {
            TextField(text: text) {
                Text(verbatim: "")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 46)
            .accessibilityLabel(language.tr("Velikost písma"))
            .accessibilityIdentifier("bandmap.spotFont")
            VStack(spacing: 0) {
                arrow("plus", language.tr("Zvětšit písmo")) {
                    model.setSpotFont(model.spotFont + 1)
                    field.text = String(model.spotFont)
                }
                arrow("minus", language.tr("Zmenšit písmo")) {
                    model.setSpotFont(model.spotFont - 1)
                    field.text = String(model.spotFont)
                }
            }
        }
    }

    private func arrow(_ symbol: String, _ label: String, action: @escaping @MainActor () -> Void) -> some View {
        IconButton(symbol: symbol, label: label, size: CGSize(width: 28, height: 15), outlined: true,
                   symbolSize: 8, secondary: true, action: action)
            .buttonStyle(.plain)
    }
}
