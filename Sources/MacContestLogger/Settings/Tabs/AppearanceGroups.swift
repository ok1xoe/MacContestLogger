import AppKit
import MCLAppModel
import MCLCore
import SwiftUI
import UniformTypeIdentifiers

/// „Skiny" (N1MM Configurer › Skins): a built-in skin or a skin file sets the appearance, the accent, the colours
/// and the fonts of the draft at once; „Uložit skin…" writes the draft's look to a file. Nothing is saved before OK.
struct SkinsGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft
    @State private var notice: String?

    var body: some View {
        SettingsGroup(title: language.tr("Skiny")) {
            FlowLayout(spacing: 8) {
                SettingsField(caption: language.tr("Vestavěný skin")) {
                    SettingsDropdown(label: language.tr("Vybrat…"),
                                     options: Skin.builtIns.map { language.tr($0.name) }, language: language) { picked in
                        if let skin = Skin.builtIns.first(where: { language.tr($0.name) == picked }) {
                            skin.apply(to: &draft)
                            notice = language.tr("Skin %s je v nastavení (uloží se tlačítkem OK).",
                                                 .string(language.tr(skin.name)))
                        }
                    }
                }
                .frame(width: 220, alignment: .leading)
                SettingsButton(language.tr("Načíst skin…")) { load() }
                SettingsButton(language.tr("Uložit skin…")) { save() }
            }
            if let notice {
                SettingsCaption(notice)
            }
            SettingsCaption(language.tr(
                "Skin je vzhled, barevný akcent, barvy a písma najednou. Soubor .mclskin jde přenést na jiný Mac."))
        }
    }

    private static var skinType: UTType {
        UTType(filenameExtension: Skin.fileExtension) ?? .json
    }

    private func load() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.skinType, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let skin: Skin = try Skin.decode(Data(contentsOf: url))
            skin.apply(to: &draft)
            notice = language.tr("Skin %s je v nastavení (uloží se tlačítkem OK).",
                                 .string(skin.name.isEmpty ? url.lastPathComponent : skin.name))
        } catch {
            notice = language.tr("Skin nejde načíst: %s", .string(error.localizedDescription))
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.skinType]
        panel.nameFieldStringValue = "MacContestLogger." + Skin.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name: String = url.deletingPathExtension().lastPathComponent
        do {
            try Skin.from(draft, name: name).encoded().write(to: url, options: .atomic)
            notice = language.tr("Skin uložen: %s", .string(url.lastPathComponent))
        } catch {
            notice = language.tr("Skin nejde uložit: %s", .string(error.localizedDescription))
        }
    }
}

/// „Barvy" (N1MM Configurer › Colors): one colour well per slot (`ColorSlot`) with its reset; a changed colour
/// replaces the built-in light and dark one. The entry focus colour is off until chosen.
struct ColorsGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        SettingsGroup(title: language.tr("Barvy")) {
            HStack(alignment: .top, spacing: 24) {
                column(.entry, title: language.tr("Vstupní okno a deník"))
                column(.bandmap, title: language.tr("Bandmapa a spoty"))
            }
            HStack(spacing: 8) {
                SettingsButton(language.tr("Všechny barvy výchozí")) {
                    draft.colorOverrides = [:]
                }
                .disabled(draft.colorOverrides.isEmpty)
            }
            SettingsCaption(language.tr(
                "Změněná barva platí ve světlém i tmavém vzhledu; výchozí barvy se přizpůsobují vzhledu."))
        }
    }

    private func column(_ group: ColorSlot.Group, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).windowFont(12, weight: .semibold)
            ForEach(ColorSlot.allCases.filter { $0.group == group }, id: \.self) { slot in
                row(slot)
            }
        }
    }

    private func row(_ slot: ColorSlot) -> some View {
        let label: String = language.tr(slot.labelKey)
        let custom: Int? = draft.colorOverrides[slot.rawValue].flatMap(ColorHex.parse)
        let binding = Binding<Color>(
            get: { Self.color(custom ?? slot.defaultLight ?? 0xFFFFFF) },
            set: { picked in
                if let rgb = Self.rgb(picked) {
                    draft.colorOverrides[slot.rawValue] = ColorHex.format(rgb)
                }
            })
        return HStack(spacing: 6) {
            ColorPicker(selection: binding, supportsOpacity: false) {
                Text(verbatim: label).windowFont(12)
            }
            .accessibilityLabel(Text(verbatim: label))
            if custom != nil {
                IconButton(symbol: "arrow.uturn.backward", label: language.tr("Výchozí barva"),
                           size: CGSize(width: 14, height: 14)) {
                    draft.colorOverrides[slot.rawValue] = nil
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private static func color(_ rgb: Int) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }

    private static func rgb(_ color: Color) -> Int? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        return (max(0, min(255, red)) << 16) | (max(0, min(255, green)) << 8) | max(0, min(255, blue))
    }
}

/// „Písma" (N1MM Configurer › Fonts): the family of the proportional texts and of the fixed ones (tables, the entry
/// fields); the sizes stay per window (A− / A+). „Bublinové" tooltips of N1MM are a Windows style: here the spot
/// tooltips are on or off.
struct FontsGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let families: [String] = Self.families
        let fixed: [String] = Self.fixedFamilies
        SettingsGroup(title: language.tr("Písma")) {
            FlowLayout(spacing: 8) {
                SettingsField(caption: language.tr("Písmo textů")) {
                    picker(current: $draft.fontFamily, families: families)
                }
                .frame(width: 240, alignment: .leading)
                SettingsField(caption: language.tr("Písmo neproporcionální (tabulky, vstupní pole)")) {
                    picker(current: $draft.fixedFontFamily, families: fixed)
                }
                .frame(width: 300, alignment: .leading)
            }
            SettingsCheckbox(label: language.tr("Bublinová nápověda u spotů (bandmapa, násobiče)"),
                             isOn: $draft.spotTooltips)
            SettingsCaption(language.tr(
                "Velikost písma má každé okno vlastní (A− / A+). Prázdná volba = systémové písmo."))
        }
    }

    private func picker(current: Binding<String>, families: [String]) -> some View {
        let system: String = language.tr("Systémové písmo")
        return SettingsDropdown(label: current.wrappedValue.isEmpty ? system : current.wrappedValue,
                                options: [system] + families, language: language) { picked in
            current.wrappedValue = picked == system ? "" : picked
        }
    }

    /// The installed families (read once).
    @MainActor private static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()
    /// The fixed-pitch ones among them.
    @MainActor private static let fixedFamilies: [String] = families.filter { isFixedPitch($0) }

    /// A family whose regular member is fixed pitch.
    @MainActor private static func isFixedPitch(_ family: String) -> Bool {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12)?.isFixedPitch ?? false
    }
}
