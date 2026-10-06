import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `ScoreReportingTab` (`SR:22-72`): the online scoreboard and Club Log Live Stream. „Odeslat teď" commits the
/// whole draft and then reports through its port (the window stays open); it is off while a commit runs
/// or the draft is not read yet. The report and Club Log status lines are the online services' live status texts.
struct ScoreReportingTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        let settings: SettingsModel = app.settings
        VStack(alignment: .leading, spacing: 12) {
            SettingsCheckbox(label: language.tr("Odesílat průběžné skóre na server"), isOn: $draft.srEnabled)
            SettingsCheckbox(label: language.tr("Včetně rozpadu po pásmech a módech"), isOn: $draft.srBreakdown)
            serverGroup
            HStack(spacing: 12) {
                SettingsButton(language.tr("Odeslat teď")) {
                    Task { await settings.sendScoreNow() }
                }
                .disabled(settings.isSaving || settings.draft == nil)
                SettingsCaption(language.text(app.onlineServices.scoreReportStatus))
            }
            clubLogGroup
            clubLogDxccGroup
        }
    }

    private var serverGroup: some View {
        let boards = ConfigurerCatalogs.scoreboards
        let current: String = ConfigurerCatalogs.scoreboardName(forUrl: draft.srUrl) ?? language.tr("vlastní URL")
        return SettingsGroup(title: "Server") {
            HStack(alignment: .top, spacing: 12) {
                SettingsField(caption: "Scoreboard") {
                    SettingsDropdown(label: current, options: boards.map(\.name), language: language) { picked in
                        if let board = boards.first(where: { $0.name == picked }) {
                            draft.srUrl = board.url
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsField(caption: "Interval (min, ≥ 2)") {
                    SettingsTextField(text: $draft.srMinutes, filter: .digits(limit: 3))
                }
                .frame(width: 140)
            }
            SettingsField(caption: "URL") {
                SettingsTextField(text: $draft.srUrl)
            }
            SettingsCaption(language.tr(
                "Skóre (XML <dynamicresults>) se posílá jen v závodě a jen po změně deníku. Kategorie se berou z nastavení závodu (Nový závod), zóny a lokátor ze stanice."))
        }
    }

    private var clubLogGroup: some View {
        SettingsGroup(title: "Club Log Live Stream") {
            SettingsCheckbox(label: language.tr("Posílat každé zapsané QSO do Club Logu"), isOn: $draft.clEnabled)
            HStack(alignment: .top, spacing: 12) {
                SettingsField(caption: language.tr("E-mail účtu")) {
                    SettingsTextField(text: $draft.clEmail)
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: "Heslo aplikace") {
                    SettingsTextField(text: $draft.clPassword, isPassword: true)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(alignment: .top, spacing: 12) {
                SettingsField(caption: language.tr("Volačka deníku (prázdné = stanice)")) {
                    SettingsTextField(text: $draft.clCallsign)
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: language.tr("API klíč")) {
                    SettingsTextField(text: $draft.clApiKey, isPassword: true)
                }
                .frame(maxWidth: .infinity)
            }
            SettingsCaption(language.tr(
                "Heslo aplikace vytvoříš na clublog.org → Settings → App Passwords. API klíč vydává Club Log (Helpdesk). Nepovedené odeslání se opakuje, dokud aplikace běží."))
            SettingsCaption(language.text(app.onlineServices.clubLogStatus))
        }
    }

    /// DXCC from Club Log's `cty.xml` (Swift only): the switch, the manual update and the cache line. The download
    /// uses the API key above; the button is off while an update runs.
    private var clubLogDxccGroup: some View {
        let tools: DataToolsModel = app.dataTools
        return SettingsGroup(title: language.tr("DXCC z Club Logu (cty.xml)")) {
            SettingsCheckbox(label: language.tr("Používat DXCC z Club Logu (stažení nejvýš jednou denně)"),
                             isOn: $draft.clCtyEnabled)
            HStack(spacing: 12) {
                SettingsButton(language.tr("Aktualizovat DXCC z Club Logu")) {
                    tools.updateClubLogDxcc()
                }
                .disabled(tools.clubLogCtyRunning)
                if let line = tools.clubLogCtyStatus {
                    SettingsCaption(language.text(line))
                }
            }
            SettingsCaption(language.tr(
                "Stáhne se s API klíčem výše nejvýš jednou za 24 hodin, vyhledávání je vždy místní. Bez stažené kopie se používají místní data (~/dxcc-json)."))
            if let result = tools.clubLogCtyResult {
                SettingsCaption(language.text(result))
            }
        }
    }
}
