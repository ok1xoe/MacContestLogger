import AppKit
import MCLAppModel
import MCLCore
import os
import SwiftUI

/// Domain colour tokens with a light and a dark variant: the meaning of a colour (dupe, multiplier,
/// multiplier state) stays, the Material 3 palette of the JVM version does not.
enum DomainColors {

    /// A dynamic colour: `light` in the aqua appearance, `dark` in dark aqua.
    static func dynamic(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func rgb(_ hex: Int) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// Dupe: red (Kotlin `colorScheme.error`).
    static let dupe: NSColor = dynamic("mcl.dupe", light: rgb(0xC62828), dark: rgb(0xFF6B6B))
    /// Multiplier: amber (Kotlin `colorScheme.tertiary`).
    static let multiplier: NSColor = dynamic("mcl.multiplier", light: rgb(0x9A6200), dark: rgb(0xFFC046))
    /// The accent the AppKit colours below resolve against (set by `AppearanceApplier`; SwiftUI reads the
    /// environment instead, see `AccentToken`).
    private static let currentAccent = OSAllocatedUnfairLock<AppearanceModel.Accent>(initialState: .teal)

    static var accent: AppearanceModel.Accent {
        get { currentAccent.withLock { $0 } }
        set { currentAccent.withLock { $0 = newValue } }
    }

    /// A colour of the accent palette that re-resolves on every draw against the current accent.
    private static func accentColor(_ name: String, _ pick: @escaping @Sendable (AccentPalette) -> AccentPalette.Pair)
        -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let dark: Bool = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(pick(AccentPalette.palette(for: accent)).value(dark: dark))
        }
    }

    /// Strip background of the frequency bar, the info bar and the score bar (Kotlin `primaryContainer`).
    static let strip: NSColor = accentColor("mcl.strip") { $0.strip }
    /// Text on the strip (Kotlin `onPrimaryContainer`).
    static let onStrip: NSColor = accentColor("mcl.onStrip") { $0.onStrip }

    /// Callsigns to act on (Kotlin `colorScheme.primary`: SCP suggestions, the reverse lookup, the next ESM key).
    static let primary: NSColor = accentColor("mcl.primary") { $0.primary }
    /// N+1 calls not in the log (Kotlin `colorScheme.secondary`).
    static let secondary: NSColor = accentColor("mcl.secondary") { $0.secondary }
    /// Spotted suggestions and the info strip items (Kotlin `colorScheme.tertiary`, the multiplier amber).
    static var tertiary: NSColor { multiplier }
    /// Kotlin `tertiaryContainer` / `onTertiaryContainer`: a worked band, a highlighted F-key.
    static var tertiaryContainer: (background: NSColor, text: NSColor) { chip(.unknownAccepted) }
    /// Kotlin `errorContainer` / `onErrorContainer`: the current band already worked (a dupe).
    static var errorContainer: (background: NSColor, text: NSColor) { chip(.invalidFormat) }
    /// An LED that is off (Kotlin `outline` at 40 %).
    static let ledOff: NSColor = dynamic("mcl.ledOff", light: rgb(0xB8C4C3), dark: rgb(0x46504F))
    /// A connected rig: the CAT LED and the TRX icon (Kotlin `CAT_CONNECTED` 0xFF2E7D32; lighter in dark aqua).
    static let catConnected: NSColor = dynamic("mcl.catConnected", light: rgb(0x2E7D32), dark: rgb(0x66BB6A))

    /// The waterfall's CW pitch line (Kotlin `Color(0xFFFFC107)` over the black waterfall in both appearances).
    static let pitchLine: NSColor = rgb(0xFFC107)

    /// Background and text of a multiplier chip by state (Kotlin `stateColors`).
    static func chip(_ state: MultiplierEvalResult.MultiplierState) -> (background: NSColor, text: NSColor) {
        switch state {
        case .knownNewMultiplier:
            return (strip, onStrip)
        case .knownAlreadyWorked:
            return (NSColor.quaternaryLabelColor, NSColor.secondaryLabelColor)
        case .unknownAccepted, .suspicious:
            return (dynamic("mcl.chip.warn", light: rgb(0xFFE3B0), dark: rgb(0x5A4100)),
                    dynamic("mcl.chip.onWarn", light: rgb(0x3D2800), dark: rgb(0xFFDEA6)))
        case .invalidFormat:
            return (dynamic("mcl.chip.error", light: rgb(0xFFDAD6), dark: rgb(0x8C1D18)),
                    dynamic("mcl.chip.onError", light: rgb(0x410002), dark: rgb(0xFFDAD6)))
        }
    }
}

extension Color {
    init(domain color: NSColor) {
        self.init(nsColor: color)
    }
}

// MARK: - SwiftUI: tokens that follow the accent live

private struct AccentKey: EnvironmentKey {
    static let defaultValue: AppearanceModel.Accent = .teal
}

extension EnvironmentValues {
    /// The chosen accent, set on every scene by `AppearanceApplier`.
    var mclAccent: AppearanceModel.Accent {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

/// A colour of the accent palette as a shape style: resolved from the environment (accent and light/dark), so a
/// change of the accent in Settings repaints the bars at once instead of keeping the colour from the first draw.
struct AccentToken: ShapeStyle {
    enum Kind: Sendable {
        case primary, secondary, strip, onStrip
    }

    let kind: Kind

    func resolve(in environment: EnvironmentValues) -> Color {
        Self.color(kind, accent: environment.mclAccent, dark: environment.colorScheme == .dark)
    }

    /// The colour for a drawing context (a `Canvas`) that has no view environment of its own.
    static func color(_ kind: Kind, in environment: EnvironmentValues) -> Color {
        color(kind, accent: environment.mclAccent, dark: environment.colorScheme == .dark)
    }

    static func color(_ kind: Kind, accent: AppearanceModel.Accent, dark: Bool) -> Color {
        let palette: AccentPalette = AccentPalette.palette(for: accent)
        let pair: AccentPalette.Pair
        switch kind {
        case .primary: pair = palette.primary
        case .secondary: pair = palette.secondary
        case .strip: pair = palette.strip
        case .onStrip: pair = palette.onStrip
        }
        let hex: Int = pair.value(dark: dark)
        return Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                     blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension ShapeStyle where Self == AccentToken {
    static var mclPrimary: AccentToken { AccentToken(kind: .primary) }
    static var mclStrip: AccentToken { AccentToken(kind: .strip) }
    static var mclOnStrip: AccentToken { AccentToken(kind: .onStrip) }
}
