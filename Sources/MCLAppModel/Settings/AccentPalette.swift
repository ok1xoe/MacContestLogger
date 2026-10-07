import Foundation

/// The colours that follow the chosen accent (Settings → Other): the callsign/primary colour, the secondary
/// colour and the container of the frequency strip, the info bar and the score bar with its text. Plain sRGB
/// values (`0xRRGGBB`) per accent and appearance; the app layer turns them into colours.
public struct AccentPalette: Equatable, Sendable {

    /// A colour with a light and a dark variant.
    public struct Pair: Equatable, Sendable {
        public let light: Int
        public let dark: Int

        public func value(dark isDark: Bool) -> Int {
            isDark ? dark : light
        }
    }

    /// Callsigns to act on, active highlights (Kotlin `primary`).
    public let primary: Pair
    /// Secondary suggestions (Kotlin `secondary`).
    public let secondary: Pair
    /// Background of the frequency strip, the info bar and the score bar (Kotlin `primaryContainer`).
    public let strip: Pair
    /// Text on the strip (Kotlin `onPrimaryContainer`).
    public let onStrip: Pair

    public static func palette(for accent: AppearanceModel.Accent) -> AccentPalette {
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

    public static let teal = AccentPalette(
        primary: Pair(light: 0x00696B, dark: 0x4CD9DB), secondary: Pair(light: 0x4A6363, dark: 0xB0CCCC),
        strip: Pair(light: 0xD7ECEA, dark: 0x1F3B39), onStrip: Pair(light: 0x0B2E2B, dark: 0xCDEBE7))
    public static let blue = AccentPalette(
        primary: Pair(light: 0x1565C0, dark: 0x9ECAFF), secondary: Pair(light: 0x535F70, dark: 0xBBC7DB),
        strip: Pair(light: 0xD6E3FF, dark: 0x1B3A5E), onStrip: Pair(light: 0x001B3E, dark: 0xD6E3FF))
    public static let orange = AccentPalette(
        primary: Pair(light: 0xB85400, dark: 0xFFB68B), secondary: Pair(light: 0x77574A, dark: 0xE7BEAB),
        strip: Pair(light: 0xFFDCC6, dark: 0x4E2A10), onStrip: Pair(light: 0x2D1600, dark: 0xFFDCC6))
    /// High contrast is dark whatever the mode, so both variants are the same.
    public static let contrast = AccentPalette(
        primary: Pair(light: 0xFFEB3B, dark: 0xFFEB3B), secondary: Pair(light: 0xFFF176, dark: 0xFFF176),
        strip: Pair(light: 0x332E00, dark: 0x332E00), onStrip: Pair(light: 0xFFF59D, dark: 0xFFF59D))
}
