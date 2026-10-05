import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ClusterTab` (`CLT:21-122`): the network multi-op log over MQTT. The connection state is the cluster model's
/// one-time snapshot after the start (`connected`): „Stav: připojeno" / „Stav: odpojeno".
struct ClusterTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        SettingsGroup(title: language.tr("Síťový multi-op deník")) {
            SettingsCheckbox(label: language.tr("Zapnout síťový multi-op deník"), isOn: $draft.clusterEnabled)
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: "Broker (IP/hostname cluster stroje)") {
                    SettingsTextField(text: $draft.brokerHost)
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: "Port (1883, TLS 8883)") {
                    SettingsTextField(text: $draft.clusterPort, filter: .digits(limit: nil))
                }
                .frame(width: 160)
            }
            SettingsField(caption: language.tr("ID stanice (= Client ID + původ QSO, např. OP1)")) {
                SettingsTextField(text: $draft.stationId, filter: .trim)
            }
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: language.tr("Uživatel (účet stanice na brokeru)")) {
                    SettingsTextField(text: $draft.username)
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: "Heslo") {
                    SettingsTextField(text: $draft.password, isPassword: true)
                }
                .frame(maxWidth: .infinity)
            }
            SettingsCheckbox(label: language.tr("TLS (ssl://, nedůvěryhodná LAN)"), isOn: $draft.tls)
            SettingsCheckbox(
                label: language.tr(
                    "Sdílet spoty z DX clusteru s ostatními stanicemi (stačí jedno telnet spojení v síti)"),
                isOn: $draft.shareSpots)
            SettingsCheckbox(
                label: language.tr(
                    "Pořadová čísla ze serial number serveru (autorita) — stanice nikdy nepošlou stejné číslo"),
                isOn: $draft.serialServer)
            choices
            Text(verbatim: app.cluster.connected ? language.tr("Stav: připojeno") : "Stav: odpojeno")
                .windowFont(12)
                .accessibilityIdentifier("settings.cluster.status")
            SettingsCaption(language.tr("Uložení restartuje spojení ke clusteru."))
        }
    }

    @ViewBuilder private var choices: some View {
        SettingsText("Typ stanice (multi-op):", size: 14)
        HStack(spacing: 12) {
            SettingsRadio(label: language.tr("Neurčen"), selected: draft.stationType == .none) {
                draft.stationType = .none
            }
            SettingsRadio(label: "RUN", selected: draft.stationType == .run) { draft.stationType = .run }
            SettingsRadio(label: language.tr("MULT (jen nové násobiče)"), selected: draft.stationType == .mult) {
                draft.stationType = .mult
            }
        }
        SettingsText(language.tr("Pravidla provozu při zápisu (pravidlo N minut, změny pásma za hodinu, MULT):"),
                     size: 14)
        HStack(spacing: 12) {
            SettingsRadio(label: language.tr("Nehlídat"), selected: draft.ruleEnforcement == .off) {
                draft.ruleEnforcement = .off
            }
            SettingsRadio(label: "Upozornit", selected: draft.ruleEnforcement == .warn) {
                draft.ruleEnforcement = .warn
            }
            SettingsRadio(label: "Nezapsat (Ctrl+Alt+Enter projde)", selected: draft.ruleEnforcement == .block) {
                draft.ruleEnforcement = .block
            }
        }
        SettingsText(language.tr("TX interlock (nevysílat, když vysílá jiná stanice):"), size: 14)
        HStack(spacing: 12) {
            SettingsRadio(label: "Vypnuto", selected: draft.interlock == .none) { draft.interlock = .none }
            SettingsRadio(label: language.tr("Kdekoli (jeden signál)"), selected: draft.interlock == .all) {
                draft.interlock = .all
            }
            SettingsRadio(label: language.tr("Na stejném pásmu"), selected: draft.interlock == .sameBand) {
                draft.interlock = .sameBand
            }
        }
    }
}
