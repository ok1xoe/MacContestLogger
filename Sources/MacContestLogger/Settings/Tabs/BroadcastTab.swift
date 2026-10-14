import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `BroadcastTab` (`BT:26-58`): N1MM UDP broadcast of contacts, radio, score and application info. The
/// greyed demo rows of „Zatím nedostupné" are left out.
struct BroadcastTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        SettingsGroup(title: "N1MM UDP broadcast") {
            SettingsCaption(language.tr(
                "Zapni typ a zadej cíle „host:port\" (víc oddělených mezerou). Výchozí N1MM port je 12060. Změny se projeví po uložení."))
            SettingsToggleRow(label: "Contacts (QSO)", isOn: $draft.bcContactsEnabled, text: $draft.bcContactsTargets)
            SettingsToggleRow(label: language.tr("Radio (frekvence/mód)"), isOn: $draft.bcRadioEnabled,
                              text: $draft.bcRadioTargets)
            SettingsToggleRow(label: language.tr("Score (skóre)"), isOn: $draft.bcScoreEnabled,
                              text: $draft.bcScoreTargets)
            SettingsToggleRow(label: "Application Info", isOn: $draft.bcAppInfoEnabled, text: $draft.bcAppInfoTargets)
            SettingsToggleRow(label: "Spots", isOn: $draft.bcSpotsEnabled, text: $draft.bcSpotsTargets)
            SettingsToggleRow(label: language.tr("Lookup (volačka před zápisem)"), isOn: $draft.bcLookupEnabled,
                              text: $draft.bcLookupTargets)
            SettingsCheckbox(label: language.tr("All QSOs: přeposílat kontakty ostatních stanic na cíle Contacts"),
                             isOn: $draft.bcAllQsosEnabled)
        }
    }
}

/// `BroadcastRow` / `WsjtxRow`: a check box (220 pt) and its text field, enabled with the check box.
struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    @Binding var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsCheckbox(label: label, isOn: $isOn)
                .frame(width: 220, alignment: .leading)
            SettingsTextField(text: $text)
                .frame(maxWidth: .infinity)
                .disabled(!isOn)
        }
    }
}
