import AppKit
import MCLAppModel
import SwiftUI

/// The look from Settings → Other (Kotlin `colorSchemeFor`; `Theme.kt:85-112`), applied to
/// every root scene: `NSApp.appearance` follows the mode (system = `nil`, light = aqua, dark = dark aqua; high
/// contrast forces dark), the accent becomes the scene's `.tint` (Kotlin's `primary` of the light and the dark
/// scheme), and high contrast paints the window black with the yellow accent.
struct AppearanceApplier: ViewModifier {
    let host: AppHost

    func body(content: Content) -> some View {
        let model: AppearanceModel? = host.model?.appearance
        let accent: AppearanceModel.Accent = model?.accent ?? .teal
        let mode: AppearanceModel.Appearance = model?.effectiveAppearance ?? .system
        content
            .tint(Color(nsColor: AppearanceColors.accent(accent)))
            .background(model?.isContrast == true ? Color.black : Color.clear)
            .onAppear { AppearanceColors.apply(mode) }
            .onChange(of: mode) { AppearanceColors.apply(mode) }
    }
}

/// The colours and the application appearance of `AppearanceModel`.
@MainActor
enum AppearanceColors {

    /// `NSApp.appearance` for a mode (a change re-renders every window).
    static func apply(_ mode: AppearanceModel.Appearance) {
        let wanted: NSAppearance?
        switch mode {
        case .system:
            wanted = nil
        case .light:
            wanted = NSAppearance(named: .aqua)
        case .dark:
            wanted = NSAppearance(named: .darkAqua)
        }
        guard NSApp.appearance?.name != wanted?.name else { return }
        NSApp.appearance = wanted
    }

    /// Kotlin's `primary` per accent: teal `#0E8A7D` / `#53DBC9`, blue `#1565C0` / `#9ECAFF`, orange `#B85400` /
    /// `#FFB68B`, high contrast `#FFEB3B` (always dark).
    static func accent(_ accent: AppearanceModel.Accent) -> NSColor {
        switch accent {
        case .teal:
            return teal
        case .blue:
            return blue
        case .orange:
            return orange
        case .contrast:
            return contrast
        }
    }

    private static let teal: NSColor = DomainColors.dynamic("mcl.accent.teal", light: rgb(0x0E8A7D), dark: rgb(0x53DBC9))
    private static let blue: NSColor = DomainColors.dynamic("mcl.accent.blue", light: rgb(0x1565C0), dark: rgb(0x9ECAFF))
    private static let orange: NSColor = DomainColors.dynamic("mcl.accent.orange", light: rgb(0xB85400),
                                                              dark: rgb(0xFFB68B))
    private static let contrast: NSColor = rgb(0xFFEB3B)

    private static func rgb(_ hex: Int) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
