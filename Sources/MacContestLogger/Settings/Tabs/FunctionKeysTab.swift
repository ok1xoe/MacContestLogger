import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `FunctionKeysTab` (`VK:113-193`): ESM, Run / S&P, and the F1–F12 messages of the SSB, CW and digi sets,
/// each for Run and S&P. Which set is shown is the tab's own state (Kotlin `remember`), reset when the tab opens.
struct FunctionKeysTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    /// 0 = SSB, 1 = CW, 2 = digi.
    @StateObject private var kindState = ViewState<Int>(0)
    private var kind: Int {
        get { kindState.value }
        nonmutating set { kindState.value = newValue }
    }
    @StateObject private var runState = ViewState<Bool>(true)
    private var run: Bool {
        get { runState.value }
        nonmutating set { runState.value = newValue }
    }

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EsmGroup(language: language, draft: $draft)
            RunSpGroup(language: language, draft: $draft)
            messagesGroup
        }
    }

    private var path: WritableKeyPath<ConfigurerDraft, [FunctionKeyDraft]> {
        switch (kind, run) {
        case (1, true): return \.cwRun
        case (1, false): return \.cwSp
        case (2, true): return \.digiRun
        case (2, false): return \.digiSp
        case (_, true): return \.vkRun
        default: return \.vkSp
        }
    }

    private var defaults: [FunctionKeyMessage] {
        switch (kind, run) {
        case (1, true): return CwKeyerConfig.defaultRun()
        case (1, false): return CwKeyerConfig.defaultSp()
        case (2, true): return DigitalConfig.defaultRun()
        case (2, false): return DigitalConfig.defaultSp()
        case (_, true): return VoiceKeyerConfig.defaultRun()
        default: return VoiceKeyerConfig.defaultSp()
        }
    }

    private var title: String {
        switch kind {
        case 1: return language.tr("CW zprávy (CW klíč)")
        case 2: return language.tr("Digi zprávy (RTTY/PSK přes fldigi)")
        default: return language.tr("SSB zprávy (hlasový klíč)")
        }
    }

    private var help: String {
        switch kind {
        case 2:
            return language.tr(
                "Text k odvysílání přes fldigi, makra jako u CW (* / {MYCALL}, !, #, {SENTRST}, {EXCH}, {LOG}, {WIPE}…); čísla se nezkracují. Mezera na začátku a konci se přidá sama.")
        case 1:
            return language.tr(
                "Text k odvysílání s makry (formát N1MM): * nebo {MYCALL} moje volačka · ! volačka protistanice · # pořadové číslo · {SENTRST} / {SENTRSTCUT} report (5NN) · {EXCH} odesílaná výměna ze setupu závodu · prosigny ] SK, + AR, [ AS, = BT · < > rychlost ±2 WPM · {LOG} {WIPE} {RUN} {S&P} akce.")
        default:
            return language.tr(
                "Zpráva = čárkou oddělené wav soubory a makra: {OPERATOR}/CQ.wav · ! volačka protistanice · # odesílané číslo · * nebo {MYCALL} moje volačka · @ frekvence. Víc souborů za sebou: a.wav,b.wav. Prázdná zpráva nic nevysílá. Nahrát zprávu s jedním wav: Ctrl+Shift+F-klávesa v zadávacím okně.")
        }
    }

    private var messagesGroup: some View {
        let path: WritableKeyPath<ConfigurerDraft, [FunctionKeyDraft]> = self.path
        return SettingsGroup(title: title) {
            SettingsCaption(help)
            switcher
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft[dynamicMember: path]) { $message in
                    MessageRow(index: indexOf(message.id, in: draft[keyPath: path]), message: $message)
                }
            }
        }
    }

    private func indexOf(_ id: UUID, in rows: [FunctionKeyDraft]) -> Int {
        rows.firstIndex { $0.id == id } ?? 0
    }

    /// SSB / CW / Digi, Run / S&P (a button is disabled while its set is shown) and „Výchozí zprávy".
    private var switcher: some View {
        HStack(spacing: 8) {
            SettingsButton("SSB", borderless: true) { kind = 0 }.disabled(kind == 0)
            SettingsButton("CW", borderless: true) { kind = 1 }.disabled(kind == 1)
            SettingsButton("Digi", borderless: true) { kind = 2 }.disabled(kind == 2)
            Spacer().frame(width: 12)
            SettingsButton("Run", borderless: true) { run = true }.disabled(run)
            SettingsButton("S&P", borderless: true) { run = false }.disabled(!run)
            SettingsCaption(run ? language.tr("Sada pro Run (voláš výzvu)") : language.tr("Sada pro S&P (loviš stanice)"))
            Spacer(minLength: 0)
            SettingsButton(language.tr("Výchozí zprávy"), borderless: true) { resetMessages() }
        }
    }

    /// Kotlin sets label and text of every shown message from the defaults by index.
    private func resetMessages() {
        let path: WritableKeyPath<ConfigurerDraft, [FunctionKeyDraft]> = self.path
        let values: [FunctionKeyMessage] = defaults
        var rows: [FunctionKeyDraft] = draft[keyPath: path]
        for index in rows.indices where index < values.count {
            rows[index].label = values[index].label
            rows[index].text = values[index].text
        }
        draft[keyPath: path] = rows
    }
}

/// One message: `F<n>`, its label (120 pt) and its text.
private struct MessageRow: View {
    let index: Int
    @Binding var message: FunctionKeyDraft

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "F" + String(index + 1))
                .windowFont(14)
                .frame(width: 32, alignment: .leading)
            SettingsTextField(text: $message.label)
                .frame(width: 120)
            SettingsTextField(text: $message.text)
                .frame(maxWidth: .infinity)
        }
    }
}

/// „ESM – Enter Sends Message" (`VK:129-134`).
private struct EsmGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        SettingsGroup(title: "ESM – Enter Sends Message") {
            SettingsCaption(language.tr(
                "Enter pošle zprávu podle stavu zadávacího okna (jako N1MM): Run – prázdná volačka F1, volačka F5+F2, platná výměna F3 a zapsat; S&P – F4, platná výměna F2 a zapsat. Klávesy, které pošle příští Enter, mají v okně rámeček. „=“ zopakuje poslední zprávu. Předpoklad: F1 CQ, F2 výměna, F3 TU, F4 moje volačka, F5 jeho volačka, F6 QSO B4, F8 znovu?"))
            SettingsCheckbox(
                label: language.tr("ESM zapnuto (přepíná i zaškrtávátko v zadávacím okně a příkaz ESM / NOESM)"),
                isOn: $draft.esmEnabled)
            SettingsCheckbox(
                label: language.tr("S&P: poslat volačku jen jednou, pak kurzor do výměny („Big Gun“)"),
                isOn: $draft.esmSpCallOnce)
            SettingsCheckbox(label: language.tr("Run: dupe dělat jako nové QSO (Work dupes)"),
                             isOn: $draft.esmWorkDupes)
        }
    }
}

/// „Run / S&P" (`VK:136-146`).
private struct RunSpGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        SettingsGroup(title: "Run / S&P") {
            SettingsCaption(language.tr(
                "F1 (CQ) nebo přepnutí do Run zapamatuje CQ frekvenci pásma (v bandmapě značka CQ). Alt+U přepíná Run/S&P, Alt+Q vrátí na CQ frekvenci, Shift+F pošle zprávu z opačné sady."))
            SettingsCheckbox(
                label: language.tr(
                    "Automaticky přepínat: QSY pryč od CQ frekvence → S&P (Alt+F11, příkaz AUTORSP / NOAUTRSP)"),
                isOn: $draft.runAutoSwitch)
            SettingsCheckbox(label: language.tr("Návrat na CQ frekvenci přepne do Run (vypnout pro sprinty)"),
                             isOn: $draft.runOnCqFrequency, enabled: draft.runAutoSwitch)
            HStack(alignment: .center, spacing: 12) {
                SettingsField(caption: "Pauza mezi CQ (s)") {
                    SettingsTextField(text: $draft.repeatSeconds, filter: .digitsAnd(extra: ".,"))
                }
                .frame(width: 150)
                SettingsCaption(language.tr(
                    "Opakování CQ: Alt+R nebo příkaz RPT zapne, Esc vypne, psaní volačky pozastaví, Ctrl+R změní pauzu."))
            }
        }
    }
}
