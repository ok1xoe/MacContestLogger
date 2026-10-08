import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The header of an entry window with two entry windows (SO2V/SO2R, `EP:1045-1051`): `tr("Rig %s")` in SO2R,
/// otherwise „VFO A"/„VFO B", then „ — " and `tr("aktivní (vysílá)")` in the primary colour or
/// `tr("klikni do okna pro přepnutí")` muted.
struct EntryWindowHeader: View {
    let app: AppModel
    let vfo: Int

    var body: some View {
        let rig: MCLAppModel.RigModel = app.rig
        if rig.vfo.twoEntryWindows {
            let active: Bool = rig.vfo.activeVfo == vfo
            Text(verbatim: Self.text(so2r: rig.vfo.so2r, vfo: vfo, active: active, language: app.language))
                .windowFont(12, weight: .medium)
                .foregroundStyle(active ? AnyShapeStyle(.mclPrimary) : AnyShapeStyle(Color.secondary))
        }
    }

    static func text(so2r: Bool, vfo: Int, active: Bool, language: LanguageModel) -> String {
        let name: String
        if so2r {
            name = language.tr("Rig %s", .int(vfo + 1))
        } else {
            name = vfo == 0 ? "VFO A" : "VFO B"
        }
        let state: String = active ? language.tr("aktivní (vysílá)") : language.tr("klikni do okna pro přepnutí")
        return name + " — " + state
    }
}

/// The frequency strip (Kotlin `InfoBar`, `EP:1052-1062, 1544-1690`): the editable frequency (sets the band without
/// CAT), `kHz`, SPLIT with the transmit frequency of the active rig (`state.cat.state`, in both windows as Kotlin),
/// the mode (a picker in a digital contest), „VFO A" (Kotlin writes it in the VFO B window too) and the TRX icon of
/// the window's rig.
struct FrequencyStripView: View {
    let app: AppModel
    let panel: EntryPanel
    let focus: EntryFocusController

    var body: some View {
        let entry: EntryModel = panel.entry
        let onStrip = AccentToken(kind: .onStrip)
        HStack(alignment: .center, spacing: 0) {
            WindowFontReader { size in
                EntryTextField(key: nil, text: entry.form.freqKHz, transform: .frequency,
                               fontSize: WindowFont.size(22, windowSize: size), bold: true, placeholder: "----.--",
                               accessibilityLabel: "kHz", onChange: { entry.setFrequency($0) })
                    .frame(width: 150 * Double(size) / Double(WindowFont.defaultSize),
                           height: WindowFont.size(34, windowSize: size))
            }
            Text(verbatim: "kHz")
                .windowFont(16, weight: .bold, design: .monospaced)
                .fixedSize()
                .padding(.leading, 4)
            SplitLabel(state: app.rig.activeState)
                .fixedSize()
            Spacer().frame(width: 12)
            ModeLabel(app: app, entry: entry)
                .fixedSize()
            StripHintsView(app: app, panel: panel, focus: focus)
            Spacer(minLength: 0)
            Text(verbatim: "VFO A")
                .windowFont(13, design: .monospaced)
                .fixedSize()
            TrxButton(app: app, vfo: panel.vfo)
                .fixedSize()
                .padding(.leading, 6)
        }
        .foregroundStyle(onStrip)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.mclStrip))
    }
}

/// „SPLIT" and, with a known transmit frequency, `" TX %.1f"` kHz (Kotlin `Locale.US`), in the error colour.
private struct SplitLabel: View {
    let state: RigState?

    var body: some View {
        if let state, state.split {
            Text(verbatim: Self.text(txFreqHz: state.txFreqHz))
                .windowFont(14, weight: .bold, design: .monospaced)
                .foregroundStyle(Color(domain: DomainColors.dupe))
                .padding(.leading, 10)
        }
    }

    static func text(txFreqHz: Int64) -> String {
        txFreqHz > 0 ? "SPLIT TX " + EntryFormat.oneDecimal(Double(txFreqHz) / 1000.0) : "SPLIT"
    }
}

/// The mode: a menu of the digital modes in a digital contest, otherwise its name.
private struct ModeLabel: View {
    let app: AppModel
    let entry: EntryModel

    var body: some View {
        if EntryGrid.digiPickable(app.contest, mode: entry.form.mode) {
            Menu {
                ForEach(EntryGrid.digiModes, id: \.self) { mode in
                    Button(mode.rawValue) { entry.setMode(mode) }
                }
            } label: {
                Text(verbatim: entry.form.mode.rawValue)
                    .windowFont(16, weight: .bold, design: .monospaced)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            Text(verbatim: entry.form.mode.rawValue)
                .windowFont(16, weight: .bold, design: .monospaced)
        }
    }
}

/// The hints of the entry window, in the strip between the mode and „VFO A": the DUPE and multiplier chips of the
/// contest preview first (Kotlin shows them in a row under the fields), then the worked-before strip, the callbook
/// line and the reverse call history lookup (Kotlin shows them in rows under the fields too; Check partial and N+1
/// stay under the call field on their own `SCP:` and `N+1:` rows),
/// a deliberate UI divergence from Java v1.1.1. At most two rows; the strip always reserves the height of two rows, so the window does not
/// change size while the hints come and go.
private struct StripHintsView: View {
    let app: AppModel
    let panel: EntryPanel
    let focus: EntryFocusController

    var body: some View {
        let language: LanguageModel = app.language
        WindowFontReader { size in
            ChipRowsLayout(rows: 2, rowHeight: WindowFont.size(20, windowSize: size),
                           maxIdealWidth: WindowFont.size(420, windowSize: size)) {
                if app.contest.isActive,
                   case .contest(let dupe, let chips) = EntryFeedback.of(entry: panel.entry, contest: app.contest) {
                    if dupe {
                        ChipView(text: "DUPE", background: DomainColors.dupe, foreground: .white)
                    }
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        let colors = DomainColors.chip(chip.state)
                        ChipView(text: chip.bindingId + ": " + language.tr(chip.stateKey),
                                 background: colors.background, foreground: colors.text)
                    }
                }
                WorkedBeforeStripView(app: app, panel: panel)
                CallbookLineView(app: app, panel: panel)
                ReverseLookupView(app: app, panel: panel, focus: focus)
            }
        }
        .padding(.leading, 12)
        .layoutPriority(1)
    }
}

/// Items left to right, wrapping into at most `rows` rows (an item that fits no row is not shown), always as tall as
/// `rows` rows of `rowHeight`; the rows are centred vertically in the strip.
struct ChipRowsLayout: Layout {
    let rows: Int
    let rowHeight: CGFloat
    let maxIdealWidth: CGFloat
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An unspecified or unbounded width (the ideal size of a `fixedSize` window) asks for about half of the items
        // per row, so many items do not stretch the window; a given width is filled.
        let width: CGFloat = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth(subviews: subviews)
        let arranged = arrange(width: width, subviews: subviews)
        return CGSize(width: arranged.width, height: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(width: bounds.width, subviews: subviews)
        let used: Int = (arranged.origins.compactMap { $0?.row }.max() ?? -1) + 1
        let usedHeight: CGFloat = CGFloat(used) * rowHeight + CGFloat(Swift.max(used - 1, 0)) * rowSpacing
        let top: CGFloat = bounds.minY + (bounds.height - usedHeight) / 2
        for (index, origin) in arranged.origins.enumerated() {
            guard let origin else {
                // No room: placed out of sight with no size (and out of the way of clicks).
                subviews[index].place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.minY), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: 0, height: 0))
                continue
            }
            let y: CGFloat = top + CGFloat(origin.row) * (rowHeight + rowSpacing)
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: y), anchor: .topLeading,
                                  proposal: .unspecified)
        }
    }

    private func idealWidth(subviews: Subviews) -> CGFloat {
        let widths: [CGFloat] = subviews.map { $0.sizeThatFits(.unspecified).width }.filter { $0 > 0 }
        let total: CGFloat = widths.reduce(0, +) + CGFloat(Swift.max(widths.count - 1, 0)) * spacing
        let half: CGFloat = rows <= 1 ? total : total / CGFloat(rows) + (widths.max() ?? 0)
        return Swift.min(half, Swift.max(maxIdealWidth, widths.max() ?? 0))
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (width: CGFloat, origins: [(x: CGFloat, row: Int)?]) {
        var origins: [(x: CGFloat, row: Int)?] = []
        var x: CGFloat = 0
        var row = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size: CGSize = subview.sizeThatFits(.unspecified)
            if size.width <= 0 {
                origins.append((0, row))
                continue
            }
            if x > 0 && x + size.width > width {
                row += 1
                x = 0
            }
            if row >= rows {
                origins.append(nil)
                continue
            }
            origins.append((x, row))
            x += size.width + spacing
            widest = Swift.max(widest, x - spacing)
        }
        return (width > 0 ? Swift.min(widest, width) : widest, origins)
    }
}
