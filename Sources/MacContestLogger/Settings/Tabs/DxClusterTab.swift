import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `DxClusterTab` (`DX:31-157`): the favourite telnet clusters (each may run in parallel), the bandmap
/// parameters and the two blacklists.
struct DxClusterTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        SettingsGroup(title: language.tr("DX Clustery (telnet spotting síť)")) {
            if draft.dxFavorites.isEmpty {
                Text(verbatim: language.tr("Zatím žádný cluster. Přidej první tlačítkem níže."))
                    .foregroundStyle(.secondary)
            }
            ForEach($draft.dxFavorites) { $favorite in
                if draft.dxFavorites.first?.id != favorite.id {
                    Divider()
                }
                FavoriteEditor(language: language, favorite: $favorite) {
                    draft.dxFavorites.removeAll { $0.id == favorite.id }
                }
            }
            SettingsButton(language.tr("Přidat cluster")) { draft.addDxFavorite() }
            parameters
            filterWidths
            SettingsCheckbox(label: language.tr("Automatický split z komentáře spotu („UP 5“, „QSX 14025“)"),
                             isOn: $draft.autoSplit)
            SettingsCheckbox(label: language.tr("Klik na spot dá volačku do rámečku nad polem (mezerník ji převezme)"),
                             isOn: $draft.callFrame)
            SettingsCheckbox(label: language.tr("Ladění na spot nastaví i mód spotu"), isOn: $draft.spotModeOnTune)
            tolerances
            SettingsCaption(language.tr(
                "Skimmer / RBN spoty: 0 = skrýt, 1 = všechny, 2+ = jen stanice hlášené aspoň tolika skimmery. ")
                + language.tr("Spoty od lidí se zobrazují vždy."))
            SettingsCaption(language.tr(
                "Příkazová tlačítka se nastavují přímo v okně DX Cluster (pravé tlačítko myši nad tlačítkem)."))
            Divider()
            Text(verbatim: language.tr("Filtr spotů")).windowFont(13, weight: .semibold)
            SpotFilterEditor(language: language, filter: $draft.spotFilter, idPrefix: "settings.spotfilter")
            SettingsCaption(language.tr(
                "Časový limit spotu = Buffer spotů (min); QSY smaže spot podle Prahu self-spotu (Hz)."))
            Divider()
            BlacklistEditor(language: language, title: language.tr("Blacklist volaček"),
                            items: $draft.blacklistedCalls)
            BlacklistEditor(language: language, title: language.tr("Blacklist spotterů"),
                            items: $draft.blacklistedSpotters)
        }
    }

    /// N1MM's tuning tolerance per mode: how close to a spot the call shows in the call-frame.
    private var tolerances: some View {
        FlowLayout(spacing: 8) {
            SettingsField(caption: language.tr("Tolerance ladění CW (Hz)")) {
                SettingsTextField(text: $draft.tuningToleranceCwHz, filter: .digits(limit: 5))
            }
            .frame(width: 170)
            SettingsField(caption: language.tr("Tolerance ladění SSB (Hz)")) {
                SettingsTextField(text: $draft.tuningToleranceSsbHz, filter: .digits(limit: 5))
            }
            .frame(width: 170)
            SettingsField(caption: language.tr("Tolerance ladění digi (Hz)")) {
                SettingsTextField(text: $draft.tuningToleranceDigiHz, filter: .digits(limit: 5))
            }
            .frame(width: 170)
        }
    }

    /// N1MM „Set Transceiver Filter Codes": the passbands of the band map's Wide/Narrow button.
    private var filterWidths: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 8) {
                widthField(language.tr("CW široký (Hz)"), $draft.filterCwWideHz)
                widthField(language.tr("CW úzký (Hz)"), $draft.filterCwNarrowHz)
                widthField(language.tr("SSB široký (Hz)"), $draft.filterSsbWideHz)
                widthField(language.tr("SSB úzký (Hz)"), $draft.filterSsbNarrowHz)
                widthField(language.tr("Digi široký (Hz)"), $draft.filterDigiWideHz)
                widthField(language.tr("Digi úzký (Hz)"), $draft.filterDigiNarrowHz)
            }
            SettingsCaption(language.tr("Šířky filtru pro tlačítko Wide/Narrow v bandmapě (0 = výchozí šířka rigu)."))
        }
    }

    private func widthField(_ caption: String, _ text: Binding<String>) -> some View {
        SettingsField(caption: caption) {
            SettingsTextField(text: text, filter: .digits(limit: 5))
        }
        .frame(width: 130)
    }

    private var parameters: some View {
        // Wraps onto further lines when the detail area is narrow (a fixed-width row would overflow it).
        FlowLayout(spacing: 8) {
            SettingsField(caption: language.tr("Buffer spotů (min)")) {
                SettingsTextField(text: $draft.spotBufferMinutes, filter: .digits(limit: nil))
            }
            .frame(width: 150)
            SettingsField(caption: language.tr("Krok kolečka (Hz)")) {
                SettingsTextField(text: $draft.wheelStepHz, filter: .digits(limit: nil))
            }
            .frame(width: 150)
            SettingsField(caption: "Krok se Shift (Hz)") {
                SettingsTextField(text: $draft.wheelStepShiftHz, filter: .digits(limit: nil))
            }
            .frame(width: 150)
            SettingsField(caption: language.tr("Práh self-spotu (Hz)")) {
                SettingsTextField(text: $draft.selfSpotThresholdHz, filter: .digits(limit: nil))
            }
            .frame(width: 150)
            SettingsField(caption: language.tr("Skimmer spoty: min. skimmerů")) {
                SettingsTextField(text: $draft.minSkimmers, filter: .digits(limit: 2))
            }
            .frame(width: 200)
        }
    }
}

/// One favourite: name, „Souběžně", „Smazat"; host and port; login and password (`DX:42-100`).
private struct FavoriteEditor: View {
    let language: LanguageModel
    @Binding var favorite: DxFavoriteDraft
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: language.tr("Jméno")) {
                    SettingsTextField(text: $favorite.name)
                }
                .frame(maxWidth: .infinity)
                Toggle(isOn: $favorite.isParallel) {
                    Text(verbatim: language.tr("Souběžně"))
                        .windowFont(12)
                }
                .toggleStyle(.checkbox)
                SettingsButton("Smazat", action: onDelete)
            }
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: "Server (host)") {
                    SettingsTextField(text: $favorite.host)
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: "Port") {
                    SettingsTextField(text: $favorite.port, filter: .digits(limit: nil))
                }
                .frame(width: 110)
            }
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: language.tr("Přihlašovací jméno (volačka)")) {
                    SettingsTextField(text: $favorite.login)
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: language.tr("Heslo (nepovinné)")) {
                    SettingsTextField(text: $favorite.password, isPassword: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
