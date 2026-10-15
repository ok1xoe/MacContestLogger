import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `CwKeyerTab` (`VK:199-238`): the keying method (rig keyer over CAT, Winkeyer on a serial port, off), the
/// speed and the serial number format. The serial ports are listed when the tab opens.
struct CwKeyerTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel { app.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            methodGroup
            speedGroup
            timingGroup
            serialGroup
            monitorGroup
            winkeyerGroup
        }
        .onAppear {
            app.settingsTools.loadSerialPorts()
            app.settingsTools.loadAudioDevices()
        }
    }

    private var methodGroup: some View {
        let ports: [String] = app.settingsTools.serialPorts
        let noPort: String = ports.isEmpty ? language.tr("Žádný sériový port") : "Vyber port"
        let serial: Bool = draft.cwOptions.serialKeying
        return SettingsGroup(title: language.tr("Způsob klíčování")) {
            SettingsRadio(label: language.tr("Klíčovač rigu přes CAT (rigctld)"), selected: !serial && draft.cwMethod == .cat) {
                draft.cwMethod = .cat
                draft.cwOptions.serialKeying = false
            }
            SettingsCaption(language.tr(
                "Text posílá rig vestavěným klíčovačem (hamlib send_morse), např. Kenwood, Icom, Yaesu, Elecraft. TRX musí být připojený. Prosigny se pošlou jako dvojice písmen a změny rychlosti < > uvnitř zprávy rig neumí."))
            SettingsRadio(label: language.tr("K1EL Winkeyer (sériový port)"),
                          selected: !serial && draft.cwMethod == .winkeyer) {
                draft.cwMethod = .winkeyer
                draft.cwOptions.serialKeying = false
            }
            SettingsField(caption: "Port Winkeyeru") {
                SettingsDropdown(label: ifBlank(app.settingsTools.portLabel(draft.cwPort), noPort), options: ports,
                                 language: language, enabled: !serial && draft.cwMethod == .winkeyer) { draft.cwPort = $0 }
            }
            MissingPortNote(app: app, port: draft.cwPort)
            SettingsRadio(label: language.tr("Linka DTR/RTS sériového portu (jednoduché rozhraní)"), selected: serial) {
                draft.cwOptions.serialKeying = true
            }
            SettingsRadio(label: "Vypnuto", selected: !serial && draft.cwMethod == .none) {
                draft.cwMethod = .none
                draft.cwOptions.serialKeying = false
            }
        }
    }

    private var speedGroup: some View {
        let styles: [CutStyle] = CutStyle.allCases
        return SettingsGroup(title: language.tr("Rychlost a čísla")) {
            HStack(alignment: .center, spacing: 12) {
                SettingsField(caption: "Rychlost (WPM)") {
                    SettingsTextField(text: $draft.cwSpeed, filter: .digits(limit: nil))
                }
                .frame(width: 140)
                SettingsCaption(language.tr("V zadávacím okně PgUp / PgDn ±2 WPM."))
            }
            SettingsCheckbox(
                label: language.tr(
                    "Pořadová čísla s cut číslicemi (FULLABBREV / PROABBREV / SEMIABBREV / NOABBREV)"),
                isOn: $draft.cwCutNumbers)
            SettingsField(caption: language.tr("Styl cut čísel")) {
                SettingsDropdown(label: draft.cwCutStyle.label, options: styles.map(\.label), language: language,
                                 enabled: draft.cwCutNumbers) { picked in
                    if let style = styles.first(where: { $0.label == picked }) {
                        draft.cwCutStyle = style
                    }
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            SettingsCheckbox(label: language.tr("Pořadová čísla s úvodními nulami (007)"), isOn: $draft.cwLeadingZeros)
            SettingsCheckbox(label: language.tr("Zobrazovat odesílané CW ve stavovém řádku"), isOn: $draft.showSentCw)
        }
    }

    /// N1MM Other tab "CW Weight" and Function Keys tab "Use CW contest word spacing".
    private var timingGroup: some View {
        SettingsGroup(title: language.tr("Váha a mezery")) {
            CwStepperRow(label: language.tr("Váha CW (%)"), value: $draft.cwOptions.weight,
                         range: CwKeyingOptions.weightRange)
            SettingsCheckbox(label: language.tr("Závodní mezera mezi slovy (6 teček místo 7)"),
                             isOn: $draft.cwOptions.contestSpacing)
            SettingsCaption(language.tr(
                "Platí pro klíčovače, které tvoří značky samy (Winkeyer s posíláním nastavení). Klíčovač rigu přes CAT používá nastavení rigu."))
        }
    }

    /// N1MM Hardware tab, CW/Other port: DTR/RTS set to CW / PTT, PTT delay; radio port "PTT via Radio Command".
    private var serialGroup: some View {
        let on: Bool = draft.cwOptions.serialKeying
        let ports: [String] = app.settingsTools.serialPorts
        let lines: [CwKeyingOptions.SerialLine] = [.dtr, .rts]
        let pttLines: [CwKeyingOptions.SerialLine] = CwKeyingOptions.SerialLine.allCases
        let noPort: String = ports.isEmpty ? language.tr("Žádný sériový port") : "Vyber port"
        let none: String = language.tr("— žádný —")
        return SettingsGroup(title: language.tr("Klíčování DTR/RTS a PTT")) {
            SettingsCaption(language.tr(
                "Jednoduché tranzistorové rozhraní na sériovém portu: jedna linka klíčuje CW, druhá (volitelně) PTT. Linky jsou po otevření portu v klidu a po Esc i zavření se vždy uvolní."))
            HStack(alignment: .top, spacing: 16) {
                SettingsField(caption: language.tr("Port")) {
                    SettingsDropdown(label: ifBlank(draft.cwOptions.serialPort, noPort), options: ports,
                                     language: language, enabled: on) { draft.cwOptions.serialPort = $0 }
                }
                .frame(width: 220, alignment: .leading)
                SettingsField(caption: language.tr("Linka CW")) {
                    SettingsDropdown(label: draft.cwOptions.serialKeyLine.rawValue, options: lines.map(\.rawValue),
                                     language: language, enabled: on) { picked in
                        draft.cwOptions.serialKeyLine = CwKeyingOptions.SerialLine(rawValue: picked) ?? .dtr
                        if draft.cwOptions.serialPttLine == draft.cwOptions.serialKeyLine {
                            draft.cwOptions.serialPttLine = .none
                        }
                    }
                }
                .frame(width: 100, alignment: .leading)
                SettingsField(caption: language.tr("Linka PTT")) {
                    SettingsDropdown(
                        label: draft.cwOptions.serialPttLine == .none ? none : draft.cwOptions.serialPttLine.rawValue,
                        options: pttLines.filter { $0 != draft.cwOptions.serialKeyLine }
                            .map { $0 == .none ? none : $0.rawValue },
                        language: language, enabled: on) { picked in
                        draft.cwOptions.serialPttLine = CwKeyingOptions.SerialLine(rawValue: picked) ?? .none
                    }
                }
                .frame(width: 120, alignment: .leading)
            }
            SettingsCheckbox(label: language.tr("PTT příkazem rádia (CAT) při CW"), isOn: $draft.cwOptions.cwPttViaCat,
                             enabled: on)
            CwStepperRow(label: language.tr("Zpoždění PTT před vysíláním (ms)"),
                         value: $draft.cwOptions.serialPttDelayMs, range: CwKeyingOptions.serialPttRange, step: 10,
                         enabled: on)
            CwStepperRow(label: language.tr("Doběh PTT po vysílání (ms)"), value: $draft.cwOptions.serialPttTailMs,
                         range: CwKeyingOptions.serialPttRange, step: 10, enabled: on)
            SettingsCaption(language.tr(
                "PTT příkazem rádia po módech: CW = volba výše (s klíčováním DTR/RTS; klíčovač rigu a Winkeyer klíčují PTT samy), SSB = Hlasový klíč → PTT přes CAT, digitální módy = PTT řídí fldigi, TinyFSK nebo TNC."))
        }
    }

    /// The sound-card CW monitor.
    private var monitorGroup: some View {
        let on: Bool = draft.cwOptions.monitorEnabled
        let fallback: String = language.tr(SettingsTools.systemDefaultDevice)
        return SettingsGroup(title: language.tr("Příposlech CW zvukovou kartou")) {
            SettingsCheckbox(label: language.tr("Přehrávat odesílané CW jako tón"), isOn: $draft.cwOptions.monitorEnabled)
            SettingsField(caption: language.tr("Výstup")) {
                SettingsDropdown(label: ifBlank(draft.cwOptions.monitorDevice, fallback),
                                 options: app.settingsTools.outputDevices, language: language, enabled: on) {
                    draft.cwOptions.monitorDevice = $0 == fallback ? "" : $0
                }
            }
            .frame(width: 280, alignment: .leading)
            CwStepperRow(label: language.tr("Výška tónu (Hz)"), value: $draft.cwOptions.monitorPitchHz,
                         range: CwKeyingOptions.monitorPitchRange, step: 10, enabled: on)
            CwStepperRow(label: language.tr("Hlasitost (%)"), value: $draft.cwOptions.monitorVolume,
                         range: CwKeyingOptions.monitorVolumeRange, step: 5, enabled: on)
        }
    }

    /// N1MM Winkey tab: keying mode, paddles, sidetone, speed pot, PTT timing and keying compensation.
    private var winkeyerGroup: some View {
        let on: Bool = draft.cwOptions.wkSendSettings
        let modes: [WinkeyerKeyMode] = WinkeyerKeyMode.allCases
        let tones: [Int] = CwKeyingOptions.winkeyerSidetones
        let hangs: [String] = ["1", "1,33", "1,67", "2"]
        return SettingsGroup(title: language.tr("Nastavení Winkeyeru")) {
            SettingsCheckbox(label: language.tr("Posílat nastavení do Winkeyeru při otevření"),
                             isOn: $draft.cwOptions.wkSendSettings)
            SettingsCaption(language.tr(
                "Vypnuto = Winkeyer si ponechá vlastní nastavení. Zapnuto = režim klíčování, příposlech, váha, PTT a další volby níže se pošlou po připojení a po každé změně (výstup KEY 1)."))
            HStack(alignment: .top, spacing: 16) {
                SettingsField(caption: language.tr("Režim klíčování")) {
                    SettingsDropdown(label: draft.cwOptions.wkKeyMode.label, options: modes.map(\.label),
                                     language: language, enabled: on) { picked in
                        if let mode = modes.first(where: { $0.label == picked }) {
                            draft.cwOptions.wkKeyMode = mode
                        }
                    }
                }
                .frame(width: 180, alignment: .leading)
                SettingsField(caption: language.tr("Kmitočet příposlechu (Hz)")) {
                    SettingsDropdown(label: String(draft.cwOptions.wkSidetoneHz), options: tones.map { String($0) },
                                     language: language, enabled: on) { picked in
                        if let hz = Int(picked) {
                            draft.cwOptions.wkSidetoneHz = hz
                        }
                    }
                }
                .frame(width: 180, alignment: .leading)
            }
            SettingsCheckbox(label: language.tr("Autospace"), isOn: $draft.cwOptions.wkAutospace, enabled: on)
            SettingsCheckbox(label: language.tr("Prohodit pádla"), isOn: $draft.cwOptions.wkSwapPaddles, enabled: on)
            SettingsCheckbox(label: language.tr("Příposlech zapnutý"), isOn: $draft.cwOptions.wkSidetone, enabled: on)
            SettingsCheckbox(label: language.tr("Příposlech jen při klíčování pádly"),
                             isOn: $draft.cwOptions.wkSidetonePaddleOnly, enabled: on)
            SettingsRadio(label: language.tr("Potenciometr rychlosti ignorovat"),
                          selected: draft.cwOptions.wkPotMode == .ignore, enabled: on) {
                draft.cwOptions.wkPotMode = .ignore
            }
            SettingsRadio(label: language.tr("Potenciometr rychlosti mění rychlost CW v deníku"),
                          selected: draft.cwOptions.wkPotMode == .follow, enabled: on) {
                draft.cwOptions.wkPotMode = .follow
            }
            CwStepperRow(label: language.tr("Potenciometr od (WPM)"), value: $draft.cwOptions.wkPotMinWpm,
                         range: CwKeyingOptions.potMinRange, enabled: on && draft.cwOptions.wkPotMode == .follow)
            CwStepperRow(label: language.tr("Rozsah potenciometru (WPM)"), value: $draft.cwOptions.wkPotRangeWpm,
                         range: CwKeyingOptions.potSpanRange, enabled: on && draft.cwOptions.wkPotMode == .follow)
            SettingsCheckbox(label: language.tr("PTT výstup Winkeyeru"), isOn: $draft.cwOptions.wkPtt, enabled: on)
            CwStepperRow(label: language.tr("PTT náběh (ms)"), value: $draft.cwOptions.wkLeadMs,
                         range: CwKeyingOptions.pttTimeRange, step: 10, enabled: on)
            CwStepperRow(label: language.tr("PTT doběh (ms, 0 = doba držení)"), value: $draft.cwOptions.wkTailMs,
                         range: CwKeyingOptions.pttTimeRange, step: 10, enabled: on)
            SettingsField(caption: language.tr("Doba držení PTT (mezery mezi slovy)")) {
                SettingsDropdown(label: hangs[draft.cwOptions.wkHangTime], options: hangs, language: language,
                                 enabled: on) { picked in
                    if let index = hangs.firstIndex(of: picked) {
                        draft.cwOptions.wkHangTime = index
                    }
                }
            }
            .frame(width: 220, alignment: .leading)
            CwStepperRow(label: language.tr("Prodloužení prvního znaku (ms)"),
                         value: $draft.cwOptions.wkFirstExtensionMs, range: CwKeyingOptions.msByteRange, enabled: on)
            CwStepperRow(label: language.tr("Kompenzace klíčování (ms)"),
                         value: $draft.cwOptions.wkKeyCompensationMs, range: CwKeyingOptions.msByteRange, enabled: on)
        }
    }
}

/// A whole-number setting with its value in the label and a stepper.
struct CwStepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var enabled: Bool = true

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            Text(verbatim: label + ": " + String(value))
                .windowFont(13)
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: String(value)))
    }
}
