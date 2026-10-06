import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `CwKeyerTab` (`VK:199-238`): the keying method (rig keyer over CAT, Winkeyer on a serial port, off), the
/// speed and the serial number format. The serial ports are listed when the tab opens.
struct CwKeyerTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            methodGroup
            speedGroup
        }
        .onAppear { app.settingsTools.loadSerialPorts() }
    }

    private var methodGroup: some View {
        let ports: [String] = app.settingsTools.serialPorts
        let noPort: String = ports.isEmpty ? language.tr("Žádný sériový port") : "Vyber port"
        return SettingsGroup(title: language.tr("Způsob klíčování")) {
            SettingsRadio(label: language.tr("Klíčovač rigu přes CAT (rigctld)"), selected: draft.cwMethod == .cat) {
                draft.cwMethod = .cat
            }
            SettingsCaption(language.tr(
                "Text posílá rig vestavěným klíčovačem (hamlib send_morse), např. Kenwood, Icom, Yaesu, Elecraft. TRX musí být připojený. Prosigny se pošlou jako dvojice písmen a změny rychlosti < > uvnitř zprávy rig neumí."))
            SettingsRadio(label: language.tr("K1EL Winkeyer (sériový port)"), selected: draft.cwMethod == .winkeyer) {
                draft.cwMethod = .winkeyer
            }
            SettingsField(caption: "Port Winkeyeru") {
                SettingsDropdown(label: ifBlank(draft.cwPort, noPort), options: ports, language: language,
                                 enabled: draft.cwMethod == .winkeyer) { draft.cwPort = $0 }
            }
            SettingsRadio(label: "Vypnuto", selected: draft.cwMethod == .none) {
                draft.cwMethod = .none
            }
        }
    }

    private var speedGroup: some View {
        let styles: [CutStyle] = CutStyle.allCases
        return SettingsGroup(title: language.tr("Rychlost a čísla")) {
            HStack(alignment: .center, spacing: 12) {
                SettingsField(caption: "Rychlost (WPM)") {
                    SettingsTextField(text: $draft.cwSpeed, filter: .digits(limit: nil))
                }
                .frame(width: 140)
                SettingsCaption(language.tr("V zadávacím okně PgUp / PgDn ±2 WPM."))
            }
            SettingsCheckbox(
                label: language.tr(
                    "Pořadová čísla s cut číslicemi (FULLABBREV / PROABBREV / SEMIABBREV / NOABBREV)"),
                isOn: $draft.cwCutNumbers)
            SettingsField(caption: language.tr("Styl cut čísel")) {
                SettingsDropdown(label: draft.cwCutStyle.label, options: styles.map(\.label), language: language,
                                 enabled: draft.cwCutNumbers) { picked in
                    if let style = styles.first(where: { $0.label == picked }) {
                        draft.cwCutStyle = style
                    }
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            SettingsCheckbox(label: language.tr("Pořadová čísla s úvodními nulami (007)"), isOn: $draft.cwLeadingZeros)
        }
    }
}
