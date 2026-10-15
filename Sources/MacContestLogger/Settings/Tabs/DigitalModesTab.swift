import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `DigitalModesTab` (`MT:57-101`): how the rig's data mode is logged, and the fldigi modem with
/// „Vyzkoušet" (the probe runs off the main thread through `SettingsToolsModel`).
struct DigitalModesTab: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: language.tr("Datový režim rigu")) {
                SettingsField(caption: "PKTUSB / PKTLSB / DATA zapisovat jako") {
                    SettingsDropdown(label: draft.dataMode, options: ConfigurerCatalogs.dataModes, language: language) {
                        draft.dataMode = $0
                    }
                }
                .frame(maxWidth: 280, alignment: .leading)
                SettingsCaption(language.tr(
                    "Např. FT8, když datovým režimem rigu děláš jen FT8. QSO z WSJT-X / JTDX si mód nesou sama (záložka WSJT/JTDX)."))
            }
            ModemGroup(app: app, draft: $draft)
            RttyHardwareGroup(language: language, draft: $draft)
            ButtonsGroup(language: language, draft: $draft)
            AppearanceGroup(language: language, draft: $draft)
        }
    }
}

/// N1MM's Digital Interface message buttons DI1…DI24 (0, 8, 16 or 24 shown), the `.mc` import / export, and CWID.
private struct ButtonsGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        SettingsGroup(title: language.tr("Tlačítka zpráv Digitálního rozhraní")) {
            SettingsCaption(language.tr(
                "Texty s makry jako F-klávesy (také {TX}, {RX}, {ENTERLF}, {CLRRX}, {CLRTX}, {FILE:soubor}, {DI1}…{DI24}); tlačítka jsou v okně Digitální rozhraní a makra {DI1}…{DI24} je vloží do jiné zprávy."))
            HStack(spacing: 8) {
                Picker(selection: $draft.diButtonCount) {
                    ForEach([0, 8, 16, 24], id: \.self) { Text(verbatim: String($0)).tag($0) }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .frame(width: 80)
                .accessibilityLabel(Text(verbatim: language.tr("Počet tlačítek")))
                SettingsButton(language.tr("Načíst .mc…"), borderless: true) { importMc() }
                SettingsButton(language.tr("Uložit .mc…"), borderless: true) { exportMc() }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(draft.diMessages.indices.prefix(max(draft.diButtonCount, 8))), id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(verbatim: "DI" + String(index + 1)).windowFont(13).frame(width: 40, alignment: .leading)
                        SettingsTextField(text: $draft.diMessages[index].label).frame(width: 120)
                        SettingsTextField(text: $draft.diMessages[index].text).frame(maxWidth: .infinity)
                    }
                }
            }
            HStack(alignment: .center, spacing: 8) {
                SettingsCheckbox(label: language.tr("CW ID po každém vysílání"), isOn: $draft.cwIdEnabled)
                SettingsTextField(text: $draft.cwIdText).frame(width: 200)
                SettingsCaption(language.tr("fldigi pošle text v CW a vrátí původní mód; * nebo {MYCALL} = moje volačka."))
            }
        }
    }

    private func importMc() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let messages: [FunctionKeyMessage] = McMessages.parse(String(decoding: data, as: UTF8.self))
        var rows: [FunctionKeyDraft] = draft.diMessages
        for (index, message) in messages.prefix(rows.count).enumerated() {
            rows[index].label = message.label
            rows[index].text = message.text
        }
        draft.diMessages = rows
        if draft.diButtonCount < min(messages.count, 24) {
            draft.diButtonCount = DigitalConfig.buttonCount(min(messages.count + 7, 24))
        }
    }

    private func exportMc() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DI Messages.mc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text: String = McMessages.format(draft.diMessages.map { $0.toMessage() })
        try? Data(text.utf8).write(to: url)
    }
}

/// „Modem pro RTTY / PSK" (`MT:69-99`).
private struct ModemGroup: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        let language: LanguageModel = app.language
        let tools: SettingsToolsModel = app.settingsTools
        SettingsGroup(title: "Modem pro RTTY / PSK") {
            HStack(spacing: 16) {
                SettingsRadio(label: language.tr("Žádný"), selected: draft.digiEngine == .none) {
                    draft.digiEngine = .none
                }
                SettingsRadio(label: "fldigi (XML-RPC)", selected: draft.digiEngine == .fldigi) {
                    draft.digiEngine = .fldigi
                }
                SettingsRadio(label: language.tr("Vestavěný (MMTTY, jen RTTY)"), selected: draft.digiEngine == .builtin) {
                    draft.digiEngine = .builtin
                }
            }
            if draft.digiEngine == .builtin {
                BuiltinModemOptions(app: app, draft: $draft)
            }
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: "fldigi — adresa") {
                    SettingsTextField(text: $draft.fldigiHost)
                }
                .frame(width: 200)
                SettingsField(caption: "Port XML-RPC") {
                    SettingsTextField(text: $draft.fldigiPort, filter: .digits(limit: 5))
                }
                .frame(width: 120)
                SettingsButton(language.tr("Vyzkoušet")) {
                    tools.probeFldigi(host: draft.fldigiHost, port: draft.fldigiPort)
                }
                SettingsCaption(tools.fldigiProbeText)
            }
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: language.tr("Mód fldigi pro RTTY")) {
                    SettingsTextField(text: $draft.rttyModem)
                }
                .frame(width: 160)
                SettingsField(caption: language.tr("Mód fldigi pro PSK")) {
                    SettingsTextField(text: $draft.pskModem)
                }
                .frame(width: 160)
                SettingsCaption(language.tr(
                    "Napsání RTTY nebo PSK do pole volačky přepne i fldigi na tento mód (názvy jako v menu Op Mode fldigi, např. RTTY, BPSK31, BPSK63)."))
            }
            SettingsCheckbox(
                label: language.tr(
                    "AutoTRXUpdate: s rigem v USB/LSB zapisovat a spotovat frekvenci rig ± audio fldigi (při otevřeném Digitálním rozhraní)"),
                isOn: $draft.autoTrxUpdate)
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: language.tr("Zarovnání RTTY (Hz)")) {
                    SettingsTextField(text: Binding(get: { String(draft.alignRttyHz) },
                                                    set: { draft.alignRttyHz = Int($0) ?? draft.alignRttyHz }),
                                      filter: .digits(limit: 4))
                }
                .frame(width: 140)
                SettingsField(caption: language.tr("Zarovnání ostatní (Hz)")) {
                    SettingsTextField(text: Binding(get: { String(draft.alignOtherHz) },
                                                    set: { draft.alignOtherHz = Int($0) ?? draft.alignOtherHz }),
                                      filter: .digits(limit: 4))
                }
                .frame(width: 140)
                SettingsCaption(language.tr(
                    "Tlačítko Align přeladí rig tak, aby signál pod kurzorem fldigi byl na této audio frekvenci (u FSK nutné; fldigi: značka + 85 Hz)."))
            }
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: language.tr("Druhé fldigi (SO2V/SO2R) — adresa")) {
                    SettingsTextField(text: $draft.fldigi2Host)
                }
                .frame(width: 200)
                SettingsField(caption: language.tr("Port (0 = žádné)")) {
                    SettingsTextField(text: Binding(get: { String(draft.fldigi2Port) },
                                                    set: { draft.fldigi2Port = Int($0) ?? 0 }),
                                      filter: .digits(limit: 5))
                }
                .frame(width: 120)
                SettingsCaption(language.tr(
                    "Okno → Digitální rozhraní 2 patří k VFO B / rigu 2; Cmd+Alt+←/→ přepíná rozhraní (N1MM Ctrl+←/→)."))
            }
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: language.tr("TX lockout mezi DI1 a DI2:"))
                    .windowFont(13)
                Picker(selection: $draft.so2rTxLockout) {
                    Text(verbatim: language.tr("Vypnuto")).tag(DigitalTxLockout.off.rawValue)
                    Text(verbatim: language.tr("První vyhrává")).tag(DigitalTxLockout.firstWins.rawValue)
                    Text(verbatim: language.tr("Poslední vyhrává")).tag(DigitalTxLockout.lastWins.rawValue)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(Text(verbatim: language.tr("TX lockout mezi DI1 a DI2:")))
            }
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: language.tr("Další příjmová okna (host:port, mezerou, max. 4)")) {
                    SettingsTextField(text: $draft.extraRx)
                }
                SettingsCheckbox(label: language.tr("Volačky z nich do Grab okna"), isOn: $draft.extraRxToGrab)
            }
            SettingsCheckbox(label: language.tr("AFC zapnout s CQ a TU"), isOn: $draft.afcOnCq)
            SettingsCheckbox(label: language.tr("NET podle Run / S&P"), isOn: $draft.netWithRunChange)
            HStack(alignment: .center, spacing: 8) {
                SettingsCheckbox(label: language.tr("Kompenzace posunu FSK (Hz)"), isOn: $draft.shiftCompEnabled)
                SettingsTextField(text: Binding(get: { String(draft.shiftCompHz) },
                                                set: { draft.shiftCompHz = Int($0) ?? draft.shiftCompHz }),
                                  filter: .digitsAnd(extra: "-"))
                    .frame(width: 80)
            }
            SettingsCaption(language.tr(
                "fldigi dělá modem (RTTY, PSK…) a MCL mu posílá zprávy F-kláves (Function Keys → Digi) a čte dekódovaný text do okna Digitální rozhraní. V RTTY/PSK s modemem funguje i ESM. Esc vysílání přeruší."))
        }
    }
}

/// N1MM „Default RTTY Interface" and the hardware: an external TU/TNC, TinyFSK, WinKeyer 3.1 FSK. PSK always goes
/// through fldigi.
private struct RttyHardwareGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    private static let interfaces: [(RttyInterface, String)] = [
        (.fldigi, "fldigi"), (.tnc, "TU / TNC"), (.tinyFsk, "TinyFSK"), (.winkeyer, "WinKeyer 3.1"),
    ]
    private static let tncTypes: [(TncType, String)] = [
        (.pk232, "PK-232"), (.kam, "KAM"), (.dxp38, "HAL DXP-38"), (.other, "Other"),
    ]

    var body: some View {
        SettingsGroup(title: language.tr("RTTY: rozhraní pro vysílání")) {
            Picker(selection: $draft.rttyInterface) {
                ForEach(Self.interfaces, id: \.0.rawValue) { item in
                    Text(verbatim: item.1).tag(item.0.rawValue)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(Text(verbatim: language.tr("RTTY: rozhraní pro vysílání")))
            SettingsCaption(language.tr(
                "PSK a ostatní módy vždy přes fldigi. TU / TNC i dekóduje (text jde do Digitálního rozhraní); TinyFSK a WinKeyer 3.1 jen klíčují FSK, příjem dál dekóduje fldigi. Hardware není vyzkoušený naživo."))
            switch RttyInterface.from(draft.rttyInterface) {
            case .tnc:
                HStack(alignment: .bottom, spacing: 8) {
                    Picker(selection: $draft.tncType) {
                        ForEach(Self.tncTypes, id: \.0.rawValue) { item in
                            Text(verbatim: item.1).tag(item.0.rawValue)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .accessibilityLabel(Text(verbatim: "TNC"))
                    SettingsField(caption: language.tr("Sériový port")) {
                        SettingsTextField(text: $draft.tncPort)
                    }
                    SettingsField(caption: language.tr("Rychlost")) {
                        SettingsTextField(text: Binding(get: { String(draft.tncBaud) },
                                                        set: { draft.tncBaud = Int($0) ?? draft.tncBaud }),
                                          filter: .digits(limit: 6))
                    }
                    .frame(width: 90)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    SettingsField(caption: "{TX}") { SettingsTextField(text: $draft.tncTx) }
                    SettingsField(caption: "{RX}") { SettingsTextField(text: $draft.tncRx) }
                    SettingsField(caption: "Esc") { SettingsTextField(text: $draft.tncEsc) }
                }
                SettingsCaption(language.tr(
                    "Prázdné = výchozí příkazy typu (PK-232, KAM podle N1MM). Makra {CTRL-C}, {ENTER}, {ENTERLF}, {ESC}. Pro DXP-38 zadej příkazy podle jeho manuálu."))
            case .tinyFsk:
                SettingsField(caption: language.tr("Sériový port TinyFSK (9600 8N1)")) {
                    SettingsTextField(text: $draft.tinyFskPort)
                }
                .frame(maxWidth: 320, alignment: .leading)
            case .winkeyer:
                HStack(spacing: 12) {
                    Picker(selection: $draft.wkRttyBaud) {
                        ForEach([45, 50, 75, 100], id: \.self) { baud in
                            Text(verbatim: baud == 45 ? "45.45 Bd" : String(baud) + " Bd").tag(baud)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel(Text(verbatim: language.tr("Rychlost")))
                    SettingsCheckbox(label: language.tr("Reverse (mark/space)"), isOn: $draft.wkRttyReverse)
                    SettingsCheckbox(label: language.tr("FSK na KEY, PTT klíčuje (FSKMAP)"), isOn: $draft.wkRttyFskOnKey)
                }
                SettingsCaption(language.tr("WinKeyer z Nastavení → CW klíč, firmware 3.1 a novější."))
            case .fldigi:
                EmptyView()
            }
        }
    }
}

/// N1MM Skins, Colors and Fonts for the Digital Interface.
private struct AppearanceGroup: View {
    let language: LanguageModel
    @Binding var draft: ConfigurerDraft

    var body: some View {
        SettingsGroup(title: language.tr("Vzhled Digitálního rozhraní")) {
            HStack(alignment: .bottom, spacing: 8) {
                SettingsField(caption: language.tr("Písmo (prázdné = systémové neproporcionální)")) {
                    SettingsTextField(text: $draft.diFontName)
                }
                SettingsField(caption: language.tr("Barva textu #RRGGBB")) {
                    SettingsTextField(text: $draft.diTextColor)
                }
                .frame(width: 140)
                SettingsField(caption: language.tr("Pozadí #RRGGBB")) {
                    SettingsTextField(text: $draft.diBackgroundColor)
                }
                .frame(width: 140)
            }
        }
    }
}

/// The built-in RTTY modem (MMTTY): the receivers' audio (one stereo input: left = radio 1, right = radio 2, or radio
/// 2's own input), linked or independent tuning, the transmit output, its level and PTT.
private struct BuiltinModemOptions: View {
    let app: AppModel
    @Binding var draft: ConfigurerDraft

    private var language: LanguageModel {
        app.language
    }

    private func text(_ key: BuiltinModemSetup.Key) -> Binding<String> {
        Binding(get: { draft.builtinModem.text(key) },
                set: { value in
                    var setup: BuiltinModemSetup = draft.builtinModem
                    setup.set(key, value)
                    draft.builtinModem = setup
                })
    }

    private func flag(_ key: BuiltinModemSetup.Key) -> Binding<Bool> {
        Binding(get: { draft.builtinModem.flag(key) },
                set: { value in
                    var setup: BuiltinModemSetup = draft.builtinModem
                    setup.set(key, flag: value)
                    draft.builtinModem = setup
                })
    }

    private func device(_ key: BuiltinModemSetup.Key, _ options: [String]) -> some View {
        let fallback: String = language.tr(SettingsTools.systemDefaultDevice)
        let value: Binding<String> = text(key)
        return SettingsDropdown(label: ifBlank(value.wrappedValue, fallback), options: options, language: language) {
            value.wrappedValue = $0 == fallback ? "" : $0
        }
    }

    private static let inputs: [(BuiltinModemSetup.Input, String)] = [
        (.radio1, "Vstup přijímače (Audio)"), (.radio2, "Vstup rádia 2"),
    ]
    private static let channels: [(BuiltinModemSetup.Channel, String)] = [
        (.left, "Levý kanál"), (.right, "Pravý kanál"), (.mix, "Oba kanály"),
    ]

    private func receiver(_ side: Int) -> some View {
        let inputKey: BuiltinModemSetup.Key = side == 1 ? .input2 : .input1
        let channelKey: BuiltinModemSetup.Key = side == 1 ? .channel2 : .channel1
        let setup: BuiltinModemSetup = draft.builtinModem
        return HStack(alignment: .center, spacing: 8) {
            Text(verbatim: language.tr(side == 1 ? "Přijímač 2 (DI2):" : "Přijímač 1 (DI1):"))
                .windowFont(13)
                .frame(width: 130, alignment: .leading)
            ForEach(Self.inputs, id: \.0.rawValue) { input, label in
                SettingsRadio(label: language.tr(label), selected: setup.input(side: side) == input) {
                    text(inputKey).wrappedValue = input.rawValue
                }
            }
            Text(verbatim: "·").windowFont(13).accessibilityHidden(true)
            ForEach(Self.channels, id: \.0.rawValue) { channel, label in
                SettingsRadio(label: language.tr(label), selected: setup.channel(side: side) == channel) {
                    text(channelKey).wrappedValue = channel.rawValue
                }
            }
        }
    }

    var body: some View {
        let tools: SettingsToolsModel = app.settingsTools
        VStack(alignment: .leading, spacing: 6) {
            SettingsCaption(language.tr(
                "Vestavěný modem (MMTTY přes RYRY) dekóduje zvuk přijímače přímo v programu: Digitální rozhraní 1 a 2 mají každé svůj přijímač s vodopádem. Obvyklé zapojení: jeden stereo vstup, levý kanál = rádio 1, pravý = rádio 2."))
            receiver(0)
            receiver(1)
            SettingsCheckbox(label: language.tr("Společné ladění obou přijímačů (mark, posun, rychlost, AFC, NET, Rev)"),
                             isOn: flag(.linkedTuning))
            HStack(alignment: .top, spacing: 12) {
                SettingsField(caption: language.tr("Výstup AFSK (vysílač)")) {
                    device(.outputDevice, tools.outputDevices)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsField(caption: language.tr("Výstup rádia 2 (SO2R; prázdné = jako rádio 1)")) {
                    device(.outputDevice2, tools.outputDevices)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SettingsField(caption: language.tr("Úroveň AFSK (%)")) {
                    SettingsTextField(text: text(.outputLevel), filter: .digits(limit: 3))
                }
                .frame(width: 130)
            }
            SettingsCheckbox(label: language.tr("PTT přes CAT (jinak VOX)"), isOn: flag(.pttViaCat))
            HStack(alignment: .bottom, spacing: 12) {
                SettingsField(caption: language.tr("Vícekanálový příjem: nejvýše kanálů (1–8)")) {
                    SettingsTextField(text: text(.channelCount), filter: .digits(limit: 1))
                }
                .frame(width: 220)
                SettingsField(caption: language.tr("Kanál zmizí po (s) bez signálu")) {
                    SettingsTextField(text: text(.channelTimeout), filter: .digits(limit: 3))
                }
                .frame(width: 200)
            }
            SettingsCaption(language.tr(
                "Vysílání: AFSK zvukem na zvolený výstup. FSK přes TinyFSK nebo WinKeyer nastavíte níže v „RTTY: rozhraní pro vysílání\" (vestavěný modem pak jen přijímá)."))
        }
    }
}
