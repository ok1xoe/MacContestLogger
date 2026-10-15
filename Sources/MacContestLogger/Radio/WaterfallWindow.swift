import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `WaterfallWindow` (`waterfall` 760×380, `WaterfallWindow.kt:48-116`) grown into N1MM+'s Spectrum Display:
/// the info line (the audio error, the frequency under the pointer, or the mode and CW pitch) and the stats box above
/// the spectrum pane and the waterfall of the receiver audio 0–3 kHz. A press tunes the rig to the frequency under
/// the pointer (in the spectrum snapped to the nearest signal), Cmd+press sets the split transmit frequency, the
/// wheel moves the levels over the spectrum and tunes over the waterfall, `−` / `+` zoom. The window holds the
/// receiver audio while it is open.
struct WaterfallWindowView: View {
    static let id = "waterfall"

    let host: AppHost

    @StateObject private var session = WindowSession(id: WaterfallWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 760, height: 380))
    @StateObject private var holder = WindowModelHolder<WaterfallModel>()
    @State private var showingOptions = false

    var body: some View {
        Group {
            if let app = host.model {
                let model: WaterfallModel = holder.model { app.makeWaterfall() }
                content(app, model)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Vodopád",
                                                binder: session.binder))
                    .task { await model.open() }
                    .onDisappear { model.close() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }

    private func content(_ app: AppModel, _ model: WaterfallModel) -> some View {
        let language: LanguageModel = app.language
        let info: (text: EntryStatus, isError: Bool) = model.infoLine
        let infoText: String = info.text.text(language.translator, decimalSeparator: language.decimalSeparator)
        return VStack(alignment: .leading, spacing: 6) {
            WindowTopBar(size: $session.fontSize, language: language)
            HStack(spacing: 8) {
                Text(verbatim: infoText)
                    .windowFont(12)
                    .foregroundStyle(info.isError ? AnyShapeStyle(Color(domain: DomainColors.dupe))
                                                  : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let stats = model.statsLine {
                    Text(verbatim: stats.text(language.translator, decimalSeparator: language.decimalSeparator))
                        .windowFont(11, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                IconButton(symbol: "minus.magnifyingglass", label: language.tr("Oddálit spektrum")) {
                    model.zoom(by: -1)
                }
                .disabled(model.zoom <= 1)
                Text(verbatim: "×" + String(model.zoom))
                    .windowFont(11, design: .monospaced)
                    .accessibilityLabel(Text(verbatim: language.tr("Zvětšení") + " " + String(model.zoom)))
                IconButton(symbol: "plus.magnifyingglass", label: language.tr("Přiblížit spektrum")) {
                    model.zoom(by: 1)
                }
                .disabled(model.zoom >= (SpectrumZoom.levels.last ?? 1))
                IconButton(symbol: "slider.horizontal.3", label: language.tr("Volby spektra")) {
                    showingOptions = true
                }
            }
            panes(model, language: language, infoText: infoText)
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
        .sheet(isPresented: $showingOptions) {
            SpectrumOptionsSheet(model: model, language: language) { showingOptions = false }
        }
    }

    private func lines(_ model: WaterfallModel) -> [SpectrumLine] {
        var lines: [SpectrumLine] = []
        if let rx = model.pitchLine {
            lines.append(SpectrumLine(fraction: rx, color: DomainColors.pitchLine))
        }
        if let tx = model.txLine {
            lines.append(SpectrumLine(fraction: tx, color: .systemRed))
        }
        return lines
    }

    private func panes(_ model: WaterfallModel, language: LanguageModel, infoText: String) -> some View {
        let setup: SpectrumSetup = model.setup
        let axis = SpectrumAxisLayout(vertical: !model.isHorizontal, binZeroAtBottom: !setup.flag(.reverseScale))
        let lines: [SpectrumLine] = lines(model)
        let share: CGFloat = setup.flag(.showWaterfall) ? CGFloat(setup.sizeFactor) / 100 : 1
        let spectrum = ZStack {
            SpectrumPaneView(picture: model.picture, setup: setup, axis: axis, lines: lines)
            SpectrumPointerArea(
                axis: axis,
                onHover: { model.hover(fraction: $0) },
                onExit: { model.hoverEnded() },
                onPress: { fraction, flags in
                    model.press(fraction: fraction, command: flags.contains(.command), inSpectrum: true)
                },
                onWheel: { steps, flags in
                    let target: SpectrumScale.WheelTarget = flags.contains(.command)
                        ? (flags.contains(.shift) ? .range : .reference) : .threshold
                    model.wheelLevels(steps, target: target)
                },
                accessibilityText: language.tr("Spektrum"),
                accessibilityValueText: infoText)
        }
        let waterfall = WaterfallLayerView(
            image: model.image,
            lines: lines,
            axis: axis,
            onHover: { model.hover(fraction: $0) },
            onExit: { model.hoverEnded() },
            onPress: { fraction, flags in
                model.press(fraction: fraction, command: flags.contains(.command), inSpectrum: false)
            },
            onWheel: { steps, flags in
                model.wheelTune(steps, large: flags.contains(.shift) || flags.contains(.command))
            },
            accessibilityText: language.tr("Vodopád"),
            accessibilityValueText: infoText)
        return GeometryReader { geometry in
            let size: CGSize = geometry.size
            Group {
                if !setup.flag(.showWaterfall) {
                    spectrum
                } else if axis.vertical {
                    HStack(spacing: 2) {
                        waterfall.frame(width: Swift.max(0, size.width * (1 - share) - 2))
                        spectrum
                    }
                } else {
                    VStack(spacing: 2) {
                        spectrum.frame(height: Swift.max(0, size.height * share - 2))
                        waterfall
                    }
                }
            }
            .onAppear { model.layout(width: size.width, height: size.height) }
            .onChange(of: size) { _, new in model.layout(width: new.width, height: new.height) }
            .onChange(of: setup.orientation) { _, _ in model.layout(width: size.width, height: size.height) }
        }
    }
}
