import AppKit
import MCLCore
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
    /// Strip background of the frequency bar and the score bar (Kotlin `primaryContainer`).
    static let strip: NSColor = dynamic("mcl.strip", light: rgb(0xD7ECEA), dark: rgb(0x1F3B39))
    /// Text on the strip (Kotlin `onPrimaryContainer`).
    static let onStrip: NSColor = dynamic("mcl.onStrip", light: rgb(0x0B2E2B), dark: rgb(0xCDEBE7))

    /// Callsigns to act on (Kotlin `colorScheme.primary`: SCP suggestions, the reverse lookup, the next ESM key).
    static let primary: NSColor = dynamic("mcl.primary", light: rgb(0x00696B), dark: rgb(0x4CD9DB))
    /// N+1 calls not in the log (Kotlin `colorScheme.secondary`).
    static let secondary: NSColor = dynamic("mcl.secondary", light: rgb(0x4A6363), dark: rgb(0xB0CCCC))
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
