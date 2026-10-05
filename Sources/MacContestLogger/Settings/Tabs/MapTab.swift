import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `MapTab` (`MP:37-101`): the colour scheme of the map background (with its light swatches, `MapStyle.kt`)
/// and the political shading of the countries (the first ten colours of its palette as a preview).
struct MapTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    /// Ocean, land and coast of the light variant of each scheme (`MAP_SCHEMES`, `MapStyle.kt:21-42`).
    private static let swatches: [String: [Int]] = [
        "green": [0xB7D4E3, 0xA9B58F, 0x808B65],
        "gray": [0xDCE4E9, 0xC6CDD2, 0x98A2AA],
        "sepia": [0xEADFC7, 0xD8C29A, 0xB29767],
        "slate": [0xC6D7E6, 0xAEB9C4, 0x8590A0],
    ]

    /// `POLITICAL_PALETTE_LIGHT.take(10)` (`MapStyle.kt:47-52`).
    private static let political: [Int] = [
        0xCBB78A, 0x9FBE8E, 0x8FB3B0, 0xC29A9A, 0xA9A6C6, 0xD0B48C, 0x9DB6C4, 0xBFC08C, 0xC7A2B4, 0x8FB79E,
    ]

    var body: some View {
        let language: LanguageModel = app.language
        SettingsGroup(title: "Vzhled mapy") {
            Text(verbatim: language.tr("Barevné schéma podkladu"))
                .windowFont(14)
                .foregroundStyle(.secondary)
            ForEach(ConfigurerCatalogs.mapSchemes, id: \.key) { scheme in
                HStack(spacing: 0) {
                    SettingsRadio(label: language.tr(scheme.labelKey), selected: draft.mapScheme == scheme.key) {
                        draft.mapScheme = scheme.key
                    }
                    Spacer(minLength: 0)
                    ForEach(Self.swatches[scheme.key] ?? [], id: \.self) { Swatch(rgb: $0) }
                }
                .padding(.vertical, 2)
            }
            SettingsCheckbox(label: language.tr("Politické podbarvení států"), isOn: $draft.mapPolitical)
                .padding(.top, 8)
            SettingsCaption(language.tr(
                "Každý stát (DXCC entita) dostane vlastní barvu; schéma pak určuje jen oceán a pobřeží."))
                .padding(.leading, 20)
            if draft.mapPolitical {
                HStack(spacing: 3) {
                    ForEach(Self.political, id: \.self) { Swatch(rgb: $0) }
                }
                .padding(.leading, 40)
                .padding(.top, 4)
            }
        }
    }
}

/// An 18 pt colour square with rounded corners.
private struct Swatch: View {
    let rgb: Int

    var body: some View {
        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(.sRGB, red: red, green: green, blue: blue, opacity: 1))
            .frame(width: 18, height: 18)
            .padding(.leading, 4)
            .accessibilityHidden(true)
    }
}
