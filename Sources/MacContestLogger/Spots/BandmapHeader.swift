import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// What the band map's header and top bar read and do (`BandmapModel`); a protocol so the layout can be measured
/// with plain values.
@MainActor
protocol BandmapBarSource: AnyObject {
    func radioName(_ language: LanguageModel) -> String
    var tunedText: String { get }
    var txText: String? { get }
    var spotFont: Int { get }
    func setSpotFont(_ size: Int)
    func zoomIn()
    func zoomOut()
    func resetView()
    func showDx()
    var filterIsNarrow: Bool? { get }
    func toggleFilterWidth()
    var canJumpToCq: Bool { get }
    func jumpToCq()
    var ritText: String { get }
    func clearRit()
    var modeText: String { get }
    func setMode(_ command: String)
    func editButtons(_ index: Int)
}

extension BandmapModel: BandmapBarSource {}

/// The widths the band map's top area needs, so the window never gets narrower than its header: the tuned frequency
/// (with the font stepper) is always shown whole, at every window font size.
enum BandmapLayout {
    /// The longest frequency text of the header (a microwave band: „10489750.00 kHz") and of the split TX line.
    static let longestFrequency = "10489750.00 kHz"
    static let longestTx = "TX 10489750.00 kHz"
    /// The window's own minimum at the default font (Kotlin `bandmap` 320 dp).
    static let baseMinWidth: CGFloat = 320
    /// The compact zoom buttons.
    static let zoomButton = CGSize(width: 20, height: 20)
    static let horizontalPadding: CGFloat = 8
    static let spacing: CGFloat = 6
    /// The font stepper (−, the size, +) with room to spare.
    static let stepperWidth: CGFloat = 64

    /// The width of `text` in the monospaced bold font of design size `base` at window font `fontSize`.
    static func monospacedWidth(_ text: String, base: Double, fontSize: Int) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(WindowFont.size(base, windowSize: fontSize)),
                                               weight: .bold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The narrowest window that shows the header's rows unclipped at window font `fontSize` (the compact layout:
    /// the frequency with the stepper; the TX line with the zoom buttons).
    static func minWidth(fontSize: Int) -> CGFloat {
        let frequencyRow: CGFloat = monospacedWidth(longestFrequency, base: 18, fontSize: fontSize)
            + spacing + stepperWidth
        let zoom: CGFloat = 3 * zoomButton.width + 2 * 4
        let txRow: CGFloat = monospacedWidth(longestTx, base: 13, fontSize: fontSize) + spacing + zoom + spacing + 24
        let needed: CGFloat = max(frequencyRow, txRow) + 2 * horizontalPadding
        return max(baseMinWidth, ceil(needed * 1.05))
    }
}

/// The band map's header: the radio (N1MM: the rig, its VFO), the tuned frequency, the transmit frequency while
/// split, the zoom buttons and the window's font stepper, which sizes the window and the spot labels together (the
/// spot font keeps its own value and 8…28 bounds and moves by the same step). On one row while it fits; otherwise
/// the frequency (which never shrinks) shares its row with the stepper and the rest goes to a second row, where the
/// radio's name gives way first.
struct BandmapHeader: View {
    let model: any BandmapBarSource
    let language: LanguageModel
    @Binding var fontSize: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: BandmapLayout.spacing) {
                radio.fixedSize()
                frequency
                tx
                Spacer(minLength: BandmapLayout.spacing)
                zoom
                stepper
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: BandmapLayout.spacing) {
                    frequency
                    Spacer(minLength: BandmapLayout.spacing)
                    stepper
                }
                HStack(alignment: .center, spacing: BandmapLayout.spacing) {
                    tx
                    radio
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                    Spacer(minLength: BandmapLayout.spacing)
                    zoom
                }
            }
        }
        .padding(.horizontal, BandmapLayout.horizontalPadding)
        .padding(.vertical, 6)
    }

    private var radio: some View {
        Text(verbatim: model.radioName(language))
            .windowFont(12, weight: .medium)
            .foregroundStyle(.secondary)
    }

    private var frequency: some View {
        Text(verbatim: model.tunedText)
            .windowFont(18, weight: .bold, design: .monospaced)
            .foregroundStyle(.mclPrimary)
            .fixedSize()
            .layoutPriority(1000)
    }

    @ViewBuilder
    private var tx: some View {
        if let tx = model.txText {
            Text(verbatim: tx)
                .windowFont(13, weight: .bold, design: .monospaced)
                .foregroundStyle(Color(nsColor: .systemRed))
                .fixedSize()
                .layoutPriority(999)
        }
    }

    private var zoom: some View {
        HStack(spacing: 4) {
            zoomButton("plus", language.tr("Přiblížit")) { model.zoomIn() }
            zoomButton("minus", language.tr("Oddálit")) { model.zoomOut() }
            zoomButton("arrow.clockwise", language.tr("Reset zobrazení")) { model.resetView() }
        }
        .fixedSize()
    }

    private var stepper: some View {
        WindowFontStepper(size: $fontSize, language: language, stepped: { step in
            model.setSpotFont(model.spotFont + step)
        })
        .fixedSize()
    }

    private func zoomButton(_ symbol: String, _ label: String,
                            action: @escaping @MainActor () -> Void) -> some View {
        IconButton(symbol: symbol, label: label, size: BandmapLayout.zoomButton, outlined: true, symbolSize: 10,
                   secondary: true, action: action)
            .buttonStyle(.plain)
    }
}
