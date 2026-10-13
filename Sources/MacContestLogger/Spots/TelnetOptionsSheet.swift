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
                ScrollView {
                    TelnetSpotCommentTab(app: app).padding(8)
                }
                .tabItem { Text(verbatim: language.tr("Komentář spotu")) }
                TelnetSpecialCallsTab(app: app)
                    .padding(8)
                    .tabItem { Text(verbatim: language.tr("Zvláštní volačky")) }
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
            spotKeeping(language, cluster)
        }
    }

    /// N1MM „Save Spots" and „Randomize incoming spot frequencies".
    @ViewBuilder
    private func spotKeeping(_ language: LanguageModel, _ cluster: DxClusterModel) -> some View {
        Divider()
        SettingsCheckbox(label: language.tr("Uchovat spoty přes restart programu"),
                         isOn: Binding(get: { cluster.saveSpots }, set: { cluster.setSaveSpots($0) }))
            .accessibilityIdentifier("telnet.savespots")
        SettingsCaption(language.tr("Při ukončení se spoty uloží a po startu se vrátí ty, které jsou ještě v časovém limitu."))
        SettingsCheckbox(label: language.tr("Náhodně posunout kmitočet při naladění spotu"),
                         isOn: Binding(get: { cluster.randomizeSpotFrequencies },
                                       set: { cluster.setRandomizeSpotFrequencies($0) }))
            .accessibilityIdentifier("telnet.randomize")
        SettingsCaption(language.tr(
            "Naladí 50–150 Hz (fonie 100–250 Hz) vedle spotu, aby všichni nevolali přesně na stejném kmitočtu."))
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

/// N1MM „Spot Comment" tab: the comment of every spot MCL makes (with the spot-comment macros) and the opt-in
/// „Spot all S&P QSOs".
struct TelnetSpotCommentTab: View {
    let app: AppModel
    @State private var comment: String = ""

    var body: some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        VStack(alignment: .leading, spacing: 10) {
            SettingsField(caption: language.tr("Komentář ke všem spotům")) {
                TextField(text: $comment) { Text(verbatim: "") }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .windowFont(13)
                    .onSubmit { cluster.setSpotComment(comment) }
                    .accessibilityLabel(language.tr("Komentář ke všem spotům"))
                    .accessibilityIdentifier("telnet.spotcomment")
            }
            SettingsCaption(language.tr(
                "Makra: {GRIDSQUARE} lokátor, {MODE} mód, {QTH} QTH/stát/okres, {ZONE} zóna — z výměny spotovaného QSO. Použije se pro Spot It (Alt+P), předvyplní Ctrl+P a {SPOTME}."))
            Divider()
            SettingsCheckbox(label: language.tr("Spotovat všechna S&P spojení"),
                             isOn: Binding(get: { cluster.spotAllSpQsos }, set: { cluster.setSpotAllSpQsos($0) }))
                .accessibilityIdentifier("telnet.spotallsp")
            SettingsCaption(language.tr(
                "Pozor: každé S&P spojení, které ještě není v bandmapě, se pošle jako spot do veřejné DX cluster sítě. Ověř, že to propozice závodu dovolují. Dupy, spojení zapsaná po závodě a simulátor se nespotují."))
        }
        .onAppear { comment = cluster.spotComment }
        .onDisappear { cluster.setSpotComment(comment) }
    }
}

/// N1MM „Special Calls" tab: the calls whose spots get a heart in the band map and the Available window.
struct TelnetSpecialCallsTab: View {
    let app: AppModel
    @State private var text: String = ""
    @Environment(\.windowFontSize) private var fontSize

    var body: some View {
        let language: LanguageModel = app.language
        let cluster: DxClusterModel = app.dxCluster
        VStack(alignment: .leading, spacing: 8) {
            SettingsCaption(language.tr(
                "Bonusové stanice, členové klubu, přátelé: jejich spoty mají v bandmapě a v okně Dostupné srdce ♥. Jedna volačka na řádek."))
            TextEditor(text: $text)
                .font(.system(size: CGFloat(WindowFont.size(12, windowSize: fontSize)), design: .monospaced))
                .frame(minHeight: 180)
                .border(Color.secondary.opacity(0.4))
                .accessibilityLabel(language.tr("Zvláštní volačky"))
                .accessibilityIdentifier("telnet.specialcalls")
            SettingsCheckbox(label: language.tr("Automaticky zahrnout bonusové stanice závodu"),
                             isOn: Binding(get: { cluster.specialCallsIncludeBonus },
                                           set: { cluster.setSpecialCallsIncludeBonus($0) }))
                .accessibilityIdentifier("telnet.specialcalls.bonus")
            HStack(spacing: 8) {
                SettingsButton(language.tr("Použít")) { apply(cluster) }
                    .accessibilityIdentifier("telnet.specialcalls.apply")
                SettingsButton(language.tr("Importovat…")) { importFile(cluster, language) }
                    .accessibilityIdentifier("telnet.specialcalls.import")
                SettingsButton(language.tr("Exportovat…")) { exportFile(cluster, language) }
                    .accessibilityIdentifier("telnet.specialcalls.export")
                SettingsButton(language.tr("Vymazat seznam")) {
                    cluster.clearSpecialCalls()
                    text = ""
                }
                .accessibilityIdentifier("telnet.specialcalls.clear")
                Spacer(minLength: 0)
            }
        }
        .onAppear { text = cluster.specialCalls.joined(separator: "\n") }
        .onDisappear { apply(cluster) }
    }

    private func apply(_ cluster: DxClusterModel) {
        cluster.setSpecialCalls(text: text)
        text = cluster.specialCalls.joined(separator: "\n")
    }

    private func importFile(_ cluster: DxClusterModel, _ language: LanguageModel) {
        apply(cluster)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = language.tr("Importovat…")
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        cluster.importSpecialCalls(String(decoding: data, as: UTF8.self))
        text = cluster.specialCalls.joined(separator: "\n")
    }

    private func exportFile(_ cluster: DxClusterModel, _ language: LanguageModel) {
        apply(cluster)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Special calls.txt"
        panel.title = language.tr("Exportovat…")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(cluster.specialCallsFileText.utf8).write(to: url)
        } catch {
            app.status.showVerbatim(ErrorText.message(error))
        }
    }
}
