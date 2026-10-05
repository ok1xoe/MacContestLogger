import MCLAppModel
import SwiftUI

/// The window's font size (Kotlin `LocalWindowFontSp`): every text of the window derives its size from it.
private struct WindowFontSizeKey: EnvironmentKey {
    static let defaultValue: Int = WindowFont.defaultSize
}

extension EnvironmentValues {
    var windowFontSize: Int {
        get { self[WindowFontSizeKey.self] }
        set { self[WindowFontSizeKey.self] = newValue }
    }
}

/// `.font(.system(size: base + delta))` with the window's font size (project rule: one stepper per window, all
/// texts grow together; `dynamicTypeSize` does not apply on macOS).
private struct WindowFontModifier: ViewModifier {
    @Environment(\.windowFontSize) private var windowSize
    let base: Double
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: WindowFont.size(base, windowSize: windowSize), weight: weight, design: design))
    }
}

extension View {
    func windowFont(_ base: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(WindowFontModifier(base: base, weight: weight, design: design))
    }
}

/// The shared font-size stepper (Kotlin `FontStepper`): −, the size, +; bounds 8–28, not persisted.
struct WindowFontStepper: View {
    @Binding var size: Int
    let language: LanguageModel

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "minus", label: language.tr("Zmenšit písmo"), size: CGSize(width: 16, height: 16)) {
                size = WindowFont.clamp(size - 1)
            }
            Text(verbatim: String(size))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            IconButton(symbol: "plus", label: language.tr("Zvětšit písmo"), size: CGSize(width: 16, height: 16)) {
                size = WindowFont.clamp(size + 1)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: language.tr("Velikost písma")))
        .accessibilityValue(Text(verbatim: String(size)))
        .accessibilityIdentifier("windowFontStepper")
    }
}

/// The top row of a window (Kotlin `WindowTopBar`): optional content on the left, the stepper on the right.
struct WindowTopBar<Leading: View>: View {
    @Binding var size: Int
    let language: LanguageModel
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leading()
            Spacer(minLength: 0)
            WindowFontStepper(size: $size, language: language)
        }
    }
}

extension WindowTopBar where Leading == EmptyView {
    init(size: Binding<Int>, language: LanguageModel) {
        self.init(size: size, language: language) { EmptyView() }
    }
}
