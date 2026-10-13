import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ContestTab` (`CT:27-148`): auto reload, the contest data directory with the counts of its definitions and
/// sets, the SCP file, the automatic backup and the call history (the main file, N1MM's merged additional files, the
/// active contest's own file and the lookup / user information switches). The counts are made off the main thread
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
            extraFilesList
            contestFileRow
            Text(verbatim: language.tr("Načteno celkem: %s volaček", .int(app.callData.callHistory.size)))
                .windowFont(12)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.callHistory.total")
            SettingsCheckbox(label: language.tr("Zapnout dohledávání v call history"),
                             isOn: $draft.callHistoryLookupEnabled)
            SettingsCheckbox(label: language.tr("Zobrazovat informace uživatele (UserText)"),
                             isOn: $draft.callHistoryShowUserInfo)
            SettingsCaption(language.tr(
                "Další soubory se sloučí za hlavní do jedné tabulky (pozdější soubor doplní prázdná pole, UserText se připojí). Řádky # s názvem závodu zapnou dohledávání jen v tom závodě."))
        }
    }

    /// N1MM's import of several files into one table: the additional files, each with „Odebrat", and „Přidat
    /// soubory…" (multiple selection).
    private var extraFilesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: language.tr("Další soubory call history (sloučené)"))
                .windowFont(12, weight: .medium)
            ForEach(Array(draft.callHistoryExtraFiles.enumerated()), id: \.offset) { index, path in
                HStack(spacing: 8) {
                    Text(verbatim: path)
                        .windowFont(12)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        draft.callHistoryExtraFiles.remove(at: index)
                    } label: {
                        Text(verbatim: language.tr("Odebrat"))
                    }
                    .accessibilityLabel(Text(verbatim: language.tr("Odebrat") + " " + path))
                }
            }
            Button {
                ExportPanels.openFiles(message: language.tr("Vyber soubory call history ke sloučení")) { urls in
                    for url in urls where !draft.callHistoryExtraFiles.contains(url.path) {
                        draft.callHistoryExtraFiles.append(url.path)
                    }
                }
            } label: {
                Text(verbatim: language.tr("Přidat soubory…"))
            }
        }
    }

    /// N1MM Contest Setup → Associated Files: the active contest's own file, applied to the contest at once.
    @ViewBuilder private var contestFileRow: some View {
        if let own = app.dataTools.contestCallHistoryFile {
            HStack(spacing: 8) {
                Text(verbatim: own.isEmpty
                     ? language.tr("Aktivní závod používá hlavní soubor call history")
                     : language.tr("Call history aktivního závodu: %s", .string(own)))
                    .windowFont(12)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    ExportPanels.openFile(message: language.tr("Vyber soubor call history pro tento závod")) { url in
                        app.dataTools.setContestCallHistoryFile(url.path)
                    }
                } label: {
                    Text(verbatim: language.tr("Přiřadit závodu…"))
                }
                if !own.isEmpty {
                    Button {
                        app.dataTools.setContestCallHistoryFile("")
                    } label: {
                        Text(verbatim: language.tr("Zrušit přiřazení"))
                    }
                }
            }
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
