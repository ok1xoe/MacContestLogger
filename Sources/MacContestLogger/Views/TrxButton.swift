import MCLAppModel
import MCLCore
import SwiftUI

/// The TRX (CAT) icon of the frequency strip (Kotlin `InfoBar`, `EP:1650-1690`): green when the window's rig is
/// connected, faded otherwise; a click connects or disconnects it (`catFor(vfo).toggle(rigConfigFor(vfo))`). The
/// tooltip names the rig — Kotlin passes `config.rig.modelLabel` for both windows — and says what a click does.
/// The description is Kotlin's: „Odpojit TRX" untranslated, `tr("Připojit TRX")`.
struct TrxButton: View {
    let app: AppModel
    let vfo: Int
    @Environment(\.windowFontSize) private var size

    var body: some View {
        let rig: MCLAppModel.RigModel = app.rig
        let language: LanguageModel = app.language
        let connected: Bool = rig.connected(vfo: vfo)
        let snapshot = rig.snapshot(vfo: vfo)
        let ledState: AccessibilityText.RigLedState = AccessibilityText.rigLedState(
            connected: connected, connecting: snapshot.connecting)
        Button {
            rig.toggle(vfo: vfo)
        } label: {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: WindowFont.size(13, windowSize: size)))
                .foregroundStyle(connected ? AnyShapeStyle(Color(domain: DomainColors.catConnected))
                                 : AnyShapeStyle(.mclOnStrip.opacity(0.45)))
                .frame(width: WindowFont.size(16, windowSize: size), height: WindowFont.size(16, windowSize: size))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: Self.tooltip(model: app.config.config.rig.modelLabel, connected: connected,
                                          language: language)))
        .accessibilityLabel(Text(verbatim: language.tr("TRX")))
        .accessibilityValue(Text(verbatim: AccessibilityText.rigLedValue(ledState, translator: language.translator)))
        .accessibilityHint(Text(verbatim: language.tr(connected ? "Odpojit TRX" : "Připojit TRX")))
    }

    /// The two lines of Kotlin's tooltip: the rig (`ifBlank { tr("TRX není nastaven") }`) and the click hint.
    static func tooltip(model: String, connected: Bool, language: LanguageModel) -> String {
        let name: String = KotlinStrings.isBlank(model) ? language.tr("TRX není nastaven") : model
        let hint: String = connected ? language.tr("Připojeno — klikni pro odpojení")
            : language.tr("Nepřipojeno — klikni pro připojení")
        return name + "\n" + hint
    }
}
