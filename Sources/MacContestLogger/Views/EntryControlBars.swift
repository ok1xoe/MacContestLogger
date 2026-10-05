import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The row under the suggestions (`EP:1252-1325`): the CAT LED of the window's rig (`catFor(vfo).connected`) and the
/// second LED (always off, as in Kotlin), Run/S&P, the band's CQ frequency, the info strip items, „ruční Run/S&P"
/// when the automatic switch is off, ESM and, in CW, the CW speed spinner.
struct InfoStripView: View {
    let app: AppModel
    let panel: EntryPanel

    /// The first LED is the rig connection: role button like the TRX icon, the state as the value.
    private var rigLedDescription: (label: String, value: String) {
        let language: LanguageModel = app.language
        let snapshot = app.rig.snapshot(vfo: panel.vfo)
        let state: AccessibilityText.RigLedState = AccessibilityText.rigLedState(
            connected: snapshot.connected, connecting: snapshot.connecting)
        return (language.tr("TRX"), AccessibilityText.rigLedValue(state, translator: language.translator))
    }

    var body: some View {
        let operating: OperatingModel = app.operating
        HStack(alignment: .center, spacing: 6) {
            LedView(on: app.rig.connected(vfo: panel.vfo), description: rigLedDescription)
            // Kotlin's second LED is a fixed-off placeholder without a meaning: nothing to announce.
            LedView(on: false, description: nil)
            RunModePicker(app: app, panel: panel)
                .padding(.leading, 6)
            if let cq = operating.cqFrequency(band: panel.entry.band) {
                Text(verbatim: " CQ " + EntryFormat.oneDecimal(Double(cq) / 1000.0))
                    .windowFont(11, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            InfoStripText(app: app, panel: panel)
            if !operating.autoRunSwitch {
                Text(verbatim: app.language.tr("ruční Run/S&P"))
                    .windowFont(11)
                    .foregroundStyle(Color(domain: DomainColors.dupe))
                    .lineLimit(1)
            }
            Toggle(isOn: Binding(get: { operating.esmEnabled }, set: { operating.setEsm($0) })) {
                Text(verbatim: "ESM")
                    .windowFont(13, weight: .medium)
            }
            .toggleStyle(.checkbox)
            .padding(.leading, 8)
            if panel.entry.form.mode == .cw {
                CwSpeedSpinner(keyer: app.keyer)
                    .padding(.leading, 8)
            }
        }
    }
}

/// The info strip items (TOUR, county line / rover, bonus stations, RPT, post-contest entry); the text must not widen
/// the window (its size follows the content), so it takes no ideal width of its own.
private struct InfoStripText: View {
    let app: AppModel
    let panel: EntryPanel

    var body: some View {
        // The text depends on the clock (TOUR, the SKED that starts within ten minutes) and nothing else changes when
        // it is due: it is read again every second, as the Info window's tick does (a one-second timeline).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let text: String = app.infoStrip.text
            if !text.isEmpty {
                Text(verbatim: text)
                    .accessibilityLabel(Text(verbatim: AccessibilityText.infoStrip(
                        text, translator: app.language.translator)))
                    .windowFont(11)
                    .foregroundStyle(Color(domain: DomainColors.tertiary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// Kotlin `Led`: a 12 pt dot, `CAT_CONNECTED` green when on. Kotlin draws it without a description; here the
/// accessibility value carries the state.
private struct LedView: View {
    let on: Bool
    /// The spoken label and state; `nil` = a decoration that is hidden from VoiceOver.
    let description: (label: String, value: String)?

    var body: some View {
        let dot = Circle()
            .fill(Color(domain: on ? DomainColors.catConnected : DomainColors.ledOff))
            .frame(width: 12, height: 12)
        if let description {
            dot.accessibilityElement()
                .accessibilityLabel(Text(verbatim: description.label))
                .accessibilityValue(Text(verbatim: description.value))
        } else {
            dot.accessibilityHidden(true)
        }
    }
}

/// Run / S&P radio buttons (`state.selectRunMode(mode, parseFreqHz(freqKHz))`).
private struct RunModePicker: View {
    let app: AppModel
    let panel: EntryPanel

    var body: some View {
        let operating: OperatingModel = app.operating
        let entry: EntryModel = panel.entry
        Picker(selection: Binding(get: { operating.runMode },
                                  set: { operating.select($0, freqHz: entry.form.freqHz) })) {
            Text(verbatim: "Run").tag(RunMode.run)
            Text(verbatim: "S&P").tag(RunMode.searchAndPounce)
        } label: {
            EmptyView()
        }
        .pickerStyle(.radioGroup)
        .horizontalRadioGroupLayout()
        .labelsHidden()
        .fixedSize()
    }
}

/// Kotlin's F1–F12 grid (`EP:1327-1350`): the set of the mode (CW, digital, voice) and of Run/S&P, the opposite set
/// while Shift is held; the message being sent (voice or CW) is highlighted, the one being recorded has „● " and is
/// highlighted; the keys the next ESM Enter sends have the strong border. Enabled in a mode that has messages.
struct FunctionKeyBar: View {
    let app: AppModel
    let panel: EntryPanel

    var body: some View {
        let entry: EntryModel = panel.entry
        let next: Set<Int> = Set(entry.esmStep?.keys ?? [])
        let enabled: Bool = entry.canTransmit
        let voice: VoiceKeyerModel = app.keyer.voice
        let cwKey: Int? = app.keyer.cwSendingKey
        VStack(alignment: .leading, spacing: 4) {
            ForEach([0, 6], id: \.self) { first in
                HStack(spacing: 4) {
                    ForEach(first..<(first + 6), id: \.self) { index in
                        let recording: Bool = voice.recordingKey == index
                        let lit: Bool = voice.playingKey == index || cwKey == index || recording
                        NkButton(label: FunctionKeyRouter.buttonText(index: index,
                                                                     label: entry.functionKeyLabel(index),
                                                                     recording: recording),
                                 highlighted: lit, next: next.contains(index), enabled: enabled) {
                            entry.handle(.functionKey(index, shift: false, ctrlShift: false))
                        }
                    }
                }
            }
        }
    }
}

/// The action bar (`EP:1352-1375`, labels verbatim): Esc: Stop, Wipe, Log It, Mark, Store and Spot It act; Edit has no action in Kotlin either (disabled). The last button looks the typed call up on the preferred online callbook (HamQTH or QRZ.com). „Log It" is
/// highlighted, with the strong border when ESM logs on the next Enter.
struct EntryActionBar: View {
    let app: AppModel
    let panel: EntryPanel
    let focus: EntryFocusController

    private static let labels: [String] = ["Esc: Stop", "Wipe", "Log It", "Edit", "Mark", "Store", "Spot It"]

    var body: some View {
        let logNext: Bool = panel.entry.esmStep?.log == true
        HStack(spacing: 4) {
            ForEach(Self.labels, id: \.self) { label in
                let action: (@MainActor () -> Void)? = self.action(label)
                NkButton(label: label, highlighted: label == "Log It", next: label == "Log It" && logNext,
                         enabled: action != nil) {
                    action?()
                }
            }
            lookupButton
        }
    }

    /// The manual callbook lookup: labelled by the preferred service, greyed without its credentials or a call.
    @ViewBuilder private var lookupButton: some View {
        let callbook: CallbookModel = app.callbook
        let service: CallbookService = callbook.preferredService
        let configured: Bool = callbook.isConfigured(service)
        let call: String = panel.suggestions.currentCall
        let hasCall: Bool = !CallbookPolicy.key(call).isEmpty
        let language: LanguageModel = app.language
        NkButton(label: service.displayName, highlighted: false, next: false, enabled: configured && hasCall,
                 help: lookupHelp(service: service, configured: configured, hasCall: hasCall, language: language)) {
            let suggestions: SuggestionsModel = panel.suggestions
            callbook.lookupNow(call, service: service, typedCall: { suggestions.currentCall })
        }
        .accessibilityIdentifier("entry.callbookLookup")
    }

    private func lookupHelp(service: CallbookService, configured: Bool, hasCall: Bool,
                            language: LanguageModel) -> String {
        if !configured {
            return language.tr("Nejsou vyplněné přihlašovací údaje %s (Nastavení → Online callbooky).",
                               .string(service.displayName))
        }
        if !hasCall {
            return language.tr("Nejdřív zadej volačku.")
        }
        return language.tr("Dohledat volačku na %s.", .string(service.displayName))
    }

    private func action(_ label: String) -> (@MainActor () -> Void)? {
        let entry: EntryModel = panel.entry
        switch label {
        case "Esc: Stop":
            return {
                entry.handle(.escape(.stopSending))
                focus.focus(.call)
            }
        case "Wipe":
            return { entry.wipe() }
        case "Log It":
            return { entry.submit() }
        case "Mark":
            return { entry.markButton() }
        case "Store":
            return { entry.storeCall() }
        case "Spot It":
            return { entry.spotIt() }
        default:
            return nil
        }
    }
}

/// Kotlin `NkButton` with `Modifier.weight(1f)`: the buttons of a row share the column's width equally (a small
/// ideal width, so the bars never widen the window; the labels are truncated). Highlighted = tertiary container,
/// `next` = a 2 pt primary border.
private struct NkButton: View {
    let label: String
    let highlighted: Bool
    let next: Bool
    let enabled: Bool
    var help: String?
    let action: @MainActor () -> Void

    /// The ideal width at the default font: the row's share comes from the column, not from this.
    private static let idealWidth: Double = 48
    @Environment(\.windowFontSize) private var size

    var body: some View {
        let strong: Bool = next && enabled
        Button(action: action) {
            Text(verbatim: label)
                .windowFont(11, design: .monospaced)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
                .frame(minWidth: 0, idealWidth: WindowFont.size(Self.idealWidth, windowSize: size),
                       maxWidth: .infinity)
                .frame(height: WindowFont.size(26, windowSize: size))
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: 3).fill(background))
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(strong ? Color(domain: DomainColors.primary) : Color.secondary.opacity(enabled ? 0.5 : 0.25),
                            lineWidth: strong ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: label))
        .help(help ?? "")
    }

    private var background: Color {
        if !enabled {
            return Color(nsColor: .quaternaryLabelColor).opacity(0.4)
        }
        return highlighted ? Color(domain: DomainColors.tertiaryContainer.background)
            : Color(nsColor: .quaternaryLabelColor)
    }

    private var foreground: Color {
        if !enabled {
            return Color.secondary.opacity(0.4)
        }
        return highlighted ? Color(domain: DomainColors.tertiaryContainer.text) : Color.primary
    }
}
