import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `MenuFileGroup` (`MT:186-259`): where the menu definition lives, which one applies now, „Vytvořit
/// menu.json k úpravám", „Otevřít adresář" and „Načíst menu znovu" with the message of the last action. The file work
/// runs off the main thread in `SettingsToolsModel`; opening the directory is the Finder's (`NSWorkspace`).
struct MenuFileGroup: View {
    let app: AppModel

    /// The message of „Otevřít adresář" (the model keeps the others); the last action's message is shown.
    @StateObject private var openMessageState = ViewState<String?>(nil)
    private var openMessage: String? {
        get { openMessageState.value }
        nonmutating set { openMessageState.value = newValue }
    }

    private var language: LanguageModel { app.language }

    var body: some View {
        let tools: SettingsToolsModel = app.settingsTools
        let state: SettingsToolsModel.MenuFileState? = tools.menuFileState
        let message: String = openMessage ?? tools.menuMessage
        SettingsGroup(title: "Menu aplikace") {
            SettingsCaption(language.tr(
                language.tr("Nabídky se berou z %s. Dokud tam soubor není, platí vestavěné menu z aplikace."),
                .string(state?.file ?? language.tr("datového adresáře"))))
            SettingsText(sourceText(state), isError: state?.source == .userInvalid)
            HStack(spacing: 8) {
                SettingsButton(language.tr("Vytvořit menu.json k úpravám")) {
                    openMessage = nil
                    tools.createMenuFile()
                }
                SettingsButton(language.tr("Otevřít adresář")) {
                    openDataDir()
                }
                SettingsButton(language.tr("Načíst menu znovu")) {
                    openMessage = nil
                    tools.reloadMenu()
                }
            }
            if !KotlinStrings.isBlank(message) {
                Text(verbatim: message)
                    .windowFont(12)
                    .foregroundStyle(.secondary)
            }
            SettingsCaption(footnote)
        }
        .onChange(of: tools.menuMessage) {
            openMessage = nil
        }
    }

    /// `MT:207-213`; the built-in text until the state is read.
    private func sourceText(_ state: SettingsToolsModel.MenuFileState?) -> String {
        switch state?.source {
        case .user:
            return language.tr("Teď platí tvůj soubor.")
        case .userInvalid:
            let error: String = state?.error ?? language.tr("neznámá chyba")
            return language.tr("Tvůj soubor se nepoužil: ") + error + language.tr(" Platí vestavěné menu.")
        default:
            return language.tr("Teď platí vestavěné menu.")
        }
    }

    private var footnote: String {
        let first: String = language.tr(
            "Po úpravě souboru stačí „Načíst menu znovu“ — restart není potřeba. Vadný soubor ")
        let second: String = language.tr(
            "aplikaci o nabídky nepřipraví: použije se vestavěné menu a důvod se ukáže tady. ")
        let third: String = language.tr("Smazáním souboru se vrátíš k vestavěnému menu.")
        return first + second + third
    }

    /// `Desktop.open(dataDir)` (`MT:239-244`): „Adresář otevřen." or the failure. `NSWorkspace` reports no reason,
    /// so the failure names the directory.
    private func openDataDir() {
        let dir: URL = app.dataDir
        if NSWorkspace.shared.open(dir) {
            openMessage = language.tr("Adresář otevřen.")
        } else {
            openMessage = language.tr("Adresář se nepodařilo otevřít: %s", .string(dir.path))
        }
    }
}
