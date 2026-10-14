import AppKit
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
            CallStackGroup(language: language, draft: $draft)
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
                "Zpráva = čárkou oddělené wav soubory a makra: {OPERATOR}/CQ.wav · ! volačka protistanice · # odesílané číslo · * nebo {MYCALL} moje volačka · @ frekvence. Víc souborů za sebou: a.wav,b.wav. Prázdná zpráva nic nevysílá. Zprávu s jedním wav souborem můžeš nahrát tlačítkem Nahrát (nebo Ctrl+Shift+F-klávesou v zadávacím okně), přehrát na počítači, nahradit vybraným souborem nebo smazat. Soubor leží tam, odkud ho hlasový klíč přehraje.")
        }
    }

    private var messagesGroup: some View {
        let path: WritableKeyPath<ConfigurerDraft, [FunctionKeyDraft]> = self.path
        return SettingsGroup(title: title) {
            SettingsCaption(help)
            switcher
            FunctionKeyFileRow(app: app, kind: fileKind, rows: fileRows)
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft[dynamicMember: path]) { $message in
                    let index: Int = indexOf(message.id, in: draft[keyPath: path])
                    MessageRow(index: index, message: $message)
                    if kind == 0 {
                        VoiceMessageControls(studio: studio, language: language, request: request(index, message))
                    }
                }
            }
            if kind == 0 {
                VoiceMessageFooter(studio: studio, language: language, wavDir: draft.vkWavDir)
            }
        }
        .onAppear {
            applyFocus()
            refreshFiles()
        }
        .onChange(of: app.menu.functionKeysFocus) { applyFocus() }
        .onChange(of: requests) { studio.refresh(requests) }
        .onDisappear { studio.abandon() }
    }

    private var studio: VoiceMessageStudio { app.keyer.voice.studio }

    /// The `.mc` file kind of the shown set.
    private var fileKind: FunctionKeyKind {
        switch kind {
        case 1: return .cw
        case 2: return .digital
        default: return .ssb
        }
    }

    /// The Run and S&P rows of the shown kind (a `.mc` file holds both).
    private var fileRows: Binding<FunctionKeySetDraft> {
        let paths: (WritableKeyPath<ConfigurerDraft, [FunctionKeyDraft]>, WritableKeyPath<ConfigurerDraft, [FunctionKeyDraft]>)
        switch kind {
        case 1: paths = (\.cwRun, \.cwSp)
        case 2: paths = (\.digiRun, \.digiSp)
        default: paths = (\.vkRun, \.vkSp)
        }
        return Binding(get: { FunctionKeySetDraft(run: draft[keyPath: paths.0], sp: draft[keyPath: paths.1]) },
                       set: { value in
                           draft[keyPath: paths.0] = value.run
                           draft[keyPath: paths.1] = value.sp
                       })
    }

    /// A right click on an F-key button opened the tab: its set is shown.
    private func applyFocus() {
        guard let focus = app.menu.functionKeysFocus else { return }
        app.menu.functionKeysFocus = nil
        switch focus.kind {
        case .cw: kind = 1
        case .digital: kind = 2
        case .ssb: kind = 0
        }
        run = focus.run
    }

    private func request(_ index: Int, _ message: FunctionKeyDraft) -> VoiceMessageStudio.Request {
        VoiceMessageStudio.Request(slot: VoiceMessageStudio.Slot(run: run, index: index), text: message.text,
                                   wavDir: draft.vkWavDir)
    }

    /// The SSB keys shown (empty for CW and digi).
    private var requests: [VoiceMessageStudio.Request] {
        guard kind == 0 else { return [] }
        return draft[keyPath: path].enumerated().map { request($0.offset, $0.element) }
    }

    private func refreshFiles() {
        studio.refresh(requests)
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
            SettingsCheckbox(label: language.tr("Opravenou volačku poslat jen v části, která se změnila (Send partial calls)"),
                             isOn: $draft.esmSendPartialCalls)
            HStack(alignment: .center, spacing: 8) {
                SettingsField(caption: language.tr("Mezi jeho volačkou a výměnou (CW)")) {
                    SettingsTextField(text: $draft.esmCallExchangeSeparator)
                }
                .frame(width: 220)
                SettingsCaption(language.tr("Text mezi F5 a F2 poslanými spolu, např. mezera nebo „ 5NN“; výchozí je mezera."))
            }
            SettingsCheckbox(
                label: language.tr("F-klávesa stisknutá během vysílání se zařadí za běžící zprávu (CW, SSB; jinak ji přeruší)"),
                isOn: $draft.cwStackMessages)
            EsmKeyAssignments(language: language, keys: $draft.esmKeyMap)
        }
    }
}

/// N1MM „Function Key Assignments for ESM": the F-key of each ESM role.
private struct EsmKeyAssignments: View {
    let language: LanguageModel
    @Binding var keys: [Int]

    private static let roles: [String] = ["CQ", "Výměna", "Konec QSO (TU)", "Moje volačka", "Jeho volačka", "QSO B4",
                                          "Znovu?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsCaption(language.tr("Přiřazení F-kláves pro ESM (výchozí F1, F2, F3, F4, F5, F6, F8):"))
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<Self.roles.count, id: \.self) { role in
                    SettingsField(caption: language.tr(Self.roles[role])) {
                        Picker(selection: binding(role)) {
                            ForEach(0..<VoiceKeyerConfig.keyCount, id: \.self) { index in
                                Text(verbatim: "F" + String(index + 1)).tag(index)
                            }
                        } label: {
                            EmptyView()
                        }
                        .labelsHidden()
                        .accessibilityLabel(Text(verbatim: language.tr(Self.roles[role])))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func binding(_ role: Int) -> Binding<Int> {
        Binding(get: { role < keys.count ? keys[role] : EsmKeyMap.n1mm.keys[role] },
                set: { value in
                    var next: [Int] = EsmKeyMap(keys: keys).keys
                    next[role] = value
                    keys = next
                })
    }
}

/// N1MM call stacking: the Next Call key of ESM, the order calls come off the stack, clearing on a band change and
/// Digital Call Stacking (the plain click in the Digital Interface).
private struct CallStackGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    private static let orders: [(CallStack.Order, String)] = [
        (.multsFirst, "FIFO, násobiče napřed"), (.fifo, "FIFO"), (.lifo, "LIFO"),
    ]

    var body: some View {
        SettingsGroup(title: language.tr("Zásobník volaček (call stacking)")) {
            SettingsCaption(language.tr(
                "Ctrl+Alt+G nebo {STACKANOTHER} dá volačku z pole do zásobníku, {SOCALLSTACK} ji prohodí se zásobníkem, Alt+G vezme další volačku, Alt+D s prázdným polem ji smaže, {CLRSTACK} zásobník vymaže. {LOGTHENPOP} zapíše QSO a pokračuje další volačkou: text před makrem jde zapisované stanici, text za ním další (např. „{LOGTHENPOP} TU {F5}{F2}“). Dupy se do zásobníku nedávají."))
            HStack(alignment: .center, spacing: 12) {
                SettingsField(caption: language.tr("Klávesa další volačky (ESM)")) {
                    Picker(selection: $draft.esmNextCallKey) {
                        Text(verbatim: language.tr("žádná")).tag(-1)
                        ForEach(0..<VoiceKeyerConfig.keyCount, id: \.self) { index in
                            Text(verbatim: "F" + String(index + 1)).tag(index)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text(verbatim: language.tr("Klávesa další volačky (ESM)")))
                }
                .frame(width: 220)
                SettingsField(caption: language.tr("Pořadí ze zásobníku")) {
                    Picker(selection: $draft.callStackOrder) {
                        ForEach(Self.orders, id: \.0.rawValue) { order in
                            Text(verbatim: language.tr(order.1)).tag(order.0.rawValue)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text(verbatim: language.tr("Pořadí ze zásobníku")))
                }
                .frame(width: 260)
            }
            SettingsCaption(language.tr(
                "ESM pošle na konci QSO v Run místo TU tuto klávesu, když v zásobníku čeká volačka a klávesa obsahuje {LOGTHENPOP} ({LOGTHENNEXT} ESM nevybere)."))
            SettingsCheckbox(label: language.tr("Při změně pásma zásobník vymazat"),
                             isOn: $draft.callStackClearOnBandChange)
            SettingsCheckbox(
                label: language.tr(
                    "Digitální rozhraní: klik na volačku při obsazeném poli ji dá do zásobníku (Digital Call Stacking, jen Run)"),
                isOn: $draft.digitalCallStacking)
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
            HStack(alignment: .center, spacing: 12) {
                SettingsField(caption: language.tr("Nejdelší opakování CQ (min)")) {
                    SettingsTextField(text: $draft.repeatMaxMinutes, filter: .digits(limit: 3))
                }
                .frame(width: 180)
                SettingsCaption(language.tr("Po této době se opakování CQ samo vypne; 0 = bez omezení."))
            }
        }
    }
}

/// The Run and S&P rows of one message set.
struct FunctionKeySetDraft {
    var run: [FunctionKeyDraft]
    var sp: [FunctionKeyDraft]

    var keys: FunctionKeySet {
        FunctionKeySet(run: run.map { $0.toMessage() }, sp: sp.map { $0.toMessage() })
    }

    /// The rows with the labels and texts of `keys` (by index).
    mutating func take(_ keys: FunctionKeySet) {
        for index in run.indices where index < keys.run.count {
            run[index].label = keys.run[index].label
            run[index].text = keys.run[index].text
        }
        for index in sp.indices where index < keys.sp.count {
            sp[index].label = keys.sp[index].label
            sp[index].text = keys.sp[index].text
        }
    }
}

/// N1MM Function Key Editor → File: load / save a `.mc` file, copy the messages to the clipboard, and the active
/// contest's associated file of this set (loaded whenever the contest opens, written when the set changes).
private struct FunctionKeyFileRow: View {
    let app: AppModel
    let kind: FunctionKeyKind
    @Binding var rows: FunctionKeySetDraft

    private var language: LanguageModel { app.language }
    private var files: FunctionKeyFilesModel { app.functionKeyFiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SettingsButton(language.tr("Načíst .mc…"), borderless: true) { load(associate: false) }
                SettingsButton(language.tr("Uložit .mc…"), borderless: true) { save(associate: false) }
                SettingsButton(language.tr("Kopírovat do schránky"), borderless: true) { copy() }
                Spacer(minLength: 0)
            }
            if app.contest.activeId != nil {
                HStack(spacing: 8) {
                    SettingsCaption(files.associatedFile(kind).map { language.tr("Soubor závodu: %s", .string($0)) }
                                    ?? language.tr("Závod nemá vlastní soubor zpráv (platí tyto zprávy)."))
                    Spacer(minLength: 0)
                    SettingsButton(language.tr("Přiřadit soubor k závodu…"), borderless: true) { load(associate: true) }
                    SettingsButton(language.tr("Uložit jako soubor závodu…"), borderless: true) { save(associate: true) }
                    if files.associatedFile(kind) != nil {
                        SettingsButton(language.tr("Zrušit přiřazení"), borderless: true) {
                            Task { await files.associate(kind, path: nil) }
                        }
                    }
                }
            }
        }
    }

    private func load(associate: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = language.tr("Vyber soubor F-kláves (.mc, formát N1MM)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let keys = FunctionKeyFilesModel.read(url) else {
            app.status.show("Soubor F-kláves %s nejde načíst", .string(url.path))
            return
        }
        rows.take(keys)
        if associate {
            Task { await files.associate(kind, path: url.path) }
        }
    }

    private func save(associate: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = kind.rawValue + " Messages.mc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FunctionKeyFilesModel.write(rows.keys, kind: kind, to: url) else {
            app.status.show("Soubor F-kláves %s nejde uložit", .string(url.path))
            return
        }
        if associate {
            Task { await files.associate(kind, path: url.path) }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(FunctionKeyFilesModel.clipboardText(rows.keys, kind: kind), forType: .string)
    }
}
