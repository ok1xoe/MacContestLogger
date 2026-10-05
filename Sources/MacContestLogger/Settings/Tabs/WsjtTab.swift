import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `WsjtTab` (`WT:22-59`): WSJT-X receive and send, N1MM / RUMlog receive, ADIF over UDP.
struct WsjtTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: language.tr("Příjem z WSJT-X")) {
                SettingsCaption(language.tr(
                    "Naslouchá WSJT-X paketům a importuje zalogovaná QSO do aktivního závodu. Nasměruj WSJT-X (UDP Server) unicastem na tuto adresu. Výchozí port 2237. Změny se projeví po uložení."))
                SettingsToggleRow(label: language.tr("Příjem zapnut"), isOn: $draft.wxReceiveEnabled,
                                  text: $draft.wxReceiveBind)
            }
            SettingsGroup(title: language.tr("Vysílání do deníků")) {
                SettingsCaption(language.tr(
                    "Při zalogování odešle QSO ve WSJT-X formátu (typ 5 + 12) na cíle „host:port\" (víc oddělených mezerou), aby je zvedly ostatní deníky (např. RUMlogNG)."))
                SettingsToggleRow(label: language.tr("Vysílání zapnuto"), isOn: $draft.wxSendEnabled,
                                  text: $draft.wxSendTargets)
            }
            SettingsGroup(title: language.tr("Příjem N1MM / RUMlog")) {
                SettingsCaption(language.tr(
                    "Naslouchá standardnímu N1MM contactinfo broadcastu a importuje QSO do aktivního závodu. V RUMlogu/N1MM+ nastav cíl broadcastu na tuto adresu (unicast host:port, nebo multicast skupina). Výchozí port 12061. Změny se projeví po uložení."))
                SettingsToggleRow(label: language.tr("Příjem zapnut"), isOn: $draft.nrReceiveEnabled,
                                  text: $draft.nrReceiveBind)
            }
            SettingsGroup(title: language.tr("ADIF přes UDP (fldigi)")) {
                SettingsCaption(language.tr(
                    "Přijímá holý ADIF záznam po UDP (fldigi apod.) a importuje QSO do aktivního závodu. V programu nastav cíl UDP na tuto adresu. Výchozí port 2333. Změny se projeví po uložení."))
                SettingsToggleRow(label: language.tr("Příjem zapnut"), isOn: $draft.auReceiveEnabled,
                                  text: $draft.auReceiveBind)
            }
        }
    }
}
