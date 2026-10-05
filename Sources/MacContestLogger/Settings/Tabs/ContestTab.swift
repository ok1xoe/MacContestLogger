import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ContestTab` (`CT:27-148`): auto reload, the contest data directory with the counts of its definitions and
/// sets, the SCP file, the automatic backup and the call history file. The counts are made off the main thread
/// (`SettingsToolsModel.updateCounts`: at once when the tab opens, 300 ms after a change). The choosers
/// are `NSOpenPanel`s with Kotlin's dialog titles as their message.
struct ContestTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: "Start programu") {
                SettingsCheckbox(
                    label: language.tr("Při startu rovnou otevřít poslední závod (příkaz AUTORELOAD / NOAUTORELOAD)"),
                    isOn: $draft.autoReload)
            }
            dataGroup
            scpGroup
            backupGroup
            callHistoryGroup
        }
        .onAppear { app.settingsTools.updateCounts(draft) }
        .onChange(of: draft.contestDataDir) { app.settingsTools.updateCounts(draft) }
        .onChange(of: draft.scpFile) { app.settingsTools.updateCounts(draft) }
        .onChange(of: draft.callHistoryFile) { app.settingsTools.updateCounts(draft) }
    }

    private var dataGroup: some View {
        let tools: SettingsToolsModel = app.settingsTools
        let contests: String = String(tools.contestYamlCount ?? 0)
        let sets: String = String(tools.multiplierYamlCount ?? 0)
        return SettingsGroup(title: language.tr("Data závodů")) {
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: language.tr("Adresář s definicemi (contests/ nebo přímo .yaml) + multipliers/")) {
                    SettingsTextField(text: $draft.contestDataDir)
                }
                .frame(maxWidth: .infinity)
                Button {
                    ExportPanels.chooseDirectory(message: language.tr("Vyber adresář dat závodů")) { url in
                        draft.contestDataDir = url.path
                    }
                } label: {
                    Text(verbatim: language.tr("Vybrat adresář…"))
                }
                .buttonStyle(.borderedProminent)
            }
            Text(verbatim: "Nalezeno: \(contests) definic, \(sets) sad")
                .windowFont(12)
                .foregroundStyle(.secondary)
            SettingsCaption(language.tr("Uložení přenačte katalog závodů a sady multiplikátorů."))
        }
    }

    private var scpGroup: some View {
        let count: Int = app.settingsTools.scpCount ?? 0
        let text: String = KotlinStrings.isBlank(draft.scpFile)
            ? language.tr(
                "Bez souboru se volačky nenašeptávají; logovat jde dál. Aktuální soubor stáhne Nastavení → Stáhnout master.scp.")
            : language.tr("Nalezeno: %s volaček", .int(count))
        return SettingsGroup(title: language.tr("Našeptávání volaček (SCP)")) {
            fileRow(caption: "Soubor master.scp", text: $draft.scpFile, panelMessage: "Vyber soubor master.scp")
            Text(verbatim: text)
                .windowFont(12)
                .foregroundStyle(.secondary)
            SettingsCheckbox(label: language.tr("Zobrazovat SCP (Check partial)"), isOn: $draft.scpSuggestionsEnabled)
            SettingsCheckbox(label: language.tr("Zobrazovat N+1"), isOn: $draft.nPlusOneEnabled)
        }
    }

    private var backupGroup: some View {
        let backups: String = app.dataDir.appendingPathComponent("backups").path
        return SettingsGroup(title: language.tr("Automatická záloha deníku")) {
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: "Interval (min, 0 = vypnuto)") {
                    SettingsTextField(text: $draft.autoBackupMinutes, filter: .digits(limit: 4))
                }
                .frame(width: 200)
                SettingsField(caption: language.tr("Počet záloh")) {
                    SettingsTextField(text: $draft.autoBackupKeep, filter: .digits(limit: 3))
                }
                .frame(width: 120)
                SettingsField(caption: language.tr("Adresář (prázdné = %s)", .string(backups))) {
                    SettingsTextField(text: $draft.autoBackupDir)
                }
                .frame(maxWidth: .infinity)
            }
            SettingsCaption(language.tr(
                "Záloha (kopie databáze) se dělá jen po změně deníku a při ukončení aplikace; starší automatické zálohy nad počet se mažou. Ruční záloha: příkaz COPYLOG."))
        }
    }

    private var callHistoryGroup: some View {
        let count: Int = app.settingsTools.callHistoryCount ?? 0
        let text: String = KotlinStrings.isBlank(draft.callHistoryFile)
            ? language.tr("Bez souboru se výměna z call history nepředvyplňuje.")
            : language.tr("Nalezeno: %s volaček", .int(count))
        return SettingsGroup(title: language.tr("Call history (předvyplnění výměny)")) {
            fileRow(caption: language.tr("Soubor call history (formát N1MM)"), text: $draft.callHistoryFile,
                    panelMessage: "Vyber soubor call history")
            Text(verbatim: text)
                .windowFont(12)
                .foregroundStyle(.secondary)
        }
    }

    /// A path field with „Vybrat soubor…" (an `NSOpenPanel` titled like Kotlin's `FileDialog`).
    private func fileRow(caption: String, text: Binding<String>, panelMessage: String) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            SettingsField(caption: caption) {
                SettingsTextField(text: text)
            }
            .frame(maxWidth: .infinity)
            Button {
                ExportPanels.openFile(message: panelMessage) { url in
                    text.wrappedValue = url.path
                }
            } label: {
                Text(verbatim: "Vybrat soubor…")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
