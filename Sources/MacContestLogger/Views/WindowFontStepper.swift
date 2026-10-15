import AppKit
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

/// The font families of Settings › Fonts (N1MM Configurer › Fonts), set on every scene by `AppearanceApplier`;
/// empty = the system font.
private struct FontFamilyKey: EnvironmentKey {
    static let defaultValue: String = ""
}

private struct FixedFontFamilyKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    /// The family of the proportional texts.
    var mclFontFamily: String {
        get { self[FontFamilyKey.self] }
        set { self[FontFamilyKey.self] = newValue }
    }

    /// The family of the monospaced texts (and the entry fields).
    var mclFixedFontFamily: String {
        get { self[FixedFontFamilyKey.self] }
        set { self[FixedFontFamilyKey.self] = newValue }
    }
}

/// `.font(.system(size: base + delta))` with the window's font size (project rule: one stepper per window, all
/// texts grow together; `dynamicTypeSize` does not apply on macOS). A family chosen in Settings › Fonts replaces
/// the system font: the fixed one for `.monospaced`, the proportional one otherwise.
private struct WindowFontModifier: ViewModifier {
    @Environment(\.windowFontSize) private var windowSize
    @Environment(\.mclFontFamily) private var family
    @Environment(\.mclFixedFontFamily) private var fixedFamily
    let base: Double
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(WindowFont.font(size: WindowFont.size(base, windowSize: windowSize), weight: weight,
                                     design: design, family: design == .monospaced ? fixedFamily : family))
    }
}

extension WindowFont {
    /// The system font of the size, weight and design, or the family's font when one is chosen and installed.
    static func font(size: Double, weight: Font.Weight, design: Font.Design, family: String) -> Font {
        guard !family.isEmpty, NSFontManager.shared.availableMembers(ofFontFamily: family) != nil else {
            return .system(size: size, weight: weight, design: design)
        }
        return .custom(family, fixedSize: size).weight(weight)
    }

    /// The AppKit font of an entry field: the fixed family when one is chosen and installed, otherwise the system
    /// monospaced font.
    static func entryFont(size: Double, bold: Bool, family: String) -> NSFont {
        if !family.isEmpty,
           let font = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [],
                                                weight: bold ? 9 : 5, size: CGFloat(size)) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: bold ? .bold : .regular)
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
