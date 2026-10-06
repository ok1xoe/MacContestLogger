import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `HardwareTab` (`HW:80-187`): the radio mode, row 1 = the real rig (port, model, line; „Set" opens the
/// „Nastavení TCVR" sheet), the foot switch, the transverters and, in SO2R, rig 2 and the OTRSP controller. The mock
/// multi-radio rows and row 1's Digi/CW check boxes are left out. The serial ports are listed
/// when the tab opens.
struct HardwareTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    @StateObject private var showRigState = ViewState<Bool>(false)
    private var showRig: Bool {
        get { showRigState.value }
        nonmutating set { showRigState.value = newValue }
    }

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCaption(language.tr("Řádek 1 = tvůj rig. Klikni na Set pro kompletní nastavení TRX."))
            radioModes
            HardwareGridHeader()
            rigRow
            FootswitchGroup(app: app, draft: $draft)
            TransvertersGroup(app: app, draft: $draft)
            if draft.radioMode == "SO2R" {
                So2rGroup(app: app, draft: $draft)
            }
        }
        .onAppear { app.settingsTools.loadSerialPorts() }
        .sheet(isPresented: $showRigState.value) {
            RigConfigSheet(app: app, draft: $draft) { showRig = false }
        }
    }

    private var radioModes: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            ForEach(["SO1V", "SO2V", "SO2R"], id: \.self) { mode in
                SettingsRadio(label: mode, selected: draft.radioMode == mode) { draft.radioMode = mode }
            }
        }
    }

    private var rigRow: some View {
        HStack(spacing: 8) {
            HardwareCell(text: HardwareSummary.cell(draft.device))
                .frame(minWidth: HardwareGridHeader.portMin, idealWidth: HardwareGridHeader.port,
                       maxWidth: HardwareGridHeader.port)
            HardwareCell(text: HardwareSummary.cell(draft.rigModelLabel))
                .frame(minWidth: HardwareGridHeader.radioMin, idealWidth: HardwareGridHeader.radio,
                       maxWidth: HardwareGridHeader.radio)
            Color.clear
                .frame(width: HardwareGridHeader.digi, height: 1)
            Color.clear
                .frame(width: HardwareGridHeader.cw, height: 1)
            Button {
                showRig = true
            } label: {
                Text(verbatim: "Set")
                    .windowFont(13)
            }
            .buttonStyle(.link)
            .frame(width: HardwareGridHeader.action, alignment: .leading)
            Text(verbatim: HardwareSummary.line(
                mode: draft.rigMode, host: draft.host, port: draft.rigPort, baud: draft.baud, parity: draft.parity,
                dataBits: draft.dataBits, stopBits: draft.stopBits))
                .windowFont(11, design: .monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The column captions of the N1MM grid (`HW:96-103`, widths of `HW:68-72`).
private struct HardwareGridHeader: View {
    static let port: CGFloat = 150
    static let radio: CGFloat = 180
    /// The port and radio columns shrink to these in a narrow window (the grid never overflows the detail area).
    static let portMin: CGFloat = 70
    static let radioMin: CGFloat = 80
    static let digi: CGFloat = 40
    static let cw: CGFloat = 64
    static let action: CGFloat = 56

    var body: some View {
        HStack(spacing: 8) {
            SettingsCaption("Port")
                .frame(minWidth: Self.portMin, idealWidth: Self.port, maxWidth: Self.port, alignment: .leading)
            SettingsCaption("Radio")
                .frame(minWidth: Self.radioMin, idealWidth: Self.radio, maxWidth: Self.radio, alignment: .leading)
            SettingsCaption("Digi").frame(width: Self.digi, alignment: .leading)
            SettingsCaption("CW/Other").frame(width: Self.cw, alignment: .leading)
            SettingsCaption("Details").frame(width: Self.action, alignment: .leading)
            SettingsCaption("Linka / IP").frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `DisplayCell`: a read-only value of the grid.
private struct HardwareCell: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .windowFont(13, design: .monospaced)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.6), lineWidth: 1))
    }
}

/// „Nožní spínač (footswitch)" (`HW:123-139`).
private struct FootswitchGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        SettingsGroup(title: language.tr("Nožní spínač (footswitch)")) {
            SettingsCaption(language.tr(
                "Spínač na USB-RS232 převodníku: propojí RTS→CTS (nebo DTR→DSR / DCD). Akce: PTT drží vysílač po dobu sešlápnutí, ENTER = jako Enter (s ESM pošle zprávu), F1 = CQ."))
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: "Port") {
                    SettingsDropdown(label: ifBlank(draft.footswitchPort, "—"),
                                     options: app.settingsTools.serialPortsWithNone, language: language) { picked in
                        draft.footswitchPort = picked == "—" ? "" : picked
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsField(caption: language.tr("Vodič")) {
                    SettingsDropdown(label: draft.footswitchPin, options: ConfigurerCatalogs.footswitchPins,
                                     language: language) { draft.footswitchPin = $0 }
                }
                .frame(width: 110)
                SettingsField(caption: "Akce") {
                    SettingsDropdown(label: draft.footswitchAction, options: ConfigurerCatalogs.footswitchActions,
                                     language: language) { draft.footswitchAction = $0 }
                }
                .frame(width: 120)
            }
        }
    }
}

/// „Transvertory" (`HW:140-155`).
private struct TransvertersGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        SettingsGroup(title: "Transvertory") {
            SettingsCaption(language.tr(
                "Rig na mezifrekvenci (IF) + offset = skutečná frekvence. Příklad 2 m přes 10 m: IF 28000–30000 kHz, offset 116000 kHz. Frekvence v IF rozsahu zapnutého transvertoru se v deníku, bandmapě i při ladění přepočítávají."))
            ForEach($draft.transverters) { $row in
                TransverterRow(language: language, row: $row) {
                    draft.transverters.removeAll { $0.id == row.id }
                }
            }
            SettingsButton(language.tr("Přidat transvertor")) {
                let entry = TransverterEntry(name: "2m", ifLowKHz: 28_000, ifHighKHz: 30_000, offsetKHz: 116_000,
                                             enabled: true)
                draft.transverters.append(TransverterDraft(entry))
            }
        }
    }
}

private struct TransverterRow: View {
    let language: LanguageModel
    @Binding var row: TransverterDraft
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Toggle(isOn: $row.enabled) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            SettingsField(caption: language.tr("Název")) {
                SettingsTextField(text: $row.name)
            }
            .frame(maxWidth: .infinity)
            SettingsField(caption: "IF od (kHz)") {
                SettingsTextField(text: $row.ifLow, filter: .digits(limit: nil))
            }
            .frame(width: 110)
            SettingsField(caption: "IF do (kHz)") {
                SettingsTextField(text: $row.ifHigh, filter: .digits(limit: nil))
            }
            .frame(width: 110)
            SettingsField(caption: "Offset (kHz)") {
                SettingsTextField(text: $row.offset, filter: .digitsAnd(extra: "-"))
            }
            .frame(width: 120)
            SettingsButton("Smazat", borderless: true, action: onDelete)
        }
    }
}

/// „SO2R — rig 2 a kontrolér" (`HW:156-174`), shown in SO2R only.
private struct So2rGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        SettingsGroup(title: language.tr("SO2R — rig 2 a kontrolér")) {
            SettingsCaption(language.tr(
                "Rig 2 se připojuje k běžícímu rigctld (spusť druhou instanci, např. rigctld -m <model> -r <port> -t 4534). OTRSP kontrolér (SO2RDuino, YCCC Box, microHAM v OTRSP) přepíná vysílání a sluchátka podle aktivního okna; „\\“ přepne okno, „`“ stereo."))
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: "rigctld rigu 2 (host)") {
                    SettingsTextField(text: $draft.rig2Host)
                }
                .frame(maxWidth: .infinity)
                SettingsField(caption: "Port") {
                    SettingsTextField(text: $draft.rig2Port, filter: .digits(limit: nil))
                }
                .frame(width: 110)
                SettingsField(caption: language.tr("OTRSP port (sériový)")) {
                    SettingsDropdown(label: ifBlank(draft.otrspPort, "—"),
                                     options: app.settingsTools.serialPortsWithNone, language: language) { picked in
                        draft.otrspPort = picked == "—" ? "" : picked
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
