import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `RotatorWindow` (`rotator` 360×460, `RotatorWindow.kt:38-93`, N1MM Rotor): the compass with the
/// rotator's needle and the ray to the typed call, the azimuth („—" when unknown), the poll status, the call's
/// azimuth, turning by the short / long path, to a typed azimuth (at most 3 digits), Stop, and the keys' hint. The N1MM
/// Rotor program's parts: the rotor picker (several rotors), the F1–F10 preset bearings, the rotors heard on the
/// network and the Setup sheet.
struct RotatorWindowView: View {
    static let id = "rotator"

    let host: AppHost

    @StateObject private var session = WindowSession(id: RotatorWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 360, height: 460))
    /// The azimuth field (Kotlin `remember { mutableStateOf("") }`).
    @StateObject private var manual = DialogFormState()
    @State private var showingSetup = false

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Rotátor",
                                                binder: session.binder))
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 280, minHeight: 300)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let rotator: RotatorModel = app.rotator
        let call: String = KotlinStrings.trim(app.typedCall)
        let target: Int? = RotorPlan.typedHeading(call) ?? app.rig.azimuthTo(call)
        return VStack(alignment: .center, spacing: 8) {
            WindowTopBar(size: $session.fontSize, language: language) {
                Button {
                    showingSetup = true
                } label: {
                    Text(verbatim: language.tr("Nastavení rotátoru…")).windowFont(12)
                }
                .accessibilityIdentifier("rotator.setup")
            }
            rotorPicker(app)
            RotatorCompass(
                azimuth: rotator.azimuth, target: target,
                value: AccessibilityText.compassValue(azimuth: rotator.azimuth, target: target,
                                                      translator: language.translator),
                label: language.tr("Kompas rotátoru"))
            Text(verbatim: RadioWindowTexts.rotatorAzimuth(rotator.azimuth))
                .windowFont(28)
            Text(verbatim: rotator.statusText.text(language.translator, decimalSeparator: language.decimalSeparator))
                .windowFont(11)
                .foregroundStyle(.secondary)
            Text(verbatim: RadioWindowTexts.rotatorCallLine(call: call, target: target)
                .text(language.translator, decimalSeparator: language.decimalSeparator))
                .windowFont(14)
            HStack(spacing: 6) {
                Button {
                    rotator.turnToCall(call, longPath: false)
                } label: {
                    Text(verbatim: language.tr("Na volačku")).windowFont(14)
                }
                Button {
                    rotator.turnToCall(call, longPath: true)
                } label: {
                    Text(verbatim: language.tr("Dlouhá cesta")).windowFont(14)
                }
            }
            manualRow(app)
            presetRow(app)
            networkRotors(app)
            Text(verbatim: language.tr("Alt+J na volačku, Alt+L dlouhou cestou, Ctrl+Alt+J stop"))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
        .sheet(isPresented: $showingSetup) {
            RotorSetupSheet(rotator: rotator, setup: app.config.config.rotor, language: language) {
                showingSetup = false
            }
        }
    }

    /// The rotor the window shows and turns (only with named rotors in the setup).
    @ViewBuilder
    private func rotorPicker(_ app: AppModel) -> some View {
        let rotator: RotatorModel = app.rotator
        let language: LanguageModel = app.language
        let choices: [String] = rotator.rotorChoices
        if choices.count > 1 {
            Picker(selection: Binding(get: { rotator.selectedRotor }, set: { rotator.selectRotor($0) })) {
                ForEach(choices, id: \.self) { name in
                    Text(verbatim: name.isEmpty ? language.tr("Výchozí rotátor") : name).tag(name)
                }
            } label: {
                Text(verbatim: language.tr("Rotátor"))
            }
            .windowFont(13)
            .frame(maxWidth: 260)
        }
    }

    /// N1MM Rotor's preset buttons: F1–F10 turn the selected rotor to the bearing set in the Setup.
    private func presetRow(_ app: AppModel) -> some View {
        let rotator: RotatorModel = app.rotator
        let presets: [Int?] = rotator.presets
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
            ForEach(Array(presets.enumerated()), id: \.offset) { index, bearing in
                Button {
                    rotator.turnToPreset(index)
                } label: {
                    Text(verbatim: "F\(index + 1) " + (bearing.map { "\($0)°" } ?? "—"))
                        .windowFont(11)
                        .frame(maxWidth: .infinity)
                }
                .disabled(bearing == nil)
                .keyboardShortcut(Self.functionKey(index), modifiers: [])
                .accessibilityIdentifier("rotator.preset\(index + 1)")
            }
        }
    }

    /// F1…F10 as a key equivalent.
    private static func functionKey(_ index: Int) -> KeyEquivalent {
        let scalar: Unicode.Scalar = Unicode.Scalar(UInt32(NSF1FunctionKey + index)) ?? "?"
        return KeyEquivalent(Character(scalar))
    }

    /// The rotors heard on the network (N1MM Rotor broadcast), when the display is on.
    @ViewBuilder
    private func networkRotors(_ app: AppModel) -> some View {
        let rotator: RotatorModel = app.rotator
        let language: LanguageModel = app.language
        if app.config.config.rotor.networkEnabled {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: language.tr("Rotátory v síti")).windowFont(12, weight: .semibold)
                if let failure = rotator.networkStatus {
                    Text(verbatim: failure.text(language.translator, decimalSeparator: language.decimalSeparator))
                        .windowFont(11)
                        .foregroundStyle(.secondary)
                } else if rotator.networkRotors.isEmpty {
                    Text(verbatim: language.tr("Zatím nic nepřišlo")).windowFont(11).foregroundStyle(.secondary)
                }
                ForEach(rotator.networkRotors.keys.sorted(), id: \.self) { name in
                    Text(verbatim: name + ": " + RadioWindowTexts.rotatorAzimuth(rotator.networkRotors[name]))
                        .windowFont(12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The azimuth field (digits only, at most 3), „Natočit" and „Stop".
    private func manualRow(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let rotator: RotatorModel = app.rotator
        let manual: DialogFormState = self.manual
        let field = Binding<String>(get: { manual.text }, set: { manual.text = RadioWindowTexts.digits($0, limit: 3) })
        return HStack(alignment: .center, spacing: 6) {
            TextField(text: field) {
                Text(verbatim: "")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .windowFont(14)
            .frame(width: 80)
            .accessibilityLabel(language.tr("Natočit"))
            Button {
                if let azimuth = RadioWindowTexts.rotatorFieldAzimuth(manual.text) {
                    rotator.turnSelected(to: azimuth)
                }
            } label: {
                Text(verbatim: language.tr("Natočit")).windowFont(14)
            }
            Button {
                rotator.stop()
            } label: {
                Text(verbatim: "Stop").windowFont(14)
            }
        }
    }
}

/// The N1MM Rotor program's Setup: the named rotors (rotctld, calibration, limits), the F1–F10 preset bearings and the
/// network rotor display. Saved with „Uložit".
private struct RotorSetupSheet: View {
    let rotator: RotatorModel
    let language: LanguageModel
    let close: () -> Void

    @State private var draft: RotorSetupDraft
    @StateObject private var form = DialogFormState()

    init(rotator: RotatorModel, setup: RotorSetup, language: LanguageModel, close: @escaping () -> Void) {
        self.rotator = rotator
        self.language = language
        self.close = close
        _draft = State(initialValue: RotorSetupDraft(setup))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.tr("Nastavení rotátoru"))
                    .windowFont(15, weight: .semibold)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    rotorTable
                    presets
                    network
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    close()
                }
                .keyboardShortcut(.cancelAction)
                Button(language.tr("Uložit")) {
                    rotator.saveSetup(draft.applied())
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("rotator.setup.save")
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 460)
        .environment(\.windowFontSize, form.fontSize)
    }

    private var rotorTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: language.tr("Rotátory")).windowFont(13, weight: .medium)
            Text(verbatim: language.tr(
                "Výchozí rotátor je v Nastavení → Antény. Další rotátory: prázdný host = jen zpráva N1MM Rotor přes UDP s tímto jménem. Kalibrace se přičte ke čtené poloze. Meze ovladače: 0–360, 0–450 (přesah), -180–180 (doraz na jihu)."))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                header(language.tr("Jméno"), width: nil)
                header("Host", width: nil)
                header("Port", width: 60)
                header(language.tr("Kalibrace"), width: 64)
                header("Min", width: 52)
                header("Max", width: 52)
                Color.clear.frame(width: 24, height: 1)
            }
            ForEach($draft.rotors) { $row in
                HStack(spacing: 6) {
                    field($row.name, label: language.tr("Jméno"), width: nil)
                    field($row.host, label: "Host", width: nil)
                    field($row.port, label: "Port", width: 60)
                    field($row.calibration, label: language.tr("Kalibrace"), width: 64)
                    field($row.minAzimuth, label: "Min", width: 52)
                    field($row.maxAzimuth, label: "Max", width: 52)
                    IconButton(symbol: "trash", label: language.tr("Smazat rotátor")) {
                        draft.rotors.removeAll { $0.id == row.id }
                    }
                    .frame(width: 24)
                }
            }
            Button(language.tr("Přidat rotátor")) {
                draft.addRotor()
            }
            .windowFont(12)
            .disabled(draft.rotors.count >= RotorSetup.maxRotors)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: language.tr("Předvolby F1–F10 (stupně)")).windowFont(13, weight: .medium)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 4) {
                ForEach(0..<RotorSetup.presetCount, id: \.self) { index in
                    HStack(spacing: 4) {
                        Text(verbatim: "F\(index + 1)").windowFont(12).frame(width: 28, alignment: .leading)
                        field($draft.presets[index], label: "F\(index + 1)", width: nil)
                    }
                }
            }
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $draft.networkEnabled) {
                Text(verbatim: language.tr("Zobrazit rotátory ze sítě (N1MM Rotor, UDP)")).windowFont(12)
            }
            .toggleStyle(.checkbox)
            HStack(spacing: 6) {
                Text(verbatim: "Port").windowFont(12)
                field($draft.networkPort, label: language.tr("Port rotátorů v síti"), width: 80)
            }
            .disabled(!draft.networkEnabled)
        }
    }

    private func header(_ text: String, width: CGFloat?) -> some View {
        Text(verbatim: text)
            .windowFont(11)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
    }

    private func field(_ text: Binding<String>, label: String, width: CGFloat?) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .windowFont(12)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : width)
            .accessibilityLabel(Text(verbatim: label))
    }
}
