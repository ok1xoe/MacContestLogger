import MCLAppModel
import MCLCore
import SwiftUI

/// The fields of the add-sked form (Kotlin `remember { mutableStateOf }`), kept while the window is open.
@MainActor
final class SkedFormState: ObservableObject {
    @Published var call = ""
    @Published var freq = ""
    @Published var mode = ""
    @Published var time = ""
    @Published var note = ""
    private var started = false

    /// The frequency and mode of the rig at the moment the window first shows (Kotlin `remember` initial values).
    func start(frequency: String, mode defaultMode: String) {
        guard !started else { return }
        started = true
        freq = frequency
        mode = defaultMode
    }
}

/// Kotlin `SkedWindow` (`skeds` 640×420, `SkedWindow.kt:30-110`): the arranged contacts of the contest with time,
/// frequency and mode. The sked that is due (a minute before to five minutes after) is highlighted and the list
/// refreshes every 15 s; a click on a row tunes the rig (QSY and the call into the entry field).
struct SkedWindowView: View {
    static let id = "skeds"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Skedy") },
                        size: CGSize(width: 640, height: 420), minSize: CGSize(width: 480, height: 260),
                        stepperInContent: true,
                        content: { app, _ in SkedContent(app: app) })
    }
}

private struct SkedContent: View {
    let app: AppModel
    @StateObject private var form = SkedFormState()

    var body: some View {
        let model: SkedModel = app.skeds
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 6) {
            formRow(model, language: language)
                .trailingFontStepper()
            ToolHint(text: language.tr(
                "Čas HHmm = nejbližší takový čas (dnes, jinak zítra), nebo 2026-11-28 1430. Klik na sked = QSY."))
            Divider()
            list(model, language: language)
        }
        .onAppear { form.start(frequency: model.defaultFrequencyText, mode: model.defaultMode) }
    }

    private func formRow(_ model: SkedModel, language: LanguageModel) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            ToolField(label: language.tr("Volačka")) {
                TextField("", text: Binding(get: { form.call }, set: { form.call = $0.uppercased() }))
                    .accessibilityIdentifier("skeds.call")
            }
            .frame(minWidth: 80)
            ToolField(label: "kHz") {
                TextField("", text: $form.freq).accessibilityIdentifier("skeds.freq")
            }
            .frame(minWidth: 70)
            ToolField(label: language.tr("Mód")) {
                TextField("", text: Binding(get: { form.mode }, set: { form.mode = $0.uppercased() }))
                    .accessibilityIdentifier("skeds.mode")
            }
            .frame(width: 60)
            ToolField(label: language.tr("Čas UTC")) {
                TextField("", text: $form.time).accessibilityIdentifier("skeds.time")
            }
            .frame(minWidth: 70)
            ToolField(label: language.tr("Poznámka")) {
                TextField("", text: $form.note).accessibilityIdentifier("skeds.note")
            }
            .frame(minWidth: 100)
            Button(language.tr("Přidat")) {
                Task { @MainActor in
                    let added: Bool = await model.add(call: form.call, freqText: form.freq, mode: form.mode,
                                                      timeText: form.time, note: form.note)
                    if added {
                        form.call = ""
                        form.time = ""
                        form.note = ""
                    }
                }
            }
            .accessibilityIdentifier("skeds.add")
        }
        .textFieldStyle(.roundedBorder)
        .windowFont(12)
    }

    private func list(_ model: SkedModel, language: LanguageModel) -> some View {
        // The highlight of the sked that is due follows the clock without a change of the list (Kotlin `tick`, 15 s).
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            let skeds: [SkedEntry] = model.skeds
            VStack(alignment: .leading, spacing: 0) {
                if skeds.isEmpty {
                    Text(verbatim: model.emptyText)
                        .windowFont(13)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("skeds.empty")
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(skeds, id: \.id) { sked in
                            row(model, sked: sked)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func row(_ model: SkedModel, sked: SkedEntry) -> some View {
        let flags = model.state(of: sked)
        let color: Color = flags.past ? Color.secondary : Color.primary
        let chip = DomainColors.tertiaryContainer
        return HStack(spacing: 10) {
            Text(verbatim: model.skedTime(sked)).frame(width: 52, alignment: .leading)
            Text(verbatim: sked.call).frame(width: 110, alignment: .leading)
            Text(verbatim: BandNotesEditing.frequencyFieldText(tunedFreqHz: Int64(sked.freqHz)))
                .frame(width: 90, alignment: .leading)
            Text(verbatim: sked.mode).frame(width: 50, alignment: .leading)
            Text(verbatim: sked.note).frame(maxWidth: .infinity, alignment: .leading)
            Button(app.language.tr("Smazat")) {
                Task { @MainActor in await model.remove(sked.id) }
            }
            .buttonStyle(.borderless)
        }
        .windowFont(12)
        .foregroundStyle(flags.due ? Color(domain: chip.text) : color)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(flags.due ? Color(domain: chip.background) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.tune(sked) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("skeds.row.\(sked.id)")
    }
}

/// Kotlin `QtcWindow` (`qtc` 620×560, `QtcWindow.kt:35-128`, WAE DX Contest): receiving a QTC series, or sending one
/// from the own log with the CW send, the limit per station and the list of the exchanged QTCs.
///
/// „Odvysílat CW" calls `QtcSending.send` (the keyer's `sendCwText`, so the simulator and the TX gate apply) and only
/// on its button; nothing is sent by itself. The message buttons (N1MM QRV, Cfm, Agn, TU, the RTTY RQTC / SQTC
/// messages) go out through the active entry window's keyer for its mode; „Nastavení QTC" edits them (Config → WAE).
struct QtcWindowView: View {
    static let id = "qtc"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("QTC") },
                        size: CGSize(width: 620, height: 560), minSize: CGSize(width: 460, height: 320),
                        appeared: { $0.qtc.open() },
                        leading: { app in QtcSetupButton(app: app) },
                        content: { app, _ in QtcContent(app: app) })
    }
}

private struct QtcContent: View {
    let app: AppModel

    var body: some View {
        let model: QtcModel = app.qtc
        let language: LanguageModel = app.language
        if model.config == nil {
            Text(verbatim: model.noQtcText)
                .windowFont(13)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("qtc.noQtc")
            Spacer(minLength: 0)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ToolChips(choices: [
                    ToolChips.Choice(label: language.tr("Přijmout QTC"), selected: !model.sendMode,
                                     identifier: "qtc.receive", action: { model.sendMode = false }),
                    ToolChips.Choice(label: "Poslat QTC", selected: model.sendMode, identifier: "qtc.send",
                                     action: { model.sendMode = true }),
                ])
                partnerRow(model, language: language)
                messageRow(model)
                if model.sendMode {
                    sendForm(model, language: language)
                } else {
                    receiveForm(model, language: language)
                }
                Divider()
                Text(verbatim: language.tr("Vyměněná QTC")).windowFont(13, weight: .medium)
                exchanged(model)
            }
        }
    }

    private func partnerRow(_ model: QtcModel, language: LanguageModel) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ToolField(label: language.tr("Stanice")) {
                TextField("", text: Binding(get: { model.partner }, set: { model.setPartner($0) }))
                    .textFieldStyle(.roundedBorder)
                    .windowFont(12)
                    .accessibilityIdentifier("qtc.partner")
            }
            .frame(width: 160)
            if let remaining = model.remainingText {
                Text(verbatim: remaining)
                    .windowFont(12, weight: .medium)
                    .accessibilityIdentifier("qtc.remaining")
            }
        }
    }

    /// The message buttons of the side and mode (N1MM QRV, Cfm, Agn n, TU / Save QTC, RU QRV?).
    private func messageRow(_ model: QtcModel) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(model.messageKinds.enumerated()), id: \.offset) { _, kind in
                Button {
                    model.press(kind)
                } label: {
                    Text(verbatim: model.label(kind))
                }
                .accessibilityIdentifier("qtc.message.\(model.label(kind))")
            }
        }
        .windowFont(12)
    }

    @ViewBuilder private func sendForm(_ model: QtcModel, language: LanguageModel) -> some View {
        let lines: [QtcPlanner.Line] = model.candidateLines
        Text(verbatim: model.seriesTitle(count: lines.count)).windowFont(13, weight: .medium)
        ForEach(Array(model.cwDisplayLines(lines: lines).enumerated()), id: \.offset) { _, text in
            Text(verbatim: text).windowFont(12, design: .monospaced)
        }
        HStack(spacing: 6) {
            Button(language.tr("Odvysílat CW")) {
                app.qtcSending.send(groupNr: model.nextGroup, lines: lines, partner: model.partner)
            }
            .disabled(lines.isEmpty)
            .accessibilityIdentifier("qtc.sendCw")
            if model.family == .digital {
                Button(language.tr("Odvysílat sérii (digi)")) {
                    model.sendDigitalSeries()
                }
                .disabled(lines.isEmpty)
                .accessibilityIdentifier("qtc.sendDigital")
            }
            Button(language.tr("Potvrzeno — uložit")) {
                Task { @MainActor in _ = await model.saveSent() }
            }
            .disabled(lines.isEmpty)
            .accessibilityIdentifier("qtc.saveSent")
        }
        .windowFont(12)
    }

    @ViewBuilder private func receiveForm(_ model: QtcModel, language: LanguageModel) -> some View {
        ToolField(label: language.tr("Série (např. 3/10)")) {
            TextField("", text: Binding(get: { model.group }, set: { model.group = $0 }))
                .textFieldStyle(.roundedBorder)
                .windowFont(12)
                .onSubmit { model.headerSubmitted() }
                .accessibilityIdentifier("qtc.group")
        }
        .frame(width: 160)
        Text(verbatim: language.tr("Řádky: čas volačka číslo (např. 1234 DL1ABC 56), každý na nový řádek"))
            .windowFont(11)
            .foregroundStyle(.secondary)
        TextEditor(text: Binding(get: { model.received }, set: { model.received = $0 }))
            .windowFont(12, design: .monospaced)
            .frame(height: 180)
            .border(Color.secondary.opacity(0.4))
            .accessibilityIdentifier("qtc.received")
        if let bad = model.badLinesText {
            Text(verbatim: bad)
                .windowFont(11)
                .foregroundStyle(Color(domain: DomainColors.dupe))
        }
        Button(language.tr("Uložit přijaté QTC")) {
            Task { @MainActor in _ = await model.saveReceived() }
        }
        .windowFont(12)
        .disabled(!model.parsedReceived.canSave)
        .accessibilityIdentifier("qtc.saveReceived")
    }

    private func exchanged(_ model: QtcModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.qtcs.reversed().enumerated()), id: \.offset) { _, record in
                    HStack {
                        Text(verbatim: model.rowText(record))
                            .windowFont(11, design: .monospaced)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(app.language.tr("Smazat")) {
                            if let id = record.id {
                                Task { @MainActor in await model.delete(id) }
                            }
                        }
                        .buttonStyle(.borderless)
                        .windowFont(12)
                    }
                }
            }
        }
        .accessibilityIdentifier("qtc.exchanged")
    }
}

/// „Nastavení QTC…" in the QTC window's top bar: the sheet of N1MM's Config → WAE options and QTC messages.
private struct QtcSetupButton: View {
    let app: AppModel
    @State private var showing = false

    var body: some View {
        Button(app.language.tr("Nastavení QTC…")) {
            showing = true
        }
        .windowFont(12)
        .accessibilityIdentifier("qtc.setup")
        .sheet(isPresented: $showing) {
            QtcSetupSheet(model: app.qtc, language: app.language) { showing = false }
        }
    }
}

/// N1MM Config → WAE: „Ctrl-Z sends QTC? automatically", „Max QTC Number for callsign colors", „Default Number of
/// QTCs to Send" and the CW, SSB and RTTY messages of the QTC window. Every change is saved at once.
private struct QtcSetupSheet: View {
    let model: QtcModel
    let language: LanguageModel
    let close: () -> Void

    @StateObject private var form = DialogFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.tr("Nastavení QTC"))
                    .windowFont(15, weight: .semibold)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    general
                    Text(verbatim: language.tr("Ve zprávách: {QTC} = hlavička série (26/10), $ = číslo QTC pro Agn, "
                        + "dále makra F-kláves (*, !, {ENTER}…)."))
                        .windowFont(11)
                        .foregroundStyle(.secondary)
                    section("CW", [(.cwAsk, "Žádost QTC?"), (.cwQrv, "QRV"), (.cwConfirm, "Cfm"),
                                   (.cwAgain, "Agn"), (.cwTu, "TU na konci (prázdné = F3)")])
                    section(language.tr("SSB (wav soubory)"),
                            [(.ssbQrv, "QRV"), (.ssbConfirm, "Cfm"), (.ssbAgain, "Agn"),
                             (.ssbTu, "TU na konci (prázdné = F3)")])
                    section("RTTY", [(.rttyQrv, "RQTC: RX Ready"), (.rttyAllAgain, "RQTC: All Agn"),
                                     (.rttyAgain, "RQTC: Agn"), (.rttyReceivedSave, "RQTC: Save QTC"),
                                     (.rttyAskQrv, "SQTC: RU QRV"), (.rttyHeading, "SQTC: Send All Heading"),
                                     (.rttyEnding, "SQTC: Send All Ending"), (.rttySentSave, "SQTC: Save QTC"),
                                     (.rttySpacing, "QTC Spacing")])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DialogButtonRow {
                Button(language.tr("Zavřít")) {
                    close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 420)
        .environment(\.windowFontSize, form.fontSize)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(language.tr("Ctrl+Z pošle QTC? automaticky (Evropa, Run, CW)"), isOn: Binding(
                get: { model.setup.flag(.ctrlZSendsAsk) }, set: { model.setSetup(.ctrlZSendsAsk, flag: $0) }))
                .accessibilityIdentifier("qtc.setup.ctrlZ")
            Toggle(language.tr("Enter v hlavičce série pošle QRV (CW)"), isOn: Binding(
                get: { model.setup.flag(.cwQrvOnHeader) }, set: { model.setSetup(.cwQrvOnHeader, flag: $0) }))
                .accessibilityIdentifier("qtc.setup.qrvOnHeader")
            HStack(spacing: 12) {
                numberField(.sendCount, language.tr("QTC v jedné sérii"))
                numberField(.colorMax, language.tr("Max. QTC pro barvy v bandmapě"))
            }
        }
        .windowFont(12)
    }

    private func numberField(_ key: QtcSetup.Key, _ label: String) -> some View {
        ToolField(label: label) {
            TextField("", text: Binding(get: { String(model.setup.number(key)) },
                                        set: { model.setSetup(key, KotlinStrings.trim($0)) }))
                .textFieldStyle(.roundedBorder)
                .windowFont(12)
                .accessibilityLabel(Text(verbatim: label))
        }
        .frame(width: 200)
    }

    private func section(_ title: String, _ rows: [(QtcSetup.Key, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).windowFont(13, weight: .medium)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(verbatim: language.tr(row.1))
                        .windowFont(12)
                        .frame(width: 190, alignment: .leading)
                    TextField("", text: Binding(get: { model.setup.text(row.0) }, set: { model.setSetup(row.0, $0) }))
                        .textFieldStyle(.roundedBorder)
                        .windowFont(12, design: .monospaced)
                        .accessibilityLabel(Text(verbatim: title + " " + language.tr(row.1)))
                }
            }
        }
    }
}
