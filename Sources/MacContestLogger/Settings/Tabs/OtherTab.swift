import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `OtherTab` (`MT:103-184`): steps, time synchronisation, the language (the content of the language
/// directory), the look, options and the application menu. The languages and the menu file state are read when the
/// tab opens (off the main thread).
struct OtherTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepsGroup
            timeGroup
            LanguageGroup(app: app, draft: $draft)
            AppearanceGroup(language: language, draft: $draft)
            SettingsGroup(title: "Volby") {
                SettingsCheckbox(label: language.tr("Po zapsání QSO vynulovat RIT"), isOn: $draft.ritClearAfterLog)
                SettingsCheckbox(label: language.tr("Pípnout, když je volačka dupe"), isOn: $draft.beepOnDupe)
            }
            MenuFileGroup(app: app)
        }
        .onAppear {
            app.settingsTools.loadLanguages()
            app.settingsTools.refreshMenuFile()
        }
    }

    private var stepsGroup: some View {
        SettingsGroup(title: "Kroky") {
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: "Krok rychlosti CW (PgUp/PgDn, WPM)") {
                    SettingsTextField(text: $draft.cwSpeedStep, filter: .digits(limit: 2))
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: language.tr("Ladění ↑↓ a RIT — CW / digi (Hz)")) {
                    SettingsTextField(text: $draft.tuneStepCw, filter: .digits(limit: 4))
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: language.tr("Ladění ↑↓ a RIT — fone (Hz)")) {
                    SettingsTextField(text: $draft.tuneStepSsb, filter: .digits(limit: 4))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var timeGroup: some View {
        SettingsGroup(title: language.tr("Synchronizace času")) {
            SettingsField(caption: language.tr("NTP server (prázdné = vypnuto)")) {
                SettingsTextField(text: $draft.ntpServer)
            }
            .frame(maxWidth: 280, alignment: .leading)
            SettingsCheckbox(label: language.tr("Opravovat čas nově zapsaných QSO o zjištěnou odchylku"),
                             isOn: $draft.ntpCorrect)
            SettingsCaption(language.tr(
                "Odchylka se zjišťuje při startu, po uložení a každou půlhodinu; nad 1 s přijde varování. Hodiny systému se nemění (vyžaduje práva správce) — nejlepší je zapnout Nastavení systému → Obecné → Datum a čas → Nastavit automaticky."))
        }
    }
}

/// „Jazyk / Language" (`MT:127-164`): the menu is the content of the language directory; the stored value is the
/// code. „Načíst znovu" restores the shipped files and lists again, „Otevřít adresář" shows the directory.
private struct LanguageGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        let languages: [LanguageCatalog.Language] = app.settingsTools.languages
        SettingsGroup(title: "Jazyk / Language") {
            FlowLayout(spacing: 8) {
                SettingsField(caption: "Jazyk") {
                    SettingsDropdown(label: LanguageChoice.selectedLabel(code: draft.language, in: languages),
                                     options: languages.map(LanguageChoice.label), language: language) { picked in
                        if let code = LanguageChoice.code(forLabel: picked, in: languages) {
                            draft.language = code
                        }
                    }
                }
                .frame(width: 260, alignment: .leading)
                SettingsButton(language.tr("Načíst znovu")) {
                    app.settingsTools.reloadLanguages()
                }
                SettingsButton(language.tr("Otevřít adresář")) {
                    openLanguageDir()
                }
            }
            SettingsCaption(help)
        }
    }

    /// The nested `tr` of `MT:154-163`: the first two parts form the key of the `%s` text.
    private var help: String {
        let language: LanguageModel = app.language
        let head: String = language.tr("Nabídka je obsah adresáře %s. Soubor se jmenuje lang_<kód>.json ")
            + language.tr("(např. lang_de.json), klíčem je český text ")
        let first: String = language.tr(head, .string(language.languageDir.path))
        let second: String = language.tr("z aplikace a hodnotou překlad; nepovinný klíč _name je název jazyka do téhle ")
        let third: String = language.tr("nabídky. Co v souboru chybí, zůstane česky, takže překládat jde po částech. ")
        let fourth: String = language.tr("Vzorem je lang_en.json, který se do adresáře vytvoří sám.")
        return [first, second, third, fourth].joined()
    }

    /// `LanguageCatalog.ensureDir` off the main thread, then the directory in the Finder.
    private func openLanguageDir() {
        let dir: URL = app.language.languageDir
        Task {
            _ = try? await BlockingQueue.run { LanguageCatalog.ensureDir(dir) }
            NSWorkspace.shared.open(dir)
        }
    }
}

/// „Vzhled" (`MT:165-177`): theme mode and accent (`ACCENTS[x] ?: tr("Tyrkysová")`).
private struct AppearanceGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let accents = ConfigurerCatalogs.accents
        SettingsGroup(title: "Vzhled") {
            HStack(spacing: 16) {
                ForEach(ConfigurerCatalogs.themeModes, id: \.key) { mode in
                    SettingsRadio(label: language.tr(mode.labelKey), selected: draft.themeMode == mode.key) {
                        draft.themeMode = mode.key
                    }
                }
            }
            SettingsField(caption: language.tr("Barevný akcent")) {
                SettingsDropdown(label: language.tr(ConfigurerCatalogs.accentLabelKey(draft.themeAccent)),
                                 options: accents.map { language.tr($0.labelKey) }, language: language) { picked in
                    if let accent = accents.first(where: { language.tr($0.labelKey) == picked }) {
                        draft.themeAccent = accent.key
                    }
                }
            }
            .frame(maxWidth: 260, alignment: .leading)
            SettingsCaption(language.tr(
                "Vysoký kontrast = černé pozadí a žlutý akcent pro noční provoz. Velikost písma má každé okno vlastní (A− / A+ vpravo nahoře)."))
        }
    }
}
