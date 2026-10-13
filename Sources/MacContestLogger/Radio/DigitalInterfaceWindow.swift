import AppKit
import Carbon.HIToolbox
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `DigitalInterfaceWindow` (`digitalinterface` 680×340, `DigitalInterfaceWindow.kt:67-228`, N1MM Digital
/// Interface): the modem status („modem · trx", „—") with „Vymazat" in the top row, the error line, the last calls
/// heard, fldigi's decoded text with the calls (primary) and the exchange words (tertiary) underlined — a click
/// puts them into the active entry window — and the hint line. F1–F12, Enter and Esc go to the active entry window
/// (the focus stays here).
struct DigitalInterfaceWindowView: View {
    static let id = "digitalinterface"
    /// N1MM's Digital Interface 2 (VFO B / rig 2).
    static let id2 = "digitalinterface2"

    let host: AppHost
    /// 0 = DI1, 1 = DI2.
    let index: Int

    @StateObject private var session: WindowSession

    init(host: AppHost, index: Int = 0) {
        self.host = host
        self.index = index
        _session = StateObject(wrappedValue: WindowSession(id: index == 1 ? Self.id2 : Self.id, persistSize: true,
                                                           defaultSize: CGSize(width: 680, height: 340)))
    }

    private var windowId: String { index == 1 ? Self.id2 : Self.id }
    @StateObject private var holder = WindowModelHolder<DigitalInterfaceModel>()
    @StateObject private var keys = WindowKeyMonitor()
    @StateObject private var tx = TxFieldState()
    @FocusState private var txFocused: Bool

    var body: some View {
        Group {
            if let app = host.model {
                let model: DigitalInterfaceModel = holder.model { app.makeDigitalInterface(index: index) }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: windowId,
                                                title: index == 1 ? "Digitální rozhraní 2" : "Digitální rozhraní",
                                                binder: session.binder))
                    .background(WindowAccessor { window in
                        let tx: TxFieldState = self.tx
                        keys.handler = { key in
                            // Enter in the TX window ends its line there (Esc still stops the transmission).
                            if tx.focused && (key.keyCode == UInt16(kVK_Return) || key.keyCode == UInt16(kVK_ANSI_KeypadEnter)) {
                                return false
                            }
                            return Self.handle(key, model: model)
                        }
                        keys.install(window: window)
                    })
                    .onAppear { model.open() }
                    .onDisappear { model.close() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }

    /// `DIGI_FUNCTION_KEYS` (F1–F12 in order), Enter, Esc.
    private static let functionKeys: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]

    private static func handle(_ key: WindowKey, model: DigitalInterfaceModel) -> Bool {
        let code = Int(key.keyCode)
        if let index = functionKeys.firstIndex(of: code) {
            return model.key(.function(index), down: key.down, shift: key.shift)
        }
        switch code {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return model.key(.enter, down: key.down, shift: key.shift)
        case kVK_Escape:
            return model.key(.escape, down: key.down, shift: key.shift)
        default:
            return false
        }
    }

    private func content(_ app: AppModel, _ model: DigitalInterfaceModel) -> some View {
        let language: LanguageModel = app.language
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language) {
                HStack(alignment: .center, spacing: 8) {
                    if model.hasTransmitFocus {
                        Text(verbatim: "TX")
                            .windowFont(12, weight: .bold)
                            .foregroundStyle(Color.red)
                            .accessibilityLabel(language.tr("Toto rozhraní má vysílání"))
                    }
                    Text(verbatim: model.status.isEmpty ? "—" : model.status)
                        .windowFont(16)
                    let frequency: String = model.frequencyCaption
                    if !frequency.isEmpty {
                        Text(verbatim: frequency)
                            .windowFont(14, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("digital.frequency")
                    }
                    Button {
                        model.clear()
                    } label: {
                        Text(verbatim: "Vymazat").windowFont(14)
                    }
                    .buttonStyle(.borderless)
                    opModeMenu(model, language: language)
                    setupMenu(model, language: language)
                }
            }
            if let error = model.error {
                Text(verbatim: error.text(language.translator, decimalSeparator: language.decimalSeparator))
                    .windowFont(14)
                    .foregroundStyle(Color(domain: DomainColors.dupe))
            }
            grabRow(app, model, language: language)
            attachedRx(model, language: language)
            HStack(alignment: .top, spacing: 4) {
                pauseBar(model, language: language)
                DigitalRxTextView(text: Self.annotated(model, size: session.fontSize),
                                  accessibilityText: language.tr("Dekódovaný text"),
                                  scrolling: !model.option(\.nonScrollingRx),
                                  onTap: { offset, flags in model.tap(offset: offset, click: Self.click(flags)) },
                                  onHover: { offset in model.hover(offset: offset) },
                                  onRightClick: { model.rightClick() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.color(hex: model.appearance.background).map { Color(nsColor: $0) } ?? Color.clear)
            }
            indicators(model, language: language)
            txArea(app, model, language: language)
            buttonsGrid(model)
            Text(verbatim: language.tr(
                "Klik: volačka do pole volačky, jiné podtržené slovo do výměny · Option+klik: do zásobníku · Cmd+klik: slovo do pole s kurzorem · Shift+klik: převod Letters/Figs. Text dekóduje fldigi."))
                .windowFont(11)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
    }

    /// N1MM's TX window: a line for free typing (Ctrl+K / Alt+T start the transmission and focus it), TX and RX.
    /// While transmitting every typed character goes out at once; otherwise Enter sends the line as a message.
    private func txArea(_ app: AppModel, _ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        let transmitting: Bool = model.transmitting
        return HStack(spacing: 6) {
            TextField(language.tr("TX: psaní volného textu (Enter odešle)"), text: Binding(
                get: { tx.text },
                set: { newValue in
                    let old: String = tx.text
                    tx.text = newValue
                    if model.transmitting, newValue.hasPrefix(old), newValue.count > old.count {
                        model.typed(String(newValue.dropFirst(old.count)).uppercased())
                    }
                }))
                .textFieldStyle(.roundedBorder)
                .windowFont(14, design: .monospaced)
                .focused($txFocused)
                .onSubmit {
                    if model.transmitting {
                        model.typed("\n")
                    } else {
                        model.typed(tx.text.uppercased())
                    }
                    tx.text = ""
                }
                .onChange(of: txFocused) { tx.focused = txFocused }
                .onChange(of: app.keyer.digital.txFocusRequest) { txFocused = true }
                .accessibilityIdentifier("digital.tx")
            Button {
                model.toggleTransmit()
                txFocused = !transmitting
            } label: {
                Text(verbatim: transmitting ? "RX" : "TX")
                    .windowFont(13, weight: .semibold)
                    .foregroundStyle(transmitting ? Color.red : Color.primary)
            }
            .help(language.tr("Vysílání zap / vyp (Alt+T); Esc vysílání přeruší"))
            .accessibilityIdentifier("digital.txButton")
            tuningButtons(model, language: language)
        }
    }

    /// N1MM's fldigi controls: Align (the signal under the cursor to the alignment frequency), AFC, NET (Lock off),
    /// Rev and Lock; a lit button is on.
    private func tuningButtons(_ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        HStack(spacing: 4) {
            Button {
                model.align()
            } label: {
                Text(verbatim: "Align").windowFont(12)
            }
            .help(language.tr("Přeladit rig, aby signál pod kurzorem byl na frekvenci zarovnání"))
            .accessibilityIdentifier("digital.align")
            switchButton("AFC", on: model.isOn(.afc), identifier: "afc") { model.toggle(.afc) }
            switchButton("NET", on: model.net, identifier: "net") { model.toggle(.lock) }
            switchButton("Rev", on: model.isOn(.reverse), identifier: "rev") { model.toggle(.reverse) }
            switchButton("Lock", on: model.isOn(.lock), identifier: "lock") { model.toggle(.lock) }
        }
    }

    private func switchButton(_ title: String, on: Bool?, identifier: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .windowFont(12, weight: on == true ? .bold : .regular)
                .foregroundStyle(on == true ? Color.accentColor : Color.primary)
        }
        .accessibilityValue(Text(verbatim: on == true ? "1" : "0"))
        .accessibilityIdentifier("digital." + identifier)
    }

    /// N1MM's extra message buttons (0, 8, 16 or 24; Settings → Digital modes or the Setup menu).
    @ViewBuilder
    private func buttonsGrid(_ model: DigitalInterfaceModel) -> some View {
        let buttons: [FunctionKeyMessage] = model.buttons
        if !buttons.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
                    Button {
                        model.pressButton(index)
                    } label: {
                        Text(verbatim: button.label.isEmpty ? "DI" + String(index + 1) : button.label)
                            .windowFont(12)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(KotlinStrings.isBlank(button.text))
                    .accessibilityIdentifier("digital.button.\(index + 1)")
                }
            }
        }
    }

    /// N1MM's Grab window: the calls heard (the highlighted one is grabbed next by Alt+G, `{GRAB}`, Insert), the
    /// Grab and CLR buttons; the right-click menu clears the list or the selected call and sets the sort order.
    private func grabRow(_ app: AppModel, _ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        let grabList: GrabListModel = app.grabList
        let highlighted: String? = model.highlightedCall
        return HStack(spacing: 6) {
            Button {
                model.grab()
            } label: {
                Text(verbatim: "Grab").windowFont(13)
            }
            .disabled(highlighted == nil)
            .help(language.tr("Volačka z Grab okna do pole volačky (Alt+G)"))
            .accessibilityIdentifier("digital.grab")
            Button {
                grabList.clear()
            } label: {
                Text(verbatim: "CLR").windowFont(13)
            }
            .disabled(model.recentCalls.isEmpty)
            .help(language.tr("Vymazat Grab okno"))
            .accessibilityIdentifier("digital.grabClear")
            ForEach(model.recentCalls, id: \.self) { call in
                SettingsChip(label: call, selected: call == highlighted) {
                    model.take(call, click: NSEvent.modifierFlags.contains(.option) ? .stack : .plain)
                }
                .contextMenu {
                    Button(language.tr("Vybrat")) { grabList.select(call) }
                    Button(language.tr("Smazat vybranou volačku")) {
                        grabList.select(call)
                        grabList.removeSelected()
                    }
                    Button(language.tr("Vymazat seznam")) { grabList.clear() }
                    Divider()
                    Button((grabList.order == .lifo ? "✓ " : "") + language.tr("Pořadí: nejnovější první (LIFO)")) {
                        grabList.setOrder(.lifo)
                    }
                    Button((grabList.order == .fifo ? "✓ " : "") + language.tr("Pořadí: nejstarší první (FIFO)")) {
                        grabList.setOrder(.fifo)
                    }
                }
            }
        }
    }

    /// macOS modifiers → N1MM's clicks: Option = Alt (stack), Cmd = Ctrl (into the focused field; Ctrl+click is the
    /// secondary click here), Shift = Letters/Figures.
    static func click(_ flags: NSEvent.ModifierFlags) -> DigitalInterfaceModel.Click {
        if flags.contains(.option) {
            return .stack
        }
        if flags.contains(.command) {
            return .force
        }
        if flags.contains(.shift) {
            return .lettersFigures
        }
        return .plain
    }

    /// N1MM's attached additional RX windows: the text of further fldigi instances decoding the same audio.
    @ViewBuilder
    private func attachedRx(_ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        ForEach(Array(model.extraTexts.enumerated()), id: \.offset) { slot, text in
            DigitalRxTextView(text: NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: WindowFont.size(13, windowSize: session.fontSize),
                                                   weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]), accessibilityText: language.tr("Další příjem") + " " + String(slot + 1))
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 60)
        }
    }

    /// N1MM's pause bar left of the received text: green = live, yellow = paused (click to switch).
    private func pauseBar(_ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        let paused: Bool = model.isPaused
        return Button {
            model.togglePause()
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(paused ? Color.yellow : Color.green)
                .frame(width: 8)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.tr(paused ? "Příjem pozastaven — klik pokračuje" : "Pozastavit příjem"))
        .accessibilityIdentifier("digital.pause")
    }

    /// N1MM's MouseOver and Letters/Figs indicators.
    private func indicators(_ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: language.tr("Pod myší") + ": " + model.mouseOver)
            Text(verbatim: language.tr("Letters/Figs") + ": " + model.lettersFigs)
            if model.isPaused {
                Text(verbatim: language.tr("POZASTAVENO"))
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
        .windowFont(11, design: .monospaced)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("digital.indicators")
    }

    /// N1MM's fldigi „Op Mode" menu: the contest modems first, the rest of fldigi's list in a submenu.
    private func opModeMenu(_ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        let modes = model.opModes
        let current: String = model.currentModem
        return Menu {
            ForEach(modes.common, id: \.self) { name in
                Button {
                    model.selectModem(name)
                } label: {
                    Text(verbatim: (name == current ? "✓ " : "") + name)
                }
            }
            if !modes.other.isEmpty {
                Menu(language.tr("Další módy")) {
                    ForEach(modes.other, id: \.self) { name in
                        Button {
                            model.selectModem(name)
                        } label: {
                            Text(verbatim: (name == current ? "✓ " : "") + name)
                        }
                    }
                }
            }
        } label: {
            Text(verbatim: language.tr("Mód")).windowFont(14)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(language.tr("Mód fldigi (Op Mode)"))
        .accessibilityIdentifier("digital.opMode")
    }

    /// N1MM's Digital Interface „Setup" menu: Digital Call Stacking (disabled, FIFO, LIFO, FIFO mults first).
    private func setupMenu(_ model: DigitalInterfaceModel, language: LanguageModel) -> some View {
        let current: CallStack.Order? = model.digitalCallStacking
        let options: [(CallStack.Order?, String)] = [
            (nil, "Vypnuto"), (.fifo, "Zapnuto: FIFO"), (.lifo, "Zapnuto: LIFO"),
            (.multsFirst, "Zapnuto: FIFO, násobiče napřed"),
        ]
        let toggles: [(WritableKeyPath<DigitalConfig, Bool>, String)] = [
            (\.captionRadioFrequency, "V titulku frekvence rigu, ne přesná"),
            (\.nonScrollingRx, "Neposuvné okno příjmu"),
            (\.pauseOnCallHover, "Pozastavit příjem nad volačkou (prázdné pole)"),
            (\.hoverMode, "Hover: volačka pod myší do pole"),
            (\.rightClickReturn, "Pravý klik = Enter (ESM)"),
            (\.sendSpaceOnClick, "Po kliku na volačku kurzor do výměny (mezera)"),
            (\.scpGarbageSearch, "Hledat volačky z Master.scp i v šumu"),
            (\.highlightBackground, "Barva volačky jako pozadí"),
            (\.rxOutputToFile, "Ukládat přijatý text do souboru (ExportFiles)"),
            (\.cwIdEnabled, "CW ID po každém vysílání"),
            (\.afcOnCq, "AFC zapnout s CQ a TU"),
            (\.netWithRunChange, "NET podle Run / S&P"),
        ]
        let grabOptions: [(WritableKeyPath<DigitalConfig, Bool>, String)] = [
            (\.grabNoDupes, "Dupy do Grab okna nedávat"),
            (\.grabOnlyScp, "Do Grab okna jen volačky z Master.scp"),
            (\.grabClearOnQsy, "QSY vymaže Grab okno"),
            (\.grabClearOnCq, "CQ vymaže Grab okno"),
            (\.grabSendSpace, "Po grabu kurzor do výměny (mezera)"),
            (\.grabAddToBandmap, "Při grabu dát volačku z pole do bandmapy (Alt+O)"),
        ]
        let resources: [(WritableKeyPath<DigitalConfig, Bool>, String)] = [
            (\.validateScp, "Master.scp"), (\.validateCallHistory, "Call history"),
            (\.validateSpotted, "Spoty z clusteru"), (\.validateLogged, "Volačky v deníku"),
        ]
        let validities: [(DigitalCallValidity, String)] = [
            (.generic, "Vše, co vypadá jako volačka"), (.resources, "Jen volačky ze zdrojů"),
            (.combined, "Obojí, neověřené žlutě"),
        ]
        return Menu {
            Button(language.tr("Odeslat textový soubor…")) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.plainText]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    model.sendTextFile(url)
                }
            }
            Menu(language.tr("Tlačítka zpráv")) {
                ForEach([0, 8, 16, 24], id: \.self) { count in
                    Button((model.buttons.count == count ? "✓ " : "") + String(count)) {
                        model.setButtonCount(count)
                    }
                }
            }
            Divider()
            Button {
                model.setAutoTrxUpdate(!model.autoTrxUpdate)
            } label: {
                Text(verbatim: (model.autoTrxUpdate ? "✓ " : "") + language.tr("AutoTRXUpdate (frekvence = rig ± audio)"))
            }
            ForEach(Array(toggles.enumerated()), id: \.offset) { _, toggle in
                Button {
                    model.setOption(toggle.0, !model.option(toggle.0))
                } label: {
                    Text(verbatim: (model.option(toggle.0) ? "✓ " : "") + language.tr(toggle.1))
                }
            }
            Menu(language.tr("Grab okno")) {
                ForEach(Array(grabOptions.enumerated()), id: \.offset) { _, item in
                    Button {
                        model.setOption(item.0, !model.option(item.0))
                    } label: {
                        Text(verbatim: (model.option(item.0) ? "✓ " : "") + language.tr(item.1))
                    }
                }
            }
            Menu(language.tr("Ověřování volaček")) {
                ForEach(Array(validities.enumerated()), id: \.offset) { _, item in
                    Button {
                        model.setCallValidity(item.0)
                    } label: {
                        Text(verbatim: (model.callValidity == item.0 ? "✓ " : "") + language.tr(item.1))
                    }
                }
                Divider()
                ForEach(Array(resources.enumerated()), id: \.offset) { _, item in
                    Button {
                        model.setOption(item.0, !model.option(item.0))
                    } label: {
                        Text(verbatim: (model.option(item.0) ? "✓ " : "") + language.tr(item.1))
                    }
                }
            }
            Section(language.tr("Digitální zásobník volaček")) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        model.setDigitalCallStacking(option.0)
                    } label: {
                        Text(verbatim: (option.0 == current ? "✓ " : "") + language.tr(option.1))
                    }
                }
            }
        } label: {
            Text(verbatim: language.tr("Nastavení")).windowFont(14)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(language.tr("Nastavení digitálního rozhraní"))
        .accessibilityIdentifier("digital.setup")
    }

    /// The window's text with the model's spans: calls in their status colour (N1MM: the bandmap's colours; yellow
    /// for an unverified call; the colour as background with „Highlight Background"), text received while
    /// transmitting dimmed, and in the non-scrolling mode the current (last) line underlined.
    static func annotated(_ model: DigitalInterfaceModel, size: Int) -> NSAttributedString {
        let text: String = model.text
        let result = NSMutableAttributedString(attributedString: annotated(text, spans: model.spans, size: size))
        // N1MM Skins, Colors and Fonts: the window's own font and text colour.
        let appearance = model.appearance
        if let font = NSFont(name: appearance.font, size: WindowFont.size(16, windowSize: size)) {
            result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        }
        if let color = Self.color(hex: appearance.text) {
            result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
                if (value as? NSColor) == NSColor.labelColor {
                    result.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }
        let length: Int = result.length
        let background: Bool = model.option(\.highlightBackground)
        for range in model.transmittedRanges where range.lowerBound >= 0 && range.upperBound <= length {
            result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                range: NSRange(location: range.lowerBound, length: range.count))
        }
        for span in model.spans where span.start >= 0 && span.end <= length && span.start < span.end {
            guard case .call(let call) = span.kind, !span.transmitted else { continue }
            let mark: DigitalInterfaceModel.CallMark = model.mark(for: call)
            let range = NSRange(location: span.start, length: span.end - span.start)
            let color: NSColor = SpotColors.color(mark.color)
            if background {
                result.addAttributes([.backgroundColor: color.withAlphaComponent(0.35)], range: range)
                if mark.unverified {
                    result.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: range)
                }
            } else {
                result.addAttribute(.foregroundColor, value: color, range: range)
                if mark.unverified {
                    result.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.45),
                                        range: range)
                }
            }
        }
        if model.option(\.nonScrollingRx), length > 0 {
            let units: [UInt16] = Array(text.utf16)
            let lastNewline: Int = units.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
            if lastNewline < length {
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                    range: NSRange(location: lastNewline, length: length - lastNewline))
            }
        }
        return result
    }

    /// `#RRGGBB` → a colour, `nil` for an empty or invalid text.
    static func color(hex: String) -> NSColor? {
        var text: String = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// The text in the window's monospaced body size with the calls (primary) and exchange words (tertiary)
    /// underlined (`buildAnnotatedString`).
    static func annotated(_ text: String, spans: [DigitalInterfaceModel.Span], size: Int) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: WindowFont.size(16, windowSize: size), weight: .regular)
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor,
        ])
        let length: Int = result.length
        for span in spans where span.start >= 0 && span.end <= length && span.start < span.end {
            let color: NSColor
            switch span.kind {
            case .call:
                color = DomainColors.primary
            case .exchange:
                color = DomainColors.tertiary
            }
            result.addAttributes([.foregroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue],
                                 range: NSRange(location: span.start, length: span.end - span.start))
        }
        return result
    }
}

/// The TX window's text and whether it has the keyboard (the window's key monitor leaves Enter to it then).
@MainActor
final class TxFieldState: ObservableObject {
    @Published var text: String = ""
    var focused: Bool = false
}
