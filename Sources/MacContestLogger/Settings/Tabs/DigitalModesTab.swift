import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `DigitalModesTab` (`MT:57-101`): how the rig's data mode is logged, and the fldigi modem with
/// „Vyzkoušet" (the probe runs off the main thread through `SettingsToolsModel`).
struct DigitalModesTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: language.tr("Datový režim rigu")) {
                SettingsField(caption: "PKTUSB / PKTLSB / DATA zapisovat jako") {
                    SettingsDropdown(label: draft.dataMode, options: ConfigurerCatalogs.dataModes, language: language) {
                        draft.dataMode = $0
                    }
                }
                .frame(width: 280, alignment: .leading)
                SettingsCaption(language.tr(
                    "Např. FT8, když datovým režimem rigu děláš jen FT8. QSO z WSJT-X / JTDX si mód nesou sama (záložka WSJT/JTDX)."))
            }
            ModemGroup(app: app, draft: $draft)
        }
    }
}

/// „Modem pro RTTY / PSK" (`MT:69-99`).
private struct ModemGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        let tools: SettingsToolsModel = app.settingsTools
        SettingsGroup(title: "Modem pro RTTY / PSK") {
            HStack(spacing: 16) {
                SettingsRadio(label: language.tr("Žádný"), selected: draft.digiEngine == .none) {
                    draft.digiEngine = .none
                }
                SettingsRadio(label: "fldigi (XML-RPC)", selected: draft.digiEngine == .fldigi) {
                    draft.digiEngine = .fldigi
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: "fldigi — adresa") {
                    SettingsTextField(text: $draft.fldigiHost)
                }
                .frame(width: 200)
                SettingsField(caption: "Port XML-RPC") {
                    SettingsTextField(text: $draft.fldigiPort, filter: .digits(limit: 5))
                }
                .frame(width: 120)
                SettingsButton(language.tr("Vyzkoušet")) {
                    tools.probeFldigi(host: draft.fldigiHost, port: draft.fldigiPort)
                }
                SettingsCaption(tools.fldigiProbeText)
            }
            SettingsCaption(language.tr(
                "fldigi dělá modem (RTTY, PSK…) a MCL mu posílá zprávy F-kláves (Function Keys → Digi) a čte dekódovaný text do okna Digitální rozhraní. V RTTY/PSK s modemem funguje i ESM. Esc vysílání přeruší."))
        }
    }
}
