import SwiftUI

/// The shared button whose face is a symbol only. The spoken label is a required parameter (callers pass `tr(…)`), and
/// it doubles as the tooltip, like the font stepper's buttons. The symbol itself is hidden from VoiceOver, so the
/// button reads as its label. The button style comes from the environment (`.buttonStyle(.plain)` / `.borderless`).
///
/// `scripts/a11y-audit.py` fails the build for a bare `Image(systemName:)` anywhere else without a label or a hiding.
struct IconButton: View {
    let symbol: String
    let label: String
    /// The fixed size of the face, `nil` = the symbol's own size.
    var size: CGSize?
    /// A thin outline around the face (the band map's square buttons).
    var outlined: Bool = false
    /// The symbol's font size, `nil` = the environment's.
    var symbolSize: CGFloat?
    var secondary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            face
        }
        .help(label)
        .accessibilityLabel(Text(verbatim: label))
    }

    @ViewBuilder
    private var symbolImage: some View {
        let base = Image(systemName: symbol)
            .font(symbolSize.map { Font.system(size: $0) })
            .accessibilityHidden(true)
        if secondary {
            base.foregroundStyle(.secondary)
        } else {
            base
        }
    }

    @ViewBuilder
    private var face: some View {
        let image = symbolImage
        if let size {
            if outlined {
                image.frame(width: size.width, height: size.height)
                    .overlay(Rectangle().stroke(Color.secondary, lineWidth: 1))
                    .contentShape(Rectangle())
            } else {
                image.frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
            }
        } else {
            image
        }
    }
}
