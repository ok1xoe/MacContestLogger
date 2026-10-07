import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The look from Settings → Other (`App.kt:146-153`, `Theme.kt:94-112`).
@MainActor @Suite struct AppearanceModelTests {

    @Test func modeAndAccentFollowTheConfiguration() async throws {
        let app = try await TestApp.make()
        let config: ConfigModel = app.model.config
        let appearance: AppearanceModel = app.model.appearance
        #expect(appearance.appearance == .system)
        #expect(appearance.accent == .teal)

        let modes: [(String, AppearanceModel.Appearance)] = [
            ("LIGHT", .light), ("DARK", .dark), ("SYSTEM", .system), ("light", .system), ("", .system),
        ]
        for (mode, expected) in modes {
            config.config.themeMode = mode
            #expect(appearance.appearance == expected, "\(mode)")
            #expect(appearance.effectiveAppearance == expected, "\(mode)")
        }
        let accents: [(String, AppearanceModel.Accent)] = [
            ("TEAL", .teal), ("BLUE", .blue), ("ORANGE", .orange), ("CONTRAST", .contrast), ("PINK", .teal),
        ]
        for (accent, expected) in accents {
            config.config.themeAccent = accent
            #expect(appearance.accent == expected, "\(accent)")
            #expect(appearance.isContrast == (expected == .contrast), "\(accent)")
        }
    }

    /// Kotlin `colorSchemeFor(useDark || accent == "CONTRAST", accent)`: high contrast is dark whatever the mode.
    @Test func contrastForcesDark() async throws {
        let app = try await TestApp.make { config, _ in
            config.themeMode = "LIGHT"
            config.themeAccent = "CONTRAST"
        }
        let appearance: AppearanceModel = app.model.appearance
        #expect(appearance.appearance == .light)
        #expect(appearance.effectiveAppearance == .dark)
    }

    /// A commit changes the look at once (observers re-render).
    @Test func aCommitChangesTheLook() async throws {
        let harness = try await SettingsHarness.make()
        let appearance: AppearanceModel = harness.model.appearance
        var draft: ConfigurerDraft = try await harness.openWithDraft()
        draft.themeMode = "DARK"
        draft.themeAccent = "ORANGE"
        harness.settings.draft = draft
        final class Flag: @unchecked Sendable { var changed = false }
        let flag = Flag()
        withObservationTracking {
            _ = appearance.appearance
        } onChange: {
            flag.changed = true
        }

        #expect(await harness.settings.confirm())

        #expect(flag.changed)
        #expect(appearance.appearance == .dark)
        #expect(appearance.accent == .orange)
    }
}

/// The colours of the strips and highlights follow the accent (the bars used to stay teal).
@MainActor @Suite struct AccentPaletteTests {

    private static let accents: [AppearanceModel.Accent] = [.teal, .blue, .orange, .contrast]

    private static func luminance(_ hex: Int) -> Double {
        func channel(_ shift: Int) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private static func contrast(_ first: Int, _ second: Int) -> Double {
        let lights = [luminance(first), luminance(second)].sorted(by: >)
        return (lights[0] + 0.05) / (lights[1] + 0.05)
    }

    @Test func everyAccentHasItsOwnStripAndPrimary() {
        for dark in [false, true] {
            let strips = Self.accents.map { AccentPalette.palette(for: $0).strip.value(dark: dark) }
            let primaries = Self.accents.map { AccentPalette.palette(for: $0).primary.value(dark: dark) }
            #expect(Set(strips).count == Self.accents.count, "strip dark=\(dark)")
            #expect(Set(primaries).count == Self.accents.count, "primary dark=\(dark)")
        }
    }

    @Test func orangeIsNotTeal() {
        #expect(AccentPalette.palette(for: .orange).strip != AccentPalette.teal.strip)
        #expect(AccentPalette.palette(for: .orange).onStrip != AccentPalette.teal.onStrip)
    }

    @Test func textOnTheStripIsReadable() {
        for accent in Self.accents {
            let palette = AccentPalette.palette(for: accent)
            for dark in [false, true] {
                let ratio = Self.contrast(palette.onStrip.value(dark: dark), palette.strip.value(dark: dark))
                #expect(ratio >= 7, "\(accent) dark=\(dark) ratio \(ratio)")
            }
        }
    }

    @Test func highContrastIsTheSameInBothAppearances() {
        let palette = AccentPalette.palette(for: .contrast)
        #expect(palette.strip.light == palette.strip.dark)
        #expect(palette.primary.light == palette.primary.dark)
    }
}
