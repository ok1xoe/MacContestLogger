import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `NumberSpinner(value = state.cwSpeed, onChange = { state.updateCwSpeed(it) })` (`EP:1314-1321`,
/// `EP:1944-1987`): the speed and ▲/▼, 76 pt wide, shown in CW only. `updateCwSpeed` clamps to 5…60 WPM and
/// reaches an open keyer; the speed is saved with the configuration later. The accessibility element is an
/// adjustable value, so VoiceOver can step it like the arrows.
struct CwSpeedSpinner: View {
    let keyer: KeyerModel
    @Environment(\.windowFontSize) private var size

    var body: some View {
        let value: Int = keyer.cwSpeed
        HStack(spacing: 0) {
            Text(verbatim: String(value))
                .windowFont(13, design: .monospaced)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                arrow("▲", label: "CW WPM +") { keyer.updateCwSpeed(value + 1) }
                arrow("▼", label: "CW WPM −") { keyer.updateCwSpeed(value - 1) }
            }
        }
        .frame(width: WindowFont.size(76, windowSize: size), height: WindowFont.size(30, windowSize: size))
        .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "CW WPM"))
        .accessibilityValue(Text(verbatim: String(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                keyer.updateCwSpeed(keyer.cwSpeed + 1)
            case .decrement:
                keyer.updateCwSpeed(keyer.cwSpeed - 1)
            @unknown default:
                break
            }
        }
    }

    /// Kotlin `SpinnerArrow`: 18×15 pt, a 9 pt glyph.
    private func arrow(_ glyph: String, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}
