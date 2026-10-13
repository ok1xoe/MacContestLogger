import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The DX Cluster window's options (the tabs of the N1MM+ Telnet window that are not the spot filter): every change
/// applies and is saved at once, like the spot filter sheet.
struct TelnetOptionsSheet: View {
    let app: AppModel
    @Binding var fontSize: Int
    let close: () -> Void

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $fontSize, language: language) {
                Text(verbatim: language.tr("Možnosti DX clusteru")).windowFont(15, weight: .semibold)
            }
            TabView {
                ScrollView {
                    TelnetClustersTab(app: app).padding(8)
                }
                .tabItem { Text(verbatim: language.tr("Clustery")) }
            }
            DialogButtonRow {
                Button(language.tr("Zavřít")) { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 600, height: 520)
        .environment(\.windowFontSize, fontSize)
    }
}

/// N1MM „Clusters" tab: auto logon, the node software (DXSpider formatting), the buttons and the band map's SH/DX
/// count.
struct TelnetClustersTab: View {
    let app: AppModel

    var body: some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        VStack(alignment: .leading, spacing: 10) {
            SettingsCheckbox(label: language.tr("Při otevření okna se připojit a přihlásit k vybranému clusteru"),
                             isOn: Binding(get: { cluster.autoLogon }, set: { cluster.setAutoLogon($0) }))
                .accessibilityIdentifier("telnet.autologon")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: language.tr("Software clusteru")).windowFont(12)
                Picker(selection: Binding(get: { cluster.configuredSoftware }, set: { cluster.setSoftware($0) })) {
                    ForEach(ClusterSoftware.allCases, id: \.self) { software in
                        Text(verbatim: software == .auto ? language.tr("Rozpoznat automaticky") : software.productName)
                            .tag(software)
                    }
                } label: {
                    Text(verbatim: language.tr("Software clusteru"))
                }
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel(language.tr("Software clusteru"))
                .accessibilityIdentifier("telnet.software")
            }
            SettingsCaption(detectedText(language, cluster))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: language.tr("Počet spotů pro SH/DX z bandmapy")).windowFont(12)
                Stepper(value: Binding(get: { cluster.showDxCount }, set: { cluster.setShowDxCount($0) }),
                        in: ClusterCommandFormat.showDxCountRange) {
                    Text(verbatim: String(cluster.showDxCount)).windowFont(12).monospacedDigit()
                }
                .accessibilityLabel(language.tr("Počet spotů pro SH/DX z bandmapy"))
                .accessibilityValue(String(cluster.showDxCount))
                .accessibilityIdentifier("telnet.shdxcount")
            }
            SettingsCaption(language.tr("Bandmapa pošle %s.", .string(cluster.showDxCommand())))
            Divider()
            SettingsCheckbox(label: language.tr("Zobrazit tlačítka příkazů"),
                             isOn: Binding(get: { cluster.showButtons }, set: { cluster.setShowButtons($0) }))
                .accessibilityIdentifier("telnet.showbuttons")
            HStack(spacing: 8) {
                SettingsButton(language.tr("Uložit tlačítka…")) { saveButtons(language) }
                    .accessibilityIdentifier("telnet.buttons.save")
                SettingsButton(language.tr("Načíst tlačítka…")) { loadButtons(language) }
                    .accessibilityIdentifier("telnet.buttons.load")
                Spacer(minLength: 0)
            }
            SettingsCaption(language.tr(
                "Makra tlačítek: {WAIT} počká 5 s, {CONN} název připojí cluster ze seznamu (např. „{CONN} RBN“)."))
        }
    }

    private func detectedText(_ language: LanguageModel, _ cluster: DxClusterModel) -> String {
        let detected: String = cluster.detectedSoftware?.productName ?? language.tr("zatím nerozpoznán")
        return language.tr("Rozpoznaný software: %s · příkazy se formátují pro %s", .string(detected),
                           .string(cluster.software.productName))
    }

    private func saveButtons(_ language: LanguageModel) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DX Cluster buttons.txt"
        panel.title = language.tr("Uložit tlačítka…")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(app.dxCluster.buttonsFileText.utf8).write(to: url)
        } catch {
            app.status.showJoined(ClusterTexts.macroSaveFailed(ErrorText.message(error)).parts, separator: "")
        }
    }

    private func loadButtons(_ language: LanguageModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = language.tr("Načíst tlačítka…")
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        app.dxCluster.loadButtons(String(decoding: data, as: UTF8.self))
    }
}
