import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `RigConfigWindow` (`HW:189-423`): „Nastavení TCVR", 620×960, not resizable — a sheet over the Settings
/// window here, with its own font stepper. Connection, rig choice (manufacturer, search, the list, the
/// scan), the serial line (only for `LAUNCH_DAEMON`) and rigctld. „Uložit a připojit" commits the whole draft with a
/// reconnect and closes Settings after a successful save; „Hotovo" only closes the sheet.
///
/// The rig list and the ports are read when the sheet opens; closing it stops a running scan
/// (`SettingsToolsModel.openRigSheet`/`closeRigSheet`).
struct RigConfigSheet: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft
    let onDone: () -> Void

    @StateObject private var fontSizeState = ViewState<Int>(WindowFont.defaultSize)
    private var fontSize: Int {
        get { fontSizeState.value }
        nonmutating set { fontSizeState.value = newValue }
    }
    @StateObject private var manufacturerState = ViewState<String?>(nil)
    private var manufacturer: String? {
        get { manufacturerState.value }
        nonmutating set { manufacturerState.value = newValue }
    }
    @StateObject private var queryState = ViewState<String>("")
    private var query: String {
        get { queryState.value }
        nonmutating set { queryState.value = newValue }
    }

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowTopBar(size: $fontSizeState.value, language: language)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    connectionGroup
                    RigChoiceGroup(app: app, draft: $draft, manufacturer: $manufacturerState.value,
                                   query: $queryState.value)
                    SerialLineGroup(app: app, draft: $draft)
                    rigctldGroup
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .windowFont(13)
        .environment(\.windowFontSize, fontSize)
        .frame(width: 620)
        .frame(minHeight: 420, idealHeight: 960, maxHeight: 960)
        .onAppear { app.settingsTools.openRigSheet() }
        .onDisappear { app.settingsTools.closeRigSheet() }
    }

    private var connectionGroup: some View {
        SettingsGroup(title: language.tr("Připojení")) {
            HStack(spacing: 16) {
                SettingsRadio(label: "Spustit rigctld", selected: draft.rigMode == .launchDaemon) {
                    draft.rigMode = .launchDaemon
                }
                SettingsRadio(label: language.tr("Připojit k běžícímu"), selected: draft.rigMode == .connectRunning) {
                    draft.rigMode = .connectRunning
                }
            }
        }
    }

    private var rigctldGroup: some View {
        SettingsGroup(title: language.tr("rigctld (síť)")) {
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: "Host") {
                    SettingsTextField(text: $draft.host)
                        .disabled(draft.rigMode != .connectRunning)
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1.6)
                SettingsField(caption: "Port") {
                    SettingsTextField(text: $draft.rigPort)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// „Uložit a (znovu) připojit TRX" (`HW:413-415`) and „Hotovo".
    private var footer: some View {
        let settings: SettingsModel = app.settings
        let connected: Bool = settings.services.catConnected()
        let title: String = connected ? language.tr("Uložit a znovu připojit TRX") : language.tr("Uložit a připojit TRX")
        return HStack(spacing: 8) {
            SettingsButton(title) {
                // The sheet goes first so the window it hangs on can close after a successful save.
                Task {
                    if await settings.commit(reconnectRig: true) {
                        onDone()
                        settings.cancel()
                    }
                }
            }
            .disabled(settings.isSaving || settings.draft == nil)
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text(verbatim: "Hotovo")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }
}

/// „Výběr rigu" (`HW:275-328`): manufacturer, search across manufacturers, the list (the chosen model highlighted),
/// „Vybráno: %s" and the scan line.
private struct RigChoiceGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft
    @Binding var manufacturer: String?
    @Binding var query: String

    var body: some View {
        let language: LanguageModel = app.language
        let tools: SettingsToolsModel = app.settingsTools
        let all: String = language.tr("Všichni")
        SettingsGroup(title: language.tr("Výběr rigu")) {
            HStack(alignment: .top, spacing: 8) {
                SettingsField(caption: language.tr("Výrobce")) {
                    SettingsDropdown(label: manufacturer ?? all, options: [all] + tools.manufacturers,
                                     language: language) { picked in
                        manufacturer = picked == all ? nil : picked
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsField(caption: language.tr("Hledat (napříč výrobci)")) {
                    SettingsTextField(text: $query)
                }
                .frame(maxWidth: .infinity)
            }
            RigList(models: tools.filtered(manufacturer: manufacturer, query: query), draft: $draft)
            Text(verbatim: language.tr("Vybráno: %s", .string(draft.rigModelLabel)))
                .windowFont(14, design: .monospaced)
            scanLine(tools)
        }
    }

    private func scanLine(_ tools: SettingsToolsModel) -> some View {
        let state: SettingsToolsModel.ScanState = tools.scanState
        let fallback: String = KotlinStrings.isBlank(draft.device) ? "Pro scan vyber port" : ""
        return HStack(spacing: 8) {
            SettingsButton(app.language.tr("Scan – najít rig")) {
                tools.startScan(draft: draft)
            }
            .disabled(!tools.canStartScan(device: draft.device))
            if state.isScanning {
                SettingsButton("Zastavit") { tools.stopScan() }
            }
            Text(verbatim: ifBlank(state.status, fallback))
                .windowFont(12)
                .foregroundStyle(.secondary)
        }
    }
}

/// The hamlib models, 120 pt high, monospaced; a click chooses the model and its label (`HW:287-313`).
private struct RigList: View {
    let models: [HamlibRigModel]
    @Binding var draft: ConfigurerDraft

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                    row(model)
                }
            }
        }
        .frame(height: 120)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
    }

    private func row(_ model: HamlibRigModel) -> some View {
        let selected: Bool = model.number == draft.rigModel
        return Text(verbatim: model.description)
            .windowFont(13, design: .monospaced)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(Color.clear))
            .contentShape(Rectangle())
            .onTapGesture {
                draft.rigModel = model.number
                draft.rigModelLabel = model.description
            }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// „Sériový port a linka" (`HW:330-389`): enabled only when the app launches rigctld.
private struct SerialLineGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private static let parities: [SerialParity] = [.none, .even, .odd, .mark, .space]
    private static let pins: [PinState] = [.unset, .on, .off]
    private static let flows: [FlowControl] = [.auto, .none, .xonxoff, .hardware]

    var body: some View {
        let language: LanguageModel = app.language
        let enabled: Bool = draft.rigMode == .launchDaemon
        SettingsGroup(title: language.tr("Sériový port a linka")) {
            if !enabled {
                Text(verbatim: language.tr("Parametry linky nastavuje běžící rigctld — v tomto režimu nedostupné."))
                    .windowFont(12)
                    .foregroundStyle(.secondary)
            }
            SettingsField(caption: "Port") {
                SettingsDropdown(label: ifBlank(draft.device, language.tr("— žádný —")),
                                 options: [""] + app.settingsTools.serialPorts, language: language,
                                 enabled: enabled) { draft.device = $0 }
            }
            lineRow(language, enabled: enabled)
            pinRow(language, enabled: enabled)
        }
    }

    private func lineRow(_ language: LanguageModel, enabled: Bool) -> some View {
        let bauds: [Int] = Array(Set(ConfigurerCatalogs.baudRates + [draft.baud])).sorted()
        return HStack(alignment: .top, spacing: 8) {
            SettingsField(caption: "Rychlost") {
                SettingsDropdown(label: String(draft.baud), options: bauds.map { String($0) }, language: language,
                                 enabled: enabled) { draft.baud = Int($0) ?? draft.baud }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsField(caption: "Parita") {
                SettingsDropdown(label: draft.parity.hamlib, options: Self.parities.map(\.hamlib), language: language,
                                 enabled: enabled) { picked in
                    draft.parity = Self.parities.first { $0.hamlib == picked } ?? draft.parity
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsField(caption: "Data bity") {
                SettingsDropdown(label: String(draft.dataBits), options: ["7", "8"], language: language,
                                 enabled: enabled) { draft.dataBits = Int($0) ?? draft.dataBits }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsField(caption: "Stop bity") {
                SettingsDropdown(label: String(draft.stopBits), options: ["1", "2"], language: language,
                                 enabled: enabled) { draft.stopBits = Int($0) ?? draft.stopBits }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pinRow(_ language: LanguageModel, enabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            SettingsField(caption: "DTR (pin 4)") {
                SettingsDropdown(label: draft.dtr.label, options: Self.pins.map(\.label), language: language,
                                 enabled: enabled) { picked in
                    draft.dtr = Self.pins.first { $0.label == picked } ?? draft.dtr
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsField(caption: "RTS (pin 7)") {
                SettingsDropdown(label: draft.rts.label, options: Self.pins.map(\.label), language: language,
                                 enabled: enabled) { picked in
                    draft.rts = Self.pins.first { $0.label == picked } ?? draft.rts
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SettingsField(caption: language.tr("Řízení toku")) {
                SettingsDropdown(label: draft.flow.label, options: Self.flows.map(\.label), language: language,
                                 enabled: enabled) { picked in
                    draft.flow = Self.flows.first { $0.label == picked } ?? draft.flow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
