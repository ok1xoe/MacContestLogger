import Foundation
import MCLCore
import Observation

/// The look from Settings → Other (Kotlin `App.kt:146-153` and `ThemePrefs`/
/// `colorSchemeFor`, `Theme.kt:85-112`): derived from `config.themeMode` and `config.themeAccent`, so a commit or a
/// profile load changes it at once (Kotlin reads both in the composition after `configRevision`). Only values — the
/// app layer maps them to `NSApp.appearance` and the scenes' tint.
@Observable @MainActor
public final class AppearanceModel {

    /// `config.themeMode`: `LIGHT`, `DARK`, anything else follows the system (Kotlin `else -> systemDark`).
    public enum Appearance: Equatable, Sendable {
        case system
        case light
        case dark
    }

    /// `config.themeAccent`: `BLUE`, `ORANGE`, `CONTRAST`; anything else is the default teal (Kotlin `else -> base`).
    public enum Accent: Equatable, Sendable {
        case teal
        case blue
        case orange
        case contrast
    }

    @ObservationIgnored private let config: ConfigModel

    init(config: ConfigModel) {
        self.config = config
    }

    /// The configured mode.
    public var appearance: Appearance {
        switch config.config.themeMode {
        case "LIGHT":
            return .light
        case "DARK":
            return .dark
        default:
            return .system
        }
    }

    public var accent: Accent {
        switch config.config.themeAccent {
        case "BLUE":
            return .blue
        case "ORANGE":
            return .orange
        case "CONTRAST":
            return .contrast
        default:
            return .teal
        }
    }

    /// High contrast: dark whatever the mode, black background, yellow accent (Kotlin
    /// `colorSchemeFor(useDark || accent == "CONTRAST", accent)`).
    public var isContrast: Bool {
        accent == .contrast
    }

    /// The appearance the windows get: high contrast forces the dark one.
    public var effectiveAppearance: Appearance {
        isContrast ? .dark : appearance
    }

    /// The colour overrides (`ColorSlot` raw value → `0xRRGGBB`), only valid ones.
    public var colorOverrides: [String: Int] {
        var out: [String: Int] = [:]
        for (key, value) in config.config.colorOverrides {
            if ColorSlot(rawValue: key) != nil, let rgb = ColorHex.parse(value) {
                out[key] = rgb
            }
        }
        return out
    }

    /// The family of the proportional texts (empty = the system font).
    public var fontFamily: String {
        config.config.fontFamily
    }

    /// The family of the monospaced texts and the entry fields (empty = the system monospaced font).
    public var fixedFontFamily: String {
        config.config.fixedFontFamily
    }

    /// N1MM „Tooltips": the spot tooltips are shown.
    public var spotTooltips: Bool {
        config.config.spotTooltips
    }
}
