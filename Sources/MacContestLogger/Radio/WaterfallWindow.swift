import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `WaterfallWindow` (`waterfall` 760×380, `WaterfallWindow.kt:48-116`): the info line (the audio error, the
/// frequency under the pointer, or the mode and CW pitch) above the waterfall of the receiver audio 0–3 kHz; a press
/// tunes the rig to the frequency under the pointer (when the dial frequency is known). The window holds the
/// receiver audio while it is open.
struct WaterfallWindowView: View {
    static let id = "waterfall"

    let host: AppHost

    @StateObject private var session = WindowSession(id: WaterfallWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 760, height: 380))
    @StateObject private var holder = WindowModelHolder<WaterfallModel>()

    var body: some View {
        Group {
            if let app = host.model {
                let model: WaterfallModel = holder.model { app.makeWaterfall() }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Vodopád",
                                                binder: session.binder))
                    .task { await model.open() }
                    .onDisappear { model.close() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }

    private func content(_ app: AppModel, _ model: WaterfallModel) -> some View {
        let language: LanguageModel = app.language
        let info: (text: EntryStatus, isError: Bool) = model.infoLine
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            Text(verbatim: info.text.text(language.translator, decimalSeparator: language.decimalSeparator))
                .windowFont(12)
                .foregroundStyle(info.isError ? AnyShapeStyle(Color(domain: DomainColors.dupe))
                                              : AnyShapeStyle(.secondary))
            WaterfallLayerView(
                image: model.image,
                pitchLine: model.pitchLine,
                onHover: { x, width in model.hover(x: x, width: width) },
                onExit: { model.hoverEnded() },
                onPress: { x, width in model.click(x: x, width: width) },
                accessibilityText: language.tr("Vodopád"),
                accessibilityValueText: info.text.text(language.translator, decimalSeparator: language.decimalSeparator))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }
}
