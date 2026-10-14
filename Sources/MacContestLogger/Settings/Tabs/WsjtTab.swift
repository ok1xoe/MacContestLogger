import AppKit
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
                SettingsCheckbox(label: language.tr("Barvit volačky v Band Activity podle dupe / násobiče"),
                                 isOn: $draft.highlightCalls)
                SettingsCheckbox(label: language.tr("DX Call z WSJT-X do pole volačky (kontrola dupe / násobiče)"),
                                 isOn: $draft.mirrorDxCall)
                SettingsCheckbox(label: language.tr("Změna pásma vymaže seznam dekódů"),
                                 isOn: $draft.clearDecodesOnBandChange)
            }
            SettingsGroup(title: language.tr("Spuštění WSJT-X / JTDX")) {
                SettingsCaption(language.tr(
                    "Okno → Spustit WSJT-X / JTDX spustí program (každé spuštění novou instanci) a otevře seznam dekódů. Pro SO2R druhá instance „rádio 2\" dostane --rig-name; její DX Call jde do okna VFO B / rig 2. Ovládání rigu: ve WSJT-X nastav Hamlib NET rigctl na stejný rigctld jako MCL."))
                HStack(spacing: 8) {
                    SettingsField(caption: language.tr("Program (.app)")) {
                        SettingsTextField(text: $draft.programPath)
                    }
                    SettingsButton(language.tr("Vybrat…"), borderless: true) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK, let url = panel.url {
                            draft.programPath = url.path
                        }
                    }
                }
                HStack(spacing: 8) {
                    SettingsField(caption: language.tr("Parametry")) {
                        SettingsTextField(text: $draft.programArgs)
                    }
                    SettingsField(caption: language.tr("Jméno instance pro rádio 2")) {
                        SettingsTextField(text: $draft.radio2Id)
                    }
                    .frame(width: 200)
                }
                SettingsCheckbox(label: language.tr("Po spuštění otevřít seznam dekódů"), isOn: $draft.openDecodesOnLaunch)
            }
            SettingsGroup(title: language.tr("JTDX: logování přes TCP")) {
                SettingsCaption(language.tr(
                    "JTDX posílá zalogovaná QSO jako ADIF přes TCP (External logbook). V JTDX nastav TCP server na tuto adresu; výchozí port 52001. Změny se projeví po uložení."))
                SettingsToggleRow(label: language.tr("Příjem zapnut"), isOn: $draft.jtdxTcpEnabled,
                                  text: $draft.jtdxTcpBind)
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
                SettingsCheckbox(label: language.tr("Sdílet port s dalšími aplikacemi"), isOn: $draft.nrSharePort)
            }
            SettingsGroup(title: language.tr("ADIF přes UDP (fldigi)")) {
                SettingsCaption(language.tr(
                    "Přijímá holý ADIF záznam po UDP (fldigi apod.) a importuje QSO do aktivního závodu. V programu nastav cíl UDP na tuto adresu. Výchozí port 2333. Změny se projeví po uložení."))
                SettingsToggleRow(label: language.tr("Příjem zapnut"), isOn: $draft.auReceiveEnabled,
                                  text: $draft.auReceiveBind)
                SettingsCheckbox(label: language.tr("Sdílet port s dalšími aplikacemi"), isOn: $draft.auSharePort)
            }
        }
    }
}
