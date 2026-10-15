import MCLAppModel
import MCLCore
import SwiftUI

/// The spectrum display's options (N1MM+: the right-click menu and the gear dialog's General Options): orientation,
/// reversed scale, the waterfall, the noise line, the instant levels, the decay speed, the background, the pane size,
/// smearing and snapping. Every change is saved at once.
struct SpectrumOptionsSheet: View {
    let model: WaterfallModel
    let language: LanguageModel
    let close: () -> Void

    @StateObject private var form = DialogFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.tr("Volby spektra"))
                    .windowFont(15, weight: .semibold)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    display
                    behaviour
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DialogButtonRow {
                Button(language.tr("Zavřít")) {
                    close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 440)
        .environment(\.windowFontSize, form.fontSize)
    }

    private func flag(_ key: SpectrumSetup.Key, _ label: String, id: String) -> some View {
        Toggle(language.tr(label), isOn: Binding(
            get: { model.setup.flag(key) },
            set: { value in model.updateSetup { $0.set(key, flag: value) } }))
            .accessibilityIdentifier(id)
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: language.tr("Zobrazení")).windowFont(13, weight: .medium)
            Picker(language.tr("Orientace"), selection: Binding(
                get: { model.setup.orientation },
                set: { value in model.updateSetup { $0.orientation = value } })) {
                Text(verbatim: language.tr("Automaticky")).tag(SpectrumOrientation.auto)
                Text(verbatim: language.tr("Vodorovně")).tag(SpectrumOrientation.horizontal)
                Text(verbatim: language.tr("Svisle (sloupce)")).tag(SpectrumOrientation.vertical)
            }
            .accessibilityIdentifier("spectrum.orientation")
            flag(.reverseScale, "Svisle: nízké frekvence nahoře", id: "spectrum.reverseScale")
            flag(.showWaterfall, "Zobrazit vodopád", id: "spectrum.showWaterfall")
            flag(.noiseAsLine, "Šum jako čára (vodorovně)", id: "spectrum.noiseAsLine")
            flag(.showInstant, "Zobrazit okamžité úrovně pod prahem", id: "spectrum.showInstant")
            Picker(language.tr("Doznívání signálu"), selection: Binding(
                get: { model.setup.decaySpeed },
                set: { value in model.updateSetup { $0.decaySpeed = value } })) {
                Text(verbatim: language.tr("Pomalé")).tag(SpectrumDecaySpeed.slow)
                Text(verbatim: language.tr("Střední")).tag(SpectrumDecaySpeed.medium)
                Text(verbatim: language.tr("Rychlé")).tag(SpectrumDecaySpeed.fast)
            }
            .accessibilityIdentifier("spectrum.decay")
            Picker(language.tr("Pozadí"), selection: Binding(
                get: { model.setup.background },
                set: { value in model.updateSetup { $0.background = value } })) {
                Text(verbatim: language.tr("Černé")).tag(SpectrumBackground.black)
                Text(verbatim: language.tr("Šedé")).tag(SpectrumBackground.gray)
                Text(verbatim: language.tr("Bílé")).tag(SpectrumBackground.white)
            }
            .accessibilityIdentifier("spectrum.background")
            HStack(spacing: 8) {
                Text(verbatim: language.tr("Velikost spektra")).windowFont(12)
                Slider(value: Binding(
                    get: { Double(model.setup.sizeFactor) },
                    set: { value in model.updateSetup { $0.sizeFactor = Int(value.rounded()) } }), in: 20...80, step: 5)
                    .frame(width: 180)
                    .accessibilityLabel(Text(verbatim: language.tr("Velikost spektra")))
                    .accessibilityIdentifier("spectrum.size")
                Text(verbatim: String(model.setup.sizeFactor) + " %").windowFont(12, design: .monospaced)
            }
        }
        .windowFont(12)
    }

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: language.tr("Chování")).windowFont(13, weight: .medium)
            flag(.snapToSignal, "Klik přichytí na signál (±2 kHz)", id: "spectrum.snap")
            flag(.reduceSmearing, "Při ladění vymazat spektrum (bez rozmazání)", id: "spectrum.smearing")
            Text(verbatim: language.tr("Kolečko nad spektrem: práh signálu; Cmd+kolečko: referenční úroveň; "
                + "Cmd+Shift+kolečko: rozsah dB. Kolečko nad vodopádem ladí (Shift/Cmd = větší krok)."))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .windowFont(12)
    }
}
